#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGInputBar : UIView

@property (nonatomic, copy, nullable) void (^onSend)(NSString *text);
@property (nonatomic, copy, nullable) void (^onAttachTap)(void);
@property (nonatomic, strong, readonly) UITextField *textField;

- (void)clearText;
- (void)focus;

@end

NS_ASSUME_NONNULL_END
