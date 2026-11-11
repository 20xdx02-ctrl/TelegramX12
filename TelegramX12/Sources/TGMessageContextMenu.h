#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TGMessageContextAction) {
    TGMessageContextActionCopy = 0,
    TGMessageContextActionReply,
    TGMessageContextActionForward,
    TGMessageContextActionEdit,
    TGMessageContextActionDelete,
    TGMessageContextActionGallery,
    TGMessageContextActionCamera,
    TGMessageContextActionSearch,
    TGMessageContextActionToggleMute,
};

/// Telegram X-style message context menu: a dark floating card with a row of
/// quick-reaction emoji buttons on top and text actions below, anchored to the
/// message bubble over a dimmed background. Long-press replacement for the
/// plain UIAlertController action sheet.
@interface TGMessageContextMenu : UIView

+ (void)presentInView:(UIView *)superview
           bubbleRect:(CGRect)bubbleRect
               emojis:(NSArray<NSString *> *)emojis
       allowedActions:(NSArray<NSNumber *> *)actions
          titleOverride:(nullable NSDictionary<NSNumber *, NSString *> *)titleOverride
           onReaction:(nullable void (^)(NSString *emoji))onReaction
             onAction:(nullable void (^)(TGMessageContextAction action))onAction;

- (void)dismissAnimated:(BOOL)animated completion:(nullable void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
