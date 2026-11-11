#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

@interface TGChatListViewController : UIViewController

- (instancetype)initWithClient:(TGTDLibClient *)client;
- (void)handleTDLibUpdate:(NSDictionary *)update;
/// Launch may show the list before TDLib authorizes; the app delegate calls
/// this once authorizationStateReady arrives so the first data load starts.
- (void)handleAuthorizationReady;

@end

NS_ASSUME_NONNULL_END
