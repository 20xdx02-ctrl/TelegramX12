#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

@interface TGChatViewController : UIViewController

- (instancetype)initWithClient:(TGTDLibClient *)client chatId:(int64_t)chatId title:(NSString *)title;
- (void)handleTDLibUpdate:(NSDictionary *)update;

@end

NS_ASSUME_NONNULL_END
