#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGMessage;
@class TGTDLibClient;

@interface TGMessageCell : UITableViewCell

@property (nonatomic, copy, nullable) void (^onMediaTap)(TGMessage *message);
@property (nonatomic, copy, nullable) void (^onStickerTap)(TGMessage *message);

- (void)configureWithMessage:(TGMessage *)message
                  showSender:(BOOL)showSender
                  senderName:(NSString *)senderName
                      client:(nullable TGTDLibClient *)client;

+ (CGFloat)heightForMessage:(TGMessage *)message width:(CGFloat)width showSender:(BOOL)showSender;

@end

NS_ASSUME_NONNULL_END
