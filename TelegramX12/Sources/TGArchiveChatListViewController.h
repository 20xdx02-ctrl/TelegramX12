#import <UIKit/UIKit.h>

@class TGTDLibClient;

NS_ASSUME_NONNULL_BEGIN

/// Folder view: chats that hold a chatListArchive position.
/// Receives TDLib updates like the main list so it stays in sync while open.
@interface TGArchiveChatListViewController : UIViewController

- (instancetype)initWithClient:(TGTDLibClient *)client;

/// AppState feed (same contract as TGChatListViewController).
- (void)handleTDLibUpdate:(NSDictionary *)update;

@end

NS_ASSUME_NONNULL_END
