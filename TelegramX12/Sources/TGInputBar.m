#import "TGInputBar.h"
#import "TGTheme.h"

@interface TGInputBar () <UITextFieldDelegate>
@property (nonatomic, strong, readwrite) UITextField *textField;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIView *separatorView;
@end

@implementation TGInputBar

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor whiteColor];

        _separatorView = [[UIView alloc] initWithFrame:CGRectZero];
        _separatorView.translatesAutoresizingMaskIntoConstraints = NO;
        _separatorView.backgroundColor = [TGTheme separatorColor];
        [self addSubview:_separatorView];

        _textField = [[UITextField alloc] initWithFrame:CGRectZero];
        _textField.translatesAutoresizingMaskIntoConstraints = NO;
        _textField.placeholder = @"Wiadomość";
        _textField.font = [TGTheme regularFontOfSize:16.0];
        _textField.backgroundColor = [TGTheme inputBackgroundColor];
        _textField.layer.cornerRadius = 18.0;
        _textField.autocorrectionType = UITextAutocorrectionTypeYes;
        _textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
        _textField.returnKeyType = UIReturnKeySend;
        _textField.delegate = self;
        UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 36)];
        _textField.leftView = padding;
        _textField.leftViewMode = UITextFieldViewModeAlways;
        [_textField addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
        [self addSubview:_textField];

        _sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
        _sendButton.backgroundColor = [TGTheme accentColor];
        _sendButton.layer.cornerRadius = 18.0;
        _sendButton.titleLabel.font = [TGTheme boldFontOfSize:19.0];
        [_sendButton setTitle:@"↑" forState:UIControlStateNormal];
        [_sendButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _sendButton.accessibilityLabel = @"Wyślij";
        [_sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_sendButton];

        [NSLayoutConstraint activateConstraints:@[
            [_separatorView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_separatorView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_separatorView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_separatorView.heightAnchor constraintEqualToConstant:0.5],

            [_textField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [_textField.topAnchor constraintEqualToAnchor:self.topAnchor constant:7.0],
            [_textField.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-7.0],
            [_textField.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-8.0],

            [_sendButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10.0],
            [_sendButton.centerYAnchor constraintEqualToAnchor:_textField.centerYAnchor],
            [_sendButton.widthAnchor constraintEqualToConstant:36.0],
            [_sendButton.heightAnchor constraintEqualToConstant:36.0]
        ]];

        [self updateSendButton];
    }
    return self;
}

- (void)textChanged {
    [self updateSendButton];
}

- (void)updateSendButton {
    NSString *trimmed = [self.textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL enabled = trimmed.length > 0;
    self.sendButton.enabled = enabled;
    self.sendButton.alpha = enabled ? 1.0 : 0.45;
}

- (void)sendTapped {
    NSString *text = [self.textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return;
    }
    if (self.onSend != nil) {
        self.onSend(text);
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
}

- (void)clearText {
    self.textField.text = @"";
    [self updateSendButton];
}

- (void)focus {
    [self.textField becomeFirstResponder];
}

@end
