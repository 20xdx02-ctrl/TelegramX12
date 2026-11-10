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
+ (NSString *)chatDayHeadingStringForTimestamp:(int32_t)timestamp;
+ (NSString *)initialsForTitle:(NSString *)title;
+ (UIColor *)avatarColorForIdentifier:(int64_t)identifier;
/// Stable accent colour used for author names in group chats.
+ (UIColor *)senderColorForIdentifier:(int64_t)identifier;
/// Strong blue used for links inside incoming bubbles.
+ (UIColor *)linkColor;
/// Light blue used for links on the accent-coloured outgoing bubble.
+ (UIColor *)outgoingLinkColor;
/// Builds message text with URLs/emails highlighted (and tappable).
+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                           font:(UIFont *)font
                                          color:(UIColor *)color
                                      linkColor:(UIColor *)linkColor;

+ (BOOL)isRTL;

@end

NS_ASSUME_NONNULL_END
