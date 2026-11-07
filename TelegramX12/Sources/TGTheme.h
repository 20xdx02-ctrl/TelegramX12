#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIColor (TelegramX12)
+ (UIColor *)tg_colorWithHex:(uint32_t)hex;
+ (UIColor *)tg_colorWithHex:(uint32_t)hex alpha:(CGFloat)alpha;
@end

@interface TGTheme : NSObject

+ (UIColor *)accentColor;
+ (UIColor *)accentPressedColor;
+ (UIColor *)outgoingBubbleColor;
+ (UIColor *)incomingBubbleColor;
+ (UIColor *)secondaryTextColor;
+ (UIColor *)separatorColor;
+ (UIColor *)inputBackgroundColor;
+ (UIColor *)dangerColor;
+ (UIColor *)chatBackgroundColor;
+ (UIColor *)groupedBackgroundColor;

+ (UIFont *)regularFontOfSize:(CGFloat)size;
+ (UIFont *)mediumFontOfSize:(CGFloat)size;
+ (UIFont *)semiboldFontOfSize:(CGFloat)size;
+ (UIFont *)boldFontOfSize:(CGFloat)size;

+ (NSString *)timeStringForTimestamp:(int32_t)timestamp;
+ (NSString *)chatListTimeStringForTimestamp:(int32_t)timestamp;
+ (NSString *)initialsForTitle:(NSString *)title;
+ (UIColor *)avatarColorForIdentifier:(int64_t)identifier;

+ (BOOL)isRTL;

@end

NS_ASSUME_NONNULL_END
