#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TGPhotoViewerController : UIViewController

- (instancetype)initWithImage:(UIImage *)image;
- (instancetype)initWithImagePath:(NSString *)imagePath;

@end

NS_ASSUME_NONNULL_END
