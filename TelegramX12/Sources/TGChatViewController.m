#import "TGChatViewController.h"

#import "TGAvatarView.h"
#import "TGInputBar.h"
#import "TGMessageCell.h"
#import "TGModels.h"
#import "TGPhotoViewerController.h"
#import "TGStickerPickerView.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface TGChatViewController () <UITableViewDataSource, UITableViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentInteractionControllerDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic) int64_t chatId;
@property (nonatomic) int64_t lastReadOutboxMessageId;
@property (nonatomic) int64_t lastReadInboxMessageId;
@property (nonatomic) int32_t unreadCountAtOpen;
@property (nonatomic) BOOL didCaptureReadState;
@property (nonatomic, strong, nullable) TGMessage *unreadDividerMessage;
@property (nonatomic, strong) UIView *titleHeaderView;
@property (nonatomic, strong) UILabel *titleHeaderLabel;
@property (nonatomic, strong) UILabel *subtitleHeaderLabel;
@property (nonatomic, strong) TGAvatarView *headerAvatarView;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSDictionary *> *typingBySender;
@property (nonatomic) NSInteger typingRefreshGeneration;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) TGInputBar *inputBar;
@property (nonatomic, strong) NSLayoutConstraint *inputBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableBottomToInputConstraint;
@property (nonatomic, strong) NSLayoutConstraint *tableBottomToPickerConstraint;
@property (nonatomic, strong) NSLayoutConstraint *pickerBottomConstraint;
@property (nonatomic, strong) TGStickerPickerView *stickerPickerView;
@property (nonatomic) BOOL stickerPickerVisible;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableArray<TGMessage *> *messages;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *messageIndexById;
@property (nonatomic) NSInteger totalCount;
@property (nonatomic) BOOL loadingOlder;
@property (nonatomic) BOOL reachedOldestMessage;
@property (nonatomic) NSInteger initialRetryCount;
@property (nonatomic) BOOL didInitialLoad;
@property (nonatomic) BOOL visible;
@property (nonatomic) BOOL showSenderNames;
@property (nonatomic, copy) NSString *chatTitleForDisplay;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) UIDocumentInteractionController *documentController;
@end

@implementation TGChatViewController

- (instancetype)initWithClient:(TGTDLibClient *)client chatId:(int64_t)chatId title:(NSString *)title {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _client = client;
        _chatId = chatId;
        _chatTitleForDisplay = [title copy];
        _messages = [NSMutableArray array];
        _messageIndexById = [NSMutableDictionary dictionary];
        _typingBySender = [NSMutableDictionary dictionary];
        _totalCount = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.chatTitleForDisplay;
    self.view.backgroundColor = [TGTheme chatBackgroundColor];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    _titleHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 212, 44)];

    _headerAvatarView = [[TGAvatarView alloc] initWithFrame:CGRectMake(0, 5, 34, 34)];
    [_titleHeaderView addSubview:_headerAvatarView];

    _titleHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 4, 168, 20)];
    _titleHeaderLabel.font = [TGTheme semiboldFontOfSize:16.0];
    _titleHeaderLabel.textColor = [UIColor blackColor];
    _titleHeaderLabel.textAlignment = NSTextAlignmentCenter;
    _titleHeaderLabel.text = self.chatTitleForDisplay;
    [_titleHeaderView addSubview:_titleHeaderLabel];

    _subtitleHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 24, 168, 16)];
    _subtitleHeaderLabel.font = [TGTheme regularFontOfSize:12.0];
    _subtitleHeaderLabel.textColor = [TGTheme secondaryTextColor];
    _subtitleHeaderLabel.textAlignment = NSTextAlignmentCenter;
    [_titleHeaderView addSubview:_subtitleHeaderLabel];

    self.navigationItem.titleView = _titleHeaderView;
    [self refreshHeaderSubtitle];
    [self loadHeaderAvatar];

    [self updateSenderVisibility];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [TGTheme chatBackgroundColor];
    self.tableView.estimatedRowHeight = 60.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:[TGMessageCell class] forCellReuseIdentifier:@"TGMessageCell"];
    [self.view addSubview:self.tableView];

    self.inputBar = [[TGInputBar alloc] initWithFrame:CGRectZero];
    self.inputBar.translatesAutoresizingMaskIntoConstraints = NO;
    __weak typeof(self) weakSelf = self;
    self.inputBar.onSend = ^(NSString *text) {
        [weakSelf sendText:text];
    };
    self.inputBar.onAttachTap = ^{
        [weakSelf presentAttachmentActionSheet];
    };
    [self.view addSubview:self.inputBar];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [TGTheme accentColor];
    [self.refreshControl addTarget:self action:@selector(loadOlderHistory) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"Brak wiadomości.\nNapisz pierwszą.";
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.font = [TGTheme regularFontOfSize:14.0];
    self.emptyLabel.textColor = [TGTheme secondaryTextColor];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    self.inputBottomConstraint = [self.inputBar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor];
    self.tableBottomToInputConstraint = [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.tableBottomToInputConstraint,

        [self.inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.inputBar.heightAnchor constraintEqualToConstant:50.0],
        self.inputBottomConstraint,

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.visible = YES;

    // Capture the read boundary before openChat/viewMessages can move it, so
    // the initial history load still knows where the first unread message is.
    if (!self.didCaptureReadState) {
        self.didCaptureReadState = YES;
        NSDictionary *chat = [self.client chatWithId:self.chatId];
        if (chat != nil) {
            self.lastReadInboxMessageId = TGInt64Value(chat[@"last_read_inbox_message_id"]);
            self.unreadCountAtOpen = TGInt32Value(chat[@"unread_count"]);
        }
    }

    [self.client openChat:self.chatId];
    if (!self.didInitialLoad) {
        [self loadInitialHistory];
    } else {
        // Re-entering an already open chat: everything on screen was read on
        // the previous visit, so drop the divider and show the latest state.
        if (self.unreadDividerMessage != nil) {
            [self removeUnreadDivider];
            [self.tableView reloadData];
            [self.tableView layoutIfNeeded];
            [self scrollToBottomAnimated:NO];
        }
        [self markMessagesRead];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
    [self hideStickerPickerAnimated:NO];
    [self.client closeChat:self.chatId];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateSenderVisibility {
    NSDictionary *chat = [self.client chatWithId:self.chatId];
    NSDictionary *type = chat[@"type"];
    NSString *typeName = TGStringValue(type[@"@type"]);
    if ([typeName isEqualToString:@"chatTypeBasicGroup"]) {
        self.showSenderNames = YES;
    } else if ([typeName isEqualToString:@"chatTypeSupergroup"]) {
        self.showSenderNames = !TGBoolValue(type[@"is_channel"]);
    } else {
        self.showSenderNames = NO;
    }
}

#pragma mark - History

- (void)loadInitialHistory {
    [self.spinner startAnimating];
    self.emptyLabel.hidden = YES;
    NSDictionary *chat = [self.client chatWithId:self.chatId];
    if (chat != nil) {
        self.lastReadOutboxMessageId = TGInt64Value(chat[@"last_read_outbox_message_id"]);
    }
    [self refreshHeaderSubtitle];
    __weak typeof(self) weakSelf = self;
    [self.client loadHistoryForChat:self.chatId fromMessageId:0 limit:50 completion:^(NSArray<NSDictionary *> *messages, NSInteger totalCount, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.spinner stopAnimating];
            [weakSelf.refreshControl endRefreshing];
            weakSelf.didInitialLoad = YES;
            if (error != nil) {
                NSString *message = TGStringValue(error[@"message"]);
                if (message.length > 0) {
                    NSLog(@"[TelegramX12] getChatHistory error: %@", message);
                }
                [weakSelf updateEmptyState];
                return;
            }
            [weakSelf replaceMessagesWithDictionaries:messages totalCount:totalCount];
            [weakSelf placeUnreadDividerIfNeeded];
            [weakSelf.tableView reloadData];
            [weakSelf.tableView layoutIfNeeded];
            if (weakSelf.unreadDividerMessage != nil) {
                [weakSelf scrollToUnreadDividerAnimated:NO];
            } else {
                [weakSelf scrollToBottomAnimated:NO];
            }
            [weakSelf markMessagesRead];
            [weakSelf updateSenderVisibility];
            [weakSelf updateEmptyState];

            // If TDLib only returned 1 message initially because server history is still loading in background,
            // retry automatically so the full history appears without manual refresh!
            if (messages.count <= 1 && weakSelf.initialRetryCount < 3) {
                weakSelf.initialRetryCount++;
                NSTimeInterval delay = weakSelf.initialRetryCount == 1 ? 0.5 : 1.2;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (weakSelf.visible) {
                        [weakSelf loadInitialHistory];
                    }
                });
            }
        });
    }];
}

- (void)replaceMessagesWithDictionaries:(NSArray<NSDictionary *> *)dictionaries totalCount:(NSInteger)totalCount {
    [self.messages removeAllObjects];
    [self.messageIndexById removeAllObjects];

    NSMutableArray<TGMessage *> *loaded = [NSMutableArray array];
    for (NSDictionary *dictionary in dictionaries) {
        TGMessage *message = [TGMessage messageWithDictionary:dictionary];
        if (message.messageId != 0) {
            if (message.isOutgoing && self.lastReadOutboxMessageId > 0) {
                message.isRead = (message.messageId <= self.lastReadOutboxMessageId);
            }
            [loaded addObject:message];
        }
    }
    [loaded sortUsingComparator:^NSComparisonResult(TGMessage *a, TGMessage *b) {
        if (a.messageId < b.messageId) {
            return NSOrderedAscending;
        }
        if (a.messageId > b.messageId) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];

    [self.messages addObjectsFromArray:loaded];
    [self rebuildMessageIndex];
    [self recomputeDateDividers];
    self.totalCount = MAX(totalCount, (NSInteger)self.messages.count);
}

- (void)loadOlderHistory {
    if (self.loadingOlder || self.messages.count == 0 || self.reachedOldestMessage) {
        [self.refreshControl endRefreshing];
        return;
    }
    self.loadingOlder = YES;

    // The synthetic unread divider carries no TDLib id; older history must be
    // requested relative to the oldest real message.
    TGMessage *oldest = nil;
    for (TGMessage *candidate in self.messages) {
        if (candidate.messageId > 0) {
            oldest = candidate;
            break;
        }
    }
    if (oldest == nil) {
        self.loadingOlder = NO;
        [self.refreshControl endRefreshing];
        return;
    }
    CGFloat oldHeight = self.tableView.contentSize.height;
    CGFloat oldOffsetY = self.tableView.contentOffset.y;

    __weak typeof(self) weakSelf = self;
    [self.client loadHistoryForChat:self.chatId fromMessageId:oldest.messageId limit:50 completion:^(NSArray<NSDictionary *> *messages, NSInteger totalCount, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.loadingOlder = NO;
            [weakSelf.refreshControl endRefreshing];
            if (error != nil) {
                return;
            }

            NSMutableArray<TGMessage *> *newMessages = [NSMutableArray array];
            for (NSDictionary *dictionary in messages) {
                TGMessage *message = [TGMessage messageWithDictionary:dictionary];
                if (message.messageId == 0 || weakSelf.messageIndexById[@(message.messageId)] != nil) {
                    continue;
                }
                [newMessages addObject:message];
            }

            if (newMessages.count == 0) {
                weakSelf.reachedOldestMessage = YES;
                return;
            }

            [newMessages sortUsingComparator:^NSComparisonResult(TGMessage *a, TGMessage *b) {
                if (a.messageId < b.messageId) {
                    return NSOrderedAscending;
                }
                if (a.messageId > b.messageId) {
                    return NSOrderedDescending;
                }
                return NSOrderedSame;
            }];

            NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, newMessages.count)];
            [weakSelf.messages insertObjects:newMessages atIndexes:indexes];
            [weakSelf recomputeDateDividers];
            [weakSelf.tableView reloadData];
            [weakSelf.tableView layoutIfNeeded];

            CGFloat newHeight = weakSelf.tableView.contentSize.height;
            CGFloat delta = newHeight - oldHeight;
            if (delta > 0.0) {
                weakSelf.tableView.contentOffset = CGPointMake(0, oldOffsetY + delta);
            }
        });
    }];
}

- (void)rebuildMessageIndex {
    [self.messageIndexById removeAllObjects];
    [self.messages enumerateObjectsUsingBlock:^(TGMessage *message, NSUInteger index, BOOL *stop) {
        self.messageIndexById[@(message.messageId)] = @(index);
    }];
}

#pragma mark - Unread divider

/// Inserts a synthetic "Nieprzeczytane" row right before the oldest message
/// that was unread when the chat was opened (mirrors Telegram X's
/// ChatUnreadItem placed at the unread boundary).
- (void)placeUnreadDividerIfNeeded {
    [self removeUnreadDivider];

    if (self.unreadCountAtOpen <= 0) {
        return;
    }

    TGMessage *firstUnread = nil;
    for (TGMessage *message in self.messages) {
        if (message.isOutgoing || message.isService) {
            continue;
        }
        if (message.messageId > self.lastReadInboxMessageId) {
            firstUnread = message;
            break;
        }
    }
    if (firstUnread == nil) {
        return;
    }

    NSUInteger index = [self.messages indexOfObjectIdenticalTo:firstUnread];
    if (index == NSNotFound) {
        return;
    }

    TGMessage *divider = [[TGMessage alloc] init];
    divider.messageId = 0;
    divider.chatId = self.chatId;
    divider.date = firstUnread.date;
    divider.isOutgoing = NO;
    divider.isService = YES;
    divider.isUnreadDivider = YES;
    divider.messageType = TGMessageTypeService;
    divider.text = @"Nieprzeczytane wiadomości";

    [self.messages insertObject:divider atIndex:index];
    self.unreadDividerMessage = divider;
    [self rebuildMessageIndex];
}

- (void)removeUnreadDivider {
    TGMessage *divider = self.unreadDividerMessage;
    if (divider == nil) {
        return;
    }
    self.unreadDividerMessage = nil;
    NSUInteger index = [self.messages indexOfObjectIdenticalTo:divider];
    if (index != NSNotFound) {
        [self.messages removeObjectAtIndex:index];
        [self rebuildMessageIndex];
    }
}

- (void)scrollToUnreadDividerAnimated:(BOOL)animated {
    NSUInteger index = [self.messages indexOfObjectIdenticalTo:self.unreadDividerMessage];
    if (index == NSNotFound) {
        [self scrollToBottomAnimated:animated];
        return;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)index inSection:0];
    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:animated];
}

- (void)markMessagesRead {
    if (!self.visible) {
        return;
    }
    NSMutableArray<NSNumber *> *ids = [NSMutableArray array];
    NSUInteger start = self.messages.count > 100 ? self.messages.count - 100 : 0;
    for (NSUInteger i = start; i < self.messages.count; i++) {
        TGMessage *message = self.messages[i];
        if (!message.isOutgoing && !message.isService) {
            [ids addObject:@(message.messageId)];
        }
    }
    [self.client viewMessages:ids inChat:self.chatId];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count == 0) {
        return;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)self.messages.count - 1 inSection:0];
    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (BOOL)isNearBottom {
    if (self.tableView.contentSize.height <= self.tableView.bounds.size.height) {
        return YES;
    }
    CGFloat offset = self.tableView.contentOffset.y + self.tableView.bounds.size.height;
    return offset >= self.tableView.contentSize.height - 100.0;
}

#pragma mark - Sending

- (void)sendText:(NSString *)text {
    [self.inputBar clearText];
    __weak typeof(self) weakSelf = self;
    [self.client sendText:text toChat:self.chatId completion:^(NSDictionary *message, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (message != nil) {
                [weakSelf upsertMessageDictionary:message scrollToBottom:YES forceScroll:YES];
                return;
            }
            NSString *messageText = TGStringValue(error[@"message"]);
            if (messageText.length == 0) {
                messageText = @"Nie udało się wysłać wiadomości.";
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Błąd wysyłania"
                                                                           message:messageText
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            if (weakSelf.inputBar.textField.text.length == 0) {
                weakSelf.inputBar.textField.text = text;
            }
        });
    }];
}

#pragma mark - Updates

- (void)handleTDLibUpdate:(NSDictionary *)update {
    NSString *type = TGStringValue(update[@"@type"]);

    if ([type isEqualToString:@"updateNewMessage"]) {
        NSDictionary *message = update[@"message"];
        if ([message isKindOfClass:[NSDictionary class]] && TGInt64Value(message[@"chat_id"]) == self.chatId) {
            [self upsertMessageDictionary:message scrollToBottom:YES forceScroll:NO];
            [self markMessagesRead];
        }
        return;
    }

    if ([type isEqualToString:@"updateMessageSendSucceeded"]) {
        NSDictionary *message = update[@"message"];
        if (![message isKindOfClass:[NSDictionary class]] || TGInt64Value(message[@"chat_id"]) != self.chatId) {
            return;
        }
        int64_t oldMessageId = TGInt64Value(update[@"old_message_id"]);
        [self replaceMessageId:oldMessageId withDictionary:message];
        return;
    }

    if ([type isEqualToString:@"updateMessageSendFailed"]) {
        NSDictionary *message = update[@"message"];
        if (![message isKindOfClass:[NSDictionary class]] || TGInt64Value(message[@"chat_id"]) != self.chatId) {
            return;
        }
        int64_t oldMessageId = TGInt64Value(update[@"old_message_id"]);
        [self replaceMessageId:oldMessageId withDictionary:message];
        NSString *errorMessage = TGStringValue(update[@"error"][@"message"]);
        if (errorMessage.length > 0) {
            NSLog(@"[TelegramX12] message send failed: %@", errorMessage);
        }
        return;
    }

    if ([type isEqualToString:@"updateMessageContent"]) {
        if (TGInt64Value(update[@"chat_id"]) != self.chatId) {
            return;
        }
        int64_t messageId = TGInt64Value(update[@"message_id"]);
        NSNumber *indexNumber = self.messageIndexById[@(messageId)];
        if (indexNumber == nil) {
            return;
        }
        NSUInteger index = indexNumber.unsignedIntegerValue;
        if (index >= self.messages.count) {
            return;
        }
        TGMessage *message = self.messages[index];
        NSMutableDictionary *raw = [message.raw mutableCopy] ?: [NSMutableDictionary dictionary];
        raw[@"content"] = update[@"new_content"] ?: @{};
        [message updateWithDictionary:raw];
        [self.tableView reloadData];
        return;
    }

    if ([type isEqualToString:@"updateDeleteMessages"]) {
        if (TGInt64Value(update[@"chat_id"]) != self.chatId) {
            return;
        }
        NSArray *messageIds = update[@"message_ids"];
        if (![messageIds isKindOfClass:[NSArray class]]) {
            return;
        }
        NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
        for (id rawId in messageIds) {
            NSNumber *indexNumber = self.messageIndexById[@(TGInt64Value(rawId))];
            if (indexNumber != nil) {
                [indexes addIndex:indexNumber.unsignedIntegerValue];
            }
        }
        if (indexes.count == 0) {
            return;
        }
        [self.messages removeObjectsAtIndexes:indexes];
        [self rebuildMessageIndex];
        [self recomputeDateDividers];
        [self.tableView reloadData];
        [self updateEmptyState];
        return;
    }

    if ([type isEqualToString:@"updateChatTitle"]) {
        if (TGInt64Value(update[@"chat_id"]) == self.chatId) {
            NSString *title = TGStringValue(update[@"title"]);
            if (title.length > 0) {
                self.chatTitleForDisplay = title;
                self.title = title;
                self.titleHeaderLabel.text = title;
            }
        }
        return;
    }

    if ([type isEqualToString:@"updateChatUserAction"]) {
        if (TGInt64Value(update[@"chat_id"]) != self.chatId) {
            return;
        }
        int64_t actorId = TGInt64Value(update[@"actor_id"]);
        NSDictionary *action = update[@"action"];
        NSString *actionType = TGStringValue(action[@"@type"]);
        if (actorId == 0 || [actionType isEqualToString:@"sendMessageCancelAction"]) {
            [self.typingBySender removeObjectForKey:@(actorId)];
        } else {
            self.typingBySender[@(actorId)] = @{ @"sender": update[@"actor_id"] ?: @{}, @"time": [NSDate date] };
        }
        [self scheduleTypingRefresh];
        [self refreshHeaderSubtitle];
        return;
    }

    if ([type isEqualToString:@"updateChatPhoto"]) {
        if (TGInt64Value(update[@"chat_id"]) == self.chatId) {
            [self loadHeaderAvatar];
        }
        return;
    }

    if ([type isEqualToString:@"updateChatReadOutbox"]) {
        if (TGInt64Value(update[@"chat_id"]) == self.chatId) {
            int64_t lastReadId = TGInt64Value(update[@"last_read_outbox_message_id"]);
            self.lastReadOutboxMessageId = lastReadId;
            BOOL didUpdate = NO;
            for (TGMessage *msg in self.messages) {
                if (msg.isOutgoing && !msg.isRead && msg.messageId <= lastReadId) {
                    msg.isRead = YES;
                    didUpdate = YES;
                }
            }
            if (didUpdate) {
                [self.tableView reloadData];
            }
        }
        return;
    }
}

- (void)loadHeaderAvatar {
    NSString *title = self.chatTitleForDisplay.length > 0 ? self.chatTitleForDisplay : self.title;
    NSDictionary *chat = [self.client chatWithId:self.chatId];
    int32_t fileId = TGInt32Value(chat[@"photo"][@"small"][@"id"]);
    [self.headerAvatarView loadAvatarWithFileId:fileId client:self.client title:title identifier:self.chatId];
}

/// Re-renders the typing subtitle a few seconds after the last activity so
/// stale timers do not keep "pisze…" on the header forever.
- (void)scheduleTypingRefresh {
    NSInteger generation = ++self.typingRefreshGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf != nil && weakSelf.typingRefreshGeneration == generation) {
            [weakSelf refreshHeaderSubtitle];
        }
    });
}

- (NSInteger)calendarDayForTimestamp:(int32_t)timestamp {
    static NSCalendar *calendar;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    });
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    NSDateComponents *components = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    return (NSInteger)[components year] * 10000 + (NSInteger)[components month] * 100 + (NSInteger)[components day];
}

/// Rebuilds the synthetic "Dziś / Wczoraj / data" rows between messages,
/// mirroring Telegram X's ChatHistoryHeaderItem day separators.
- (void)recomputeDateDividers {
    NSIndexSet *existing = [self.messages indexesOfObjectsPassingTest:^BOOL(TGMessage *msg, NSUInteger idx, BOOL *stop) {
        return msg.isDateDivider;
    }];
    if (existing.count > 0) {
        [self.messages removeObjectsAtIndexes:existing];
    }

    NSMutableArray<TGMessage *> *withDividers = [NSMutableArray array];
    NSInteger previousDay = 0;
    for (TGMessage *message in self.messages) {
        if (message.date <= 0) {
            [withDividers addObject:message];
            continue;
        }
        NSInteger day = [self calendarDayForTimestamp:message.date];
        if (day != previousDay) {
            TGMessage *divider = [[TGMessage alloc] init];
            divider.messageId = 0;
            divider.chatId = self.chatId;
            divider.date = message.date;
            divider.isOutgoing = NO;
            divider.isService = YES;
            divider.isDateDivider = YES;
            divider.messageType = TGMessageTypeService;
            divider.text = [TGTheme chatDayHeadingStringForTimestamp:message.date];
            [withDividers addObject:divider];
            previousDay = day;
        }
        [withDividers addObject:message];
    }
    [self.messages removeAllObjects];
    [self.messages addObjectsFromArray:withDividers];
    [self rebuildMessageIndex];
}

- (void)refreshHeaderSubtitle {
    // Typing indicator (Telegram style): the transient "pisze…" state wins
    // over the static status for as long as recent activities keep coming.
    NSDate *now = [NSDate date];
    for (NSNumber *senderId in [self.typingBySender copy]) {
        NSDictionary *entry = self.typingBySender[senderId];
        NSDate *at = entry[@"time"];
        if ([at isKindOfClass:[NSDate class]] && [now timeIntervalSinceDate:at] > 6.0) {
            [self.typingBySender removeObjectForKey:senderId];
        }
    }
    if (self.typingBySender.count > 0) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSNumber *senderId in self.typingBySender) {
            NSString *name = [self.client displayNameForSender:self.typingBySender[senderId][@"sender"]];
            if (name.length > 0) {
                [names addObject:name];
            } else {
                [names addObject:@"Ktoś"];
            }
        }
        if (names.count == 1) {
            self.subtitleHeaderLabel.text = [names[0] stringByAppendingString:@" pisze…"];
        } else if (names.count == 2) {
            self.subtitleHeaderLabel.text = [NSString stringWithFormat:@"%@ i %@ piszą…", names[0], names[1]];
        } else {
            self.subtitleHeaderLabel.text = [NSString stringWithFormat:@"%lu osób pisze…", (unsigned long)names.count];
        }
        self.subtitleHeaderLabel.textColor = [TGTheme accentColor];
        return;
    }

    NSDictionary *chat = [self.client chatWithId:self.chatId];
    if (chat == nil) return;
    NSDictionary *type = chat[@"type"];
    NSString *typeName = TGStringValue(type[@"@type"]);

    if ([typeName isEqualToString:@"chatTypePrivate"] || [typeName isEqualToString:@"chatTypeSecret"]) {
        int64_t userId = TGInt64Value(type[@"user_id"]);
        NSDictionary *user = [self.client userWithId:userId];
        if (user != nil) {
            NSDictionary *status = user[@"status"];
            NSString *statusType = TGStringValue(status[@"@type"]);
            if ([statusType isEqualToString:@"userStatusOnline"]) {
                self.subtitleHeaderLabel.text = @"online";
                self.subtitleHeaderLabel.textColor = [TGTheme accentColor];
                return;
            } else if ([statusType isEqualToString:@"userStatusOffline"]) {
                int32_t was = TGInt32Value(status[@"was_online"]);
                if (was > 0) {
                    self.subtitleHeaderLabel.text = [NSString stringWithFormat:@"był(a) %@", [TGTheme chatListTimeStringForTimestamp:was]];
                } else {
                    self.subtitleHeaderLabel.text = @"niedawno";
                }
                self.subtitleHeaderLabel.textColor = [TGTheme secondaryTextColor];
                return;
            } else if ([statusType isEqualToString:@"userStatusRecently"]) {
                self.subtitleHeaderLabel.text = @"niedawno";
                self.subtitleHeaderLabel.textColor = [TGTheme secondaryTextColor];
                return;
            }
        }
    } else if ([typeName isEqualToString:@"chatTypeBasicGroup"] || [typeName isEqualToString:@"chatTypeSupergroup"]) {
        int32_t count = TGInt32Value(chat[@"member_count"]);
        if (count > 0) {
            self.subtitleHeaderLabel.text = [NSString stringWithFormat:@"%d członków", count];
        } else {
            self.subtitleHeaderLabel.text = @"grupa";
        }
        self.subtitleHeaderLabel.textColor = [TGTheme secondaryTextColor];
        return;
    } else if (chat[@"is_channel"] != nil && TGBoolValue(chat[@"is_channel"])) {
        self.subtitleHeaderLabel.text = @"kanał";
        self.subtitleHeaderLabel.textColor = [TGTheme secondaryTextColor];
        return;
    }
}

- (void)presentAttachmentActionSheet {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Zdjęcie z galerii" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        }]];
    }
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Zrób zdjęcie" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.sourceType = UIImagePickerControllerSourceTypeCamera;
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        }]];
    }
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Stickery" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf toggleStickerPicker];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Anuluj" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController != nil) {
        sheet.popoverPresentationController.sourceView = self.inputBar;
        sheet.popoverPresentationController.sourceRect = self.inputBar.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toggleStickerPicker {
    if (self.stickerPickerVisible) {
        [self hideStickerPickerAnimated:YES];
    } else {
        [self showStickerPickerAnimated:YES];
    }
}

/// Shows the sticker grid panel above the input bar (Telegram X style): the
/// message list shrinks so the last messages stay visible above the panel.
- (void)showStickerPickerAnimated:(BOOL)animated {
    if (self.stickerPickerVisible) {
        return;
    }
    [self.inputBar.textField resignFirstResponder];

    if (self.stickerPickerView == nil) {
        TGStickerPickerView *picker = [[TGStickerPickerView alloc] initWithClient:self.client];
        picker.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view insertSubview:picker belowSubview:self.inputBar];

        self.pickerBottomConstraint = [picker.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor];
        [NSLayoutConstraint activateConstraints:@[
            [picker.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [picker.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [picker.heightAnchor constraintEqualToConstant:280.0],
            self.pickerBottomConstraint
        ]];

        __weak typeof(self) weakSelf = self;
        picker.onSelectSticker = ^(NSDictionary *sticker) {
            [weakSelf hideStickerPickerAnimated:YES];
            [weakSelf sendSticker:sticker];
        };
        picker.onClose = ^{
            [weakSelf hideStickerPickerAnimated:YES];
        };
        self.stickerPickerView = picker;
    }

    if (self.tableBottomToPickerConstraint == nil) {
        self.tableBottomToPickerConstraint = [self.tableView.bottomAnchor constraintEqualToAnchor:self.stickerPickerView.topAnchor];
    }

    self.tableBottomToInputConstraint.active = NO;
    self.tableBottomToPickerConstraint.active = YES;
    self.stickerPickerVisible = YES;
    self.stickerPickerView.hidden = NO;
    self.stickerPickerView.transform = CGAffineTransformMakeTranslation(0.0, 280.0);
    [self.stickerPickerView reloadFromServer];

    void (^animations)(void) = ^{
        self.stickerPickerView.transform = CGAffineTransformIdentity;
        [self.view layoutIfNeeded];
    };
    if (animated) {
        [UIView animateWithDuration:0.25
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:animations
                         completion:nil];
    } else {
        animations();
    }

    if ([self isNearBottom]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToBottomAnimated:YES];
        });
    }
}

- (void)hideStickerPickerAnimated:(BOOL)animated {
    if (!self.stickerPickerVisible || self.stickerPickerView == nil) {
        return;
    }
    self.stickerPickerVisible = NO;
    self.tableBottomToPickerConstraint.active = NO;
    self.tableBottomToInputConstraint.active = YES;

    __weak typeof(self) weakSelf = self;
    void (^animations)(void) = ^{
        weakSelf.stickerPickerView.transform = CGAffineTransformMakeTranslation(0.0, 280.0);
        [weakSelf.view layoutIfNeeded];
    };
    void (^finish)(void) = ^{
        weakSelf.stickerPickerView.hidden = YES;
        weakSelf.stickerPickerView.transform = CGAffineTransformIdentity;
    };
    if (animated) {
        [UIView animateWithDuration:0.25
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:animations
                         completion:^(BOOL finished) {
            finish();
        }];
    } else {
        animations();
        finish();
    }
}

- (void)sendSticker:(NSDictionary *)sticker {
    __weak typeof(self) weakSelf = self;
    [self.client sendSticker:sticker toChat:self.chatId completion:^(NSDictionary *message, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (message != nil) {
                [weakSelf upsertMessageDictionary:message scrollToBottom:YES forceScroll:YES];
                return;
            }
            NSString *messageText = TGStringValue(error[@"message"]);
            if (messageText.length == 0) {
                messageText = @"Nie udało się wysłać stickera.";
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Błąd wysyłania"
                                                                            message:messageText
                                                                     preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image == nil) return;

    NSString *tmpDir = NSTemporaryDirectory();
    NSString *filePath = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"send_%llu.jpg", (unsigned long long)(CACurrentMediaTime() * 1000.0)]];
    NSData *data = UIImageJPEGRepresentation(image, 0.85);
    [data writeToFile:filePath atomically:YES];

    __weak typeof(self) weakSelf = self;
    [self.client sendPhotoAtPath:filePath toChat:self.chatId caption:nil completion:^(NSDictionary *message, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (message != nil) {
                [weakSelf upsertMessageDictionary:message scrollToBottom:YES forceScroll:YES];
                return;
            }
            NSString *messageText = TGStringValue(error[@"message"]);
            if (messageText.length == 0) {
                messageText = @"Nie udało się wysłać zdjęcia.";
            }
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Błąd wysyłania"
                                                                            message:messageText
                                                                     preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        });
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)upsertMessageDictionary:(NSDictionary *)dictionary scrollToBottom:(BOOL)scroll forceScroll:(BOOL)forceScroll {
    TGMessage *message = [TGMessage messageWithDictionary:dictionary];
    if (message.messageId == 0) {
        return;
    }
    NSNumber *key = @(message.messageId);
    NSNumber *existingIndex = self.messageIndexById[key];
    BOOL nearBottom = [self isNearBottom];

    if (existingIndex != nil && existingIndex.unsignedIntegerValue < self.messages.count) {
        TGMessage *existing = self.messages[existingIndex.unsignedIntegerValue];
        [existing updateWithDictionary:dictionary];
        [self.tableView reloadData];
    } else {
        NSUInteger insertIndex = self.messages.count;
        for (NSUInteger i = 0; i < self.messages.count; i++) {
            if (self.messages[i].messageId > message.messageId) {
                insertIndex = i;
                break;
            }
        }
        [self.messages insertObject:message atIndex:insertIndex];
        [self rebuildMessageIndex];
        [self recomputeDateDividers];
        [self.tableView reloadData];
    }

    self.totalCount = MAX(self.totalCount, (NSInteger)self.messages.count);
    [self updateEmptyState];

    if (scroll && (forceScroll || nearBottom)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToBottomAnimated:YES];
        });
    }
}

- (void)replaceMessageId:(int64_t)oldMessageId withDictionary:(NSDictionary *)dictionary {
    TGMessage *newMessage = [TGMessage messageWithDictionary:dictionary];
    if (newMessage.messageId == 0) {
        return;
    }

    NSNumber *oldIndexNumber = self.messageIndexById[@(oldMessageId)];
    if (oldIndexNumber != nil && oldIndexNumber.unsignedIntegerValue < self.messages.count) {
        self.messages[oldIndexNumber.unsignedIntegerValue] = newMessage;
        [self rebuildMessageIndex];
    } else {
        NSNumber *existingIndex = self.messageIndexById[@(newMessage.messageId)];
        if (existingIndex != nil && existingIndex.unsignedIntegerValue < self.messages.count) {
            self.messages[existingIndex.unsignedIntegerValue] = newMessage;
        } else {
            [self.messages addObject:newMessage];
            [self rebuildMessageIndex];
            [self recomputeDateDividers];
        }
    }
    [self.tableView reloadData];
    [self updateEmptyState];

    if ([self isNearBottom]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToBottomAnimated:YES];
        });
    }
}

- (void)updateEmptyState {
    self.emptyLabel.hidden = self.messages.count > 0 || self.spinner.isAnimating;
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TGMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TGMessageCell" forIndexPath:indexPath];
    TGMessage *message = self.messages[(NSUInteger)indexPath.row];
    NSString *senderName = @"";
    if (!message.isOutgoing && !message.isService) {
        senderName = [self.client displayNameForSender:message.raw[@"sender_id"]];
    }
    [cell configureWithMessage:message showSender:self.showSenderNames senderName:senderName client:self.client];

    __weak typeof(self) weakSelf = self;
    cell.onMediaTap = ^(TGMessage *msg) {
        [weakSelf handleMediaTapForMessage:msg];
    };
    cell.onRetryTap = ^(TGMessage *msg) {
        [weakSelf resendFailedMessage:msg];
    };
    return cell;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.contentOffset.y < 120.0 && !self.loadingOlder && !self.reachedOldestMessage && self.messages.count > 0 && self.didInitialLoad) {
        [self loadOlderHistory];
    }
}

- (void)handleMediaTapForMessage:(TGMessage *)message {
    if (message.messageType == TGMessageTypePhoto) {
        int32_t fileId = message.mediaFileId > 0 ? message.mediaFileId : message.thumbnailFileId;
        NSString *path = [self.client localPathForFileId:fileId];
        if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            TGPhotoViewerController *viewer = [[TGPhotoViewerController alloc] initWithImagePath:path];
            [self presentViewController:viewer animated:YES completion:nil];
        } else if (fileId > 0) {
            __weak typeof(self) weakSelf = self;
            [self.client downloadFileWithId:fileId priority:32 completion:^(NSString *downloadedPath, NSDictionary *file) {
                if (downloadedPath.length > 0) {
                    TGPhotoViewerController *viewer = [[TGPhotoViewerController alloc] initWithImagePath:downloadedPath];
                    [weakSelf presentViewController:viewer animated:YES completion:nil];
                }
            }];
        }
    } else if (message.messageType == TGMessageTypeVideo || message.messageType == TGMessageTypeAnimation) {
        int32_t fileId = message.mediaFileId;
        NSString *path = [self.client localPathForFileId:fileId];
        if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self playVideoAtPath:path isLooping:(message.messageType == TGMessageTypeAnimation)];
        } else if (fileId > 0) {
            __weak typeof(self) weakSelf = self;
            [self.client downloadFileWithId:fileId priority:32 completion:^(NSString *downloadedPath, NSDictionary *file) {
                if (downloadedPath.length > 0) {
                    [weakSelf playVideoAtPath:downloadedPath isLooping:(message.messageType == TGMessageTypeAnimation)];
                }
            }];
        }
    } else if (message.messageType == TGMessageTypeVoiceNote || message.messageType == TGMessageTypeAudio) {
        [self playAudioForMessage:message];
    } else if (message.messageType == TGMessageTypeDocument) {
        [self openDocumentForMessage:message];
    }
}

// Voice notes are Ogg/Opus — AVAudioPlayer may refuse them on iOS; fall back
// to a clear message instead of silence.
- (void)playAudioForMessage:(TGMessage *)message {
    int32_t fileId = message.mediaFileId > 0 ? message.mediaFileId : message.thumbnailFileId;
    __weak typeof(self) weakSelf = self;
    void (^playBlock)(NSString *path) = ^(NSString *path) {
        if (weakSelf == nil || path.length == 0) {
            return;
        }
        weakSelf.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:nil];
        if (weakSelf.audioPlayer != nil) {
            [weakSelf.audioPlayer play];
        } else {
            [weakSelf presentSimpleAlertWithTitle:@"Nie można odtworzyć"
                                             message:@"Ten format audio nie jest jeszcze obsługiwany (ogg/opus)."];
        }
    };
    if (fileId <= 0) {
        [self presentSimpleAlertWithTitle:@"Nie można odtworzyć" message:@"Brak pliku audio w wiadomości."];
        return;
    }
    NSString *path = [self.client localPathForFileId:fileId];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        playBlock(path);
    } else {
        [self.client downloadFileWithId:fileId priority:32 completion:^(NSString *downloadedPath, NSDictionary *file) {
            dispatch_async(dispatch_get_main_queue(), ^{
                playBlock(downloadedPath);
            });
        }];
    }
}

- (void)openDocumentForMessage:(TGMessage *)message {
    int32_t fileId = message.mediaFileId > 0 ? message.mediaFileId : message.thumbnailFileId;
    if (fileId <= 0) {
        [self presentSimpleAlertWithTitle:@"Nie można otworzyć" message:@"Brak pliku w wiadomości."];
        return;
    }
    __weak typeof(self) weakSelf = self;
    void (^openBlock)(NSString *path) = ^(NSString *path) {
        if (weakSelf == nil || path.length == 0) {
            return;
        }
        UIDocumentInteractionController *controller = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:path]];
        weakSelf.documentController = controller;
        [controller presentPreviewAnimated:YES];
    };
    NSString *path = [self.client localPathForFileId:fileId];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        openBlock(path);
    } else {
        [self.client downloadFileWithId:fileId priority:32 completion:^(NSString *downloadedPath, NSDictionary *file) {
            dispatch_async(dispatch_get_main_queue(), ^{
                openBlock(downloadedPath);
            });
        }];
    }
}

/// Tapping a failed bubble re-sends it (TDLib swaps the message id on success).
- (void)resendFailedMessage:(TGMessage *)message {
    __weak typeof(self) weakSelf = self;
    [self.client resendMessages:@[@(message.messageId)] inChat:self.chatId completion:^(NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *messageText = TGStringValue(error[@"message"]);
            if (messageText.length > 0) {
                [weakSelf presentSimpleAlertWithTitle:@"Nie udało się ponowić"
                                                message:messageText];
            }
        });
    }];
}

- (void)presentSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)playVideoAtPath:(NSString *)path isLooping:(BOOL)isLooping {
    NSURL *url = [NSURL fileURLWithPath:path];
    AVPlayer *player = [AVPlayer playerWithURL:url];
    AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
    playerVC.player = player;

    if (isLooping) {
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                          object:[player currentItem]
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [player seekToTime:kCMTimeZero];
            [player play];
        }];
    }

    [self presentViewController:playerVC animated:YES completion:^{
        [player play];
    }];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    TGMessage *message = self.messages[(NSUInteger)indexPath.row];
    return [TGMessageCell heightForMessage:message width:CGRectGetWidth(tableView.bounds) showSender:self.showSenderNames];
}

#pragma mark - Keyboard

- (void)keyboardWillChangeFrame:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(converted));
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat offset = MAX(0.0, overlap - safeBottom);
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    self.inputBottomConstraint.constant = -offset;
    [self.view layoutIfNeeded];
    [UIView commitAnimations];

    if (offset > 0.0) {
        // The keyboard takes over the panel area; Telegram X closes the
        // sticker pane the same way when the text field gets focus.
        [self hideStickerPickerAnimated:NO];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToBottomAnimated:YES];
        });
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:duration];
    [UIView setAnimationCurve:curve];
    self.inputBottomConstraint.constant = 0.0;
    [self.view layoutIfNeeded];
    [UIView commitAnimations];
}

@end
