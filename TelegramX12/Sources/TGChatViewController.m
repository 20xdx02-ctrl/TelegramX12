#import "TGChatViewController.h"

#import "TGInputBar.h"
#import "TGMessageCell.h"
#import "TGModels.h"
#import "TGPhotoViewerController.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface TGChatViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic) int64_t chatId;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) TGInputBar *inputBar;
@property (nonatomic, strong) NSLayoutConstraint *inputBottomConstraint;
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
        _totalCount = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.chatTitleForDisplay;
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    [self updateSenderVisibility];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor whiteColor];
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

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.inputBar.topAnchor],

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
    [self.client openChat:self.chatId];
    if (!self.didInitialLoad) {
        [self loadInitialHistory];
    } else {
        [self markMessagesRead];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
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
            [weakSelf.tableView reloadData];
            [weakSelf.tableView layoutIfNeeded];
            [weakSelf scrollToBottomAnimated:NO];
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
    self.totalCount = MAX(totalCount, (NSInteger)self.messages.count);
}

- (void)loadOlderHistory {
    if (self.loadingOlder || self.messages.count == 0 || self.reachedOldestMessage) {
        [self.refreshControl endRefreshing];
        return;
    }
    self.loadingOlder = YES;

    TGMessage *oldest = self.messages.firstObject;
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
            [weakSelf rebuildMessageIndex];
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
            }
        }
        return;
    }
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
    if (self.showSenderNames && !message.isOutgoing && !message.isService) {
        senderName = [self.client displayNameForSender:message.raw[@"sender_id"]];
    }
    [cell configureWithMessage:message showSender:self.showSenderNames senderName:senderName client:self.client];

    __weak typeof(self) weakSelf = self;
    cell.onMediaTap = ^(TGMessage *msg) {
        [weakSelf handleMediaTapForMessage:msg];
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
    }
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
