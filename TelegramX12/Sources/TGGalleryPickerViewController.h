#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Multi-select photo gallery (Photos framework) used by the attachment menu.
/// Sends back JPEG file paths ready for TDLib upload.
@interface TGGalleryPickerViewController : UIViewController

/// Called after the picker dismisses itself. Paths are temporary JPEG files.
@property (nonatomic, copy, nullable) void (^onSend)(NSArray<NSString *> *filePaths);

- (instancetype)initWithMaxSelection:(NSInteger)maxSelection;

@end

NS_ASSUME_NONNULL_END
