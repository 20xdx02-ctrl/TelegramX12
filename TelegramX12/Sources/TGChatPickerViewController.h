#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

typedef void (^TGChatPickerCompletion)(int64_t chatId, NSString *title);

/// Simple chat list used by "Przekaż" (forward). The current chat is hidden.
@interface TGChatPickerViewController : UIViewController

- (instancetype)initWithClient:(TGTDLibClient *)client
               excludingChatId:(int64_t)excludingChatId
                    completion:(TGChatPickerCompletion)completion;

@end

NS_ASSUME_NONNULL_END
