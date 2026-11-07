#import "TGLogoView.h"
#import "TGTheme.h"

@implementation TGLogoView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context == NULL) {
        return;
    }

    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    CGRect circleRect = CGRectMake((CGRectGetWidth(self.bounds) - side) / 2.0,
                                   (CGRectGetHeight(self.bounds) - side) / 2.0,
                                   side, side);

    [[TGTheme accentColor] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:circleRect] fill];

    // Paper plane, expressed in normalized coordinates of the circle.
    CGFloat x = CGRectGetMinX(circleRect);
    CGFloat y = CGRectGetMinY(circleRect);
    CGFloat w = side;
    CGFloat h = side;

    UIBezierPath *plane = [UIBezierPath bezierPath];
    [plane moveToPoint:CGPointMake(x + 0.20 * w, y + 0.53 * h)];
    [plane addLineToPoint:CGPointMake(x + 0.82 * w, y + 0.24 * h)];
    [plane addLineToPoint:CGPointMake(x + 0.64 * w, y + 0.79 * h)];
    [plane addLineToPoint:CGPointMake(x + 0.49 * w, y + 0.60 * h)];
    [plane addLineToPoint:CGPointMake(x + 0.37 * w, y + 0.73 * h)];
    [plane addLineToPoint:CGPointMake(x + 0.38 * w, y + 0.57 * h)];
    [plane addLineToPoint:CGPointMake(x + 0.62 * w, y + 0.35 * h)];
    [plane addLineToPoint:CGPointMake(x + 0.32 * w, y + 0.50 * h)];
    [plane closePath];

    [[UIColor whiteColor] setFill];
    [plane fill];
}

@end
