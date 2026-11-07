#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGChat;

@interface TGChatListCell : UITableViewCell

- (void)configureWithChat:(TGChat *)chat;

@end

NS_ASSUME_NONNULL_END
