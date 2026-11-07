#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGMessage;

@interface TGMessageCell : UITableViewCell

- (void)configureWithMessage:(TGMessage *)message showSender:(BOOL)showSender senderName:(NSString *)senderName;
+ (CGFloat)heightForMessage:(TGMessage *)message width:(CGFloat)width showSender:(BOOL)showSender;

@end

NS_ASSUME_NONNULL_END
