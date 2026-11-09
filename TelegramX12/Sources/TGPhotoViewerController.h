#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGPhotoViewerController : UIViewController

- (instancetype)initWithImage:(nullable UIImage *)image;
- (instancetype)initWithImagePath:(NSString *)imagePath;

/// Swaps the displayed image for a higher-resolution version.
/// Can be called after presentation to upgrade from a placeholder thumbnail.
- (void)upgradeToImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
