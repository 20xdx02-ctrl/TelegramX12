#import "TGLoginViewController.h"

#import "TGConfig.h"
#import "TGLogoView.h"
#import "TGModels.h"
#import "TGSettingsViewController.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"

typedef NS_ENUM(NSInteger, TGLoginStep) {
    TGLoginStepTdlibParameters,
    TGLoginStepPhone,
    TGLoginStepCode,
    TGLoginStepPassword,
    TGLoginStepRegistration,
    TGLoginStepTerms,
    TGLoginStepOther
};

@interface TGLoginViewController () <UITextFieldDelegate>

@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) NSDictionary *state;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *formStack;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;
@property (nonatomic, strong) UITextField *countryField;
@property (nonatomic, strong) UITextField *phoneField;
@property (nonatomic, strong) UITextField *codeField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *firstNameField;
@property (nonatomic, strong) UITextField *lastNameField;
@property (nonatomic, strong) UILabel *fieldHintLabel;
@property (nonatomic) TGLoginStep step;
@property (nonatomic, copy) NSString *lastPhoneNumber;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL didFocusOnce;

@end

@implementation TGLoginViewController

- (instancetype)initWithClient:(TGTDLibClient *)client {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _client = client;
        _step = TGLoginStepTdlibParameters;
        _lastPhoneNumber = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    [self buildLayout];
    [self registerForKeyboardNotifications];

    if (self.state != nil) {
        [self renderState];
    } else {
        [self renderStep:TGLoginStepTdlibParameters];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.didFocusOnce) {
        self.didFocusOnce = YES;
        [self focusCurrentField];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleDefault;
}

#pragma mark - Layout

- (void)buildLayout {
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectZero];
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:contentView];

    UIStackView *rootStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.axis = UILayoutConstraintAxisVertical;
    rootStack.alignment = UIStackViewAlignmentFill;
    rootStack.spacing = 0;
    [contentView addSubview:rootStack];

    UIView *logoContainer = [[UIView alloc] initWithFrame:CGRectZero];
    logoContainer.translatesAutoresizingMaskIntoConstraints = NO;
    TGLogoView *logo = [[TGLogoView alloc] initWithFrame:CGRectZero];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    [logoContainer addSubview:logo];
    [rootStack addArrangedSubview:logoContainer];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = @"Telegram X 12";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = [UIColor blackColor];
    titleLabel.font = [TGTheme boldFontOfSize:30.0];
    [rootStack addArrangedSubview:titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.text = @"Nowoczesny klient Telegrama dla iOS 12";
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.textColor = [TGTheme secondaryTextColor];
    self.subtitleLabel.font = [TGTheme regularFontOfSize:15.0];
    self.subtitleLabel.numberOfLines = 0;
    [rootStack addArrangedSubview:self.subtitleLabel];

    UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer.heightAnchor constraintEqualToConstant:26.0].active = YES;
    [rootStack addArrangedSubview:spacer];

    self.formStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.formStack.axis = UILayoutConstraintAxisVertical;
    self.formStack.alignment = UIStackViewAlignmentFill;
    self.formStack.spacing = 12.0;
    [rootStack addArrangedSubview:self.formStack];

    self.errorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.errorLabel.textColor = [TGTheme dangerColor];
    self.errorLabel.font = [TGTheme regularFontOfSize:14.0];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.hidden = YES;
    [rootStack addArrangedSubview:self.errorLabel];

    UIView *footerSpacer = [[UIView alloc] initWithFrame:CGRectZero];
    [footerSpacer.heightAnchor constraintEqualToConstant:24.0].active = YES;
    [rootStack addArrangedSubview:footerSpacer];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    footerLabel.text = @"TDLib 1.8.69 • API 233 • iOS 12+";
    footerLabel.textAlignment = NSTextAlignmentCenter;
    footerLabel.textColor = [TGTheme secondaryTextColor];
    footerLabel.font = [TGTheme regularFontOfSize:12.0];
    [rootStack addArrangedSubview:footerLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],

        [rootStack.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:44.0],
        [rootStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:28.0],
        [rootStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-28.0],
        [rootStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-28.0],

        [logoContainer.heightAnchor constraintEqualToConstant:110.0],
        [logo.centerXAnchor constraintEqualToAnchor:logoContainer.centerXAnchor],
        [logo.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [logo.widthAnchor constraintEqualToConstant:96.0],
        [logo.heightAnchor constraintEqualToConstant:96.0]
    ]];
}

- (UITextField *)makeTextFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.font = [TGTheme regularFontOfSize:17.0];
    field.textColor = [UIColor blackColor];
    field.backgroundColor = [TGTheme inputBackgroundColor];
    field.layer.cornerRadius = 10.0;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.delegate = self;
    UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 50)];
    field.leftView = padding;
    field.leftViewMode = UITextFieldViewModeAlways;
    [field.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return field;
}

- (UIButton *)makePrimaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [TGTheme accentColor];
    button.layer.cornerRadius = 11.0;
    button.titleLabel.font = [TGTheme semiboldFontOfSize:17.0];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button setTitleColor:[[UIColor whiteColor] colorWithAlphaComponent:0.65] forState:UIControlStateDisabled];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:50.0].active = YES;
    return button;
}

- (UIButton *)makeSecondaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.titleLabel.font = [TGTheme regularFontOfSize:15.0];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[TGTheme accentColor] forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:36.0].active = YES;
    return button;
}

- (UILabel *)makeHintLabel {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.textColor = [TGTheme secondaryTextColor];
    label.font = [TGTheme regularFontOfSize:14.0];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

- (void)clearForm {
    for (UIView *view in [self.formStack.arrangedSubviews copy]) {
        [self.formStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    self.primaryButton = nil;
    self.secondaryButton = nil;
    self.countryField = nil;
    self.phoneField = nil;
    self.codeField = nil;
    self.passwordField = nil;
    self.firstNameField = nil;
    self.lastNameField = nil;
}

#pragma mark - State rendering

- (void)applyAuthorizationState:(NSDictionary *)state {
    self.state = state;
    if (self.isViewLoaded) {
        [self renderState];
    }
}

- (void)renderState {
    NSString *type = TGStringValue(self.state[@"@type"]);
    self.busy = NO;
    self.errorLabel.hidden = YES;

    if ([type isEqualToString:@"authorizationStateWaitTdlibParameters"]) {
        if ([TGConfig hasCredentials]) {
            [self renderConnecting];
            [self.client applyCredentialsIfNeeded];
        } else {
            [self renderStep:TGLoginStepTdlibParameters];
        }
        return;
    }
    if ([type isEqualToString:@"authorizationStateWaitPhoneNumber"]) {
        [self renderStep:TGLoginStepPhone];
        return;
    }
    if ([type isEqualToString:@"authorizationStateWaitCode"]) {
        [self renderStep:TGLoginStepCode];
        return;
    }
    if ([type isEqualToString:@"authorizationStateWaitPassword"]) {
        [self renderStep:TGLoginStepPassword];
        return;
    }
    if ([type isEqualToString:@"authorizationStateWaitRegistration"]) {
        [self renderStep:TGLoginStepRegistration];
        return;
    }
    if ([type isEqualToString:@"authorizationStateWaitTermsOfService"]) {
        [self renderStep:TGLoginStepTerms];
        return;
    }
    if ([type isEqualToString:@"authorizationStateWaitOtherDeviceConfirmation"]) {
        [self renderOtherWithTitle:@"Potwierdź logowanie"
                            detail:@"Zaloguj się w oficjalnej aplikacji Telegram na innym urządzeniu, aby zatwierdzić ten klient."];
        return;
    }
    if ([type isEqualToString:@"authorizationStateLoggingOut"]) {
        [self renderOtherWithTitle:@"Wylogowywanie…"
                            detail:@"Trwa zamykanie sesji."];
        return;
    }
    if ([type isEqualToString:@"authorizationStateClosed"]) {
        [self renderOtherWithTitle:@"Sesja zamknięta"
                            detail:@"Uruchom aplikację ponownie, aby się zalogować."];
        return;
    }

    [self renderOtherWithTitle:@"Łączenie z Telegramem…"
                        detail:type.length > 0 ? type : @"Proszę czekać."];
}

- (void)renderConnecting {
    [self clearForm];
    self.step = TGLoginStepOther;

    UILabel *label = [self makeHintLabel];
    label.text = @"Łączenie z Telegramem…";
    [self.formStack addArrangedSubview:label];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [self.formStack addArrangedSubview:spinner];
}

- (void)renderOtherWithTitle:(NSString *)title detail:(NSString *)detail {
    [self clearForm];
    self.step = TGLoginStepOther;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = title;
    titleLabel.font = [TGTheme semiboldFontOfSize:19.0];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 0;
    [self.formStack addArrangedSubview:titleLabel];

    UILabel *detailLabel = [self makeHintLabel];
    detailLabel.text = detail;
    [self.formStack addArrangedSubview:detailLabel];

    if (![TGConfig hasCredentials]) {
        UIButton *settings = [self makePrimaryButtonWithTitle:@"Ustawienia API" action:@selector(openSettings)];
        [self.formStack addArrangedSubview:settings];
        self.primaryButton = settings;
    }
}

- (void)renderStep:(TGLoginStep)step {
    [self clearForm];
    self.step = step;
    self.errorLabel.hidden = YES;

    switch (step) {
        case TGLoginStepTdlibParameters: {
            UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            titleLabel.text = @"Konfiguracja API";
            titleLabel.font = [TGTheme semiboldFontOfSize:19.0];
            titleLabel.textAlignment = NSTextAlignmentCenter;
            [self.formStack addArrangedSubview:titleLabel];

            UILabel *hint = [self makeHintLabel];
            hint.text = @"Ta aplikacja korzysta z TDLib. Aby się zalogować, podaj własny api_id i api_hash z my.telegram.org.";
            [self.formStack addArrangedSubview:hint];

            UIButton *settings = [self makePrimaryButtonWithTitle:@"Otwórz ustawienia API" action:@selector(openSettings)];
            [self.formStack addArrangedSubview:settings];
            self.primaryButton = settings;
            break;
        }
        case TGLoginStepPhone: {
            UILabel *hint = [self makeHintLabel];
            hint.text = @"Podaj numer telefonu powiązany z kontem Telegram.";
            [self.formStack addArrangedSubview:hint];

            UIStackView *phoneRow = [[UIStackView alloc] initWithFrame:CGRectZero];
            phoneRow.axis = UILayoutConstraintAxisHorizontal;
            phoneRow.spacing = 8.0;
            phoneRow.alignment = UIStackViewAlignmentFill;

            self.countryField = [self makeTextFieldWithPlaceholder:@"+48"];
            self.countryField.text = @"+48";
            self.countryField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            self.countryField.textAlignment = NSTextAlignmentCenter;
            [self.countryField.widthAnchor constraintEqualToConstant:76.0].active = YES;

            self.phoneField = [self makeTextFieldWithPlaceholder:@"600 000 000"];
            self.phoneField.keyboardType = UIKeyboardTypePhonePad;

            [phoneRow addArrangedSubview:self.countryField];
            [phoneRow addArrangedSubview:self.phoneField];
            [self.formStack addArrangedSubview:phoneRow];

            UIButton *next = [self makePrimaryButtonWithTitle:@"Dalej" action:@selector(submitPhone)];
            [self.formStack addArrangedSubview:next];
            self.primaryButton = next;

            UIButton *settings = [self makeSecondaryButtonWithTitle:@"Ustawienia API" action:@selector(openSettings)];
            [self.formStack addArrangedSubview:settings];
            self.secondaryButton = settings;
            break;
        }
        case TGLoginStepCode: {
            NSDictionary *codeInfo = self.state[@"code_info"];
            UILabel *hint = [self makeHintLabel];
            hint.text = [self codeHintForInfo:codeInfo];
            [self.formStack addArrangedSubview:hint];

            self.codeField = [self makeTextFieldWithPlaceholder:@"Kod"];
            self.codeField.keyboardType = UIKeyboardTypeNumberPad;
            self.codeField.textAlignment = NSTextAlignmentCenter;
            self.codeField.font = [TGTheme semiboldFontOfSize:24.0];
            [self.formStack addArrangedSubview:self.codeField];

            UIButton *next = [self makePrimaryButtonWithTitle:@"Zaloguj" action:@selector(submitCode)];
            [self.formStack addArrangedSubview:next];
            self.primaryButton = next;

            UIButton *change = [self makeSecondaryButtonWithTitle:@"Zmień numer telefonu" action:@selector(changePhoneNumber)];
            [self.formStack addArrangedSubview:change];
            self.secondaryButton = change;
            break;
        }
        case TGLoginStepPassword: {
            NSString *hintText = @"To konto jest chronione hasłem dwuetapowym.";
            NSString *passwordHint = TGStringValue(self.state[@"password_hint"]);
            if (passwordHint.length > 0) {
                hintText = [hintText stringByAppendingFormat:@"\nWskazówka: %@", passwordHint];
            }
            UILabel *hint = [self makeHintLabel];
            hint.text = hintText;
            [self.formStack addArrangedSubview:hint];

            self.passwordField = [self makeTextFieldWithPlaceholder:@"Hasło"];
            self.passwordField.secureTextEntry = YES;
            self.passwordField.returnKeyType = UIReturnKeyGo;
            [self.formStack addArrangedSubview:self.passwordField];

            UIButton *next = [self makePrimaryButtonWithTitle:@"Zaloguj" action:@selector(submitPassword)];
            [self.formStack addArrangedSubview:next];
            self.primaryButton = next;

            UIButton *change = [self makeSecondaryButtonWithTitle:@"Zmień numer telefonu" action:@selector(changePhoneNumber)];
            [self.formStack addArrangedSubview:change];
            self.secondaryButton = change;
            break;
        }
        case TGLoginStepRegistration: {
            UILabel *hint = [self makeHintLabel];
            hint.text = @"Ten numer nie ma jeszcze konta Telegram. Utwórz je, podając imię i nazwisko.";
            [self.formStack addArrangedSubview:hint];

            self.firstNameField = [self makeTextFieldWithPlaceholder:@"Imię"];
            self.firstNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
            [self.formStack addArrangedSubview:self.firstNameField];

            self.lastNameField = [self makeTextFieldWithPlaceholder:@"Nazwisko (opcjonalnie)"];
            self.lastNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
            [self.formStack addArrangedSubview:self.lastNameField];

            UIButton *next = [self makePrimaryButtonWithTitle:@"Utwórz konto" action:@selector(submitRegistration)];
            [self.formStack addArrangedSubview:next];
            self.primaryButton = next;
            break;
        }
        case TGLoginStepTerms: {
            UILabel *hint = [self makeHintLabel];
            hint.text = @"Zaakceptuj warunki korzystania z usługi Telegram, aby kontynuować.";
            [self.formStack addArrangedSubview:hint];

            NSDictionary *terms = self.state[@"terms_of_service"];
            NSString *text = TGStringValue(terms[@"text"][@"text"]);
            if (text.length > 0) {
                UILabel *termsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
                termsLabel.text = text;
                termsLabel.font = [TGTheme regularFontOfSize:13.0];
                termsLabel.textColor = [TGTheme secondaryTextColor];
                termsLabel.numberOfLines = 0;
                [self.formStack addArrangedSubview:termsLabel];
            }

            UIButton *next = [self makePrimaryButtonWithTitle:@"Akceptuję" action:@selector(submitTerms)];
            [self.formStack addArrangedSubview:next];
            self.primaryButton = next;
            break;
        }
        default:
            break;
    }

    [self focusCurrentField];
}

- (NSString *)codeHintForInfo:(NSDictionary *)codeInfo {
    NSDictionary *codeType = codeInfo[@"type"];
    NSString *type = TGStringValue(codeType[@"@type"]);
    NSString *phone = TGStringValue(codeInfo[@"phone_number"]);
    if (phone.length == 0) {
        phone = self.lastPhoneNumber;
    }

    if ([type isEqualToString:@"authenticationCodeTypeTelegramMessage"]) {
        return [NSString stringWithFormat:@"Wysłaliśmy kod w aplikacji Telegram na numer %@.", phone];
    }
    if ([type isEqualToString:@"authenticationCodeTypeSms"]) {
        return [NSString stringWithFormat:@"Wysłaliśmy kod SMS-em na numer %@.", phone];
    }
    if ([type isEqualToString:@"authenticationCodeTypeCall"]) {
        return [NSString stringWithFormat:@"Dzwonimy do Ciebie z kodem na numer %@.", phone];
    }
    if ([type isEqualToString:@"authenticationCodeTypeFlashCall"]) {
        return [NSString stringWithFormat:@"Połączymy się z numerem %@, aby odczytać kod.", phone];
    }
    if ([type isEqualToString:@"authenticationCodeTypeMissedCall"]) {
        return [NSString stringWithFormat:@"Otrzymasz połączenie na numer %@ z kodem w numerze dzwoniącego.", phone];
    }
    return [NSString stringWithFormat:@"Wpisz kod wysłany na numer %@.", phone];
}

- (void)focusCurrentField {
    if (!self.isViewLoaded || self.view.window == nil) {
        return;
    }
    UITextField *field = nil;
    switch (self.step) {
        case TGLoginStepPhone:
            field = self.phoneField;
            break;
        case TGLoginStepCode:
            field = self.codeField;
            break;
        case TGLoginStepPassword:
            field = self.passwordField;
            break;
        case TGLoginStepRegistration:
            field = self.firstNameField;
            break;
        default:
            break;
    }
    if (field != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [field becomeFirstResponder];
        });
    }
}

#pragma mark - Actions

- (void)submitPhone {
    if (![TGConfig hasCredentials]) {
        [self showError:@"Najpierw skonfiguruj api_id i api_hash."];
        [self openSettings];
        return;
    }

    NSString *country = [self digitsFromString:self.countryField.text];
    NSString *phone = [self digitsFromString:self.phoneField.text];
    if (phone.length == 0) {
        [self showError:@"Wpisz numer telefonu."];
        return;
    }

    NSString *fullNumber = nil;
    if ([self.phoneField.text hasPrefix:@"+"]) {
        fullNumber = [@"+" stringByAppendingString:phone];
    } else {
        if (country.length == 0) {
            country = @"48";
        }
        fullNumber = [NSString stringWithFormat:@"+%@%@", country, phone];
    }

    if (fullNumber.length < 8) {
        [self showError:@"Numer telefonu jest za krótki."];
        return;
    }

    self.lastPhoneNumber = fullNumber;
    [self setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [self.client sendPhoneNumber:fullNumber completion:^(NSDictionary *response) {
        [weakSelf handleResponse:response];
    }];
}

- (void)submitCode {
    NSString *code = [self digitsFromString:self.codeField.text];
    if (code.length < 3) {
        [self showError:@"Wpisz kod z wiadomości."];
        return;
    }
    [self setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [self.client sendAuthenticationCode:code completion:^(NSDictionary *response) {
        [weakSelf handleResponse:response];
    }];
}

- (void)submitPassword {
    NSString *password = self.passwordField.text ?: @"";
    if (password.length == 0) {
        [self showError:@"Wpisz hasło dwuetapowe."];
        return;
    }
    [self setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [self.client sendPassword:password completion:^(NSDictionary *response) {
        [weakSelf handleResponse:response];
    }];
}

- (void)submitRegistration {
    NSString *firstName = [self.firstNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (firstName.length == 0) {
        [self showError:@"Wpisz imię."];
        return;
    }
    NSString *lastName = [self.lastNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [self.client registerFirstName:firstName lastName:lastName completion:^(NSDictionary *response) {
        [weakSelf handleResponse:response];
    }];
}

- (void)submitTerms {
    NSDictionary *terms = self.state[@"terms_of_service"];
    NSString *termsId = TGStringValue(terms[@"id"]);
    if (termsId.length == 0) {
        [self showError:@"Nie udało się odczytać identyfikatora regulaminu."];
        return;
    }
    [self setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [self.client acceptTermsOfServiceWithId:termsId completion:^(NSDictionary *response) {
        [weakSelf handleResponse:response];
    }];
}

- (void)changePhoneNumber {
    [self renderStep:TGLoginStepPhone];
    if (self.lastPhoneNumber.length > 1) {
        NSString *withoutPlus = [self.lastPhoneNumber substringFromIndex:1];
        if ([withoutPlus hasPrefix:@"48"] && withoutPlus.length > 2) {
            self.countryField.text = @"+48";
            self.phoneField.text = [withoutPlus substringFromIndex:2];
        } else {
            self.countryField.text = @"";
            self.phoneField.text = self.lastPhoneNumber;
        }
    }
}

- (void)openSettings {
    [self dismissKeyboard];
    TGSettingsViewController *settings = [[TGSettingsViewController alloc] initWithClient:self.client];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak typeof(self) weakSelf = self;
    settings.onDismiss = ^{
        [weakSelf.client applyCredentialsIfNeeded];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf renderState];
        });
    };
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)handleResponse:(NSDictionary *)response {
    if ([TGStringValue(response[@"@type"]) isEqualToString:@"error"]) {
        [self setBusy:NO];
        [self showError:[self localizedError:response]];
        return;
    }
    // The authorization state update will re-render the screen.
}

- (NSString *)localizedError:(NSDictionary *)error {
    NSString *message = TGStringValue(error[@"message"]);
    if ([message hasPrefix:@"FLOOD_WAIT_"]) {
        return @"Zbyt wiele prób. Odczekaj chwilę i spróbuj ponownie.";
    }
    if ([message isEqualToString:@"PHONE_NUMBER_INVALID"]) {
        return @"Nieprawidłowy numer telefonu.";
    }
    if ([message isEqualToString:@"PHONE_CODE_INVALID"]) {
        return @"Nieprawidłowy kod.";
    }
    if ([message isEqualToString:@"PHONE_CODE_EXPIRED"]) {
        return @"Kod wygasł. Poproś o nowy.";
    }
    if ([message isEqualToString:@"PASSWORD_HASH_INVALID"]) {
        return @"Nieprawidłowe hasło dwuetapowe.";
    }
    if ([message isEqualToString:@"API_ID_INVALID"]) {
        return @"Nieprawidłowy api_id lub api_hash.";
    }
    if ([message isEqualToString:@"PHONE_NUMBER_BANNED"]) {
        return @"Ten numer został zablokowany przez Telegram.";
    }
    if ([message isEqualToString:@"PHONE_NUMBER_UNOCCUPIED"]) {
        return @"Ten numer nie ma konta Telegram.";
    }
    if (message.length > 0) {
        return message;
    }
    return @"Wystąpił błąd. Spróbuj ponownie.";
}

- (void)showError:(NSString *)message {
    self.errorLabel.text = message;
    self.errorLabel.hidden = NO;
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.primaryButton.enabled = !busy;
    self.secondaryButton.enabled = !busy;
    if (busy) {
        [self.primaryButton setTitle:@"Proszę czekać…" forState:UIControlStateDisabled];
        self.primaryButton.alpha = 0.7;
    } else {
        self.primaryButton.alpha = 1.0;
    }
}

- (NSString *)digitsFromString:(NSString *)string {
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar character = [string characterAtIndex:i];
        if (character >= '0' && character <= '9') {
            [result appendFormat:@"%C", character];
        }
    }
    return result;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Keyboard

- (void)registerForKeyboardNotifications {
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

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(converted));
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = overlap + 16.0;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
    [UIView commitAnimations];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    self.scrollView.contentInset = UIEdgeInsetsZero;
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
    [UIView commitAnimations];
}

@end
