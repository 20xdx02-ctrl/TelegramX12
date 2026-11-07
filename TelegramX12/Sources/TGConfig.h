#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Build-time defaults. You can override them from the compiler flags, e.g.:
///   TelegramX12_CFLAGS += -DTG_DEFAULT_API_ID=12345 -DTG_DEFAULT_API_HASH='@"abc"'
#ifndef TG_DEFAULT_API_ID
#define TG_DEFAULT_API_ID 0
#endif
#ifndef TG_DEFAULT_API_HASH
#define TG_DEFAULT_API_HASH @""
#endif

/// api_id / api_hash can be entered at runtime in the in-app settings screen.
/// They are stored in NSUserDefaults. Get your own pair at https://my.telegram.org.
@interface TGConfig : NSObject

+ (int)apiId;
+ (NSString *)apiHash;
+ (BOOL)hasCredentials;

+ (void)setAPIId:(int)apiId apiHash:(NSString *)apiHash;
+ (void)resetCredentials;

@end

NS_ASSUME_NONNULL_END
