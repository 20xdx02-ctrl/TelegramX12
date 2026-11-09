#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGMessage;
@class TGTDLibClient;

@interface TGMessageCell : UITableViewCell

@property (nonatomic, copy, nullable) void (^onMediaTap)(TGMessage *message);
@property (nonatomic, copy, nullable) void (^onStickerTap)(TGMessage *message);
@property (nonatomic, copy, nullable) void (^onRetryTap)(TGMessage *message);
/// Called when the user long-presses the message bubble or sticker.
@property (nonatomic, copy, nullable) void (^onLongPress)(TGMessage *message);

/// @param isGroupStart  YES for the first message of a consecutive run from the
///                      same sender – this is where the avatar is rendered.
- (void)configureWithMessage:(TGMessage *)message
                  showSender:(BOOL)showSender
                  senderName:(NSString *)senderName
                isGroupStart:(BOOL)isGroupStart
                      client:(nullable TGTDLibClient *)client;

+ (CGFloat)heightForMessage:(TGMessage *)message width:(CGFloat)width showSender:(BOOL)showSender;

@end

NS_ASSUME_NONNULL_END
