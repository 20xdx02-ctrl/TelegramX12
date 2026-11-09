#import "TGMessageCell.h"

#import "TGAvatarView.h"
#import "TGModels.h"
#import "TGTheme.h"
#import "TGTDLibClient.h"
#import "TGWebPConverter.h"

static const CGFloat TGMessageCellHorizontalMargin = 12.0;
static const CGFloat TGMessageCellBubblePadding = 12.0;
static const CGFloat TGMessageCellTimeHeight = 12.0;
static const CGFloat TGMessageCellSenderHeight = 14.0;
static const CGFloat TGMessageCellTextSize = 16.0;
static const CGFloat TGMessageCellMaxBubbleWidth = 420.0; // cap bubbles on wide screens (iPad)
static const CGFloat TGMessageCellAvatarSize = 30.0;
static const CGFloat TGMessageCellAvatarGap = 8.0;
static const CGFloat TGMessageCellAvatarSlot = TGMessageCellAvatarSize + TGMessageCellAvatarGap;
static const CGFloat TGMessageCellReplyBlockHeight = 38.0;
static const CGFloat TGMessageCellForwardLineHeight = 17.0;

@interface TGMessageCell ()

@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UILabel *senderLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *serviceLabel;

// Reply quote strip and forward header (M3)
@property (nonatomic, strong) UIView *replyContainer;
@property (nonatomic, strong) UIView *replyBarView;
@property (nonatomic, strong) UILabel *replyNameLabel;
@property (nonatomic, strong) UILabel *replyTextLabel;
@property (nonatomic, strong) UILabel *forwardLabel;

// Media views
@property (nonatomic, strong) UIView *mediaContainer;
@property (nonatomic, strong) UIImageView *mediaImageView;
@property (nonatomic, strong) UILabel *mediaBadgeLabel;
@property (nonatomic, strong) UIView *playButtonView;
@property (nonatomic, strong) UILabel *playTriangleLabel;
@property (nonatomic, strong) UILabel *captionLabel;

// Sticker view
@property (nonatomic, strong) UIImageView *stickerImageView;
@property (nonatomic, strong) UILabel *stickerEmojiLabel;
@property (nonatomic, strong) UIView *stickerTimePill;
@property (nonatomic, strong) UILabel *stickerTimeLabel;

// Unread divider bar (synthetic "Nieprzeczytane" row)
@property (nonatomic, strong) UIView *unreadBarView;
@property (nonatomic, strong) UILabel *unreadBarLabel;

// Author avatar column (incoming messages with sender names)
@property (nonatomic, strong) TGAvatarView *authorAvatarView;

// File / Audio / Extra views
@property (nonatomic, strong) UIView *docIconView;
@property (nonatomic, strong) UILabel *docIconLabel;
@property (nonatomic, strong) UILabel *docTitleLabel;
@property (nonatomic, strong) UILabel *docSubtitleLabel;

@property (nonatomic, strong) TGMessage *message;
@property (nonatomic, weak) TGTDLibClient *client;
@property (nonatomic) BOOL showSender;
@property (nonatomic, copy) NSString *senderName;
@property (nonatomic) BOOL isGroupStart;
@property (nonatomic) int64_t currentMessageId;

@end

@implementation TGMessageCell

+ (CGFloat)bubbleWidthForWidth:(CGFloat)width {
    return MIN(floor(width * 0.78), TGMessageCellMaxBubbleWidth);
}

+ (BOOL)showsAuthorAvatarForMessage:(TGMessage *)message showSender:(BOOL)showSender {
    // Author avatar for every incoming message; showSender only controls the
    // in-bubble name row (groups).
    return !message.isOutgoing && !message.isService && !message.isUnreadDivider;
}

/// Effective max bubble width, shrunk by the avatar column on the incoming
/// side when sender avatars are enabled (groups / supergroups).
+ (CGFloat)bubbleWidthForMessage:(TGMessage *)message width:(CGFloat)width showSender:(BOOL)showSender {
    CGFloat cap = MIN(floor(width * 0.78), TGMessageCellMaxBubbleWidth);
    if ([self showsAuthorAvatarForMessage:message showSender:showSender]) {
        CGFloat available = width - TGMessageCellHorizontalMargin * 2 - TGMessageCellAvatarSlot;
        cap = MIN(cap, MAX(60.0, available));
    }
    return cap;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];

        _bubbleView = [[UIView alloc] initWithFrame:CGRectZero];
        _bubbleView.layer.cornerRadius = 16.0;
        _bubbleView.clipsToBounds = YES;
        [self.contentView addSubview:_bubbleView];

        _senderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _senderLabel.font = [TGTheme semiboldFontOfSize:12.0];
        _senderLabel.numberOfLines = 1;
        [_bubbleView addSubview:_senderLabel];

        _bodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.font = [TGTheme regularFontOfSize:TGMessageCellTextSize];
        [_bubbleView addSubview:_bodyLabel];

        // Reply quote strip: accent bar + sender + one-line preview.
        _replyContainer = [[UIView alloc] initWithFrame:CGRectZero];
        _replyContainer.clipsToBounds = YES;
        _replyContainer.hidden = YES;
        [_bubbleView addSubview:_replyContainer];

        _replyBarView = [[UIView alloc] initWithFrame:CGRectZero];
        [self.replyContainer addSubview:_replyBarView];

        _replyNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _replyNameLabel.font = [TGTheme semiboldFontOfSize:12.0];
        _replyNameLabel.numberOfLines = 1;
        [_replyContainer addSubview:_replyNameLabel];

        _replyTextLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _replyTextLabel.font = [TGTheme regularFontOfSize:13.0];
        _replyTextLabel.numberOfLines = 1;
        [_replyContainer addSubview:_replyTextLabel];

        // Forward header ("Przekazano od …").
        _forwardLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _forwardLabel.font = [TGTheme semiboldFontOfSize:12.0];
        _forwardLabel.numberOfLines = 1;
        _forwardLabel.hidden = YES;
        [_bubbleView addSubview:_forwardLabel];

        // Media Container
        _mediaContainer = [[UIView alloc] initWithFrame:CGRectZero];
        _mediaContainer.clipsToBounds = YES;
        _mediaContainer.layer.cornerRadius = 12.0;
        _mediaContainer.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
        _mediaContainer.userInteractionEnabled = YES;
        [_bubbleView addSubview:_mediaContainer];

        _mediaImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _mediaImageView.contentMode = UIViewContentModeScaleAspectFill;
        _mediaImageView.clipsToBounds = YES;
        [_mediaContainer addSubview:_mediaImageView];

        _mediaBadgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _mediaBadgeLabel.font = [TGTheme semiboldFontOfSize:11.0];
        _mediaBadgeLabel.textColor = [UIColor whiteColor];
        _mediaBadgeLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.6];
        _mediaBadgeLabel.textAlignment = NSTextAlignmentCenter;
        _mediaBadgeLabel.layer.cornerRadius = 4.0;
        _mediaBadgeLabel.clipsToBounds = YES;
        _mediaBadgeLabel.hidden = YES;
        [_mediaContainer addSubview:_mediaBadgeLabel];

        _playButtonView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
        _playButtonView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
        _playButtonView.layer.cornerRadius = 24.0;
        _playButtonView.clipsToBounds = YES;
        _playButtonView.userInteractionEnabled = NO;
        _playButtonView.hidden = YES;
        [_mediaContainer addSubview:_playButtonView];

        _playTriangleLabel = [[UILabel alloc] initWithFrame:_playButtonView.bounds];
        _playTriangleLabel.text = @"▶";
        _playTriangleLabel.textColor = [UIColor whiteColor];
        _playTriangleLabel.font = [UIFont systemFontOfSize:20.0];
        _playTriangleLabel.textAlignment = NSTextAlignmentCenter;
        [_playButtonView addSubview:_playTriangleLabel];

        UITapGestureRecognizer *mediaTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMediaTap)];
        [_mediaContainer addGestureRecognizer:mediaTap];

        _captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _captionLabel.numberOfLines = 0;
        _captionLabel.font = [TGTheme regularFontOfSize:TGMessageCellTextSize];
        [_bubbleView addSubview:_captionLabel];

        // Document / Audio card
        _docIconView = [[UIView alloc] initWithFrame:CGRectZero];
        _docIconView.backgroundColor = [TGTheme accentColor];
        _docIconView.layer.cornerRadius = 20.0;
        _docIconView.clipsToBounds = YES;
        [_bubbleView addSubview:_docIconView];

        _docIconLabel = [[UILabel alloc] initWithFrame:_docIconView.bounds];
        _docIconLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _docIconLabel.textAlignment = NSTextAlignmentCenter;
        _docIconLabel.font = [UIFont systemFontOfSize:20.0];
        [_docIconView addSubview:_docIconLabel];

        _docTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _docTitleLabel.font = [TGTheme semiboldFontOfSize:15.0];
        _docTitleLabel.numberOfLines = 1;
        [_bubbleView addSubview:_docTitleLabel];

        _docSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _docSubtitleLabel.font = [TGTheme regularFontOfSize:12.0];
        _docSubtitleLabel.textColor = [TGTheme secondaryTextColor];
        _docSubtitleLabel.numberOfLines = 1;
        [_bubbleView addSubview:_docSubtitleLabel];

        // Time Label
        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [TGTheme regularFontOfSize:10.0];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_bubbleView addSubview:_timeLabel];

        // Sticker Views (rendered floating without bubble)
        _stickerImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _stickerImageView.contentMode = UIViewContentModeScaleAspectFit;
        _stickerImageView.clipsToBounds = YES;
        _stickerImageView.userInteractionEnabled = YES;
        [self.contentView addSubview:_stickerImageView];

        _stickerEmojiLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _stickerEmojiLabel.font = [UIFont systemFontOfSize:44.0];
        _stickerEmojiLabel.textAlignment = NSTextAlignmentCenter;
        _stickerEmojiLabel.hidden = YES;
        [self.contentView addSubview:_stickerEmojiLabel];

        _stickerTimePill = [[UIView alloc] initWithFrame:CGRectZero];
        _stickerTimePill.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.4];
        _stickerTimePill.layer.cornerRadius = 9.0;
        _stickerTimePill.clipsToBounds = YES;
        [self.contentView addSubview:_stickerTimePill];

        _stickerTimeLabel = [[UILabel alloc] initWithFrame:_stickerTimePill.bounds];
        _stickerTimeLabel.font = [TGTheme regularFontOfSize:10.0];
        _stickerTimeLabel.textColor = [UIColor whiteColor];
        _stickerTimeLabel.textAlignment = NSTextAlignmentCenter;
        [_stickerTimePill addSubview:_stickerTimeLabel];

        UITapGestureRecognizer *stickerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleStickerTap)];
        [_stickerImageView addGestureRecognizer:stickerTap];

        // Service Label
        _serviceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _serviceLabel.font = [TGTheme regularFontOfSize:12.0];
        _serviceLabel.textColor = [TGTheme secondaryTextColor];
        _serviceLabel.textAlignment = NSTextAlignmentCenter;
        _serviceLabel.numberOfLines = 0;
        [self.contentView addSubview:_serviceLabel];

        // Unread divider bar (styled like Telegram X's unread bar)
        _unreadBarView = [[UIView alloc] initWithFrame:CGRectZero];
        _unreadBarView.backgroundColor = [TGTheme accentColor];
        _unreadBarView.layer.cornerRadius = 13.0;
        _unreadBarView.clipsToBounds = YES;
        _unreadBarView.hidden = YES;
        [self.contentView addSubview:_unreadBarView];

        _unreadBarLabel = [[UILabel alloc] initWithFrame:_unreadBarView.bounds];
        _unreadBarLabel.font = [TGTheme semiboldFontOfSize:13.0];
        _unreadBarLabel.textColor = [UIColor whiteColor];
        _unreadBarLabel.textAlignment = NSTextAlignmentCenter;
        _unreadBarLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_unreadBarView addSubview:_unreadBarLabel];

        // Author avatar column on the left of incoming messages.
        _authorAvatarView = [[TGAvatarView alloc] initWithFrame:CGRectMake(0, 0, TGMessageCellAvatarSize, TGMessageCellAvatarSize)];
        _authorAvatarView.hidden = YES;
        [self.contentView addSubview:_authorAvatarView];

        // Cell-level tap: retries failed sends and opens file/audio cards.
        UITapGestureRecognizer *cellTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCellTap)];
        [self.contentView addGestureRecognizer:cellTap];

        // Long press: shows the message action sheet (copy / reply / delete / forward).
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = 0.45;
        [self.contentView addGestureRecognizer:longPress];
    }
    return self;
}

- (void)handleCellTap {
    if (self.message == nil) {
        return;
    }
    if (self.message.isFailed && self.onRetryTap != nil) {
        self.onRetryTap(self.message);
        return;
    }
    // Media containers / stickers have their own tap handlers.
    TGMessageType type = self.message.messageType;
    if (type == TGMessageTypePhoto || type == TGMessageTypeVideo ||
        type == TGMessageTypeAnimation || type == TGMessageTypeSticker) {
        return;
    }
    if (self.onMediaTap != nil) {
        self.onMediaTap(self.message);
    }
}

- (void)handleMediaTap {
    if (self.onMediaTap && self.message != nil) {
        self.onMediaTap(self.message);
    }
}

- (void)handleStickerTap {
    if (self.onStickerTap && self.message != nil) {
        self.onStickerTap(self.message);
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan && self.onLongPress != nil && self.message != nil) {
        self.onLongPress(self.message);
    }
}

- (void)loadAuthorAvatar {
    if (self.client == nil) {
        return;
    }
    NSString *title = self.senderName.length > 0 ? self.senderName : @"?";
    int32_t fileId = 0;
    if (self.message.senderIsUser) {
        NSDictionary *user = [self.client userWithId:self.message.senderId];
        fileId = TGInt32Value(user[@"profile_photo"][@"small"][@"id"]);
    } else {
        NSDictionary *chat = [self.client chatWithId:self.message.senderId];
        fileId = TGInt32Value(chat[@"photo"][@"small"][@"id"]);
    }
    [self.authorAvatarView loadAvatarWithFileId:fileId
                                        client:self.client
                                         title:title
                                    identifier:self.message.senderId];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.currentMessageId = 0;
    self.replyContainer.hidden = YES;
    self.replyNameLabel.text = nil;
    self.replyTextLabel.text = nil;
    self.forwardLabel.hidden = YES;
    self.forwardLabel.text = nil;
    self.mediaImageView.image = nil;
    self.stickerImageView.image = nil;
    self.stickerEmojiLabel.hidden = YES;
    self.mediaBadgeLabel.hidden = YES;
    self.playButtonView.hidden = YES;
    self.bodyLabel.text = nil;
    self.captionLabel.text = nil;
    self.senderLabel.text = nil;
    self.timeLabel.text = nil;
    self.serviceLabel.text = nil;
    self.unreadBarView.hidden = YES;
    self.authorAvatarView.hidden = YES;
    self.docTitleLabel.text = nil;
    self.docSubtitleLabel.text = nil;
}

#pragma mark - Sizing Helpers

+ (CGSize)mediaSizeForMessage:(TGMessage *)message maxBubbleWidth:(CGFloat)maxBubbleWidth {
    CGFloat maxWidth = MIN(maxBubbleWidth, 260.0);
    CGFloat maxHeight = 300.0;

    if (message.messageType == TGMessageTypeSticker) {
        CGFloat size = 160.0;
        if (message.mediaWidth > 0 && message.mediaHeight > 0) {
            CGFloat aspect = message.mediaWidth / message.mediaHeight;
            if (aspect >= 1.0) {
                return CGSizeMake(size, floor(size / aspect));
            } else {
                return CGSizeMake(floor(size * aspect), size);
            }
        }
        return CGSizeMake(size, size);
    }

    if (message.messageType == TGMessageTypePhoto ||
        message.messageType == TGMessageTypeVideo ||
        message.messageType == TGMessageTypeAnimation) {
        if (message.mediaWidth > 0 && message.mediaHeight > 0) {
            CGFloat aspect = message.mediaHeight / message.mediaWidth;
            CGFloat w = maxWidth;
            CGFloat h = floor(w * aspect);
            if (h > maxHeight) {
                h = maxHeight;
                w = floor(h / aspect);
            }
            if (h < 100.0) h = 100.0;
            if (w < 120.0) w = 120.0;
            return CGSizeMake(w, h);
        }
        return CGSizeMake(maxWidth, floor(maxWidth * 0.75));
    }

    if (message.messageType == TGMessageTypeDocument ||
        message.messageType == TGMessageTypeAudio ||
        message.messageType == TGMessageTypeContact ||
        message.messageType == TGMessageTypeLocation) {
        return CGSizeMake(MIN(maxBubbleWidth, 240.0), 48.0);
    }

    if (message.messageType == TGMessageTypeVoiceNote) {
        return CGSizeMake(MIN(maxBubbleWidth, 200.0), 40.0);
    }

    if (message.messageType == TGMessageTypePoll) {
        CGFloat optsHeight = (message.pollOptions.count ?: 2) * 22.0;
        return CGSizeMake(MIN(maxBubbleWidth, 250.0), 30.0 + optsHeight);
    }

    return CGSizeZero;
}

+ (CGSize)textSizeForString:(NSString *)text maxWidth:(CGFloat)maxWidth {
    if (text.length == 0) return CGSizeZero;
    NSDictionary *attributes = @{NSFontAttributeName: [TGTheme regularFontOfSize:TGMessageCellTextSize]};
    CGRect rect = [text boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:attributes
                                     context:nil];
    return CGSizeMake(MIN(maxWidth, ceil(CGRectGetWidth(rect))), MAX(1.0, ceil(CGRectGetHeight(rect))));
}

/// Extra vertical space consumed by the forward header and the reply quote
/// strip above the message content.
+ (CGFloat)replyBlockHeightForMessage:(TGMessage *)message {
    if (message.isService || message.messageType == TGMessageTypeSticker) {
        return 0.0;
    }
    CGFloat height = 0.0;
    if (message.forwardInfo != nil) {
        height += TGMessageCellForwardLineHeight;
    }
    if (message.replyToMessageId > 0) {
        height += TGMessageCellReplyBlockHeight;
    }
    return height;
}

+ (CGFloat)heightForMessage:(TGMessage *)message width:(CGFloat)width showSender:(BOOL)showSender {
    if (message.isUnreadDivider) {
        return 36.0;
    }

    if (message.isService) {
        return 32.0;
    }

    CGFloat maxBubbleWidth = [self bubbleWidthForMessage:message width:width showSender:showSender];
    CGFloat maxTextWidth = MAX(60.0, maxBubbleWidth - TGMessageCellBubblePadding * 2.0);

    // Floating stickers do not use the bubble; height is just the media size.
    if (message.messageType == TGMessageTypeSticker) {
        CGSize stickerSize = [self mediaSizeForMessage:message maxBubbleWidth:maxBubbleWidth];
        return stickerSize.height + 12.0;
    }

    CGFloat senderHeight = (showSender && !message.isOutgoing) ? TGMessageCellSenderHeight : 0.0;
    CGFloat contentHeight = 0.0;
    if (message.messageType == TGMessageTypeText || message.messageType == TGMessageTypeUnsupported) {
        NSString *txt = message.text.length > 0 ? message.text : @"Nieobsługiwana wiadomość";
        CGSize sz = [self textSizeForString:txt maxWidth:maxTextWidth];
        contentHeight = sz.height;
    } else {
        CGSize mediaSize = [self mediaSizeForMessage:message maxBubbleWidth:maxBubbleWidth];
        contentHeight = mediaSize.height;

        if (message.mediaCaption.length > 0) {
            CGSize capSize = [self textSizeForString:message.mediaCaption maxWidth:maxTextWidth];
            contentHeight += 6.0 + capSize.height;
        }
    }

    CGFloat headerHeight = [self replyBlockHeightForMessage:message];
    CGFloat bubbleHeight = 6.0 + headerHeight + senderHeight + contentHeight + 2.0 + TGMessageCellTimeHeight + 6.0;
    return bubbleHeight + 6.0;
}

#pragma mark - Configuration

- (void)configureWithMessage:(TGMessage *)message
                  showSender:(BOOL)showSender
                  senderName:(NSString *)senderName
                isGroupStart:(BOOL)isGroupStart
                      client:(nullable TGTDLibClient *)client {
    self.message = message;
    self.client = client;
    self.showSender = showSender;
    self.senderName = senderName;
    self.isGroupStart = isGroupStart;
    self.currentMessageId = message.messageId;

    if (message.isUnreadDivider) {
        _unreadBarView.hidden = NO;
        _unreadBarLabel.text = message.text.length > 0 ? message.text : @"Nieprzeczytane wiadomości";
        _serviceLabel.hidden = YES;
        _bubbleView.hidden = YES;
        _stickerImageView.hidden = YES;
        _stickerEmojiLabel.hidden = YES;
        _stickerTimePill.hidden = YES;
        _replyContainer.hidden = YES;
        _forwardLabel.hidden = YES;
        [self setNeedsLayout];
        return;
    }

    _unreadBarView.hidden = YES;

    if (message.isService) {
        _serviceLabel.hidden = NO;
        _bubbleView.hidden = YES;
        _stickerImageView.hidden = YES;
        _stickerEmojiLabel.hidden = YES;
        _stickerTimePill.hidden = YES;
        _replyContainer.hidden = YES;
        _forwardLabel.hidden = YES;
        _serviceLabel.text = message.text;
        [self setNeedsLayout];
        return;
    }

    _serviceLabel.hidden = YES;

    if (message.messageType == TGMessageTypeSticker) {
        // Floating Sticker (No Bubble)
        _bubbleView.hidden = YES;
        _stickerImageView.hidden = NO;
        _stickerTimePill.hidden = NO;
        _stickerTimeLabel.text = [self timeTextForMessage:message];
        _replyContainer.hidden = YES;
        _forwardLabel.hidden = YES;

        [self loadStickerForMessage:message client:client];
        [self setNeedsLayout];
        return;
    }

    // Normal message with bubble
    _stickerImageView.hidden = YES;
    _stickerEmojiLabel.hidden = YES;
    _stickerTimePill.hidden = YES;
    _bubbleView.hidden = NO;

    _bubbleView.backgroundColor = message.isOutgoing ? [TGTheme outgoingBubbleColor] : [TGTheme incomingBubbleColor];
    if (@available(iOS 11.0, *)) {
        _bubbleView.layer.cornerRadius = 16.0;
        if (message.isOutgoing) {
            _bubbleView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner;
        } else {
            _bubbleView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
        }
    }
    _bodyLabel.textColor = message.isOutgoing ? [UIColor whiteColor] : [UIColor blackColor];
    _captionLabel.textColor = message.isOutgoing ? [UIColor whiteColor] : [UIColor blackColor];
    _timeLabel.textColor = message.isOutgoing ? [UIColor colorWithWhite:1.0 alpha:0.75] : [TGTheme secondaryTextColor];
    _senderLabel.textColor = message.isOutgoing ? [UIColor colorWithWhite:1.0 alpha:0.9] : [TGTheme accentColor];
    _senderLabel.text = senderName;
    _senderLabel.hidden = !(showSender && !message.isOutgoing);
    _timeLabel.text = [self timeTextForMessage:message];

    // Forward header ("Przekazano od …") and reply quote strip (M3).
    UIColor *headerColor = message.isOutgoing ? [UIColor colorWithWhite:1.0 alpha:0.92] : [TGTheme accentColor];
    if (message.forwardInfo != nil) {
        NSString *originName = [client displayNameForMessageOrigin:message.forwardInfo[@"origin"]];
        _forwardLabel.text = originName.length > 0
            ? [NSString stringWithFormat:@"Przekazano od %@", originName]
            : @"Przekazano wiadomość";
        _forwardLabel.textColor = headerColor;
        _forwardLabel.hidden = NO;
    } else {
        _forwardLabel.text = nil;
        _forwardLabel.hidden = YES;
    }

    if (message.replyToMessageId > 0) {
        _replyNameLabel.text = message.replyToSenderName.length > 0 ? message.replyToSenderName : @"Wiadomość";
        _replyNameLabel.textColor = headerColor;
        _replyTextLabel.text = message.replyToText.length > 0 ? message.replyToText : @"…";
        _replyTextLabel.textColor = message.isOutgoing ? [UIColor colorWithWhite:1.0 alpha:0.82] : [TGTheme secondaryTextColor];
        _replyBarView.backgroundColor = message.isOutgoing ? [UIColor colorWithWhite:1.0 alpha:0.75] : [TGTheme accentColor];
        _replyContainer.hidden = NO;
    } else {
        _replyContainer.hidden = YES;
        _replyNameLabel.text = nil;
        _replyTextLabel.text = nil;
    }

    // Author avatar: visible only on the first message of a sender's consecutive
    // run (isGroupStart). It is pinned to the TOP of the bubble, not the bottom,
    // mirroring the layout used by Telegram X / modern Telegram clients.
    BOOL withAvatar = [[self class] showsAuthorAvatarForMessage:message showSender:showSender] && isGroupStart;
    _authorAvatarView.hidden = !withAvatar;
    if (withAvatar) {
        [self loadAuthorAvatar];
    }

    // Reset visibility of media subviews
    _mediaContainer.hidden = YES;
    _mediaImageView.image = nil;
    _mediaBadgeLabel.hidden = YES;
    _playButtonView.hidden = YES;
    _captionLabel.hidden = YES;
    _docIconView.hidden = YES;
    _docTitleLabel.hidden = YES;
    _docSubtitleLabel.hidden = YES;
    _bodyLabel.hidden = YES;

    switch (message.messageType) {
        case TGMessageTypeText:
        case TGMessageTypeUnsupported: {
            _bodyLabel.hidden = NO;
            _bodyLabel.text = message.text.length > 0 ? message.text : @"Nieobsługiwana wiadomość";
            break;
        }
        case TGMessageTypePhoto: {
            _mediaContainer.hidden = NO;
            if (message.mediaCaption.length > 0) {
                _captionLabel.hidden = NO;
                _captionLabel.text = message.mediaCaption;
            }
            [self loadPhotoForMessage:message client:client];
            break;
        }
        case TGMessageTypeAnimation: {
            _mediaContainer.hidden = NO;
            _mediaBadgeLabel.hidden = NO;
            _mediaBadgeLabel.text = @" GIF ";
            if (message.mediaCaption.length > 0) {
                _captionLabel.hidden = NO;
                _captionLabel.text = message.mediaCaption;
            }
            [self loadAnimationForMessage:message client:client];
            break;
        }
        case TGMessageTypeVideo: {
            _mediaContainer.hidden = NO;
            _playButtonView.hidden = NO;
            if (message.mediaDuration > 0) {
                _mediaBadgeLabel.hidden = NO;
                _mediaBadgeLabel.text = [NSString stringWithFormat:@" %@ ", TGDurationString(message.mediaDuration)];
            }
            if (message.mediaCaption.length > 0) {
                _captionLabel.hidden = NO;
                _captionLabel.text = message.mediaCaption;
            }
            [self loadVideoForMessage:message client:client];
            break;
        }
        case TGMessageTypeVoiceNote: {
            _docIconView.hidden = NO;
            _docIconLabel.text = @"🎤";
            _docTitleLabel.hidden = NO;
            _docTitleLabel.text = @"Wiadomość głosowa";
            _docSubtitleLabel.hidden = NO;
            _docSubtitleLabel.text = TGDurationString(message.mediaDuration);
            break;
        }
        case TGMessageTypeAudio: {
            _docIconView.hidden = NO;
            _docIconLabel.text = @"🎵";
            _docTitleLabel.hidden = NO;
            _docTitleLabel.text = message.mediaTitle.length > 0 ? message.mediaTitle : (message.mediaFileName.length > 0 ? message.mediaFileName : @"Audio");
            _docSubtitleLabel.hidden = NO;
            NSString *sub = message.mediaPerformer.length > 0 ? message.mediaPerformer : @"";
            if (message.mediaFileSize > 0) {
                sub = sub.length > 0 ? [NSString stringWithFormat:@"%@ • %@", sub, TGDataSizeString(message.mediaFileSize)] : TGDataSizeString(message.mediaFileSize);
            }
            _docSubtitleLabel.text = sub;
            break;
        }
        case TGMessageTypeDocument: {
            _docIconView.hidden = NO;
            _docIconLabel.text = @"📎";
            _docTitleLabel.hidden = NO;
            _docTitleLabel.text = message.mediaFileName.length > 0 ? message.mediaFileName : @"Dokument";
            _docSubtitleLabel.hidden = NO;
            _docSubtitleLabel.text = message.mediaFileSize > 0 ? TGDataSizeString(message.mediaFileSize) : @"Plik";
            if (message.mediaCaption.length > 0) {
                _captionLabel.hidden = NO;
                _captionLabel.text = message.mediaCaption;
            }
            break;
        }
        case TGMessageTypeContact: {
            _docIconView.hidden = NO;
            _docIconLabel.text = @"👤";
            _docTitleLabel.hidden = NO;
            _docTitleLabel.text = message.contactName.length > 0 ? message.contactName : @"Kontakt";
            _docSubtitleLabel.hidden = NO;
            _docSubtitleLabel.text = message.contactPhone;
            break;
        }
        case TGMessageTypeLocation: {
            _docIconView.hidden = NO;
            _docIconLabel.text = @"📍";
            _docTitleLabel.hidden = NO;
            _docTitleLabel.text = @"Lokalizacja";
            _docSubtitleLabel.hidden = NO;
            _docSubtitleLabel.text = [NSString stringWithFormat:@"%.4f, %.4f", message.latitude, message.longitude];
            break;
        }
        case TGMessageTypePoll: {
            _docIconView.hidden = NO;
            _docIconLabel.text = @"📊";
            _docTitleLabel.hidden = NO;
            _docTitleLabel.text = message.pollQuestion.length > 0 ? message.pollQuestion : @"Ankieta";
            _docSubtitleLabel.hidden = NO;
            _docSubtitleLabel.text = [NSString stringWithFormat:@"%lu opcji", (unsigned long)message.pollOptions.count];
            break;
        }
        default: {
            _bodyLabel.hidden = NO;
            _bodyLabel.text = message.text;
            break;
        }
    }

    [self setNeedsLayout];
}

#pragma mark - Media Loaders

- (void)loadPhotoForMessage:(TGMessage *)message client:(nullable TGTDLibClient *)client {
    // 0. Locally-available file (pending sends keep the input file path)
    if (message.mediaLocalPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:message.mediaLocalPath]) {
        UIImage *localImage = [UIImage imageWithContentsOfFile:message.mediaLocalPath];
        if (localImage != nil) {
            self.mediaImageView.image = localImage;
            return;
        }
    }

    // 1. Minithumbnail
    if (message.minithumbnailData.length > 0 && self.mediaImageView.image == nil) {
        self.mediaImageView.image = [UIImage imageWithData:message.minithumbnailData];
    }

    int32_t fileId = message.mediaFileId > 0 ? message.mediaFileId : message.thumbnailFileId;
    if (fileId <= 0 || client == nil) return;

    NSString *path = [client localPathForFileId:fileId];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.mediaImageView.image = [UIImage imageWithContentsOfFile:path];
        return;
    }

    int64_t msgId = message.messageId;
    __weak typeof(self) weakSelf = self;
    [client downloadFileWithId:fileId priority:24 completion:^(NSString *downloadedPath, NSDictionary *file) {
        if (weakSelf.currentMessageId == msgId && downloadedPath.length > 0) {
            UIImage *img = [UIImage imageWithContentsOfFile:downloadedPath];
            if (img != nil) {
                [UIView transitionWithView:weakSelf.mediaImageView
                                  duration:0.2
                                   options:UIViewAnimationOptionTransitionCrossDissolve
                                animations:^{ weakSelf.mediaImageView.image = img; }
                                completion:nil];
            }
        }
    }];
}

- (void)loadAnimationForMessage:(TGMessage *)message client:(nullable TGTDLibClient *)client {
    if (message.minithumbnailData.length > 0 && self.mediaImageView.image == nil) {
        self.mediaImageView.image = [UIImage imageWithData:message.minithumbnailData];
    }

    int32_t thumbId = message.thumbnailFileId > 0 ? message.thumbnailFileId : message.mediaFileId;
    if (thumbId <= 0 || client == nil) return;

    NSString *path = [client localPathForFileId:thumbId];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.mediaImageView.image = [UIImage imageWithContentsOfFile:path];
    } else {
        int64_t msgId = message.messageId;
        __weak typeof(self) weakSelf = self;
        [client downloadFileWithId:thumbId priority:20 completion:^(NSString *downloadedPath, NSDictionary *file) {
            if (weakSelf.currentMessageId == msgId && downloadedPath.length > 0) {
                UIImage *img = [UIImage imageWithContentsOfFile:downloadedPath];
                if (img != nil) {
                    weakSelf.mediaImageView.image = img;
                }
            }
        }];
    }

    // Also preload the actual animation video file in background
    if (message.mediaFileId > 0 && [client localPathForFileId:message.mediaFileId] == nil) {
        [client downloadFileWithId:message.mediaFileId priority:12 completion:nil];
    }
}

- (void)loadVideoForMessage:(TGMessage *)message client:(nullable TGTDLibClient *)client {
    if (message.minithumbnailData.length > 0 && self.mediaImageView.image == nil) {
        self.mediaImageView.image = [UIImage imageWithData:message.minithumbnailData];
    }

    int32_t thumbId = message.thumbnailFileId > 0 ? message.thumbnailFileId : message.mediaFileId;
    if (thumbId <= 0 || client == nil) return;

    NSString *path = [client localPathForFileId:thumbId];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        self.mediaImageView.image = [UIImage imageWithContentsOfFile:path];
    } else {
        int64_t msgId = message.messageId;
        __weak typeof(self) weakSelf = self;
        [client downloadFileWithId:thumbId priority:20 completion:^(NSString *downloadedPath, NSDictionary *file) {
            if (weakSelf.currentMessageId == msgId && downloadedPath.length > 0) {
                UIImage *img = [UIImage imageWithContentsOfFile:downloadedPath];
                if (img != nil) {
                    weakSelf.mediaImageView.image = img;
                }
            }
        }];
    }
}

- (void)loadStickerForMessage:(TGMessage *)message client:(nullable TGTDLibClient *)client {
    // 1. Direct path from message if already locally present
    NSString *path = message.mediaLocalPath;
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self displayStickerAtPath:path messageId:message.messageId];
        return;
    }

    int32_t fileId = message.mediaFileId > 0 ? message.mediaFileId : message.thumbnailFileId;
    if (fileId <= 0 || client == nil) {
        self.stickerEmojiLabel.hidden = NO;
        self.stickerEmojiLabel.text = message.stickerEmoji.length > 0 ? message.stickerEmoji : @"🌟";
        return;
    }

    path = [client localPathForFileId:fileId];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self displayStickerAtPath:path messageId:message.messageId];
        return;
    }

    // Try thumbnail if main file not yet local
    if (message.thumbnailFileId > 0 && message.thumbnailFileId != fileId) {
        NSString *thumbPath = [client localPathForFileId:message.thumbnailFileId];
        if (thumbPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:thumbPath]) {
            [self displayStickerAtPath:thumbPath messageId:message.messageId];
        }
    }

    // Show emoji placeholder while sticker is loading
    if (self.stickerImageView.image == nil) {
        self.stickerEmojiLabel.hidden = NO;
        self.stickerEmojiLabel.text = message.stickerEmoji.length > 0 ? message.stickerEmoji : @"🌟";
    }

    int64_t msgId = message.messageId;
    __weak typeof(self) weakSelf = self;
    [client downloadFileWithId:fileId priority:30 completion:^(NSString *downloadedPath, NSDictionary *file) {
        if (weakSelf.currentMessageId == msgId && downloadedPath.length > 0) {
            [weakSelf displayStickerAtPath:downloadedPath messageId:msgId];
        } else if (weakSelf.currentMessageId == msgId && message.thumbnailFileId > 0 && message.thumbnailFileId != fileId) {
            [client downloadFileWithId:message.thumbnailFileId priority:25 completion:^(NSString *thumbDownloadedPath, NSDictionary *thumbFile) {
                if (weakSelf.currentMessageId == msgId && thumbDownloadedPath.length > 0) {
                    [weakSelf displayStickerAtPath:thumbDownloadedPath messageId:msgId];
                }
            }];
        }
    }];
}

- (void)displayStickerAtPath:(NSString *)path messageId:(int64_t)msgId {
    if (path.length == 0) return;
    __weak typeof(self) weakSelf = self;

    // Check cached image first
    UIImage *cached = [TGWebPConverter cachedImageForPath:path];
    if (cached != nil) {
        if (weakSelf.currentMessageId == msgId) {
            weakSelf.stickerEmojiLabel.hidden = YES;
            weakSelf.stickerImageView.image = cached;
        }
        return;
    }

    // Check if it is a WebP file or regular image
    if ([TGWebPConverter isWebPFile:path]) {
        [TGWebPConverter convertWebPAtPath:path completion:^(NSString *jpgPath, UIImage *image) {
            if (weakSelf.currentMessageId == msgId && image != nil) {
                weakSelf.stickerEmojiLabel.hidden = YES;
                weakSelf.stickerImageView.image = image;
            }
        }];
    } else {
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        if (img != nil && weakSelf.currentMessageId == msgId) {
            weakSelf.stickerEmojiLabel.hidden = YES;
            weakSelf.stickerImageView.image = img;
        }
    }
}

- (NSString *)timeTextForMessage:(TGMessage *)message {
    if (message.isFailed) {
        return @"Nie wysłano  ⚠️";
    }
    NSString *time = [TGTheme timeStringForTimestamp:message.date];
    if (message.editDate > 0) {
        time = [time stringByAppendingString:@" · edytowano"];
    }
    if (message.isSending) {
        return [time stringByAppendingString:@"  ⏳"];
    }
    if (message.isOutgoing) {
        return [time stringByAppendingString:message.isRead ? @"  ✓✓" : @"  ✓"];
    }
    return time;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    if (self.message == nil || width <= 0) {
        return;
    }

    if (self.message.isUnreadDivider) {
        CGFloat barWidth = width - 32.0;
        self.unreadBarView.frame = CGRectMake(16.0,
                                              floor((CGRectGetHeight(self.contentView.bounds) - 26.0) / 2.0),
                                              barWidth,
                                              26.0);
        return;
    }

    if (self.message.isService) {
        CGFloat labelWidth = width - 32.0;
        CGSize size = [self.serviceLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)];
        self.serviceLabel.frame = CGRectMake(16.0,
                                             floor((CGRectGetHeight(self.contentView.bounds) - size.height) / 2.0),
                                             labelWidth,
                                             size.height);
        return;
    }

    CGFloat maxBubbleWidth = [[self class] bubbleWidthForMessage:self.message width:width showSender:self.showSender];

    BOOL withAvatar = [[self class] showsAuthorAvatarForMessage:self.message showSender:self.showSender];
    // The avatar column is always reserved so bubbles stay aligned across a run,
    // but the image is only rendered for the first message (isGroupStart == YES).
    BOOL avatarVisible = withAvatar && self.isGroupStart;
    CGFloat leadingMargin = TGMessageCellHorizontalMargin;
    if (withAvatar) {
        leadingMargin += TGMessageCellAvatarSlot;
    }

    // Layout floating sticker
    if (self.message.messageType == TGMessageTypeSticker) {
        CGSize stickerSize = [[self class] mediaSizeForMessage:self.message maxBubbleWidth:maxBubbleWidth];
        CGFloat stickerX = self.message.isOutgoing
            ? width - TGMessageCellHorizontalMargin - stickerSize.width
            : leadingMargin;
        CGFloat stickerY = 6.0;

        self.stickerImageView.frame = CGRectMake(stickerX, stickerY, stickerSize.width, stickerSize.height);
        self.stickerEmojiLabel.frame = self.stickerImageView.frame;

        CGSize pillSize = CGSizeMake(48.0, 18.0);
        self.stickerTimePill.frame = CGRectMake(CGRectGetMaxX(self.stickerImageView.frame) - pillSize.width - 4.0,
                                                CGRectGetMaxY(self.stickerImageView.frame) - pillSize.height - 4.0,
                                                pillSize.width,
                                                pillSize.height);
        self.stickerTimeLabel.frame = self.stickerTimePill.bounds;

        if (avatarVisible) {
            self.authorAvatarView.frame = CGRectMake(TGMessageCellHorizontalMargin,
                                                     stickerY,
                                                     TGMessageCellAvatarSize,
                                                     TGMessageCellAvatarSize);
        }
        return;
    }

    // Normal bubble layout
    CGFloat maxTextWidth = MAX(60.0, maxBubbleWidth - TGMessageCellBubblePadding * 2.0);
    CGFloat senderHeight = (self.showSender && !self.message.isOutgoing) ? TGMessageCellSenderHeight : 0.0;
    CGFloat timeWidth = [self.timeLabel sizeThatFits:CGSizeMake(maxBubbleWidth, TGMessageCellTimeHeight)].width;

    CGFloat headerHeight = [[self class] replyBlockHeightForMessage:self.message];
    CGFloat curY = 6.0 + headerHeight + senderHeight;
    CGFloat contentWidth = 0.0;

    if (self.message.messageType == TGMessageTypeText || self.message.messageType == TGMessageTypeUnsupported) {
        CGSize textSize = [[self class] textSizeForString:self.bodyLabel.text maxWidth:maxTextWidth];
        contentWidth = MAX(textSize.width, timeWidth);
        self.bodyLabel.frame = CGRectMake(TGMessageCellBubblePadding, curY, textSize.width, textSize.height);
        curY += textSize.height;
    } else if (self.message.messageType == TGMessageTypePhoto ||
               self.message.messageType == TGMessageTypeVideo ||
               self.message.messageType == TGMessageTypeAnimation) {
        CGSize mediaSize = [[self class] mediaSizeForMessage:self.message maxBubbleWidth:maxBubbleWidth];
        contentWidth = MAX(mediaSize.width, timeWidth);

        self.mediaContainer.frame = CGRectMake(4.0, curY, mediaSize.width, mediaSize.height);
        self.mediaImageView.frame = self.mediaContainer.bounds;
        self.playButtonView.center = CGPointMake(mediaSize.width / 2.0, mediaSize.height / 2.0);

        if (!self.mediaBadgeLabel.hidden) {
            CGSize badgeSize = [self.mediaBadgeLabel sizeThatFits:CGSizeMake(100, 20)];
            self.mediaBadgeLabel.frame = CGRectMake(8.0, mediaSize.height - badgeSize.height - 8.0, badgeSize.width + 8.0, badgeSize.height + 4.0);
        }

        curY += mediaSize.height;

        if (self.message.mediaCaption.length > 0) {
            curY += 6.0;
            CGSize capSize = [[self class] textSizeForString:self.message.mediaCaption maxWidth:maxTextWidth];
            self.captionLabel.frame = CGRectMake(TGMessageCellBubblePadding, curY, capSize.width, capSize.height);
            contentWidth = MAX(contentWidth, capSize.width);
            curY += capSize.height;
        }
    } else {
        // Document / Audio / Voice / Contact / Location / Poll
        CGSize cardSize = [[self class] mediaSizeForMessage:self.message maxBubbleWidth:maxBubbleWidth];
        contentWidth = MAX(cardSize.width, timeWidth);

        self.docIconView.frame = CGRectMake(TGMessageCellBubblePadding, curY + 4.0, 40.0, 40.0);
        CGFloat textX = CGRectGetMaxX(self.docIconView.frame) + 10.0;
        CGFloat textW = cardSize.width - 40.0 - 10.0;
        self.docTitleLabel.frame = CGRectMake(textX, curY + 4.0, textW, 20.0);
        self.docSubtitleLabel.frame = CGRectMake(textX, curY + 24.0, textW, 18.0);

        curY += cardSize.height;

        if (self.message.mediaCaption.length > 0) {
            curY += 4.0;
            CGSize capSize = [[self class] textSizeForString:self.message.mediaCaption maxWidth:maxTextWidth];
            self.captionLabel.frame = CGRectMake(TGMessageCellBubblePadding, curY, capSize.width, capSize.height);
            contentWidth = MAX(contentWidth, capSize.width);
            curY += capSize.height;
        }
    }

    curY += 4.0;

    if (!self.forwardLabel.hidden) {
        CGSize forwardSize = [self.forwardLabel sizeThatFits:CGSizeMake(maxTextWidth, TGMessageCellForwardLineHeight)];
        contentWidth = MAX(contentWidth, MIN(maxTextWidth, forwardSize.width + 4.0));
    }
    if (!self.replyContainer.hidden) {
        contentWidth = MAX(contentWidth, MIN(maxTextWidth, 170.0));
    }

    CGFloat bubbleWidth = MIN(maxBubbleWidth, contentWidth + TGMessageCellBubblePadding * 2.0);
    bubbleWidth = MAX(bubbleWidth, 68.0);
    CGFloat bubbleHeight = curY + TGMessageCellTimeHeight + 6.0;

    CGFloat bubbleX;
    if (self.message.isOutgoing) {
        bubbleX = width - TGMessageCellHorizontalMargin - bubbleWidth;
    } else {
        bubbleX = leadingMargin;
    }
    CGFloat bubbleY = 3.0;

    self.bubbleView.frame = CGRectMake(bubbleX, bubbleY, bubbleWidth, bubbleHeight);

    if (avatarVisible) {
        // Pin the avatar to the TOP of the bubble (first message in the group).
        self.authorAvatarView.frame = CGRectMake(TGMessageCellHorizontalMargin,
                                                 bubbleY,
                                                 TGMessageCellAvatarSize,
                                                 TGMessageCellAvatarSize);
    }

    if (self.showSender && !self.message.isOutgoing) {
        self.senderLabel.frame = CGRectMake(TGMessageCellBubblePadding, 6.0 + headerHeight, bubbleWidth - TGMessageCellBubblePadding * 2.0, TGMessageCellSenderHeight);
    }

    // Forward header and reply quote strip, stacked above the message content.
    CGFloat stripY = 6.0;
    if (!self.forwardLabel.hidden) {
        self.forwardLabel.frame = CGRectMake(TGMessageCellBubblePadding, stripY,
                                             bubbleWidth - TGMessageCellBubblePadding * 2.0,
                                             TGMessageCellForwardLineHeight);
        stripY += TGMessageCellForwardLineHeight;
    }
    if (!self.replyContainer.hidden) {
        CGFloat replyX = 8.0;
        CGFloat replyWidth = bubbleWidth - replyX * 2.0;
        self.replyContainer.frame = CGRectMake(replyX, stripY, replyWidth, TGMessageCellReplyBlockHeight);
        self.replyBarView.frame = CGRectMake(0.0, 3.0, 3.0, TGMessageCellReplyBlockHeight - 6.0);
        self.replyNameLabel.frame = CGRectMake(9.0, 1.0, replyWidth - 13.0, 16.0);
        self.replyTextLabel.frame = CGRectMake(9.0, 18.0, replyWidth - 13.0, 16.0);
    }

    self.timeLabel.frame = CGRectMake(bubbleWidth - TGMessageCellBubblePadding - timeWidth - 2.0,
                                      bubbleHeight - TGMessageCellTimeHeight - 6.0,
                                      timeWidth + 2.0,
                                      TGMessageCellTimeHeight);
}

@end
