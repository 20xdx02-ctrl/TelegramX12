#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TGTDLibClient;

@interface TGAvatarView : UIView

- (void)setTitle:(NSString *)title identifier:(int64_t)identifier;
- (void)setImage:(nullable UIImage *)image;
- (void)loadAvatarWithFileId:(int32_t)fileId
                      client:(nullable TGTDLibClient *)client
                       title:(NSString *)title
                  identifier:(int64_t)identifier;

@end

NS_ASSUME_NONNULL_END
