#import "TGChatListViewController.h"

#import "TGChatListCell.h"
#import "TGChatViewController.h"
#import "TGModels.h"
#import "TGSettingsViewController.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"

@interface TGChatListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TGChat *> *chats;
@property (nonatomic, strong) NSArray<TGChat *> *sortedChats;
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

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:32.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-32.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    [self loadChats];
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
    for (TGChat *chat in self.chats.allValues) {
        if (chat.hasMainListPosition) {
            [visible addObject:chat];
        }
    }
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
    self.emptyLabel.hidden = self.sortedChats.count > 0;
    [self.tableView reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sortedChats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TGChatListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TGChatListCell" forIndexPath:indexPath];
    [cell configureWithChat:self.sortedChats[(NSUInteger)indexPath.row] client:self.client];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TGChat *chat = self.sortedChats[(NSUInteger)indexPath.row];
    TGChatViewController *controller = [[TGChatViewController alloc] initWithClient:self.client
                                                                            chatId:chat.chatId
                                                                             title:chat.title];
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - Settings

- (void)openSettings {
    TGSettingsViewController *settings = [[TGSettingsViewController alloc] initWithClient:self.client];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navigation animated:YES completion:nil];
}

@end
