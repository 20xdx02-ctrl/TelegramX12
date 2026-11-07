#import "TGMessageCell.h"

#import "TGModels.h"
#import "TGTheme.h"

static const CGFloat TGMessageCellHorizontalMargin = 12.0;
static const CGFloat TGMessageCellBubblePadding = 12.0;
static const CGFloat TGMessageCellTimeHeight = 12.0;
static const CGFloat TGMessageCellSenderHeight = 14.0;
static const CGFloat TGMessageCellTextSize = 16.0;

@interface TGMessageCell ()
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UILabel *senderLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *serviceLabel;
@property (nonatomic, strong) TGMessage *message;
@property (nonatomic) BOOL showSender;
@property (nonatomic, copy) NSString *senderName;
@end

@implementation TGMessageCell

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

        _bodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.font = [TGTheme regularFontOfSize:TGMessageCellTextSize];
        [_bubbleView addSubview:_bodyLabel];

        _senderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _senderLabel.font = [TGTheme semiboldFontOfSize:12.0];
        _senderLabel.numberOfLines = 1;
        [_bubbleView addSubview:_senderLabel];

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [TGTheme regularFontOfSize:10.0];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_bubbleView addSubview:_timeLabel];

        _serviceLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _serviceLabel.font = [TGTheme regularFontOfSize:12.0];
        _serviceLabel.textColor = [TGTheme secondaryTextColor];
        _serviceLabel.textAlignment = NSTextAlignmentCenter;
        _serviceLabel.numberOfLines = 0;
        [self.contentView addSubview:_serviceLabel];
    }
    return self;
}

- (void)configureWithMessage:(TGMessage *)message showSender:(BOOL)showSender senderName:(NSString *)senderName {
    self.message = message;
    self.showSender = showSender;
    self.senderName = senderName;

    if (message.isService) {
        _serviceLabel.hidden = NO;
        _bubbleView.hidden = YES;
        _serviceLabel.text = message.text;
    } else {
        _serviceLabel.hidden = YES;
        _bubbleView.hidden = NO;
        _bodyLabel.text = message.text.length > 0 ? message.text : @"Nieobsługiwana wiadomość";
        _senderLabel.text = senderName;
        _senderLabel.hidden = !(showSender && !message.isOutgoing);
        _timeLabel.text = [self timeTextForMessage:message];
    }

    [self setNeedsLayout];
}

+ (CGFloat)heightForMessage:(TGMessage *)message width:(CGFloat)width showSender:(BOOL)showSender {
    if (message.isService) {
        return 30.0;
    }
    CGFloat maxBubbleWidth = floor(width * 0.78);
    CGFloat maxTextWidth = MAX(60.0, maxBubbleWidth - TGMessageCellBubblePadding * 2.0);
    CGSize textSize = [self textSizeForMessage:message maxWidth:maxTextWidth];
    CGFloat senderHeight = (showSender && !message.isOutgoing) ? TGMessageCellSenderHeight : 0.0;
    CGFloat bubbleHeight = 7.0 + senderHeight + textSize.height + 2.0 + TGMessageCellTimeHeight + 6.0;
    return 3.0 + bubbleHeight + 3.0;
}

+ (CGSize)textSizeForMessage:(TGMessage *)message maxWidth:(CGFloat)maxWidth {
    NSString *text = message.text.length > 0 ? message.text : @" ";
    NSDictionary *attributes = @{NSFontAttributeName: [TGTheme regularFontOfSize:TGMessageCellTextSize]};
    CGRect rect = [text boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  attributes:attributes
                                     context:nil];
    return CGSizeMake(MIN(maxWidth, ceil(CGRectGetWidth(rect))), MAX(1.0, ceil(CGRectGetHeight(rect))));
}

- (NSString *)timeTextForMessage:(TGMessage *)message {
    if (message.isFailed) {
        return @"Nie wysłano";
    }
    NSString *time = [TGTheme timeStringForTimestamp:message.date];
    if (message.isSending) {
        return [time stringByAppendingString:@"  ⏳"];
    }
    return time;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    if (self.message == nil || width <= 0) {
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

    CGFloat maxBubbleWidth = floor(width * 0.78);
    CGFloat maxTextWidth = MAX(60.0, maxBubbleWidth - TGMessageCellBubblePadding * 2.0);
    CGSize textSize = [[self class] textSizeForMessage:self.message maxWidth:maxTextWidth];

    CGFloat senderHeight = (self.showSender && !self.message.isOutgoing) ? TGMessageCellSenderHeight : 0.0;
    CGFloat timeWidth = [self.timeLabel sizeThatFits:CGSizeMake(maxBubbleWidth, TGMessageCellTimeHeight)].width;
    CGFloat contentWidth = MAX(textSize.width, timeWidth);
    CGFloat bubbleWidth = MIN(maxBubbleWidth, contentWidth + TGMessageCellBubblePadding * 2.0);
    bubbleWidth = MAX(bubbleWidth, 58.0);
    CGFloat bubbleHeight = 7.0 + senderHeight + textSize.height + 2.0 + TGMessageCellTimeHeight + 6.0;

    CGFloat bubbleX = self.message.isOutgoing
        ? width - TGMessageCellHorizontalMargin - bubbleWidth
        : TGMessageCellHorizontalMargin;
    CGFloat bubbleY = 3.0;

    self.bubbleView.frame = CGRectMake(bubbleX, bubbleY, bubbleWidth, bubbleHeight);
    self.bubbleView.backgroundColor = self.message.isOutgoing
        ? [TGTheme outgoingBubbleColor]
        : [TGTheme incomingBubbleColor];

    if (senderHeight > 0.0) {
        self.senderLabel.frame = CGRectMake(TGMessageCellBubblePadding,
                                            7.0,
                                            bubbleWidth - TGMessageCellBubblePadding * 2.0,
                                            senderHeight);
        self.senderLabel.textColor = [TGTheme avatarColorForIdentifier:self.message.senderId];
    }

    self.bodyLabel.frame = CGRectMake(TGMessageCellBubblePadding,
                                      7.0 + senderHeight,
                                      bubbleWidth - TGMessageCellBubblePadding * 2.0,
                                      textSize.height);
    self.bodyLabel.textColor = self.message.isOutgoing ? [UIColor whiteColor] : [UIColor blackColor];

    CGFloat timeX = bubbleWidth - TGMessageCellBubblePadding - timeWidth;
    self.timeLabel.frame = CGRectMake(timeX,
                                      7.0 + senderHeight + textSize.height + 2.0,
                                      timeWidth,
                                      TGMessageCellTimeHeight);
    self.timeLabel.textColor = self.message.isOutgoing
        ? [[UIColor whiteColor] colorWithAlphaComponent:0.75]
        : [TGTheme secondaryTextColor];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.message = nil;
    self.senderName = nil;
    self.bodyLabel.text = nil;
    self.senderLabel.text = nil;
    self.timeLabel.text = nil;
    self.serviceLabel.text = nil;
}

@end
