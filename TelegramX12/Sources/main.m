#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <execinfo.h>

#import "TGAppDelegate.h"

static NSString *TGCrashLogPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/app.log"];
}

static void TGWriteCrashRecord(NSString *title, NSString *body) {
    time_t now = time(NULL);
    struct tm tmBuffer;
    localtime_r(&now, &tmBuffer);
    char stamp[40];
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmBuffer);
    NSString *record = [NSString stringWithFormat:@"%s crash: %@\n%@\n\n", stamp, title, body];
    [record writeToFile:TGCrashLogPath()
             atomically:NO
               encoding:NSUTF8StringEncoding
                  error:nil];
    [record writeToFile:@"/tmp/TelegramX12-exception.log"
             atomically:YES
               encoding:NSUTF8StringEncoding
                  error:nil];
}

static void TGUncaughtExceptionHandler(NSException *exception) {
    NSString *details = [NSString stringWithFormat:@"%@\n%@", exception, exception.callStackSymbols];
    TGWriteCrashRecord(@"exception", details);
}

static void TGSignalHandler(int signalValue) {
    void *frames[64];
    int count = backtrace(frames, 64);
    char **symbols = backtrace_symbols(frames, count);
    NSMutableString *stack = [NSMutableString stringWithCapacity:count * 48];
    for (int i = 0; i < count; i++) {
        [stack appendFormat:@"  %s\n", symbols[i]];
    }
    free(symbols);
    TGWriteCrashRecord([NSString stringWithFormat:@"signal %d", signalValue], stack);
    // Restore the default disposition so the process still terminates with
    // the signal the system expects to see in crash reports.
    signal(signalValue, SIG_DFL);
    raise(signalValue);
}

static void TGInstallCrashLogging(void) {
    NSSetUncaughtExceptionHandler(&TGUncaughtExceptionHandler);
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = &TGSignalHandler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = SA_RESTART;
    sigaction(SIGABRT, &action, NULL);
    sigaction(SIGSEGV, &action, NULL);
    sigaction(SIGBUS, &action, NULL);
    sigaction(SIGILL, &action, NULL);
    sigaction(SIGFPE, &action, NULL);
    sigaction(SIGTRAP, &action, NULL);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        TGInstallCrashLogging();
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([TGAppDelegate class]));
    }
}
