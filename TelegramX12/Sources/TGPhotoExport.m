#import "TGPhotoExport.h"
#import "TGLog.h"

#import <ImageIO/ImageIO.h>

static const NSUInteger TGPhotoMaxBytes = 10u * 1024u * 1024u;
static const CGFloat TGPhotoMaxPixelSum = 10000.0;
static const CGFloat TGPhotoMaxAspectRatio = 20.0;

CGSize TGPhotoPixelSizeForImageData(NSData *data) {
    if (data.length == 0) {
        return CGSizeZero;
    }
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (source == NULL) {
        return CGSizeZero;
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    if (![properties isKindOfClass:[NSDictionary class]]) {
        return CGSizeZero;
    }
    CGFloat width = [properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat height = [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    return CGSizeMake(width, height);
}

BOOL TGPhotoDataFitsServerLimits(NSData *data, CGSize pixelSize) {
    if (data.length == 0 || data.length > TGPhotoMaxBytes) {
        return NO;
    }
    if (pixelSize.width < 1.0 || pixelSize.height < 1.0) {
        return NO;
    }
    if (pixelSize.width + pixelSize.height > TGPhotoMaxPixelSum) {
        return NO;
    }
    CGFloat shortSide = MIN(pixelSize.width, pixelSize.height);
    CGFloat longSide = MAX(pixelSize.width, pixelSize.height);
    return (longSide / shortSide) <= TGPhotoMaxAspectRatio;
}

static BOOL TGPhotoDataLooksLikeJPEG(NSData *data) {
    if (data.length < 3) {
        return NO;
    }
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
}

static BOOL TGPhotoUTIIsJPEG(NSString *uti) {
    NSString *lowercase = uti.lowercaseString;
    return [lowercase isEqualToString:@"public.jpeg"] ||
           [lowercase containsString:@"jpeg"] ||
           [lowercase containsString:@"jpg"];
}

/// Draws the image upright at one point per pixel: the resulting UIImage has
/// scale 1 and `size` equal to the bitmap dimensions, which keeps the original
/// resolution and makes the server-limit arithmetic exact.
static UIImage *TGPhotoFlatImage(UIImage *image) {
    CGSize pixelSize = CGSizeMake(round(image.size.width * image.scale),
                                  round(image.size.height * image.scale));
    if (image.imageOrientation == UIImageOrientationUp && image.scale == 1.0) {
        return image;
    }
    if (pixelSize.width < 1.0 || pixelSize.height < 1.0) {
        return image;
    }
    UIGraphicsBeginImageContextWithOptions(pixelSize, NO, 1.0);
    [image drawInRect:CGRectMake(0.0, 0.0, pixelSize.width, pixelSize.height)];
    UIImage *flat = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return flat ?: image;
}

static UIImage *TGPhotoImageScaledToSize(UIImage *image, CGSize size) {
    if (size.width < 1.0 || size.height < 1.0) {
        return image;
    }
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    [image drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled ?: image;
}

/// Telegram rejects panoramas wider than 20:1; crop the long side around the
/// centre so the content can still be sent at full height.
static UIImage *TGPhotoImageCroppedToServerAspect(UIImage *image) {
    CGSize size = image.size;
    CGFloat shortSide = MIN(size.width, size.height);
    CGFloat longSide = MAX(size.width, size.height);
    if (shortSide < 1.0 || (longSide / shortSide) <= TGPhotoMaxAspectRatio) {
        return image;
    }
    CGFloat targetLongSide = floor(shortSide * TGPhotoMaxAspectRatio);
    CGRect cropRect;
    if (size.width >= size.height) {
        cropRect = CGRectMake(floor((size.width - targetLongSide) / 2.0), 0.0, targetLongSide, size.height);
    } else {
        cropRect = CGRectMake(0.0, floor((size.height - targetLongSide) / 2.0), size.width, targetLongSide);
    }
    CGImageRef imageRef = image.CGImage;
    if (imageRef == NULL) {
        return image;
    }
    CGImageRef croppedRef = CGImageCreateWithImageInRect(imageRef, cropRect);
    if (croppedRef == NULL) {
        return image;
    }
    UIImage *cropped = [UIImage imageWithCGImage:croppedRef scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(croppedRef);
    return cropped ?: image;
}

NSData *TGMaximumQualityJPEGForImage(UIImage *image) {
    if (image == nil) {
        return nil;
    }
    UIImage *working = TGPhotoFlatImage(image);
    working = TGPhotoImageCroppedToServerAspect(working);

    CGSize size = working.size;
    if (size.width + size.height > TGPhotoMaxPixelSum) {
        CGFloat scale = TGPhotoMaxPixelSum / (size.width + size.height);
        CGSize fitted = CGSizeMake(MAX(1.0, floor(size.width * scale)),
                                   MAX(1.0, floor(size.height * scale)));
        working = TGPhotoImageScaledToSize(working, fitted);
    }

    // Start at 1.0 (no extra compression loss) and lower the quality only when
    // the data would exceed the 10 MB limit.
    static const CGFloat qualities[] = {1.0, 0.95, 0.9, 0.85, 0.8, 0.72, 0.64, 0.56, 0.5};
    NSData *jpeg = nil;
    for (size_t index = 0; index < sizeof(qualities) / sizeof(qualities[0]); index++) {
        jpeg = UIImageJPEGRepresentation(working, qualities[index]);
        if (jpeg.length > 0 && jpeg.length <= TGPhotoMaxBytes) {
            return jpeg;
        }
    }

    // Very large photos: keep the resolution as high as the 10 MB cap allows.
    UIImage *scaled = working;
    for (NSInteger attempt = 0; attempt < 8; attempt++) {
        CGSize currentSize = scaled.size;
        CGSize smaller = CGSizeMake(MAX(1.0, floor(currentSize.width * 0.85)),
                                    MAX(1.0, floor(currentSize.height * 0.85)));
        scaled = TGPhotoImageScaledToSize(scaled, smaller);
        jpeg = UIImageJPEGRepresentation(scaled, 0.9);
        if (jpeg.length > 0 && jpeg.length <= TGPhotoMaxBytes) {
            return jpeg;
        }
    }
    return UIImageJPEGRepresentation(working, 0.5);
}

NSData *TGMaximumQualityJPEGForImageData(NSData *data, NSString *uti) {
    if (data.length == 0) {
        return nil;
    }
    CGSize pixelSize = TGPhotoPixelSizeForImageData(data);
    BOOL isJPEG = TGPhotoUTIIsJPEG(uti) || TGPhotoDataLooksLikeJPEG(data);
    if (isJPEG && TGPhotoDataFitsServerLimits(data, pixelSize)) {
        // Untouched original: full resolution, no generational quality loss.
        return data;
    }
    UIImage *image = [UIImage imageWithData:data];
    if (image == nil) {
        TGXLogLine(@"photo: cannot decode %lu bytes (uti=%@, %.0fx%.0f)",
                   (unsigned long)data.length, uti, pixelSize.width, pixelSize.height);
        return nil;
    }
    return TGMaximumQualityJPEGForImage(image);
}
