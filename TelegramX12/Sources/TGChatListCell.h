#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGChat;
@class TGTDLibClient;

@interface TGChatListCell : UITableViewCell

- (void)configureWithChat:(TGChat *)chat;
- (void)configureWithChat:(TGChat *)chat client:(nullable TGTDLibClient *)client;

@end

NS_ASSUME_NONNULL_END
