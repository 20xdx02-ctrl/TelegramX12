#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

@interface TGChatListViewController : UIViewController

- (instancetype)initWithClient:(TGTDLibClient *)client;
- (void)handleTDLibUpdate:(NSDictionary *)update;

@end

NS_ASSUME_NONNULL_END
