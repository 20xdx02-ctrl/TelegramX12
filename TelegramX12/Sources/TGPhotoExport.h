#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Telegram server limits for photo messages: at most 10 MB of data, the sum
/// of width and height must not exceed 10000 pixels and the aspect ratio must
/// be at most 20.
FOUNDATION_EXPORT BOOL TGPhotoDataFitsServerLimits(NSData * _Nullable data, CGSize pixelSize);

/// Pixel dimensions read from the image header (no full decode).
FOUNDATION_EXPORT CGSize TGPhotoPixelSizeForImageData(NSData * _Nullable data);

/// Returns JPEG data ready for a photo message. Already valid JPEG data is
/// passed through untouched, so the original resolution and quality are kept.
/// Other formats (HEIC, PNG, …) are converted to JPEG at the highest quality
/// that still fits the Telegram server limits.
FOUNDATION_EXPORT NSData * _Nullable TGMaximumQualityJPEGForImageData(NSData * _Nullable data,
                                                                     NSString * _Nullable uti);

/// Re-encodes a UIImage at the highest quality that still fits the Telegram
/// server limits (no downscaling unless the server would reject the photo).
FOUNDATION_EXPORT NSData * _Nullable TGMaximumQualityJPEGForImage(UIImage * _Nullable image);

NS_ASSUME_NONNULL_END
