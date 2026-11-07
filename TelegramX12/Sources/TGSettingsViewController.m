#import "TGSettingsViewController.h"

#import "TGConfig.h"
#import "TGModels.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"

@interface TGSettingsViewController ()
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextField *apiIdField;
@property (nonatomic, strong) UITextField *apiHashField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL notifiedDismiss;
@end

@implementation TGSettingsViewController

- (instancetype)initWithClient:(TGTDLibClient *)client {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _client = client;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ustawienia";
    self.view.backgroundColor = [TGTheme groupedBackgroundColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Gotowe"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(dismissSelf)];

    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    stack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:stack];

    UILabel *sectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    sectionLabel.text = @"DANE API";
    sectionLabel.font = [TGTheme mediumFontOfSize:12.0];
    sectionLabel.textColor = [TGTheme secondaryTextColor];
    [stack addArrangedSubview:sectionLabel];

    self.apiIdField = [self makeFieldWithPlaceholder:@"api_id (np. 12345678)"];
    self.apiIdField.keyboardType = UIKeyboardTypeNumberPad;
    self.apiIdField.text = [TGConfig apiId] > 0 ? [NSString stringWithFormat:@"%d", [TGConfig apiId]] : @"";
    [stack addArrangedSubview:self.apiIdField];

    self.apiHashField = [self makeFieldWithPlaceholder:@"api_hash"];
    self.apiHashField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.apiHashField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.apiHashField.text = [TGConfig apiHash];
    [stack addArrangedSubview:self.apiHashField];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectZero];
    hint.text = @"Własną parę api_id / api_hash otrzymasz bezpłatnie na my.telegram.org, w sekcji „API development tools”. Dane są zapisywane lokalnie w NSUserDefaults.";
    hint.font = [TGTheme regularFontOfSize:13.0];
    hint.textColor = [TGTheme secondaryTextColor];
    hint.numberOfLines = 0;
    [stack addArrangedSubview:hint];

    UIButton *save = [UIButton buttonWithType:UIButtonTypeCustom];
    save.translatesAutoresizingMaskIntoConstraints = NO;
    save.backgroundColor = [TGTheme accentColor];
    save.layer.cornerRadius = 10.0;
    save.titleLabel.font = [TGTheme semiboldFontOfSize:16.0];
    [save setTitle:@"Zapisz dane API" forState:UIControlStateNormal];
    [save setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [save.heightAnchor constraintEqualToConstant:46.0].active = YES;
    [save addTarget:self action:@selector(saveCredentials) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:save];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [TGTheme regularFontOfSize:13.0];
    self.statusLabel.textColor = [TGTheme secondaryTextColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.hidden = YES;
    [stack addArrangedSubview:self.statusLabel];

    if (self.client.isReady) {
        UILabel *accountHeader = [[UILabel alloc] initWithFrame:CGRectZero];
        accountHeader.text = @"KONTO";
        accountHeader.font = [TGTheme mediumFontOfSize:12.0];
        accountHeader.textColor = [TGTheme secondaryTextColor];
        [stack addArrangedSubview:accountHeader];

        UIButton *logout = [UIButton buttonWithType:UIButtonTypeCustom];
        logout.translatesAutoresizingMaskIntoConstraints = NO;
        logout.backgroundColor = [UIColor whiteColor];
        logout.layer.cornerRadius = 10.0;
        logout.titleLabel.font = [TGTheme semiboldFontOfSize:16.0];
        [logout setTitle:@"Wyloguj się" forState:UIControlStateNormal];
        [logout setTitleColor:[TGTheme dangerColor] forState:UIControlStateNormal];
        [logout.heightAnchor constraintEqualToConstant:46.0].active = YES;
        [logout addTarget:self action:@selector(confirmLogout) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:logout];
    }

    UILabel *version = [[UILabel alloc] initWithFrame:CGRectZero];
    version.text = @"Telegram X 12 • TDLib 1.8.69 • iOS 12+";
    version.font = [TGTheme regularFontOfSize:12.0];
    version.textColor = [TGTheme secondaryTextColor];
    version.textAlignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:version];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [stack.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor constant:20.0],
        [stack.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor constant:-20.0],
        [stack.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor constant:-24.0],
        [stack.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor constant:-40.0]
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UITextField *)makeFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.font = [TGTheme regularFontOfSize:16.0];
    field.backgroundColor = [UIColor whiteColor];
    field.layer.cornerRadius = 10.0;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 46)];
    field.leftView = padding;
    field.leftViewMode = UITextFieldViewModeAlways;
    [field.heightAnchor constraintEqualToConstant:46.0].active = YES;
    return field;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed) {
        [self notifyDismiss];
    }
}

- (void)dismissSelf {
    [self.view endEditing:YES];
    [self notifyDismiss];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)notifyDismiss {
    if (self.notifiedDismiss) {
        return;
    }
    self.notifiedDismiss = YES;
    if (self.onDismiss != nil) {
        self.onDismiss();
    }
}

- (void)saveCredentials {
    [self.view endEditing:YES];
    NSString *apiIdText = [self.apiIdField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *hash = [self.apiHashField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSInteger apiId = [apiIdText integerValue];
    if (apiId <= 0) {
        [self showStatus:@"api_id musi być liczbą większą od zera." error:YES];
        return;
    }
    if (hash.length < 8) {
        [self showStatus:@"api_hash wygląda na nieprawidłowy." error:YES];
        return;
    }

    [TGConfig setAPIId:(int)apiId apiHash:hash];
    [self.client applyCredentialsIfNeeded];
    [self showStatus:@"Zapisano. Możesz wrócić do logowania." error:NO];
}

- (void)showStatus:(NSString *)message error:(BOOL)error {
    self.statusLabel.text = message;
    self.statusLabel.textColor = error ? [TGTheme dangerColor] : [TGTheme accentColor];
    self.statusLabel.hidden = NO;
}

- (void)confirmLogout {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Wylogować się?"
                                                                   message:@"Sesja zostanie zakończona, a dane logowania usunięte z TDLib."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Anuluj" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Wyloguj" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf.client logOut];
        [weakSelf dismissSelf];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(converted));
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        UIEdgeInsets insets = self.scrollView.contentInset;
        insets.bottom = overlap;
        self.scrollView.contentInset = insets;
        self.scrollView.scrollIndicatorInsets = insets;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{
        self.scrollView.contentInset = UIEdgeInsetsZero;
        self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }];
}

@end
