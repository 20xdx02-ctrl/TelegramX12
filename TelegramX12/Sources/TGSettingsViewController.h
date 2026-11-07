#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

@interface TGSettingsViewController : UIViewController

@property (nonatomic, copy, nullable) void (^onDismiss)(void);

- (instancetype)initWithClient:(TGTDLibClient *)client;

@end

NS_ASSUME_NONNULL_END
