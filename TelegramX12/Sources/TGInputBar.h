#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGInputBar : UIView

@property (nonatomic, copy, nullable) void (^onSend)(NSString *text);
@property (nonatomic, copy, nullable) void (^onAttachTap)(void);
@property (nonatomic, copy, nullable) void (^onStickerTap)(void);
/// Called when the user dismisses the quote strip above the text field.
@property (nonatomic, copy, nullable) void (^onCancelReply)(void);
@property (nonatomic, strong, readonly) UITextField *textField;

/// Height the chat screen should give the bar: 50pt, plus 44pt for a quote.
@property (nonatomic, readonly) CGFloat preferredHeight;

- (void)showReplyToName:(nullable NSString *)name text:(NSString *)text;
- (void)hideReply;

- (void)clearText;
- (void)focus;

@end

NS_ASSUME_NONNULL_END
