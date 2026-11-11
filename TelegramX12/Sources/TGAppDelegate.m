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
                                             selector:@selector(deviceOrientationDidChange:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    // UIKit must finish attaching the initial controller before TDLib can
    // deliver a cached authorization state.  On iOS 12 an already-authorized
    // account can otherwise replace the root controller while launch is still
    // being processed, which terminates the process with SIGABRT.
    // A cached TDLib session means we can go straight to the chat list: no
    // login/loading screen flash while TDLib re-authorizes in the background.
    // Fresh installs still start on the login screen.
    if ([self.client hasCachedSession]) {
        [self showChatsAnimated:NO];
    } else {
        [self showLoginAnimated:NO];
    }
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

    UIViewController *root = nil;
    if (isPhone) {
        root = self.masterNavigation;
    } else {
        // Determine current orientation without relying on deprecated statusBarOrientation.
        UIInterfaceOrientation orientation = [self currentInterfaceOrientation];
        if ([self iPadOrientationIsPortrait:orientation]) {
            // Portrait: single-column phone-style navigation.
            self.splitViewController = nil;
            root = self.masterNavigation;
        } else {
            // Landscape: two-pane split view.
            self.splitViewController = [self installSplitForMaster:self.masterNavigation];
            root = self.splitViewController;
        }
    }
    [self setRootViewController:root animated:animated];
}

/// Builds an empty split view controller (no columns yet — callers must
/// detach the previous window root before installing a master navigation).
- (UISplitViewController *)makeSplitViewController {
    UISplitViewController *split = [[UISplitViewController alloc] init];
    split.minimumPrimaryColumnWidth = 320.0;
    split.maximumPrimaryColumnWidth = 420.0;
    split.presentsWithGesture = NO;
    return split;
}

/// Detail column hosting just the empty-state placeholder.
- (UINavigationController *)makePlaceholderDetailNavigation {
    UINavigationController *detail = [[UINavigationController alloc] initWithRootViewController:[[TGChatPlaceholderViewController alloc] init]];
    return detail;
}

- (BOOL)iPadOrientationIsPortrait:(UIInterfaceOrientation)orientation {
    return orientation != UIInterfaceOrientationLandscapeLeft && orientation != UIInterfaceOrientationLandscapeRight;
}

/// Returns the current interface orientation in a way that works on all iOS versions
/// without relying on deprecated UIApplication.statusBarOrientation.
- (UIInterfaceOrientation)currentInterfaceOrientation {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 16.0, *)) {
        // On iOS 16+ query the window scene directly.
        UIWindowScene *scene = (UIWindowScene *)self.window.windowScene;
        if (scene != nil) {
            return (UIInterfaceOrientation)scene.interfaceOrientation;
        }
    }
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
}

/// Notification: retry layout only on iPad while chats are visible.
- (void)deviceOrientationDidChange:(NSNotification *)notification {
    if (!self.readyScreenShown) {
        return;
    }
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return;
    }
    UIInterfaceOrientation orientation = [self currentInterfaceOrientation];
    // Skip unknown / face-up / face-down orientations.
    if (orientation == UIInterfaceOrientationUnknown) {
        return;
    }
    BOOL targetPortrait = [self iPadOrientationIsPortrait:orientation];
    BOOL currentPortrait = (self.window.rootViewController != self.splitViewController);
    if (targetPortrait == currentPortrait) {
        return;
    }
    if (targetPortrait) {
        [self collapseIpadSplitToPortraitAnimated:YES];
    } else {
        [self expandIpadToSplitAnimated:YES];
    }
}

/// Portrait: move any open chat from the detail column into the master stack,
/// then drop the split view and promote the master navigation as root.
- (void)collapseIpadSplitToPortraitAnimated:(BOOL)animated {
    if (self.splitViewController == nil) {
        return;
    }
    TGChatViewController *openChat = [self currentlyOpenChat];
    // If the chat is in the detail column (not yet in the master stack), migrate it.
    if (openChat != nil && ![self.masterNavigation.viewControllers containsObject:openChat]) {
        // Remove it from the detail navigation controller first.
        UINavigationController *detail = [self.splitViewController viewControllers].lastObject;
        if ([detail isKindOfClass:[UINavigationController class]]) {
            UINavigationController *detailNav = (UINavigationController *)detail;
            NSMutableArray *controllers = [detailNav.viewControllers mutableCopy];
            [controllers removeObject:openChat];
            detailNav.viewControllers = controllers;
        }
        // Push it onto the master stack so it stays accessible in portrait.
        [self.masterNavigation pushViewController:openChat animated:NO];
    }
    // Detach the master column from the split before promoting it to the
    // window root (same re-parenting constraint as in installSplitForMaster).
    NSMutableArray *columns = [[self.splitViewController viewControllers] mutableCopy];
    [columns removeAllObjects];
    UINavigationController *holdingStack = [[UINavigationController alloc] initWithRootViewController:[[UIViewController alloc] init]];
    [columns addObject:holdingStack];
    [self.splitViewController setViewControllers:columns];

    self.splitViewController = nil;
    [self setRootViewController:self.masterNavigation animated:animated];
}

/// Builds the two-pane layout around the chat-list navigation. iOS throws
/// "adding a root view controller ... as a child" when the window's current
/// root view controller is re-parented into the split, so detach it first.
- (UISplitViewController *)installSplitForMaster:(UINavigationController *)master {
    UISplitViewController *split = [self makeSplitViewController];
    UINavigationController *detail = [self makePlaceholderDetailNavigation];
    if (self.window.rootViewController == master) {
        // Detach cleanly so the master navigation may move under the split.
        self.window.rootViewController = [[UIViewController alloc] init];
    }
    split.viewControllers = @[master, detail];
    self.splitViewController = split;
    return split;
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
    // Detach the chat from the phone stack before it is re-parented into
    // its own detail column.
    [self.masterNavigation setViewControllers:masterControllers animated:NO];

    UISplitViewController *split = [self installSplitForMaster:self.masterNavigation];
    if (openChat != nil) {
        UINavigationController *chatStack = [[UINavigationController alloc] initWithRootViewController:openChat];
        split.viewControllers = @[self.masterNavigation, chatStack];
    }
    [self setRootViewController:split animated:animated];
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
        // Swap instantly: the animated cross-dissolve reads as a loading screen.
        [self showChatsAnimated:NO];
        [self notifyAuthorizationReady];
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
    [self showChatsAnimated:NO];
    [self notifyAuthorizationReady];
}

/// The chat list may already be the root (cached session at launch) before
/// TDLib finishes authorizing; let it perform its first data load now.
- (void)notifyAuthorizationReady {
    for (UIViewController *vc in [self visibleUpdateTargets]) {
        if ([vc respondsToSelector:@selector(handleAuthorizationReady)]) {
            [(TGChatListViewController *)vc handleAuthorizationReady];
        }
    }
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
