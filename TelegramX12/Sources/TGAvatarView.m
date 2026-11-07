#import "TGAvatarView.h"
#import "TGTheme.h"

@interface TGAvatarView ()
@property (nonatomic, strong) UILabel *initialsLabel;
@end

@implementation TGAvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        _initialsLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _initialsLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _initialsLabel.textAlignment = NSTextAlignmentCenter;
        _initialsLabel.textColor = [UIColor whiteColor];
        _initialsLabel.font = [TGTheme semiboldFontOfSize:22.0];
        [self addSubview:_initialsLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds)) / 2.0;
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    self.initialsLabel.font = [TGTheme semiboldFontOfSize:side * 0.40];
}

- (void)setTitle:(NSString *)title identifier:(int64_t)identifier {
    self.initialsLabel.text = [TGTheme initialsForTitle:title];
    self.backgroundColor = [TGTheme avatarColorForIdentifier:identifier];
}

@end
