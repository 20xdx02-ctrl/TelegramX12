#import "TGLog.h"

#import <QuartzCore/QuartzCore.h>

static CFTimeInterval TGLaunchStartTime = 0.0;

void TGLaunchBegin(void) {
    TGLaunchStartTime = CACurrentMediaTime();
}

double TGLaunchElapsedMilliseconds(void) {
    if (TGLaunchStartTime <= 0.0) {
        return 0.0;
    }
    return (CACurrentMediaTime() - TGLaunchStartTime) * 1000.0;
}

void TGXLogLine(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[TGX] %@", message);

    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (documents.length == 0) {
        return;
    }
    NSString *path = [documents stringByAppendingPathComponent:@"app.log"];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    @synchronized (path) {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle == nil) {
            [data writeToFile:path atomically:YES];
        } else {
            @try {
                [handle seekToEndOfFile];
                [handle writeData:data];
            } @catch (__unused NSException *exception) {
            }
            [handle closeFile];
        }
    }
}
