#import "TGWebPConverter.h"

#include <spawn.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>

extern char **environ;

@implementation TGWebPConverter

+ (NSCache<NSString *, UIImage *> *)sharedCache {
    static NSCache<NSString *, UIImage *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 300;
        cache.totalCostLimit = 64 * 1024 * 1024; // 64 MB
    });
    return cache;
}

+ (dispatch_queue_t)workQueue {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.telegramx12.webp", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

+ (nullable NSString *)converterBinaryPath {
    static NSString *cachedPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSString *> *candidates = [NSMutableArray array];

        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"webp2jpeg" ofType:nil];
        if (bundlePath.length > 0) {
            [candidates addObject:bundlePath];
        }
        NSString *inAppPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"webp2jpeg"];
        if (inAppPath.length > 0) {
            [candidates addObject:inAppPath];
        }

        [candidates addObject:@"/usr/libexec/hitomi-webp2jpeg"];
        [candidates addObject:@"/usr/libexec/manga-webp2jpeg"];
        [candidates addObject:@"/usr/local/bin/webp2jpeg"];

        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"TelegramX12/webp2jpeg"];
        [candidates addObject:appSupport];

        for (NSString *candidate in candidates) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
                // Ensure executable permissions if writable
                chmod([candidate UTF8String], 0755);
                if (access([candidate UTF8String], X_OK) == 0) {
                    cachedPath = [candidate copy];
                    NSLog(@"[TelegramX12] Found working webp2jpeg binary at: %@", cachedPath);
                    break;
                }
            }
        }

        // If no candidate was executable, try copying bundle version to App Support
        if (cachedPath == nil && bundlePath.length > 0) {
            NSString *dir = [appSupport stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:appSupport error:nil];
            if ([[NSFileManager defaultManager] copyItemAtPath:bundlePath toPath:appSupport error:nil]) {
                chmod([appSupport UTF8String], 0755);
                if (access([appSupport UTF8String], X_OK) == 0) {
                    cachedPath = [appSupport copy];
                }
            }
        }
    });
    return cachedPath;
}

+ (BOOL)isWebPData:(NSData *)data {
    if (data.length < 12) {
        return NO;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    return bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F' &&
           bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P';
}

+ (BOOL)isWebPFile:(NSString *)path {
    if (path.length == 0) {
        return NO;
    }
    if ([path.pathExtension.lowercaseString isEqualToString:@"webp"]) {
        return YES;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) {
        return NO;
    }
    NSData *header = [handle readDataOfLength:12];
    [handle closeFile];
    return [self isWebPData:header];
}

+ (nullable UIImage *)cachedImageForPath:(NSString *)webpPath {
    if (webpPath.length == 0) return nil;
    return [[self sharedCache] objectForKey:webpPath];
}

+ (NSString *)cacheDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        dir = [caches stringByAppendingPathComponent:@"TelegramX12/webp"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

+ (void)convertWebPAtPath:(NSString *)webpPath
               completion:(void (^)(NSString * _Nullable jpgPath, UIImage * _Nullable image))completion {
    if (webpPath.length == 0) {
        if (completion) completion(nil, nil);
        return;
    }

    // 1. Check in-memory cache
    UIImage *cached = [[self sharedCache] objectForKey:webpPath];
    if (cached != nil) {
        if (completion) completion(nil, cached);
        return;
    }

    dispatch_async([self workQueue], ^{
        // 2. Direct UIImage load attempt (in case system handles it)
        UIImage *directImage = [UIImage imageWithContentsOfFile:webpPath];
        if (directImage != nil) {
            [[self sharedCache] setObject:directImage forKey:webpPath];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(webpPath, directImage);
            });
            return;
        }

        // 3. Compute destination converted JPEG path
        NSString *filename = [NSString stringWithFormat:@"%llu_%@.jpg", (unsigned long long)webpPath.hash, webpPath.lastPathComponent.stringByDeletingPathExtension];
        NSString *dstPath = [[self cacheDirectory] stringByAppendingPathComponent:filename];

        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:dstPath error:nil];
        if (attrs != nil && [attrs fileSize] > 0) {
            UIImage *img = [UIImage imageWithContentsOfFile:dstPath];
            if (img != nil) {
                [[self sharedCache] setObject:img forKey:webpPath];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(dstPath, img);
                });
                return;
            }
        }

        // 4. Run webp2jpeg conversion
        NSString *bin = [self converterBinaryPath];
        if (bin.length == 0) {
            NSLog(@"[TelegramX12] Cannot convert WebP: webp2jpeg binary not found");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil);
            });
            return;
        }

        pid_t pid = 0;
        char *argv[] = {
            (char *)[bin UTF8String],
            (char *)"-q",
            (char *)"90",
            (char *)"-f",
            (char *)"-o",
            (char *)[dstPath UTF8String],
            (char *)[webpPath UTF8String],
            NULL
        };

        int spawnStatus = posix_spawn(&pid, [bin UTF8String], NULL, NULL, argv, environ);
        if (spawnStatus == 0) {
            int status = 0;
            waitpid(pid, &status, 0);
        } else {
            NSLog(@"[TelegramX12] posix_spawn failed for %@ with error: %d", bin, spawnStatus);
        }

        UIImage *convertedImage = nil;
        NSDictionary *dstAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:dstPath error:nil];
        if (dstAttrs != nil && [dstAttrs fileSize] > 0) {
            convertedImage = [UIImage imageWithContentsOfFile:dstPath];
        }

        if (convertedImage != nil) {
            [[self sharedCache] setObject:convertedImage forKey:webpPath];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(dstPath, convertedImage);
            });
        } else {
            NSLog(@"[TelegramX12] WebP conversion failed for: %@", webpPath);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil);
            });
        }
    });
}

@end
