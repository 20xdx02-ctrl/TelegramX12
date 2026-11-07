#import "TGConfig.h"

static NSString *const TGAPIIdKey = @"TGAPIId";
static NSString *const TGAPIHashKey = @"TGAPIHash";

@implementation TGConfig

+ (int)apiId {
    NSInteger stored = [[NSUserDefaults standardUserDefaults] integerForKey:TGAPIIdKey];
    if (stored > 0) {
        return (int)stored;
    }
    return TG_DEFAULT_API_ID;
}

+ (NSString *)apiHash {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:TGAPIHashKey];
    if (stored.length > 0) {
        return stored;
    }
    return TG_DEFAULT_API_HASH;
}

+ (BOOL)hasCredentials {
    return [self apiId] > 0 && [self apiHash].length > 0;
}

+ (void)setAPIId:(int)apiId apiHash:(NSString *)apiHash {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:apiId forKey:TGAPIIdKey];
    [defaults setObject:apiHash forKey:TGAPIHashKey];
    [defaults synchronize];
}

+ (void)resetCredentials {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:TGAPIIdKey];
    [defaults removeObjectForKey:TGAPIHashKey];
    [defaults synchronize];
}

@end
