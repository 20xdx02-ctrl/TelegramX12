#import "TGChatListCell.h"

#import "TGModels.h"
#import "TGTheme.h"
#import "TGAvatarView.h"

@interface TGChatListCell ()
@property (nonatomic, strong) TGAvatarView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *unreadLabel;
@property (nonatomic, strong) UIView *separatorView;
@property (nonatomic, strong) NSLayoutConstraint *previewTrailingConstraint;
@property (nonatomic, strong) NSLayoutConstraint *unreadWidthConstraint;
@end

@implementation TGChatListCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        self.contentView.backgroundColor = [UIColor whiteColor];

        _avatarView = [[TGAvatarView alloc] initWithFrame:CGRectZero];
        _avatarView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_avatarView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [TGTheme semiboldFontOfSize:17.0];
        _titleLabel.textColor = [UIColor blackColor];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        _previewLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _previewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _previewLabel.font = [TGTheme regularFontOfSize:15.0];
        _previewLabel.textColor = [TGTheme secondaryTextColor];
        _previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_previewLabel];

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.font = [TGTheme regularFontOfSize:12.0];
        _timeLabel.textColor = [TGTheme secondaryTextColor];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_timeLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.contentView addSubview:_timeLabel];

        _unreadLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _unreadLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _unreadLabel.backgroundColor = [TGTheme accentColor];
        _unreadLabel.textColor = [UIColor whiteColor];
        _unreadLabel.font = [TGTheme semiboldFontOfSize:12.0];
        _unreadLabel.textAlignment = NSTextAlignmentCenter;
        _unreadLabel.layer.cornerRadius = 11.0;
        _unreadLabel.clipsToBounds = YES;
        [self.contentView addSubview:_unreadLabel];

        _separatorView = [[UIView alloc] initWithFrame:CGRectZero];
        _separatorView.translatesAutoresizingMaskIntoConstraints = NO;
        _separatorView.backgroundColor = [TGTheme separatorColor];
        [self.contentView addSubview:_separatorView];

        _previewTrailingConstraint = [_previewLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0];
        _unreadWidthConstraint = [_unreadLabel.widthAnchor constraintEqualToConstant:22.0];

        [NSLayoutConstraint activateConstraints:@[
            [_avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_avatarView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatarView.widthAnchor constraintEqualToConstant:54.0],
            [_avatarView.heightAnchor constraintEqualToConstant:54.0],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_avatarView.trailingAnchor constant:12.0],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_timeLabel.leadingAnchor constant:-6.0],

            [_timeLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_timeLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
            [_timeLabel.widthAnchor constraintEqualToConstant:62.0],

            [_previewLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_previewLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3.0],
            _previewTrailingConstraint,
            [_previewLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-9.0],

            [_unreadLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],
            [_unreadLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_unreadLabel.heightAnchor constraintEqualToConstant:22.0],
            _unreadWidthConstraint,

            [_separatorView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:82.0],
            [_separatorView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_separatorView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [_separatorView.heightAnchor constraintEqualToConstant:0.5]
        ]];
    }
    return self;
}

- (void)configureWithChat:(TGChat *)chat {
    [self.avatarView setTitle:chat.title identifier:chat.chatId];
    self.titleLabel.text = chat.title.length > 0 ? chat.title : @"Czat";

    NSString *preview = chat.lastMessageText.length > 0 ? chat.lastMessageText : @"Brak wiadomości";
    if (chat.lastMessageIsOutgoing && chat.lastMessageText.length > 0) {
        preview = [@"Ty: " stringByAppendingString:preview];
    }
    if (chat.isChannel && chat.lastMessageText.length == 0) {
        preview = @"Kanał";
    }
    self.previewLabel.text = preview;
    self.timeLabel.text = [TGTheme chatListTimeStringForTimestamp:chat.lastMessageDate];

    if (chat.unreadCount > 0) {
        self.unreadLabel.hidden = NO;
        self.unreadLabel.text = chat.unreadCount > 99 ? @"99+" : [NSString stringWithFormat:@"%ld", (long)chat.unreadCount];
        self.unreadWidthConstraint.constant = chat.unreadCount > 99 ? 32.0 : 22.0;
        self.previewTrailingConstraint.constant = chat.unreadCount > 99 ? -52.0 : -42.0;
        self.titleLabel.textColor = [UIColor blackColor];
    } else {
        self.unreadLabel.hidden = YES;
        self.previewTrailingConstraint.constant = -16.0;
        self.titleLabel.textColor = [UIColor blackColor];
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.previewLabel.text = nil;
    self.timeLabel.text = nil;
    self.unreadLabel.text = nil;
    self.unreadLabel.hidden = YES;
}

@end
