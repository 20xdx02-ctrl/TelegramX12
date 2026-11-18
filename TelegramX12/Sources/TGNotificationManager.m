#import "TGNotificationManager.h"
#import "TGModels.h"
#import "TGTDLibClient.h"
#import "TGChatViewController.h"

@interface TGNotificationManager ()

@property (nonatomic, weak) TGTDLibClient *client;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *unreadCountsByChatId;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *mutedByChatId;
@property (nonatomic) NSTimeInterval launchTimestamp;
@property (nonatomic) BOOL isAuthorized;

@end

@implementation TGNotificationManager

+ (instancetype)sharedManager {
    static TGNotificationManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[TGNotificationManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _unreadCountsByChatId = [NSMutableDictionary dictionary];
        _mutedByChatId = [NSMutableDictionary dictionary];
        _launchTimestamp = [[NSDate date] timeIntervalSince1970];
    }
    return self;
}

- (void)setupWithClient:(TGTDLibClient *)client {
    self.client = client;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    [self requestAuthorization];
}

- (void)requestAuthorization {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    __weak typeof(self) weakSelf = self;
    UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    [center requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError * _Nullable error) {
        weakSelf.isAuthorized = granted;
        if (granted) {
            NSLog(@"[TGNotificationManager] Powiadomienia włączone");
        } else if (error != nil) {
            NSLog(@"[TGNotificationManager] Błąd autoryzacji powiadomień: %@", error);
        }
    }];
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    NSDictionary *userInfo = notification.request.content.userInfo;
    int64_t chatId = [userInfo[@"chat_id"] longLongValue];

    // Jeśli czat z powiadomienia jest obecnie otwarty na ekranie, nie pokazuj banera.
    // Musimy sprawdzić na głównym wątku bo to operacja UI.
    __block BOOL suppressNotification = NO;
    void (^checkVisible)(void) = ^{
        UIViewController *visibleVC = [self.delegate currentlyVisibleChatViewController];
        if ([visibleVC isKindOfClass:[TGChatViewController class]]) {
            TGChatViewController *chatVC = (TGChatViewController *)visibleVC;
            suppressNotification = (chatVC.chatId == chatId);
        }
    };
    if ([NSThread isMainThread]) {
        checkVisible();
    } else {
        dispatch_sync(dispatch_get_main_queue(), checkVisible);
    }
    if (suppressNotification) {
        completionHandler(0);
        return;
    }

    // W przeciwnym razie wyświetl powiadomienie nawet gdy aplikacja jest na pierwszym planie.
    // UNNotificationPresentationOptionBadge wymaga iOS 14+ – nie używamy go.
    completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    int64_t chatId = [userInfo[@"chat_id"] longLongValue];
    int64_t messageId = [userInfo[@"message_id"] longLongValue];

    if (chatId != 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(notificationManagerDidSelectChatId:messageId:)]) {
                [self.delegate notificationManagerDidSelectChatId:chatId messageId:messageId];
            }
        });
    }

    completionHandler();
}

#pragma mark - TDLib Updates

- (void)handleTDLibUpdate:(NSDictionary *)update {
    NSString *type = TGStringValue(update[@"@type"]);

    if ([type isEqualToString:@"updateNewChat"]) {
        NSDictionary *chat = update[@"chat"];
        if ([chat isKindOfClass:[NSDictionary class]]) {
            int64_t chatId = TGInt64Value(chat[@"id"]);
            self.unreadCountsByChatId[@(chatId)] = @(TGInt32Value(chat[@"unread_count"]));
            NSDictionary *notif = chat[@"notification_settings"];
            if ([notif isKindOfClass:[NSDictionary class]]) {
                BOOL isMuted = !TGBoolValue(notif[@"use_default_mute_for"]) && (TGInt32Value(notif[@"mute_for"]) > 0);
                self.mutedByChatId[@(chatId)] = @(isMuted);
            }
            [self updateAppBadge];
        }
        return;
    }

    if ([type isEqualToString:@"updateChatNotificationSettings"]) {
        int64_t chatId = TGInt64Value(update[@"chat_id"]);
        NSDictionary *notif = update[@"notification_settings"];
        if (chatId != 0 && [notif isKindOfClass:[NSDictionary class]]) {
            BOOL isMuted = !TGBoolValue(notif[@"use_default_mute_for"]) && (TGInt32Value(notif[@"mute_for"]) > 0);
            self.mutedByChatId[@(chatId)] = @(isMuted);
            [self updateAppBadge];
        }
        return;
    }

    if ([type isEqualToString:@"updateChatReadInbox"]) {
        int64_t chatId = TGInt64Value(update[@"chat_id"]);
        int32_t count = TGInt32Value(update[@"unread_count"]);
        if (chatId != 0) {
            self.unreadCountsByChatId[@(chatId)] = @(count);
            [self updateAppBadge];
        }
        return;
    }

    if ([type isEqualToString:@"updateNewMessage"]) {
        NSDictionary *message = update[@"message"];
        if ([message isKindOfClass:[NSDictionary class]]) {
            [self handleNewMessage:message];
        }
        return;
    }
}

- (void)handleNewMessage:(NSDictionary *)message {
    // 1. Ignoruj wiadomości wychodzące (wysłane przez nas)
    if (TGBoolValue(message[@"is_outgoing"])) {
        return;
    }

    // 2. Ignoruj stare wiadomości (np. synchronizowane podczas startu)
    int32_t date = TGInt32Value(message[@"date"]);
    if (date > 0 && date < (int32_t)(self.launchTimestamp - 5.0)) {
        return;
    }

    int64_t chatId = TGInt64Value(message[@"chat_id"]);
    int64_t messageId = TGInt64Value(message[@"id"]);
    if (chatId == 0) {
        return;
    }

    // 3. Sprawdź czy czat jest wyciszony
    if ([self.mutedByChatId[@(chatId)] boolValue]) {
        return;
    }
    NSDictionary *chat = [self.client chatWithId:chatId];
    if (chat != nil) {
        NSDictionary *notif = chat[@"notification_settings"];
        if ([notif isKindOfClass:[NSDictionary class]]) {
            BOOL isMuted = !TGBoolValue(notif[@"use_default_mute_for"]) && (TGInt32Value(notif[@"mute_for"]) > 0);
            self.mutedByChatId[@(chatId)] = @(isMuted);
            if (isMuted) {
                return;
            }
        }
    }

    // 4. Jeśli aplikacja jest na pierwszym planie i ten czat jest otwarty, nie emituj powiadomienia
    // UIApplication musi być odpytany na głównym wątku.
    __block BOOL isChatOpen = NO;
    void (^checkOpen)(void) = ^{
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            UIViewController *visibleVC = [self.delegate currentlyVisibleChatViewController];
            if ([visibleVC isKindOfClass:[TGChatViewController class]]) {
                TGChatViewController *chatVC = (TGChatViewController *)visibleVC;
                isChatOpen = (chatVC.chatId == chatId);
            }
        }
    };
    if ([NSThread isMainThread]) {
        checkOpen();
    } else {
        dispatch_sync(dispatch_get_main_queue(), checkOpen);
    }
    if (isChatOpen) {
        return;
    }

    // 5. Zbuduj treść powiadomienia
    NSString *chatTitle = TGStringValue(chat[@"title"]);
    NSString *senderName = [self.client displayNameForSender:message[@"sender_id"]];

    NSDictionary *type = chat[@"type"];
    NSString *typeName = TGStringValue(type[@"@type"]);
    BOOL isPrivate = [typeName isEqualToString:@"chatTypePrivate"] || [typeName isEqualToString:@"chatTypeSecret"];

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];

    if (isPrivate) {
        content.title = senderName.length > 0 ? senderName : (chatTitle.length > 0 ? chatTitle : @"Telegram");
    } else {
        content.title = chatTitle.length > 0 ? chatTitle : @"Telegram";
        if (senderName.length > 0) {
            content.subtitle = senderName;
        }
    }

    NSString *bodyText = TGMessagePreviewText(message[@"content"]);
    content.body = bodyText.length > 0 ? bodyText : @"Nowa wiadomość";
    content.sound = [UNNotificationSound defaultSound];
    content.userInfo = @{
        @"chat_id": @(chatId),
        @"message_id": @(messageId)
    };

    NSInteger totalBadge = [self calculateTotalUnread];
    if (totalBadge > 0) {
        content.badge = @(totalBadge);
    }

    NSString *requestIdentifier = [NSString stringWithFormat:@"msg-%lld-%lld", chatId, messageId];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:requestIdentifier
                                                                          content:content
                                                                          trigger:nil];

    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"[TGNotificationManager] addNotificationRequest error: %@", error);
        }
    }];
}

#pragma mark - Badge

- (void)updateAppBadge {
    NSInteger total = [self calculateTotalUnread];
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].applicationIconBadgeNumber = total;
    });
}

- (NSInteger)calculateTotalUnread {
    NSInteger total = 0;
    for (NSNumber *chatId in self.unreadCountsByChatId) {
        if (![self.mutedByChatId[chatId] boolValue]) {
            total += [self.unreadCountsByChatId[chatId] integerValue];
        }
    }
    return total;
}

@end
