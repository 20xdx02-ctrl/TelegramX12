#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Appends one timestamped line to `Documents/app.log` (and NSLog). Used for
/// diagnostics on device, where the console is not available.
FOUNDATION_EXPORT void TGXLogLine(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Marks the beginning of the launch; used by the startup timing logs.
FOUNDATION_EXPORT void TGLaunchBegin(void);
FOUNDATION_EXPORT double TGLaunchElapsedMilliseconds(void);

NS_ASSUME_NONNULL_END
