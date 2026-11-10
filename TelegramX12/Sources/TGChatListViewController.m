#import "TGChatListViewController.h"

#import "TGChatListCell.h"
#import "TGChatPlaceholderViewController.h"
#import "TGArchiveChatListViewController.h"
#import "TGChatViewController.h"
#import "TGModels.h"
#import "TGSettingsViewController.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"

@interface TGChatListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating, UISplitViewControllerDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TGChat *> *chats;
@property (nonatomic, strong) NSArray<TGChat *> *sortedChats;
@property (nonatomic, strong) NSArray<TGChat *> *filteredChats;
@property (nonatomic, strong) NSArray<TGChat *> *archivedChats;
@property (nonatomic, copy) NSString *savedMessagesPreview;
@property (nonatomic) int32_t savedMessagesDate;
@property (nonatomic) NSInteger pendingChatLoads;
@property (nonatomic) BOOL didLoadOnce;
@end

@implementation TGChatListViewController

- (instancetype)initWithClient:(TGTDLibClient *)client {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _client = client;
        _chats = [NSMutableDictionary dictionary];
        _sortedChats = @[];
        _filteredChats = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Czaty";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Ustawienia"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(openSettings)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.dimsBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Szukaj czatów i wiadomości";
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    self.splitViewController.delegate = self;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 72.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor whiteColor];
    [self.tableView registerClass:[TGChatListCell class] forCellReuseIdentifier:@"TGChatListCell"];
    [self.view addSubview:self.tableView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [TGTheme accentColor];
    [self.refreshControl addTarget:self action:@selector(refreshChats) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refreshControl];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"Brak czatów\n\nZacznij rozmowę w oficjalnej aplikacji Telegram,\na pojawi się tutaj.";
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.font = [TGTheme regularFontOfSize:15.0];
    self.emptyLabel.textColor = [TGTheme secondaryTextColor];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.tableView.leadingAnchor constant:32.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.tableView.trailingAnchor constant:-32.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor]
    ]];

    [self loadChats];
    [self loadArchiveFolder];
    [self refreshSavedMessagesInfo];
}

/// The main list never receives archive-only chats from getChats(chatListMain),
/// so the fixed Archive row stays hidden unless we merge the folder ourselves.
- (void)loadArchiveFolder {
    __weak typeof(self) weakSelf = self;
    [self.client loadArchiveChatListWithCompletion:^(NSArray<NSDictionary *> *chats, NSDictionary *error) {
        if (error != nil) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([chats isKindOfClass:[NSArray class]]) {
                for (NSDictionary *dictionary in chats) {
                    [weakSelf mergeChatDictionary:dictionary];
                }
                [weakSelf reloadUI];
            }
        });
    }];
}

#pragma mark - Saved Messages info

- (void)refreshSavedMessagesInfo {
    int64_t myUserId = [self.client myUserId];
    if (myUserId == 0) {
        // getMe may still be in flight during startup; retry in a moment.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([self.viewIfLoaded window] != nil) {
                [self refreshSavedMessagesInfo];
            }
        });
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.client loadChat:myUserId completion:^(NSDictionary *chat, NSDictionary *error) {
        if (chat == nil) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf applySavedMessagesChat:chat];
        });
    }];
}

- (void)applySavedMessagesChat:(NSDictionary *)chat {
    if (self.viewIfLoaded.window == nil) {
        return;
    }
    NSDictionary *lastMessage = chat[@"last_message"];
    if ([lastMessage isKindOfClass:[NSDictionary class]]) {
        id content = lastMessage[@"content"];
        self.savedMessagesPreview = [content isKindOfClass:[NSDictionary class]]
            ? TGMessagePreviewText(content)
            : @"Brak wiadomości";
        self.savedMessagesDate = TGInt32Value(lastMessage[@"date"]);
    } else {
        self.savedMessagesPreview = @"Brak wiadomości";
        self.savedMessagesDate = 0;
    }
    [self reloadUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    [self reloadUI];
    if (!self.didLoadOnce) {
        self.didLoadOnce = YES;
    }
}

- (void)loadChats {
    [self.spinner startAnimating];
    self.emptyLabel.hidden = YES;
    __weak typeof(self) weakSelf = self;
    [self.client loadChatListWithCompletion:^(NSArray<NSNumber *> *chatIds, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.spinner stopAnimating];
            [weakSelf.refreshControl endRefreshing];
            if (error != nil) {
                NSString *message = TGStringValue(error[@"message"]);
                if (message.length > 0) {
                    NSLog(@"[TelegramX12] getChats error: %@", message);
                }
                [weakSelf reloadUI];
                return;
            }
            [weakSelf loadChatDictionaries:chatIds];
        });
    }];
}

- (void)loadChatDictionaries:(NSArray<NSNumber *> *)chatIds {
    if (chatIds.count == 0) {
        [self reloadUI];
        return;
    }
    self.pendingChatLoads += (NSInteger)chatIds.count;
    __weak typeof(self) weakSelf = self;
    for (NSNumber *chatId in chatIds) {
        [self.client loadChat:chatId.longLongValue completion:^(NSDictionary *chat, NSDictionary *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (chat != nil) {
                    [weakSelf mergeChatDictionary:chat];
                }
                weakSelf.pendingChatLoads -= 1;
                if (weakSelf.pendingChatLoads <= 0) {
                    weakSelf.pendingChatLoads = 0;
                    [weakSelf reloadUI];
                }
            });
        }];
    }
}

- (void)refreshChats {
    [self loadChats];
    [self.client loadMoreChatsWithCompletion:nil];
}

#pragma mark - Updates

- (void)handleTDLibUpdate:(NSDictionary *)update {
    NSString *type = TGStringValue(update[@"@type"]);

    if ([type isEqualToString:@"updateNewChat"] || [type isEqualToString:@"updateChatLastMessage"]) {
        if (TGInt64Value(update[@"chat_id"]) == [self.client myUserId]) {
            [self refreshSavedMessagesInfo];
        }
    }

    if ([type isEqualToString:@"updateNewChat"]) {
        NSDictionary *dictionary = update[@"chat"];
        if ([dictionary isKindOfClass:[NSDictionary class]]) {
            [self mergeChatDictionary:dictionary];
            [self reloadUI];
        }
        return;
    }

    if ([type isEqualToString:@"updateChatPosition"]) {
        int64_t chatId = TGInt64Value(update[@"chat_id"]);
        NSDictionary *position = update[@"position"];
        if (chatId == 0 || ![position isKindOfClass:[NSDictionary class]]) {
            return;
        }
        TGChat *chat = self.chats[@(chatId)];
        if (chat == nil) {
            [self.client loadChat:chatId completion:^(NSDictionary *dictionary, NSDictionary *error) {
                if (dictionary != nil) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self mergeChatDictionary:dictionary];
                        [self reloadUI];
                    });
                }
            }];
            return;
        }
        [chat applyPosition:position];
        [self reloadUI];
        return;
    }

    if ([type isEqualToString:@"updateChatLastMessage"]) {
        TGChat *chat = [self chatForUpdate:update];
        NSDictionary *lastMessage = update[@"last_message"];
        if (chat != nil && [lastMessage isKindOfClass:[NSDictionary class]]) {
            [chat applyLastMessage:lastMessage];
        }
        NSArray *positions = update[@"positions"];
        if (chat != nil && [positions isKindOfClass:[NSArray class]]) {
            [chat applyPositions:positions];
        }
        [self reloadUI];
        return;
    }

    if ([type isEqualToString:@"updateChatReadInbox"]) {
        TGChat *chat = [self chatForUpdate:update];
        if (chat != nil) {
            chat.unreadCount = (NSInteger)TGInt32Value(update[@"unread_count"]);
        }
        [self reloadUI];
        return;
    }

    if ([type isEqualToString:@"updateChatTitle"]) {
        TGChat *chat = [self chatForUpdate:update];
        NSString *title = TGStringValue(update[@"title"]);
        if (chat != nil && title.length > 0) {
            chat.title = title;
        }
        [self reloadUI];
        return;
    }

    if ([type isEqualToString:@"updateChatIsMarkedAsUnread"]) {
        [self reloadUI];
        return;
    }
}

- (TGChat *)chatForUpdate:(NSDictionary *)update {
    int64_t chatId = TGInt64Value(update[@"chat_id"]);
    if (chatId == 0) {
        return nil;
    }
    TGChat *chat = self.chats[@(chatId)];
    if (chat == nil) {
        [self.client loadChat:chatId completion:^(NSDictionary *dictionary, NSDictionary *error) {
            if (dictionary != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self mergeChatDictionary:dictionary];
                    [self reloadUI];
                });
            }
        }];
    }
    return chat;
}

- (void)mergeChatDictionary:(NSDictionary *)dictionary {
    int64_t chatId = TGInt64Value(dictionary[@"id"]);
    if (chatId == 0) {
        return;
    }
    TGChat *chat = self.chats[@(chatId)];
    if (chat == nil) {
        chat = [TGChat chatWithDictionary:dictionary];
        self.chats[@(chatId)] = chat;
    } else {
        [chat updateWithDictionary:dictionary];
    }
}

#pragma mark - UI

- (void)reloadUI {
    NSMutableArray<TGChat *> *visible = [NSMutableArray array];
    NSMutableArray<TGChat *> *archived = [NSMutableArray array];
    for (TGChat *chat in self.chats.allValues) {
        if (chat.hasArchivePosition) {
            [archived addObject:chat];
        }
        if (chat.hasMainListPosition) {
            [visible addObject:chat];
        }
    }
    [archived sortUsingComparator:^NSComparisonResult(TGChat *a, TGChat *b) {
        return a.archiveOrder > b.archiveOrder ? NSOrderedAscending : NSOrderedDescending;
    }];
    self.archivedChats = archived;
    [visible sortUsingComparator:^NSComparisonResult(TGChat *a, TGChat *b) {
        if (a.pinned != b.pinned) {
            return a.pinned ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.order != b.order) {
            return a.order > b.order ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.lastMessageDate != b.lastMessageDate) {
            return a.lastMessageDate > b.lastMessageDate ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.chatId != b.chatId) {
            return a.chatId > b.chatId ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    self.sortedChats = visible;
    [self applySearchFilter];
    self.emptyLabel.hidden = self.filteredChats.count > 0 || self.archivedChats.count > 0;
    [self.tableView reloadData];
}

- (void)applySearchFilter {
    NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        self.filteredChats = self.sortedChats;
        return;
    }
    self.filteredChats = [self.sortedChats filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TGChat *chat, NSDictionary *bindings) {
        return [chat.title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
               [chat.lastMessageText rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
    }]];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchQuery = searchController.searchBar.text ?: @"";
    [self applySearchFilter];
    self.emptyLabel.hidden = self.filteredChats.count > 0 || self.archivedChats.count > 0;
    [self.tableView reloadData];
}

#pragma mark - UITableView

/// Special rows above the chat list: the archive folder and Saved Messages,
/// mirroring Telegram X's fixed area over the history list.
- (NSInteger)archiveRowIndex {
    return self.archivedChats.count > 0 ? 0 : -1;
}

- (NSInteger)savedRowIndex {
    return (self.archivedChats.count > 0 ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger specialRows = [self savedRowIndex] + (self.archivedChats.count > 0 ? 1 : 0);
    return specialRows + (NSInteger)self.filteredChats.count;
}

- (TGChat *)fakeChatForArchiveRow {
    TGChat *chat = [[TGChat alloc] init];
    chat.chatId = 0;
    chat.title = @"Archiwum";
    chat.lastMessageText = [NSString stringWithFormat:@"%lu czatów", (unsigned long)self.archivedChats.count];
    chat.lastMessageDate = 0;
    return chat;
}

- (TGChat *)fakeChatForSavedRow {
    TGChat *chat = [[TGChat alloc] init];
    chat.chatId = -1;
    chat.title = @"Zapisane wiadomości";
    chat.lastMessageText = self.savedMessagesPreview ?: @"";
    chat.lastMessageDate = self.savedMessagesDate;
    NSDictionary *me = [self.client userWithId:[self.client myUserId]];
    int32_t photoFileId = TGInt32Value(me[@"profile_photo"][@"small"][@"id"]);
    if (photoFileId > 0) {
        chat.raw = @{@"photo": @{@"small": @{@"id": @(photoFileId)}}};
    } else {
        chat.raw = @{};
    }
    return chat;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TGChatListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TGChatListCell" forIndexPath:indexPath];
    if (indexPath.row == [self archiveRowIndex]) {
        [cell configureWithChat:[self fakeChatForArchiveRow] client:nil];
        return cell;
    }
    if (indexPath.row == [self savedRowIndex]) {
        [cell configureWithChat:[self fakeChatForSavedRow] client:self.client];
        return cell;
    }
    NSInteger chatIndex = (NSInteger)indexPath.row - [self savedRowIndex] - 1;
    [cell configureWithChat:self.filteredChats[(NSUInteger)chatIndex] client:self.client];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == [self archiveRowIndex]) {
        TGArchiveChatListViewController *archive = [[TGArchiveChatListViewController alloc] initWithClient:self.client];
        [self.navigationController pushViewController:archive animated:YES];
        return;
    }
    if (indexPath.row == [self savedRowIndex]) {
        [self openSavedMessages];
        return;
    }
    NSInteger chatIndex = (NSInteger)indexPath.row - [self savedRowIndex] - 1;
    TGChat *chat = self.filteredChats[(NSUInteger)chatIndex];
    TGChatViewController *controller = [[TGChatViewController alloc] initWithClient:self.client
                                                                            chatId:chat.chatId
                                                                             title:chat.title];
    if (self.splitViewController != nil) {
        // iPad two pane layout: replace the detail column, keep the list.
        controller.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
        UINavigationController *detail = [[UINavigationController alloc] initWithRootViewController:controller];
        [self.splitViewController showDetailViewController:detail sender:self];
        return;
    }
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - Saved Messages

- (void)openSavedMessages {
    __weak typeof(self) weakSelf = self;
    [self.client createPrivateChatWithUserId:[self.client myUserId] completion:^(NSDictionary *chat, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            int64_t chatId = TGInt64Value(chat[@"id"]);
            if (chatId == 0) {
                NSString *messageText = TGStringValue(error[@"message"]);
                if (messageText.length > 0) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nie udało się otworzyć"
                                                                                     message:messageText
                                                                              preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [weakSelf presentViewController:alert animated:YES completion:nil];
                }
                return;
            }
            TGChatViewController *controller = [[TGChatViewController alloc] initWithClient:weakSelf.client
                                                                                     chatId:chatId
                                                                                      title:@"Zapisane wiadomości"];
            if (weakSelf.splitViewController != nil) {
                controller.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
                UINavigationController *detail = [[UINavigationController alloc] initWithRootViewController:controller];
                [weakSelf.splitViewController showDetailViewController:detail sender:weakSelf];
                return;
            }
            [weakSelf.navigationController pushViewController:controller animated:YES];
        });
    }];
}

#pragma mark - UISplitViewControllerDelegate

/// On compact sizes the split merges the detail column onto the navigation
/// stack. Throw away the placeholder, keep an open chat.
- (BOOL)splitViewController:(UISplitViewController *)splitViewController
 collapseSecondaryViewController:(UIViewController *)secondaryViewController
    ontoPrimaryViewController:(UIViewController *)primaryViewController {
    if (![secondaryViewController isKindOfClass:[UINavigationController class]]) {
        return NO;
    }
    UIViewController *top = ((UINavigationController *)secondaryViewController).viewControllers.firstObject;
    return [top isKindOfClass:[TGChatPlaceholderViewController class]];
}

#pragma mark - Settings

- (void)openSettings {
    TGSettingsViewController *settings = [[TGSettingsViewController alloc] initWithClient:self.client];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

@end
