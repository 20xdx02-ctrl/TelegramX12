#import "TGChatPlaceholderViewController.h"

#import "TGLogoView.h"
#import "TGTheme.h"

@interface TGChatPlaceholderViewController ()
@property (nonatomic, strong) TGLogoView *logoView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation TGChatPlaceholderViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)bundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:bundleOrNil];
    if (self) {
        self.title = @"";
        _logoView = [[TGLogoView alloc] initWithFrame:CGRectMake(0, 0, 96, 96)];
        _logoView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_logoView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.text = @"Telegram X 12";
        _titleLabel.font = [TGTheme boldFontOfSize:20.0];
        _titleLabel.textColor = [TGTheme secondaryTextColor];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.text = @"Wybierz czat, aby zacząć rozmowę.";
        _subtitleLabel.font = [TGTheme regularFontOfSize:15.0];
        _subtitleLabel.textColor = [TGTheme secondaryTextColor];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:_subtitleLabel];

        UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_logoView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [_logoView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-48.0],
            [_logoView.widthAnchor constraintEqualToConstant:96.0],
            [_logoView.heightAnchor constraintEqualToConstant:96.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_logoView.bottomAnchor constant:16.0],
            [_titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24.0],

            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:6.0],
            [_subtitleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:32.0],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-32.0]
        ]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithPatternImage:[TGTheme chatWallpaperImage]];
}

@end
