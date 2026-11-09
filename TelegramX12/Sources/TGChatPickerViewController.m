#import "TGChatPickerViewController.h"

#import "TGChatListCell.h"
#import "TGModels.h"
#import "TGTheme.h"
#import "TGTDLibClient.h"

@interface TGChatPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic) int64_t excludingChatId;
@property (nonatomic, copy) TGChatPickerCompletion completion;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<TGChat *> *chats;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation TGChatPickerViewController

- (instancetype)initWithClient:(TGTDLibClient *)client
               excludingChatId:(int64_t)excludingChatId
                    completion:(TGChatPickerCompletion)completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _client = client;
        _excludingChatId = excludingChatId;
        _completion = [completion copy];
        _chats = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Przekaż do";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                         target:self
                                                                                         action:@selector(cancelTapped)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 70.0;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.tableView registerClass:[TGChatListCell class] forCellReuseIdentifier:@"TGChatPickerCell"];
    [self.view addSubview:self.tableView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.emptyLabel.text = @"Brak innych czatów.";
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [TGTheme regularFontOfSize:14.0];
    self.emptyLabel.textColor = [TGTheme secondaryTextColor];
    self.emptyLabel.hidden = YES;
    [self.view addSubview:self.emptyLabel];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],

        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [self.emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0]
    ]];

    [self loadChats];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)loadChats {
    [self.spinner startAnimating];
    self.emptyLabel.hidden = YES;
    __weak typeof(self) weakSelf = self;
    [self.client loadChatListWithCompletion:^(NSArray<NSNumber *> *chatIds, NSDictionary *error) {
        if (chatIds.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishLoading];
            });
            return;
        }
        NSMutableArray<TGChat *> *loaded = [NSMutableArray array];
        __block NSInteger pending = (NSInteger)chatIds.count;
        for (NSNumber *chatIdNumber in chatIds) {
            int64_t chatId = chatIdNumber.longLongValue;
            if (chatId == weakSelf.excludingChatId) {
                pending -= 1;
                continue;
            }
            [weakSelf.client loadChat:chatId completion:^(NSDictionary *chatDictionary, NSDictionary *chatError) {
                if (chatDictionary != nil) {
                    TGChat *chat = [TGChat chatWithDictionary:chatDictionary];
                    @synchronized (loaded) {
                        [loaded addObject:chat];
                    }
                }
                pending -= 1;
                if (pending <= 0) {
                    [loaded sortUsingComparator:^NSComparisonResult(TGChat *a, TGChat *b) {
                        if (a.order == b.order) return NSOrderedSame;
                        return a.order > b.order ? NSOrderedAscending : NSOrderedDescending;
                    }];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        weakSelf.chats = [loaded copy];
                        [weakSelf finishLoading];
                    });
                }
            }];
        }
        if (pending <= 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf finishLoading];
            });
        }
    }];
}

- (void)finishLoading {
    [self.spinner stopAnimating];
    self.emptyLabel.hidden = self.chats.count > 0;
    [self.tableView reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TGChatListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TGChatPickerCell" forIndexPath:indexPath];
    [cell configureWithChat:self.chats[(NSUInteger)indexPath.row] client:self.client];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TGChat *chat = self.chats[(NSUInteger)indexPath.row];
    if (self.completion != nil) {
        self.completion(chat.chatId, chat.title);
    }
}

@end
