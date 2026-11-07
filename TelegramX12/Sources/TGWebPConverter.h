#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGWebPConverter : NSObject

+ (nullable NSString *)converterBinaryPath;
+ (BOOL)isWebPData:(NSData *)data;
+ (BOOL)isWebPFile:(NSString *)path;

+ (void)convertWebPAtPath:(NSString *)webpPath
               completion:(void (^)(NSString * _Nullable jpgPath, UIImage * _Nullable image))completion;

+ (nullable UIImage *)cachedImageForPath:(NSString *)webpPath;

@end

NS_ASSUME_NONNULL_END
