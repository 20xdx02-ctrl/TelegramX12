#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "TGAppDelegate.h"

static void TGLogUncaughtException(NSException *exception) {
    NSString *details = [NSString stringWithFormat:@"%@\n%@\n", exception, exception.callStackSymbols];
    [details writeToFile:@"/tmp/TelegramX12-exception.log"
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&TGLogUncaughtException);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([TGAppDelegate class]));
    }
}
