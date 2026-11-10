#import "TGArchiveChatListViewController.h"

#import "TGChatListCell.h"
#import "TGChatViewController.h"
#import "TGModels.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"

@interface TGArchiveChatListViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, TGChat *> *chats;
@property (nonatomic, strong) NSArray<TGChat *> *sortedChats;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation TGArchiveChatListViewController

- (instancetype)initWithClient:(TGTDLibClient *)client {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _client = client;
        _chats = [NSMutableDictionary dictionary];
        _sortedChats = @[];
        // Seed from any chats already cached by the main list so the folder is
        // populated immediately.
        for (NSDictionary *dictionary in [self.client cachedArchiveChatDictionaries]) {
            [self mergeChatDictionary:dictionary];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Archiwum";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 72.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.backgroundColor = [UIColor whiteColor];
    [self.tableView registerClass:[TGChatListCell class] forCellReuseIdentifier:@"TGChatListCell"];
    [self.view addSubview:self.tableView];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"Archiwum jest puste.";
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.numberOfLines = 0;
    self.emptyLabel.font = [TGTheme regularFontOfSize:15.0];
    self.emptyLabel.textColor = [TGTheme secondaryTextColor];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.tableView.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.tableView.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.tableView.leadingAnchor constant:32.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.tableView.trailingAnchor constant:-32.0]
    ]];

    [self loadArchive];
}

- (void)loadArchive {
    __weak typeof(self) weakSelf = self;
    [self.client loadArchiveChatListWithCompletion:^(NSArray<NSDictionary *> *chats, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([chats isKindOfClass:[NSArray class]]) {
                for (NSDictionary *dictionary in chats) {
                    [weakSelf mergeChatDictionary:dictionary];
                }
            }
            [weakSelf reloadUI];
        });
    }];
}

#pragma mark - Updates

- (void)handleTDLibUpdate:(NSDictionary *)update {
    NSString *type = TGStringValue(update[@"@type"]);

    if ([type isEqualToString:@"updateChatPosition"] || [type isEqualToString:@"updateChatLastMessage"] ||
        [type isEqualToString:@"updateChatReadInbox"] || [type isEqualToString:@"updateChatTitle"]) {
        int64_t chatId = TGInt64Value(update[@"chat_id"]);
        if (chatId == 0) {
            return;
        }
        TGChat *chat = self.chats[@(chatId)];
        if (chat == nil) {
            // A chat may just have been moved into the archive.
            __weak typeof(self) weakSelf = self;
            [self.client loadChat:chatId completion:^(NSDictionary *dictionary, NSDictionary *error) {
                if ([dictionary isKindOfClass:[NSDictionary class]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf mergeChatDictionary:dictionary];
                        [weakSelf reloadUI];
                    });
                }
            }];
            return;
        }
        if ([type isEqualToString:@"updateChatPosition"]) {
            [chat applyPositions:@[update[@"position"] ?: @{}]];
        } else if ([type isEqualToString:@"updateChatLastMessage"]) {
            if ([update[@"last_message"] isKindOfClass:[NSDictionary class]]) {
                [chat applyLastMessage:update[@"last_message"]];
            }
            if ([update[@"positions"] isKindOfClass:[NSArray class]]) {
                [chat applyPositions:update[@"positions"]];
            }
        } else if ([type isEqualToString:@"updateChatReadInbox"]) {
            chat.unreadCount = (NSInteger)TGInt32Value(update[@"unread_count"]);
        } else if ([type isEqualToString:@"updateChatTitle"]) {
            NSString *title = TGStringValue(update[@"title"]);
            if (title.length > 0) {
                chat.title = title;
            }
        }
        [self reloadUI];
    }
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
        if (chat.hasArchivePosition) {
            [visible addObject:chat];
        } else {
            // Chat was unarchived; drop it from the folder.
            [self.chats removeObjectForKey:@(chat.chatId)];
        }
    }
    [visible sortUsingComparator:^NSComparisonResult(TGChat *a, TGChat *b) {
        return a.archiveOrder > b.archiveOrder ? NSOrderedAscending : NSOrderedDescending;
    }];
    self.sortedChats = visible;
    self.emptyLabel.hidden = visible.count > 0;
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

@end
