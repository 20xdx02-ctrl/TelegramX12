#import "TGChatViewController.h"

#import "TGAvatarView.h"
#import "TGChatPickerViewController.h"
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
@property (nonatomic, strong) NSLayoutConstraint *inputHeightConstraint;
@property (nonatomic, strong, nullable) TGMessage *replyTargetMessage;
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
@property (nonatomic, strong) UIButton *scrollToBottomButton;
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
    // Exact heights come from heightForRowAtIndexPath; leaving estimates on
    // makes UITableView place rows at estimated offsets and then correct them
    // when paginating history, which reads as the list jumping.
    self.tableView.estimatedRowHeight = 0.0;
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
    self.inputBar.onCancelReply = ^{
        [weakSelf cancelReply];
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
    self.inputHeightConstraint = [self.inputBar.heightAnchor constraintEqualToConstant:50.0];
    self.tableBottomToInputConstraint = [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.tableBottomToInputConstraint,

        [self.inputBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.inputBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.inputHeightConstraint,
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

    // Floating scroll-to-bottom button
    self.scrollToBottomButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollToBottomButton.backgroundColor = [UIColor whiteColor];
    self.scrollToBottomButton.layer.cornerRadius = 20.0;
    self.scrollToBottomButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.scrollToBottomButton.layer.shadowOpacity = 0.18;
    self.scrollToBottomButton.layer.shadowRadius = 4.0;
    self.scrollToBottomButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.scrollToBottomButton.clipsToBounds = NO;
    [self.scrollToBottomButton setTitle:@"↓" forState:UIControlStateNormal];
    [self.scrollToBottomButton setTitleColor:[TGTheme accentColor] forState:UIControlStateNormal];
    self.scrollToBottomButton.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightMedium];
    self.scrollToBottomButton.alpha = 0.0;
    [self.scrollToBottomButton addTarget:self action:@selector(scrollToBottomButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.scrollToBottomButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollToBottomButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [self.scrollToBottomButton.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor constant:-12.0],
        [self.scrollToBottomButton.widthAnchor constraintEqualToConstant:40.0],
        [self.scrollToBottomButton.heightAnchor constraintEqualToConstant:40.0],
    ]];
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
            // Sender names affect row heights (group layouts) — settle this
            // before laying out and scrolling, otherwise cells reflow and the
            // list visibly jumps right after opening the chat.
            [weakSelf updateSenderVisibility];
            [weakSelf placeUnreadDividerIfNeeded];
            [weakSelf.tableView reloadData];
            [weakSelf.tableView layoutIfNeeded];
            if (weakSelf.unreadDividerMessage != nil) {
                [weakSelf scrollToUnreadDividerAnimated:NO];
            } else {
                [weakSelf scrollToBottomAnimated:NO];
            }
            [weakSelf markMessagesRead];
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
    [self rebuildMessageLayout];
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
            [weakSelf rebuildMessageLayout];

            // Insert the rows at the top incrementally, then shift the offset
            // by the growth in content size so the visible messages stay put.
            if ([weakSelf.tableView numberOfRowsInSection:0] + (NSInteger)newMessages.count == (NSInteger)weakSelf.messages.count) {
                NSMutableArray *insertPaths = [NSMutableArray arrayWithCapacity:newMessages.count];
                for (NSUInteger i = 0; i < newMessages.count; i++) {
                    [insertPaths addObject:[NSIndexPath indexPathForRow:i inSection:0]];
                }
                [weakSelf.tableView beginUpdates];
                [weakSelf.tableView insertRowsAtIndexPaths:insertPaths withRowAnimation:UITableViewRowAnimationNone];
                [weakSelf.tableView endUpdates];
            } else {
                [weakSelf.tableView reloadData];
            }
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
        if (message.isAlbum) {
            for (TGMessage *member in message.albumMessages) {
                if (member.messageId != 0) {
                    self.messageIndexById[@(member.messageId)] = @(index);
                }
            }
        }
        if (message.messageId != 0) {
            self.messageIndexById[@(message.messageId)] = @(index);
        }
    }];
}

#pragma mark - Albums

/// Splits every synthetic album row back into its member messages.
- (void)expandAlbums {
    NSMutableArray<TGMessage *> *expanded = [NSMutableArray arrayWithCapacity:self.messages.count];
    for (TGMessage *message in self.messages) {
        if (message.isAlbum && message.albumMessages.count > 0) {
            [expanded addObjectsFromArray:message.albumMessages];
        } else {
            [expanded addObject:message];
        }
    }
    [self.messages removeAllObjects];
    [self.messages addObjectsFromArray:expanded];
    [self rebuildMessageIndex];
}

- (TGMessage *)albumMessageWithMembers:(NSArray<TGMessage *> *)members {
    TGMessage *first = members.firstObject;
    TGMessage *last = members.lastObject;
    TGMessage *album = [[TGMessage alloc] init];
    // Use the last member id: it lets the unread divider detect a partially
    // unread album correctly (first id may already be below last_read_inbox).
    album.messageId = last.messageId;
    album.chatId = self.chatId;
    album.date = first.date;
    album.isOutgoing = first.isOutgoing;
    album.senderId = first.senderId;
    album.senderIsUser = first.senderIsUser;
    album.raw = first.raw;
    album.isRead = last.isRead;
    album.isSending = last.isSending;
    album.isFailed = last.isFailed;
    album.isAlbum = YES;
    album.mediaAlbumId = first.mediaAlbumId;
    album.albumMessages = members;
    album.forwardInfo = first.forwardInfo;
    album.replyToMessageId = first.replyToMessageId;
    album.replyToText = first.replyToText;
    album.replyToSenderName = first.replyToSenderName;
    album.replyToOrigin = first.replyToOrigin;
    album.editDate = first.editDate;
    album.messageType = (first.messageType == TGMessageTypeVideo) ? TGMessageTypeVideo : TGMessageTypePhoto;
    for (TGMessage *member in members) {
        if (member.mediaCaption.length > 0 && album.mediaCaption.length == 0) {
            album.mediaCaption = member.mediaCaption;
        }
        album.isSending = album.isSending || member.isSending;
        album.isFailed = album.isFailed || member.isFailed;
    }
    return album;
}

/// Merges consecutive photo/video messages that belong to the same TDLib
/// media album into one synthetic collage row.
- (void)recomputeAlbums {
    [self expandAlbums];

    NSMutableArray<TGMessage *> *result = [NSMutableArray arrayWithCapacity:self.messages.count];
    NSUInteger index = 0;
    while (index < self.messages.count) {
        TGMessage *message = self.messages[index];
        BOOL groupable = !message.isService &&
            message.mediaAlbumId != 0 &&
            (message.messageType == TGMessageTypePhoto || message.messageType == TGMessageTypeVideo);
        if (!groupable) {
            [result addObject:message];
            index += 1;
            continue;
        }

        NSMutableArray<TGMessage *> *members = [NSMutableArray arrayWithObject:message];
        NSUInteger next = index + 1;
        while (next < self.messages.count) {
            TGMessage *candidate = self.messages[next];
            if (candidate.isService ||
                candidate.mediaAlbumId != message.mediaAlbumId ||
                candidate.senderId != message.senderId ||
                candidate.isOutgoing != message.isOutgoing ||
                (candidate.messageType != TGMessageTypePhoto && candidate.messageType != TGMessageTypeVideo)) {
                break;
            }
            [members addObject:candidate];
            next += 1;
        }

        if (members.count >= 2) {
            [result addObject:[self albumMessageWithMembers:members]];
        } else {
            [result addObject:message];
        }
        index = next;
    }

    [self.messages removeAllObjects];
    [self.messages addObjectsFromArray:result];
    [self rebuildMessageIndex];
}

/// Rebuilds album collages and day dividers after the message list changes.
- (void)rebuildMessageLayout {
    [self recomputeAlbums];
    [self recomputeDateDividers];
    // Keep the id → row map in sync; targeted row updates below rely on it.
    [self rebuildMessageIndex];
}

- (NSArray<NSNumber *> *)messageIdsForMessage:(TGMessage *)message {
    if (message.isAlbum) {
        NSMutableArray<NSNumber *> *ids = [NSMutableArray arrayWithCapacity:message.albumMessages.count];
        for (TGMessage *member in message.albumMessages) {
            if (member.messageId != 0) {
                [ids addObject:@(member.messageId)];
            }
        }
        if (ids.count > 0) {
            return ids;
        }
    }
    return @[@(message.messageId)];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateScrollToBottomButtonVisibility];
    });
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
    int64_t replyToId = self.replyTargetMessage.messageId;
    if (replyToId > 0) {
        [self cancelReply];
    }
    __weak typeof(self) weakSelf = self;
    [self.client sendText:text toChat:self.chatId replyToMessageId:replyToId completion:^(NSDictionary *message, NSDictionary *error) {
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

#pragma mark - Message actions (M3)

/// One-line label describing a message inside reply quotes and action sheets.
- (NSString *)previewTextForMessage:(TGMessage *)message {
    if (message.text.length > 0) {
        return message.text;
    }
    if (message.mediaCaption.length > 0) {
        return message.mediaCaption;
    }
    switch (message.messageType) {
        case TGMessageTypePhoto: return @"Zdjęcie";
        case TGMessageTypeVideo: return @"Wideo";
        case TGMessageTypeAnimation: return @"GIF";
        case TGMessageTypeSticker: return message.stickerEmoji.length > 0 ? message.stickerEmoji : @"Sticker";
        case TGMessageTypeVoiceNote: return @"Wiadomość głosowa";
        case TGMessageTypeAudio: return message.mediaTitle.length > 0 ? message.mediaTitle : @"Audio";
        case TGMessageTypeDocument: return message.mediaFileName.length > 0 ? message.mediaFileName : @"Dokument";
        case TGMessageTypeContact: return message.contactName.length > 0 ? message.contactName : @"Kontakt";
        case TGMessageTypeLocation: return @"Lokalizacja";
        case TGMessageTypePoll: return message.pollQuestion.length > 0 ? message.pollQuestion : @"Ankieta";
        default: return @"Wiadomość";
    }
}

- (NSString *)senderNameForMessage:(TGMessage *)message {
    if (message.isOutgoing) {
        return @"Ty";
    }
    if (message.raw[@"sender_id"] != nil) {
        NSString *name = [self.client displayNameForSender:message.raw[@"sender_id"]];
        if (name.length > 0 && ![name isEqualToString:@"…"]) {
            return name;
        }
    }
    return self.chatTitleForDisplay.length > 0 ? self.chatTitleForDisplay : @"Wiadomość";
}

/// Fills `replyToSenderName`/`replyToText` on replies from locally loaded
/// messages, so the quote strip can show the original sender immediately.
- (void)resolveReplyMetadataForMessage:(TGMessage *)message {
    if (message.replyToMessageId <= 0) {
        return;
    }
    BOOL needsSenderName = message.replyToSenderName.length == 0 || [message.replyToSenderName isEqualToString:@"…"];
    if (needsSenderName && message.replyToOrigin != nil) {
        NSString *originName = [self.client displayNameForMessageOrigin:message.replyToOrigin];
        if (originName.length > 0) {
            message.replyToSenderName = originName;
            needsSenderName = [originName isEqualToString:@"…"];
        }
    }
    if (!needsSenderName && message.replyToText.length > 0) {
        return;
    }
    NSNumber *indexNumber = self.messageIndexById[@(message.replyToMessageId)];
    if (indexNumber == nil || indexNumber.unsignedIntegerValue >= self.messages.count) {
        return;
    }
    TGMessage *target = self.messages[indexNumber.unsignedIntegerValue];
    if (message.replyToText.length == 0) {
        message.replyToText = [self previewTextForMessage:target];
    }
    if (needsSenderName) {
        message.replyToSenderName = [self senderNameForMessage:target];
    }
}

- (void)presentMessageActionsForMessage:(TGMessage *)message {
    if (message.isService || message.isDateDivider || message.isUnreadDivider || message.messageId == 0) {
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    NSString *copyText = message.text.length > 0 ? message.text : message.mediaCaption;
    if (copyText.length > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Kopiuj" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [UIPasteboard generalPasteboard].string = copyText;
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Odpowiedz" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf beginReplyToMessage:message];
        });
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Przekaż" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf presentForwardPickerForMessage:message];
        });
    }]];

    if (message.isOutgoing && message.messageType == TGMessageTypeText && !message.isSending && !message.isFailed) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Edytuj" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf presentEditAlertForMessage:message];
            });
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Usuń" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf confirmDeleteMessage:message];
        });
    }]];

    // Quick reaction row: 👍 ❤️ 😂 😮 😢 🔥
    NSArray *quickEmojis = @[@"👍", @"❤️", @"😂", @"😮", @"😢", @"🔥"];
    for (NSString *emoji in quickEmojis) {
        [sheet addAction:[UIAlertAction actionWithTitle:emoji style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [weakSelf handleReactionTap:emoji forMessage:message];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Anuluj" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController != nil) {
        NSNumber *indexNumber = self.messageIndexById[@(message.messageId)];
        NSIndexPath *indexPath = indexNumber != nil
            ? [NSIndexPath indexPathForRow:(NSInteger)indexNumber.unsignedIntegerValue inSection:0]
            : nil;
        UITableViewCell *cell = indexPath != nil ? [self.tableView cellForRowAtIndexPath:indexPath] : nil;
        if (cell != nil) {
            sheet.popoverPresentationController.sourceView = cell;
            sheet.popoverPresentationController.sourceRect = cell.bounds;
        } else {
            sheet.popoverPresentationController.sourceView = self.view;
            sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                                        CGRectGetMidY(self.view.bounds),
                                                                        1.0, 1.0);
        }
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)beginReplyToMessage:(TGMessage *)message {
    self.replyTargetMessage = message;
    NSString *name = [self senderNameForMessage:message];
    NSString *preview = [self previewTextForMessage:message];
    [self.inputBar showReplyToName:name text:preview];
    [self updateInputBarHeightAnimated:YES];
    [self.inputBar focus];
}

- (void)cancelReply {
    if (self.replyTargetMessage == nil && self.inputBar.preferredHeight <= 50.0) {
        return;
    }
    self.replyTargetMessage = nil;
    [self.inputBar hideReply];
    [self updateInputBarHeightAnimated:YES];
}

- (void)updateInputBarHeightAnimated:(BOOL)animated {
    CGFloat height = self.inputBar.preferredHeight;
    if (fabs(self.inputHeightConstraint.constant - height) < 0.5) {
        return;
    }
    self.inputHeightConstraint.constant = height;
    if (animated) {
        [UIView animateWithDuration:0.2 animations:^{
            [self.view layoutIfNeeded];
        }];
    } else {
        [self.view layoutIfNeeded];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scrollToBottomAnimated:animated];
    });
}

- (void)presentEditAlertForMessage:(TGMessage *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Edytuj wiadomość"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = message.text;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Anuluj" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Zapisz" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *newText = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (newText.length == 0 || [newText isEqualToString:message.text]) {
            return;
        }
        [weakSelf.client editMessageText:newText inChat:weakSelf.chatId messageId:message.messageId completion:^(NSDictionary *edited, NSDictionary *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (edited != nil) {
                    [weakSelf upsertMessageDictionary:edited scrollToBottom:NO forceScroll:NO];
                } else {
                    [weakSelf presentSimpleAlertWithTitle:@"Nie udało się edytować"
                                                   message:TGStringValue(error[@"message"]) ?: @"Spróbuj ponownie."];
                }
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmDeleteMessage:(TGMessage *)message {
    NSString *title = message.isOutgoing
        ? (message.isAlbum ? @"Usunąć album u wszystkich?" : @"Usunąć wiadomość u wszystkich?")
        : (message.isAlbum ? @"Usunąć album?" : @"Usunąć wiadomość?");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Anuluj" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Usuń" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [weakSelf.client deleteMessages:[weakSelf messageIdsForMessage:message]
                                  inChat:weakSelf.chatId
                                  revoke:message.isOutgoing
                              completion:^(NSDictionary *error) {
            if (error == nil) {
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf presentSimpleAlertWithTitle:@"Nie udało się usunąć"
                                               message:TGStringValue(error[@"message"]) ?: @"Spróbuj ponownie."];
            });
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentForwardPickerForMessage:(TGMessage *)message {
    __weak typeof(self) weakSelf = self;
    TGChatPickerViewController *picker = [[TGChatPickerViewController alloc] initWithClient:self.client
                                                                           excludingChatId:self.chatId
                                                                                completion:^(int64_t chatId, NSString *title) {
        [weakSelf dismissViewControllerAnimated:YES completion:^{
            [weakSelf.client forwardMessages:[weakSelf messageIdsForMessage:message]
                                    fromChat:weakSelf.chatId
                                      toChat:chatId
                                  completion:^(NSArray<NSDictionary *> *messages, NSDictionary *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error != nil) {
                        [weakSelf presentSimpleAlertWithTitle:@"Nie udało się przekazać"
                                                       message:TGStringValue(error[@"message"]) ?: @"Spróbuj ponownie."];
                        return;
                    }
                    NSString *name = title.length > 0 ? title : @"czatu";
                    [weakSelf presentSimpleAlertWithTitle:@"Przekazano"
                                                   message:[NSString stringWithFormat:@"Wiadomość trafiła do %@.", name]];
                });
            }];
        }];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
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
        [self expandAlbums];
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
        [self rebuildMessageLayout];
        [self reloadMessageRowAtIndex:(NSInteger)index];
        return;
    }

    if ([type isEqualToString:@"updateMessageEdited"]) {
        if (TGInt64Value(update[@"chat_id"]) != self.chatId) {
            return;
        }
        [self expandAlbums];
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
        raw[@"edit_date"] = update[@"edit_date"] ?: @0;
        [message updateWithDictionary:raw];
        [self rebuildMessageLayout];
        [self reloadMessageRowAtIndex:(NSInteger)index];
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
        [self expandAlbums];
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
        // Capture the row paths while the index map is still valid, then
        // remove incrementally so the table does not jump.
        NSMutableArray *deletePaths = [NSMutableArray array];
        [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
            [deletePaths addObject:[NSIndexPath indexPathForRow:index inSection:0]];
        }];
        NSInteger rowsBefore = [self.tableView numberOfRowsInSection:0];
        [self.messages removeObjectsAtIndexes:indexes];
        [self rebuildMessageLayout];
        if (rowsBefore == (NSInteger)deletePaths.count + (NSInteger)self.messages.count) {
            [self.tableView beginUpdates];
            [self.tableView deleteRowsAtIndexPaths:deletePaths withRowAnimation:UITableViewRowAnimationFade];
            [self.tableView endUpdates];
        } else {
            [self.tableView reloadData];
        }
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
            __block BOOL didUpdate = NO;
            NSMutableArray *changedPaths = [NSMutableArray array];
            [self.messages enumerateObjectsUsingBlock:^(TGMessage *msg, NSUInteger index, BOOL *stop) {
                if (msg.isOutgoing && !msg.isRead && msg.messageId <= lastReadId) {
                    msg.isRead = YES;
                    didUpdate = YES;
                    [changedPaths addObject:[NSIndexPath indexPathForRow:index inSection:0]];
                }
            }];
            // Reload only the affected rows so the scroll position stays put.
            if (didUpdate && [self.tableView numberOfRowsInSection:0] == (NSInteger)self.messages.count) {
                [self.tableView reloadRowsAtIndexPaths:changedPaths withRowAnimation:UITableViewRowAnimationNone];
            }
        }
        return;
    }

    if ([type isEqualToString:@"updateMessageInteractionInfo"]) {
        if (TGInt64Value(update[@"chat_id"]) != self.chatId) {
            return;
        }
        int64_t messageId = TGInt64Value(update[@"message_id"]);
        NSNumber *indexNumber = self.messageIndexById[@(messageId)];
        if (indexNumber == nil || indexNumber.unsignedIntegerValue >= self.messages.count) {
            return;
        }
        TGMessage *message = self.messages[indexNumber.unsignedIntegerValue];
        // Re-parse reactions from the update's interaction_info
        NSMutableDictionary *raw = [message.raw mutableCopy] ?: [NSMutableDictionary dictionary];
        raw[@"interaction_info"] = update[@"interaction_info"] ?: @{};
        [message updateWithDictionary:raw];
        [self reloadMessageRowAtIndex:(NSInteger)indexNumber.unsignedIntegerValue];
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
    [self expandAlbums];
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
        [self rebuildMessageLayout];
        [self reloadMessageRowAtIndex:existingIndex.unsignedIntegerValue];
    } else {
        NSUInteger insertIndex = self.messages.count;
        for (NSUInteger i = 0; i < self.messages.count; i++) {
            if (self.messages[i].messageId > message.messageId) {
                insertIndex = i;
                break;
            }
        }
        [self.messages insertObject:message atIndex:insertIndex];
        [self rebuildMessageLayout];
        [self insertMessageRowAtIndex:(NSInteger)insertIndex];
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
    [self expandAlbums];
    TGMessage *newMessage = [TGMessage messageWithDictionary:dictionary];
    if (newMessage.messageId == 0) {
        return;
    }

    NSNumber *oldIndexNumber = self.messageIndexById[@(oldMessageId)];
    if (oldIndexNumber != nil && oldIndexNumber.unsignedIntegerValue < self.messages.count) {
        NSUInteger oldIndex = oldIndexNumber.unsignedIntegerValue;
        self.messages[oldIndex] = newMessage;
        [self rebuildMessageLayout];
        NSNumber *newIndexNumber = self.messageIndexById[@(newMessage.messageId)];
        [self reloadMessageRowAtIndex:(newIndexNumber != nil
                                           ? (NSInteger)newIndexNumber.unsignedIntegerValue
                                           : (NSInteger)oldIndex)];
    } else {
        NSNumber *existingIndex = self.messageIndexById[@(newMessage.messageId)];
        if (existingIndex != nil && existingIndex.unsignedIntegerValue < self.messages.count) {
            self.messages[existingIndex.unsignedIntegerValue] = newMessage;
        } else {
            [self.messages addObject:newMessage];
        }
        [self rebuildMessageLayout];
        [self insertMessageRowAtIndex:(NSInteger)(self.messages.count - 1)];
    }
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

#pragma mark - Targeted row updates

/// Reloads one message row (plus the row after it, whose group-start layout
/// depends on the previous row) without rebuilding the whole table, so the
/// scroll position and visible cells stay exactly where they are.
- (void)reloadMessageRowAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.messages.count) {
        [self.tableView reloadData];
        return;
    }
    // Guard: album regrouping can change the row count; a full reload is the
    // only correct option in that case.
    if ([self.tableView numberOfRowsInSection:0] != (NSInteger)self.messages.count) {
        [self.tableView reloadData];
        return;
    }
    NSMutableArray *paths = [NSMutableArray arrayWithObject:[NSIndexPath indexPathForRow:index inSection:0]];
    if (index + 1 < (NSInteger)self.messages.count) {
        [paths addObject:[NSIndexPath indexPathForRow:index + 1 inSection:0]];
    }
    [self.tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
}

/// Inserts one message row incrementally, preserving the scroll position and
/// avoiding the full-table flash of reloadData.
- (void)insertMessageRowAtIndex:(NSInteger)index {
    if (index < 0 || index > (NSInteger)self.messages.count) {
        [self.tableView reloadData];
        return;
    }
    if ([self.tableView numberOfRowsInSection:0] + 1 != (NSInteger)self.messages.count) {
        // Row structure changed beyond this insertion (albums, dividers).
        [self.tableView reloadData];
        return;
    }
    [self.tableView beginUpdates];
    [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:index inSection:0]]
                          withRowAnimation:UITableViewRowAnimationNone];
    [self.tableView endUpdates];
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
    [self resolveReplyMetadataForMessage:message];

    // A message is the START of a group when it is the first message in a
    // consecutive run from the same sender (looking backwards through the list).
    // Service rows and date dividers break the grouping.
    BOOL isGroupStart = YES;
    if (indexPath.row > 0) {
        TGMessage *prev = self.messages[(NSUInteger)(indexPath.row - 1)];
        if (!prev.isService && !prev.isDateDivider && !prev.isUnreadDivider &&
            !message.isService && !message.isDateDivider && !message.isUnreadDivider &&
            prev.senderId == message.senderId &&
            prev.isOutgoing == message.isOutgoing) {
            isGroupStart = NO;
        }
    }

    [cell configureWithMessage:message
                    showSender:self.showSenderNames
                    senderName:senderName
                  isGroupStart:isGroupStart
                        client:self.client];

    __weak typeof(self) weakSelf = self;
    cell.onMediaTap = ^(TGMessage *msg) {
        [weakSelf handleMediaTapForMessage:msg];
    };
    cell.onRetryTap = ^(TGMessage *msg) {
        [weakSelf resendFailedMessage:msg];
    };
    cell.onLongPress = ^(TGMessage *msg) {
        [weakSelf presentMessageActionsForMessage:msg];
    };
    cell.onLinkTap = ^(NSURL *url) {
        [weakSelf openLink:url];
    };
    cell.onAlbumItemTap = ^(TGMessage *msg, NSInteger index) {
        [weakSelf openAlbumItemInMessage:msg index:index];
    };
    cell.onReactionTap = ^(TGMessage *msg, NSString *emoji) {
        [weakSelf handleReactionTap:emoji forMessage:msg];
    };
    return cell;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.contentOffset.y < 120.0 && !self.loadingOlder && !self.reachedOldestMessage && self.messages.count > 0 && self.didInitialLoad) {
        [self loadOlderHistory];
    }
    [self updateScrollToBottomButtonVisibility];
}

- (void)openLink:(NSURL *)url {
    if (url == nil) {
        return;
    }
    UIApplication *application = [UIApplication sharedApplication];
    [application openURL:url options:@{} completionHandler:nil];
}

- (void)openAlbumItemInMessage:(TGMessage *)message index:(NSInteger)index {
    if (!message.isAlbum || message.albumMessages.count == 0) {
        return;
    }
    NSInteger safeIndex = MAX(0, MIN(index, (NSInteger)message.albumMessages.count - 1));
    TGMessage *item = message.albumMessages[(NSUInteger)safeIndex];
    [self handleMediaTapForMessage:item];
}

- (void)handleMediaTapForMessage:(TGMessage *)message {
    if (message.messageType == TGMessageTypePhoto) {        // Open the photo viewer immediately with the best locally-available image
        // (thumbnail or medium-res), then upgrade to full-resolution in the background.
        UIImage *placeholderImage = nil;

        // Try the bubble preview image (medium res) as the placeholder.
        int32_t previewId = message.mediaFileId > 0 ? message.mediaFileId : message.thumbnailFileId;
        NSString *previewPath = previewId > 0 ? [self.client localPathForFileId:previewId] : nil;
        if (previewPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:previewPath]) {
            placeholderImage = [UIImage imageWithContentsOfFile:previewPath];
        } else if (message.mediaLocalPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:message.mediaLocalPath]) {
            placeholderImage = [UIImage imageWithContentsOfFile:message.mediaLocalPath];
        } else if (message.minithumbnailData.length > 0) {
            placeholderImage = [UIImage imageWithData:message.minithumbnailData];
        }

        // Present the viewer immediately so the user gets instant feedback.
        TGPhotoViewerController *viewer = [[TGPhotoViewerController alloc] initWithImage:placeholderImage];
        [self presentViewController:viewer animated:YES completion:nil];

        // Now kick off full-resolution download (or use it straight away if already cached).
        int32_t fullResId = message.fullResFileId > 0 ? message.fullResFileId : previewId;
        if (fullResId > 0) {
            NSString *fullPath = [self.client localPathForFileId:fullResId];
            if (fullPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:fullPath]) {
                [viewer upgradeToImage:[UIImage imageWithContentsOfFile:fullPath]];
            } else {
                __weak TGPhotoViewerController *weakViewer = viewer;
                [self.client downloadFileWithId:fullResId priority:32 completion:^(NSString *downloadedPath, NSDictionary *file) {
                    if (downloadedPath.length > 0) {
                        UIImage *fullImage = [UIImage imageWithContentsOfFile:downloadedPath];
                        if (fullImage != nil) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [weakViewer upgradeToImage:fullImage];
                            });
                        }
                    }
                }];
            }
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

- (void)scrollToBottomButtonTapped {
    [self scrollToBottomAnimated:YES];
}

- (void)handleReactionTap:(NSString *)emoji forMessage:(TGMessage *)message {
    [self.client toggleReaction:emoji
                      onMessage:message.messageId
                         inChat:self.chatId
                     completion:nil];
}

- (void)updateScrollToBottomButtonVisibility {
    BOOL shouldShow = ![self isNearBottom] && self.messages.count > 0;
    CGFloat targetAlpha = shouldShow ? 1.0 : 0.0;
    if (fabs(self.scrollToBottomButton.alpha - targetAlpha) < 0.01) {
        return;
    }
    [UIView animateWithDuration:0.2 animations:^{
        self.scrollToBottomButton.alpha = targetAlpha;
    }];
}

@end
