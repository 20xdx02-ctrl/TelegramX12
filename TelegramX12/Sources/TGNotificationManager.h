#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

@protocol TGNotificationManagerDelegate <NSObject>
@optional
- (void)notificationManagerDidSelectChatId:(int64_t)chatId messageId:(int64_t)messageId;
- (nullable UIViewController *)currentlyVisibleChatViewController;
@end

/// Handles iOS local notifications (UNUserNotificationCenter) for new incoming
/// messages, chat muting rules, and application icon badge counter updates.
@interface TGNotificationManager : NSObject <UNUserNotificationCenterDelegate>

@property (nonatomic, weak, nullable) id<TGNotificationManagerDelegate> delegate;

+ (instancetype)sharedManager;

- (void)setupWithClient:(TGTDLibClient *)client;
- (void)requestAuthorization;

- (void)handleTDLibUpdate:(NSDictionary *)update;

/// Recalculates and updates the app icon badge number based on unread counts.
- (void)updateAppBadge;

@end

NS_ASSUME_NONNULL_END
