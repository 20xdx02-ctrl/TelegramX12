#import "TGAppDelegate.h"
#import "TGTheme.h"
#import "TGTDLibClient.h"
#import "TGLoginViewController.h"
#import "TGChatListViewController.h"
#import "TGModels.h"

@interface TGAppDelegate () <TGTDLibClientDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) UINavigationController *navigationController;
@property (nonatomic, weak) TGLoginViewController *loginViewController;
@property (nonatomic) BOOL readyScreenShown;
@end

@implementation TGAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];

    self.client = [[TGTDLibClient alloc] init];
    self.client.delegate = self;
    // UIKit must finish attaching the initial controller before TDLib can
    // deliver a cached authorization state.  On iOS 12 an already-authorized
    // account can otherwise replace the root controller while launch is still
    // being processed, which terminates the process with SIGABRT.
    [self showLoginAnimated:NO];
    [self.window makeKeyAndVisible];

    TGTDLibClient *client = self.client;
    dispatch_async(dispatch_get_main_queue(), ^{
        [client start];
    });
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    [self.client shutdown];
}

#pragma mark - Screens

- (void)showLoginAnimated:(BOOL)animated {
    self.readyScreenShown = NO;

    TGLoginViewController *login = [[TGLoginViewController alloc] initWithClient:self.client];
    self.loginViewController = login;

    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:login];
    navigation.navigationBarHidden = YES;
    [self setRootViewController:navigation animated:animated];

    NSDictionary *state = self.client.authorizationState;
    if (state != nil) {
        [login applyAuthorizationState:state];
    }
}

- (void)showChatsAnimated:(BOOL)animated {
    if (self.readyScreenShown) {
        return;
    }
    self.readyScreenShown = YES;
    self.loginViewController = nil;

    TGChatListViewController *chatList = [[TGChatListViewController alloc] initWithClient:self.client];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:chatList];
    [self setRootViewController:navigation animated:animated];
}

- (void)setRootViewController:(UIViewController *)viewController animated:(BOOL)animated {
    self.navigationController = [viewController isKindOfClass:[UINavigationController class]]
        ? (UINavigationController *)viewController
        : nil;
    BOOL hadRoot = self.window.rootViewController != nil;
    if (!animated || !hadRoot) {
        self.window.rootViewController = viewController;
        return;
    }
    [UIView transitionWithView:self.window
                      duration:0.28
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        self.window.rootViewController = viewController;
                    }
                    completion:nil];
}

#pragma mark - TGTDLibClientDelegate

- (void)tgClient:(TGTDLibClient *)client didChangeAuthorizationState:(NSDictionary *)state {
    NSString *type = TGStringValue(state[@"@type"]);
    NSLog(@"[TGX] app delegate auth state: %@", type);
    NSString *logPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"app.log"];
    NSString *line = [NSString stringWithFormat:@"%@ delegate auth state: %@\n", [NSDate date], type];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (handle == nil) { [data writeToFile:logPath atomically:YES]; }
    else { [handle seekToEndOfFile]; [handle writeData:data]; [handle closeFile]; }

    if ([type isEqualToString:@"authorizationStateReady"]) {
        [self showChatsAnimated:YES];
        return;
    }

    if ([type isEqualToString:@"authorizationStateWaitPhoneNumber"] ||
        [type isEqualToString:@"authorizationStateWaitCode"] ||
        [type isEqualToString:@"authorizationStateWaitPassword"] ||
        [type isEqualToString:@"authorizationStateWaitRegistration"] ||
        [type isEqualToString:@"authorizationStateWaitTermsOfService"] ||
        [type isEqualToString:@"authorizationStateWaitTdlibParameters"] ||
        [type isEqualToString:@"authorizationStateLoggingOut"] ||
        [type isEqualToString:@"authorizationStateClosed"]) {
        if (self.readyScreenShown || self.loginViewController == nil) {
            [self showLoginAnimated:YES];
        }
        [self.loginViewController applyAuthorizationState:state];
    }
}

- (void)tgClientDidBecomeReady:(TGTDLibClient *)client {
    [self showChatsAnimated:YES];
}

- (void)tgClient:(TGTDLibClient *)client didReceiveUpdate:(NSDictionary *)update {
    NSArray<UIViewController *> *viewControllers = [self.navigationController.viewControllers copy];
    for (UIViewController *vc in viewControllers) {
        if ([vc respondsToSelector:@selector(handleTDLibUpdate:)]) {
            [(id)vc handleTDLibUpdate:update];
        }
    }
}

- (void)tgClient:(TGTDLibClient *)client didFailWithError:(NSDictionary *)error {
    NSString *message = TGStringValue(error[@"message"]);
    if (message.length == 0) {
        return;
    }
    NSLog(@"[TelegramX12] TDLib error %@: %@", error[@"code"], message);
}

@end
