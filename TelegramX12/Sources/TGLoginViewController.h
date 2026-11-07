#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

@interface TGLoginViewController : UIViewController

- (instancetype)initWithClient:(TGTDLibClient *)client;
- (void)applyAuthorizationState:(NSDictionary *)state;

@end

NS_ASSUME_NONNULL_END
