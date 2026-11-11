#import "TGTheme.h"

@implementation UIColor (TelegramX12)

+ (UIColor *)tg_colorWithHex:(uint32_t)hex {
    return [self tg_colorWithHex:hex alpha:1.0];
}

+ (UIColor *)tg_colorWithHex:(uint32_t)hex alpha:(CGFloat)alpha {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

@end

@implementation TGTheme

+ (UIColor *)accentColor {
    return [UIColor tg_colorWithHex:0x2AABEE];
}

+ (UIColor *)accentPressedColor {
    return [UIColor tg_colorWithHex:0x1E96D6];
}

+ (UIColor *)outgoingBubbleColor {
    return [UIColor tg_colorWithHex:0x2AABEE];
}

+ (UIColor *)incomingBubbleColor {
    return [UIColor tg_colorWithHex:0xEFEFF1];
}

+ (UIColor *)secondaryTextColor {
    return [UIColor tg_colorWithHex:0x8E8E93];
}

+ (UIColor *)separatorColor {
    return [UIColor tg_colorWithHex:0xD1D1D6];
}

+ (UIColor *)inputBackgroundColor {
    return [UIColor tg_colorWithHex:0xF2F2F7];
}

+ (UIColor *)dangerColor {
    return [UIColor tg_colorWithHex:0xFF3B30];
}

+ (UIColor *)chatBackgroundColor {
    return [UIColor tg_colorWithHex:0xDEDEE2];
}

+ (UIColor *)groupedBackgroundColor {
    return [UIColor tg_colorWithHex:0xF2F2F7];
}

+ (UIFont *)regularFontOfSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size];
}

+ (UIFont *)mediumFontOfSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

+ (UIFont *)semiboldFontOfSize:(CGFloat)size {
    return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

+ (UIFont *)boldFontOfSize:(CGFloat)size {
    return [UIFont boldSystemFontOfSize:size];
}

+ (NSString *)timeStringForTimestamp:(int32_t)timestamp {
    if (timestamp <= 0) {
        return @"";
    }
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"pl_PL"];
        formatter.dateFormat = @"HH:mm";
    });
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    return [formatter stringFromDate:date];
}

+ (NSString *)chatListTimeStringForTimestamp:(int32_t)timestamp {
    if (timestamp <= 0) {
        return @"";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) {
        return [self timeStringForTimestamp:timestamp];
    }
    if ([calendar isDateInYesterday:date]) {
        return @"wczoraj";
    }
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"pl_PL"];
        formatter.dateFormat = @"dd.MM.yy";
    });
    return [formatter stringFromDate:date];
}

+ (NSString *)chatDayHeadingStringForTimestamp:(int32_t)timestamp {
    if (timestamp <= 0) {
        return @"";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    if ([calendar isDateInToday:date]) {
        return @"Dziś";
    }
    if ([calendar isDateInYesterday:date]) {
        return @"Wczoraj";
    }
    NSDateComponents *today = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth
                                          fromDate:[NSDate date]];
    NSDateComponents *then = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth
                                         fromDate:date];
    static dispatch_once_t onceToken;
    static NSDateFormatter *dayFormatter;
    dispatch_once(&onceToken, ^{
        dayFormatter = [[NSDateFormatter alloc] init];
        dayFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"pl_PL"];
    });
    if ([today year] == [then year] && [today month] == [then month]) {
        dayFormatter.dateFormat = @"d MMMM";
    } else if ([today year] == [then year]) {
        dayFormatter.dateFormat = @"d MMMM";
    } else {
        dayFormatter.dateFormat = @"d MMMM yyyy";
    }
    return [dayFormatter stringFromDate:date];
}

+ (NSString *)initialsForTitle:(NSString *)title {
    NSString *trimmed = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return @"?";
    }
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableString *result = [NSMutableString string];
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        [result appendString:[part substringToIndex:1]];
        if (result.length == 2) {
            break;
        }
    }
    return [result uppercaseStringWithLocale:[NSLocale currentLocale]];
}

+ (UIColor *)avatarColorForIdentifier:(int64_t)identifier {
    static NSArray<NSNumber *> *colors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        colors = @[
            @0xE17076, @0x7BC862, @0xE5CA77, @0xFAA774,
            @0x8D77AB, @0x65AADD, @0xE38F9E, @0x6EC9CB
        ];
    });
    NSUInteger index = (NSUInteger)(identifier < 0 ? -identifier : identifier) % colors.count;
    return [UIColor tg_colorWithHex:[colors[index] unsignedIntValue]];
}

+ (UIColor *)senderColorForIdentifier:(int64_t)identifier {
    static NSArray<NSNumber *> *colors;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Slightly deeper tones so 12pt names stay readable on white.
        colors = @[
            @0xD9524F, @0x3E9E4F, @0xB88A00, @0xC56A1E,
            @0x7A5AB8, @0x2F7FBF, @0xC2467A, @0x3A9A9C
        ];
    });
    NSUInteger index = (NSUInteger)(identifier < 0 ? -identifier : identifier) % colors.count;
    return [UIColor tg_colorWithHex:[colors[index] unsignedIntValue]];
}

+ (UIColor *)linkColor {
    return [UIColor tg_colorWithHex:0x1A7FD4];
}

+ (UIColor *)outgoingLinkColor {
    return [UIColor tg_colorWithHex:0xCDEFFF];
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
                                           font:(UIFont *)font
                                          color:(UIColor *)color
                                      linkColor:(UIColor *)linkColor {
    if (text.length == 0) {
        return [[NSAttributedString alloc] initWithString:@""];
    }
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange fullRange = NSMakeRange(0, text.length);
    [attributed addAttributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color
    } range:fullRange];

    static NSDataDetector *detector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    });
    if (detector != nil) {
        [detector enumerateMatchesInString:text
                                   options:0
                                     range:fullRange
                                usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            if (result.range.location == NSNotFound || result.URL == nil) {
                return;
            }
            [attributed addAttributes:@{
                NSForegroundColorAttributeName: linkColor,
                NSLinkAttributeName: result.URL
            } range:result.range];
        }];
    }
    return attributed;
}

+ (BOOL)isRTL {
    return [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
}

@end
