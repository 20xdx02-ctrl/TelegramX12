#import "TGWebPConverter.h"
#import "webp/decode.h"
#import "w2j.h"

static void TGWebPReleaseData(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    WebPFree((void *)data);
}

@implementation TGWebPConverter

+ (NSCache<NSString *, UIImage *> *)sharedCache {
    static NSCache<NSString *, UIImage *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 400;
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

+ (nullable UIImage *)convertWebPData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }

    int width = 0;
    int height = 0;
    uint8_t *rgba = WebPDecodeRGBA((const uint8_t *)data.bytes, (size_t)data.length, &width, &height);
    if (rgba != NULL && width > 0 && height > 0) {
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, rgba, (size_t)width * (size_t)height * 4, TGWebPReleaseData);
        if (provider != NULL) {
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            CGImageRef imageRef = CGImageCreate(
                (size_t)width,
                (size_t)height,
                8,
                32,
                (size_t)width * 4,
                colorSpace,
                kCGBitmapByteOrder32Big | kCGImageAlphaLast,
                provider,
                NULL,
                NO,
                kCGRenderingIntentDefault
            );
            CGColorSpaceRelease(colorSpace);
            CGDataProviderRelease(provider);

            if (imageRef != NULL) {
                UIImage *image = [UIImage imageWithCGImage:imageRef scale:1.0 orientation:UIImageOrientationUp];
                CGImageRelease(imageRef);
                return image;
            }
        }
        WebPFree(rgba);
    }

    // Fallback: w2j convert to JPEG
    w2j_options opt;
    w2j_options_default(&opt);
    opt.quality = 90;
    opt.background = 0xFFFFFF;

    w2j_result result;
    memset(&result, 0, sizeof(result));
    char err[128] = {0};

    int status = w2j_convert((const uint8_t *)data.bytes, data.length, &opt, &result, err, sizeof(err));
    if (status == 0 && result.jpeg != NULL && result.jpeg_size > 0) {
        NSData *jpegData = [NSData dataWithBytes:result.jpeg length:result.jpeg_size];
        w2j_result_free(&result);
        return [UIImage imageWithData:jpegData];
    }
    return nil;
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
        // 2. Direct UIImage load attempt
        UIImage *directImage = [UIImage imageWithContentsOfFile:webpPath];
        if (directImage != nil) {
            [[self sharedCache] setObject:directImage forKey:webpPath];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(webpPath, directImage);
            });
            return;
        }

        // 3. Read WebP data and convert in-process using libwebp
        NSData *data = [NSData dataWithContentsOfFile:webpPath options:NSDataReadingMappedIfSafe error:nil];
        if (data.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil);
            });
            return;
        }

        UIImage *convertedImage = [self convertWebPData:data];
        if (convertedImage != nil) {
            [[self sharedCache] setObject:convertedImage forKey:webpPath];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, convertedImage);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(nil, nil);
            });
        }
    });
}

@end
