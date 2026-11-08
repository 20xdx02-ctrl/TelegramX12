#import "TGAppDelegate.h"
#import "TGTheme.h"
#import "TGTDLibClient.h"
#import "TGChatViewController.h"
#import "TGLoginViewController.h"
#import "TGChatListViewController.h"
#import "TGChatPlaceholderViewController.h"
#import "TGModels.h"

@interface TGAppDelegate () <TGTDLibClientDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) UINavigationController *navigationController;
@property (nonatomic, strong) UINavigationController *masterNavigation;
@property (nonatomic, strong) UISplitViewController *splitViewController;
@property (nonatomic, weak) TGLoginViewController *loginViewController;
@property (nonatomic) BOOL readyScreenShown;
@end

@implementation TGAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor whiteColor];

    self.client = [[TGTDLibClient alloc] init];
    self.client.delegate = self;
    // iPad rotates between the two-pane split (landscape) and the plain phone
    // layout (portrait); watch the orientation channel for the swap.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusBarOrientationWillChange:)
                                                 name:UIApplicationWillChangeStatusBarOrientationNotification
                                               object:nil];
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
    self.masterNavigation = [[UINavigationController alloc] initWithRootViewController:chatList];

    // iPad / regular width: Telegram X style two pane layout — chat list on
    // the left, conversation (or the placeholder) on the right. In portrait
    // the iPad falls back to the plain phone navigation stack instead.
    BOOL isPhone = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone;
    if (!isPhone) {
        self.splitViewController = [self buildSplitViewControllerForMaster:self.masterNavigation];
    }

    UIViewController *root = nil;
    if (isPhone) {
        root = self.masterNavigation;
    } else if ([self iPadOrientationIsPortrait:[UIApplication sharedApplication].statusBarOrientation]) {
        root = self.masterNavigation;
        self.splitViewController = nil;
    } else {
        root = self.splitViewController;
    }
    [self setRootViewController:root animated:animated];
}

/// Builds the two-pane iPad layout with the chat list as the master column.
- (UISplitViewController *)buildSplitViewControllerForMaster:(UINavigationController *)master {
    UISplitViewController *split = [[UISplitViewController alloc] init];
    UINavigationController *detail = [[UINavigationController alloc] initWithRootViewController:[[TGChatPlaceholderViewController alloc] init]];
    split.viewControllers = @[master, detail];
    split.minimumPrimaryColumnWidth = 320.0;
    split.maximumPrimaryColumnWidth = 420.0;
    split.presentsWithGesture = NO;
    return split;
}

- (BOOL)iPadOrientationIsPortrait:(UIInterfaceOrientation)orientation {
    return orientation != UIInterfaceOrientationLandscapeLeft && orientation != UIInterfaceOrientationLandscapeRight;
}

/// Notification: retry layout only on iPad while chats are visible.
- (void)statusBarOrientationWillChange:(NSNotification *)notification {
    if (!self.readyScreenShown) {
        return;
    }
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return;
    }
    NSNumber *target = notification.userInfo[UIApplicationStatusBarOrientationUserInfoKey];
    UIInterfaceOrientation orientation = (UIInterfaceOrientation)target.integerValue;
    BOOL targetPortrait = [self iPadOrientationIsPortrait:orientation];
    BOOL currentPortrait = (self.window.rootViewController != self.splitViewController);
    if (targetPortrait == currentPortrait) {
        return;
    }
    if (targetPortrait) {
        [self collapseIpadSplitToPortraitAnimated:NO];
    } else {
        [self expandIpadToSplitAnimated:NO];
    }
}

/// Portrait: every controller already lives in the master phone stack, so the
/// split view is simply dropped and the master stack becomes the root.
- (void)collapseIpadSplitToPortraitAnimated:(BOOL)animated {
    if (self.splitViewController == nil) {
        return;
    }
    TGChatViewController *openChat = [self currentlyOpenChat];
    if (openChat != nil && self.masterNavigation.viewControllers.lastObject != openChat) {
        UINavigationController *detail = [self.splitViewController viewControllers].lastObject;
        if ([detail isKindOfClass:[UINavigationController class]]) {
            NSMutableArray *detailControllers = [((UINavigationController *)detail).viewControllers mutableCopy];
            [detailControllers removeObject:openChat];
            ((UINavigationController *)detail).viewControllers = detailControllers;
        }
        [self.masterNavigation pushViewController:openChat animated:NO];
    }
    self.splitViewController = nil;
    [self setRootViewController:self.masterNavigation animated:animated];
}

/// Landscape: rebuild the two-pane layout, moving any open chat from the
/// phone stack into the detail column.
- (void)expandIpadToSplitAnimated:(BOOL)animated {
    NSMutableArray *masterControllers = [self.masterNavigation.viewControllers mutableCopy];
    UIViewController *top = masterControllers.lastObject;
    TGChatViewController *openChat = nil;
    if ([top isKindOfClass:[TGChatViewController class]]) {
        openChat = (TGChatViewController *)top;
        [masterControllers removeLastObject];
    }
    [self.masterNavigation setViewControllers:masterControllers animated:NO];

    self.splitViewController = [self buildSplitViewControllerForMaster:self.masterNavigation];
    if (openChat != nil) {
        UINavigationController *chatStack = [[UINavigationController alloc] initWithRootViewController:openChat];
        self.splitViewController.viewControllers = @[self.masterNavigation, chatStack];
    }
    [self setRootViewController:self.splitViewController animated:animated];
}

/// Looks up a chat controller that is on screen: top of the detail column
/// when the split is active, otherwise top of the phone stack.
- (TGChatViewController *)currentlyOpenChat {
    UINavigationController *detail = [self.splitViewController viewControllers].lastObject;
    if ([detail isKindOfClass:[UINavigationController class]]) {
        UIViewController *top = detail.viewControllers.lastObject;
        if ([top isKindOfClass:[TGChatViewController class]]) {
            return (TGChatViewController *)top;
        }
    }
    UIViewController *masterTop = self.masterNavigation.viewControllers.lastObject;
    if ([masterTop isKindOfClass:[TGChatViewController class]]) {
        return (TGChatViewController *)masterTop;
    }
    return nil;
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
    for (UIViewController *vc in [self visibleUpdateTargets]) {
        if ([vc respondsToSelector:@selector(handleTDLibUpdate:)]) {
            [(id)vc handleTDLibUpdate:update];
        }
    }
}

/// Collects every presented navigation root across the window hierarchy so
/// TDLib updates reach both columns of an iPad split view.
- (NSArray<UIViewController *> *)visibleUpdateTargets {
    NSMutableArray<UIViewController *> *targets = [NSMutableArray array];
    UIViewController *root = self.window.rootViewController;
    if ([root isKindOfClass:[UISplitViewController class]]) {
        UISplitViewController *split = (UISplitViewController *)root;
        for (UIViewController *column in split.viewControllers) {
            if ([column isKindOfClass:[UINavigationController class]]) {
                [targets addObjectsFromArray:((UINavigationController *)column).viewControllers];
            } else if (column != nil) {
                [targets addObject:column];
            }
        }
    } else if ([root isKindOfClass:[UINavigationController class]]) {
        [targets addObjectsFromArray:((UINavigationController *)root).viewControllers];
    } else if (root != nil) {
        [targets addObject:root];
    }
    return targets;
}

- (void)tgClient:(TGTDLibClient *)client didFailWithError:(NSDictionary *)error {
    NSString *message = TGStringValue(error[@"message"]);
    if (message.length == 0) {
        return;
    }
    NSLog(@"[TelegramX12] TDLib error %@: %@", error[@"code"], message);
}

@end
