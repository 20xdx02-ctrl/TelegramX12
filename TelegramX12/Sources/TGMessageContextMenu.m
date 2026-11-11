#import "TGMessageContextMenu.h"

static const CGFloat TGMenuCardWidth = 210.0;
static const CGFloat TGMenuEmojiRowHeight = 54.0;
static const CGFloat TGMenuEmojiButtonWidth = 44.0;
static const CGFloat TGMenuActionRowHeight = 44.0;
static const CGFloat TGMenuCardCornerRadius = 14.0;

@interface TGMessageContextMenu () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UIView *dimView;
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) NSArray<UIButton *> *emojiButtons;
@property (nonatomic, copy) void (^onReaction)(NSString *emoji);
@property (nonatomic, copy) void (^onAction)(TGMessageContextAction action);
@property (nonatomic) BOOL dismissing;
@property (nonatomic) CGRect anchorRect;
@property (nonatomic, strong) UITapGestureRecognizer *outsideTapRecognizer;

@end

@implementation TGMessageContextMenu

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // Only taps outside the card dismiss the menu; button touches inside the
    // card must reach their controls untouched.
    if (gestureRecognizer == self.outsideTapRecognizer) {
        return !CGRectContainsPoint(self.cardView.frame, [gestureRecognizer locationInView:self]);
    }
    return YES;
}

#pragma mark - Presentation

+ (void)presentInView:(UIView *)superview
           bubbleRect:(CGRect)bubbleRect
               emojis:(NSArray<NSString *> *)emojis
       allowedActions:(NSArray<NSNumber *> *)actions
           onReaction:(void (^)(NSString *))onReaction
             onAction:(void (^)(TGMessageContextAction))onAction {
    TGMessageContextMenu *menu = [[TGMessageContextMenu alloc] initWithFrame:superview.bounds];
    menu.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    menu.anchorRect = bubbleRect;
    menu.onReaction = onReaction;
    menu.onAction = onAction;
    [menu buildCardWithEmojis:emojis actions:actions];
    [superview addSubview:menu];
    [menu animateIn];
}

#pragma mark - Construction

- (void)buildCardWithEmojis:(NSArray<NSString *> *)emojis actions:(NSArray<NSNumber *> *)actions {
    self.backgroundColor = [UIColor clearColor];

    _dimView = [[UIView alloc] initWithFrame:self.bounds];
    _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:1.0];
    _dimView.alpha = 0.0;
    [self addSubview:_dimView];

    UITapGestureRecognizer *outsideTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleOutsideTap)];
    outsideTap.delegate = self;
    outsideTap.cancelsTouchesInView = NO;
    [self addGestureRecognizer:outsideTap];
    self.outsideTapRecognizer = outsideTap;

    BOOL hasEmojiRow = emojis.count > 0;
    CGFloat cardHeight = (hasEmojiRow ? TGMenuEmojiRowHeight : 0.0) + (CGFloat)actions.count * TGMenuActionRowHeight;
    CGFloat cardWidth = TGMenuCardWidth;
    if (hasEmojiRow) {
        cardWidth = MAX(cardWidth, (CGFloat)emojis.count * TGMenuEmojiButtonWidth + 16.0);
    }

    // Anchor the card to the bubble: prefer directly above, fall back below.
    CGFloat safeTop = CGRectGetMinY(self.safeAreaLayoutGuide.layoutFrame) + 8.0;
    CGFloat safeBottom = CGRectGetHeight(self.bounds) - CGRectGetMaxY(self.safeAreaLayoutGuide.layoutFrame) + 8.0;
    CGFloat cardY = CGRectGetMinY(self.anchorRect) - cardHeight - 10.0;
    if (cardY < safeTop) {
        cardY = CGRectGetMaxY(self.anchorRect) + 10.0;
    }
    CGFloat cardX = CGRectGetMidX(self.anchorRect) - cardWidth / 2.0;
    cardX = MAX(8.0, MIN(cardX, CGRectGetWidth(self.bounds) - cardWidth - 8.0));
    cardY = MAX(safeTop, MIN(cardY, CGRectGetHeight(self.bounds) - cardHeight - safeBottom));

    _cardView = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, cardWidth, cardHeight)];
    _cardView.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.98];
    _cardView.layer.cornerRadius = TGMenuCardCornerRadius;
    _cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    _cardView.layer.shadowOpacity = 0.28;
    _cardView.layer.shadowRadius = 14.0;
    _cardView.layer.shadowOffset = CGSizeMake(0.0, 5.0);
    [self addSubview:_cardView];

    CGFloat y = 0.0;
    if (hasEmojiRow) {
        UIView *emojiRow = [[UIView alloc] initWithFrame:CGRectMake(0.0, y, cardWidth, TGMenuEmojiRowHeight)];
        emojiRow.backgroundColor = [UIColor clearColor];
        [_cardView addSubview:emojiRow];

        CGFloat totalWidth = (CGFloat)emojis.count * TGMenuEmojiButtonWidth;
        CGFloat startX = floor((cardWidth - totalWidth) / 2.0);
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        for (NSUInteger i = 0; i < emojis.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake(startX + (CGFloat)i * TGMenuEmojiButtonWidth, 0.0, TGMenuEmojiButtonWidth, TGMenuEmojiRowHeight);
            button.titleLabel.font = [UIFont systemFontOfSize:26.0];
            [button setTitle:emojis[i] forState:UIControlStateNormal];
            button.accessibilityLabel = emojis[i];
            [button addTarget:self action:@selector(emojiTapped:) forControlEvents:UIControlEventTouchUpInside];
            [emojiRow addSubview:button];
            [buttons addObject:button];
        }
        _emojiButtons = [buttons copy];
        y += TGMenuEmojiRowHeight;

        UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(10.0, y - 0.5, cardWidth - 20.0, 0.5)];
        separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        [_cardView addSubview:separator];
    }

    NSDictionary<NSNumber *, NSString *> *titles = @{
        @(TGMessageContextActionCopy): @"Kopiuj",
        @(TGMessageContextActionReply): @"Odpowiedz",
        @(TGMessageContextActionForward): @"Przekaż",
        @(TGMessageContextActionEdit): @"Edytuj",
        @(TGMessageContextActionDelete): @"Usuń",
    };
    for (NSUInteger i = 0; i < actions.count; i++) {
        TGMessageContextAction action = (TGMessageContextAction)actions[i].integerValue;
        BOOL destructive = (action == TGMessageContextActionDelete);
        CGFloat rowY = y + (CGFloat)i * TGMenuActionRowHeight;

        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0.0, rowY, cardWidth, TGMenuActionRowHeight);
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        row.contentEdgeInsets = UIEdgeInsetsMake(0.0, 16.0, 0.0, 8.0);
        row.titleLabel.font = [UIFont systemFontOfSize:15.0];
        [row setTitle:titles[@(action)] forState:UIControlStateNormal];
        [row setTitleColor:destructive ? [UIColor colorWithRed:1.0 green:0.45 blue:0.42 alpha:1.0]
                                         : [UIColor colorWithWhite:1.0 alpha:0.96]
                forState:UIControlStateNormal];
        row.accessibilityLabel = titles[@(action)];
        [row addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_cardView addSubview:row];

        if (i + 1 < actions.count) {
            UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(14.0, rowY + TGMenuActionRowHeight - 0.5, cardWidth - 28.0, 0.5)];
            separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
            separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [_cardView addSubview:separator];
        }
    }
}

#pragma mark - Animation

- (void)animateIn {
    self.cardView.alpha = 0.0;
    // Grow out of the bubble's direction, like Telegram X's context menu.
    BOOL aboveBubble = CGRectGetMaxY(self.cardView.frame) <= CGRectGetMinY(self.anchorRect) + 1.0;
    CGAffineTransform start = CGAffineTransformMakeTranslation(0.0, aboveBubble ? 14.0 : -14.0);
    start = CGAffineTransformScale(start, 0.72, 0.72);
    self.cardView.transform = start;
    [UIView animateWithDuration:0.22
                          delay:0.0
         usingSpringWithDamping:0.85
          initialSpringVelocity:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.dimView.alpha = 0.38;
                         self.cardView.alpha = 1.0;
                         self.cardView.transform = CGAffineTransformIdentity;
                     }
                     completion:nil];
}

- (void)dismissAnimated:(BOOL)animated completion:(void (^)(void))completion {
    if (self.dismissing) {
        return;
    }
    self.dismissing = YES;
    void (^finish)(void) = ^{
        [self removeFromSuperview];
        if (completion != nil) {
            completion();
        }
    };
    if (!animated) {
        finish();
        return;
    }
    [UIView animateWithDuration:0.16
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.dimView.alpha = 0.0;
                         self.cardView.alpha = 0.0;
                         self.cardView.transform = CGAffineTransformMakeScale(0.85, 0.85);
                     }
                     completion:^(BOOL finished) {
                         finish();
                     }];
}

#pragma mark - Interaction

- (void)handleOutsideTap {
    [self dismissAnimated:YES completion:nil];
}

- (void)emojiTapped:(UIButton *)sender {
    NSString *emoji = sender.accessibilityLabel;
    void (^reaction)(NSString *) = self.onReaction;
    [self dismissAnimated:YES completion:nil];
    if (reaction != nil && emoji.length > 0) {
        reaction(emoji);
    }
}

- (void)actionTapped:(UIButton *)sender {
    NSString *label = sender.accessibilityLabel;
    NSDictionary<NSString *, NSNumber *> *titles = @{
        @"Kopiuj": @(TGMessageContextActionCopy),
        @"Odpowiedz": @(TGMessageContextActionReply),
        @"Przekaż": @(TGMessageContextActionForward),
        @"Edytuj": @(TGMessageContextActionEdit),
        @"Usuń": @(TGMessageContextActionDelete),
    };
    NSNumber *actionNumber = titles[label];
    void (^onAction)(TGMessageContextAction) = self.onAction;
    [self dismissAnimated:YES completion:nil];
    if (onAction != nil && actionNumber != nil) {
        onAction((TGMessageContextAction)actionNumber.integerValue);
    }
}

@end
