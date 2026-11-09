#import "TGInputBar.h"
#import "TGTheme.h"

@interface TGInputBar () <UITextFieldDelegate>
@property (nonatomic, strong, readwrite) UITextField *textField;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIView *separatorView;

// Reply quote strip shown above the text field ("Odpowiedź na …").
@property (nonatomic, strong) UIView *replyContainer;
@property (nonatomic, strong) UIView *replyBarView;
@property (nonatomic, strong) UILabel *replyNameLabel;
@property (nonatomic, strong) UILabel *replyTextLabel;
@property (nonatomic, strong) UIButton *replyCancelButton;
@property (nonatomic, strong) NSLayoutConstraint *replyHeightConstraint;
@property (nonatomic) BOOL replyVisible;
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

        _attachButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _attachButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_attachButton setTitle:@"📎" forState:UIControlStateNormal];
        _attachButton.titleLabel.font = [UIFont systemFontOfSize:22.0];
        _attachButton.accessibilityLabel = @"Załącznik";
        [_attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_attachButton];

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

        // Reply quote strip (hidden until the user picks "Odpowiedz").
        _replyContainer = [[UIView alloc] initWithFrame:CGRectZero];
        _replyContainer.translatesAutoresizingMaskIntoConstraints = NO;
        _replyContainer.backgroundColor = [TGTheme inputBackgroundColor];
        _replyContainer.hidden = YES;
        [self addSubview:_replyContainer];

        _replyBarView = [[UIView alloc] initWithFrame:CGRectZero];
        _replyBarView.translatesAutoresizingMaskIntoConstraints = NO;
        _replyBarView.backgroundColor = [TGTheme accentColor];
        _replyBarView.layer.cornerRadius = 1.5;
        [_replyContainer addSubview:_replyBarView];

        _replyNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _replyNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _replyNameLabel.font = [TGTheme semiboldFontOfSize:12.0];
        _replyNameLabel.textColor = [TGTheme accentColor];
        [_replyContainer addSubview:_replyNameLabel];

        _replyTextLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _replyTextLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _replyTextLabel.font = [TGTheme regularFontOfSize:13.0];
        _replyTextLabel.textColor = [TGTheme secondaryTextColor];
        _replyTextLabel.numberOfLines = 1;
        [_replyContainer addSubview:_replyTextLabel];

        _replyCancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _replyCancelButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_replyCancelButton setTitle:@"✕" forState:UIControlStateNormal];
        [_replyCancelButton setTitleColor:[TGTheme secondaryTextColor] forState:UIControlStateNormal];
        _replyCancelButton.titleLabel.font = [UIFont systemFontOfSize:16.0];
        _replyCancelButton.accessibilityLabel = @"Anuluj odpowiedź";
        [_replyCancelButton addTarget:self action:@selector(cancelReplyTapped) forControlEvents:UIControlEventTouchUpInside];
        [_replyContainer addSubview:_replyCancelButton];

        self.replyHeightConstraint = [_replyContainer.heightAnchor constraintEqualToConstant:0.0];

        [NSLayoutConstraint activateConstraints:@[
            [_separatorView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_separatorView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_separatorView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_separatorView.heightAnchor constraintEqualToConstant:0.5],

            [_replyContainer.topAnchor constraintEqualToAnchor:_separatorView.bottomAnchor],
            [_replyContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_replyContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            self.replyHeightConstraint,

            [_replyBarView.leadingAnchor constraintEqualToAnchor:_replyContainer.leadingAnchor constant:12.0],
            [_replyBarView.topAnchor constraintEqualToAnchor:_replyContainer.topAnchor constant:6.0],
            [_replyBarView.bottomAnchor constraintEqualToAnchor:_replyContainer.bottomAnchor constant:-6.0],
            [_replyBarView.widthAnchor constraintEqualToConstant:3.0],

            [_replyNameLabel.leadingAnchor constraintEqualToAnchor:_replyBarView.trailingAnchor constant:8.0],
            [_replyNameLabel.topAnchor constraintEqualToAnchor:_replyContainer.topAnchor constant:5.0],
            [_replyNameLabel.trailingAnchor constraintEqualToAnchor:_replyCancelButton.leadingAnchor constant:-6.0],
            [_replyNameLabel.heightAnchor constraintEqualToConstant:16.0],

            [_replyTextLabel.leadingAnchor constraintEqualToAnchor:_replyNameLabel.leadingAnchor],
            [_replyTextLabel.topAnchor constraintEqualToAnchor:_replyNameLabel.bottomAnchor constant:1.0],
            [_replyTextLabel.trailingAnchor constraintEqualToAnchor:_replyNameLabel.trailingAnchor],
            [_replyTextLabel.bottomAnchor constraintLessThanOrEqualToAnchor:_replyContainer.bottomAnchor constant:-5.0],

            [_replyCancelButton.trailingAnchor constraintEqualToAnchor:_replyContainer.trailingAnchor constant:-10.0],
            [_replyCancelButton.centerYAnchor constraintEqualToAnchor:_replyContainer.centerYAnchor],
            [_replyCancelButton.widthAnchor constraintEqualToConstant:28.0],
            [_replyCancelButton.heightAnchor constraintEqualToConstant:28.0],

            [_attachButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0],
            [_attachButton.centerYAnchor constraintEqualToAnchor:_textField.centerYAnchor],
            [_attachButton.widthAnchor constraintEqualToConstant:32.0],
            [_attachButton.heightAnchor constraintEqualToConstant:32.0],

            [_textField.leadingAnchor constraintEqualToAnchor:_attachButton.trailingAnchor constant:6.0],
            [_textField.topAnchor constraintEqualToAnchor:_replyContainer.bottomAnchor constant:7.0],
            [_textField.heightAnchor constraintEqualToConstant:36.0],
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

- (CGFloat)preferredHeight {
    return 50.0 + (self.replyVisible ? 44.0 : 0.0);
}

- (void)showReplyToName:(NSString *)name text:(NSString *)text {
    self.replyVisible = YES;
    _replyContainer.hidden = NO;
    _replyNameLabel.text = name.length > 0 ? name : @"Odpowiedź";
    _replyTextLabel.text = text.length > 0 ? text : @"Wiadomość";
    self.replyHeightConstraint.constant = 44.0;
}

- (void)hideReply {
    self.replyVisible = NO;
    _replyContainer.hidden = YES;
    self.replyHeightConstraint.constant = 0.0;
    _replyNameLabel.text = nil;
    _replyTextLabel.text = nil;
}

- (void)cancelReplyTapped {
    if (self.onCancelReply != nil) {
        self.onCancelReply();
    }
}

- (void)attachTapped {
    if (self.onAttachTap) {
        self.onAttachTap();
    }
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
