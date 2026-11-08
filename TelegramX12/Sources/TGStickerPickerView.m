#import "TGStickerPickerView.h"

#import "TGModels.h"
#import "TGTDLibClient.h"
#import "TGTheme.h"
#import "TGWebPConverter.h"

static const CGFloat TGStickerPickerHeaderHeight = 30.0;
static const CGFloat TGStickerPickerBarHeight = 34.0;
static const CGFloat TGStickerPickerInset = 8.0;
static const CGFloat TGStickerPickerSpacing = 8.0;

#pragma mark - Cell

@interface TGStickerPickerCell : UICollectionViewCell
@property (nonatomic, strong, readonly) UIImageView *imageView;
@property (nonatomic, strong, readonly) UILabel *emojiLabel;
@property (nonatomic) int32_t currentFileId;
- (void)configureWithSticker:(NSDictionary *)sticker client:(TGTDLibClient *)client;
@end

@implementation TGStickerPickerCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
        self.contentView.layer.cornerRadius = 10.0;
        self.contentView.clipsToBounds = YES;

        _imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFit;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];

        _emojiLabel = [[UILabel alloc] initWithFrame:self.contentView.bounds];
        _emojiLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _emojiLabel.font = [UIFont systemFontOfSize:32.0];
        _emojiLabel.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_emojiLabel];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.currentFileId = 0;
    self.imageView.image = nil;
    self.emojiLabel.text = nil;
    self.emojiLabel.hidden = NO;
}

- (void)configureWithSticker:(NSDictionary *)sticker client:(TGTDLibClient *)client {
    self.currentFileId = TGInt32Value(sticker[@"sticker"][@"id"]);
    int32_t thumbnailId = TGInt32Value(sticker[@"thumbnail"][@"file"][@"id"]);
    self.imageView.image = nil;

    NSString *emoji = TGStringValue(sticker[@"emoji"]);
    self.emojiLabel.text = emoji.length > 0 ? emoji : @"✳️";
    self.emojiLabel.hidden = NO;

    if (self.currentFileId <= 0 || client == nil) {
        return;
    }

    int32_t expectedFileId = self.currentFileId;

    NSString *mainPath = [client localPathForFileId:self.currentFileId];
    if (mainPath.length > 0) {
        [self displayPath:mainPath expectedFileId:expectedFileId];
        return;
    }
    if (thumbnailId > 0) {
        NSString *thumbnailPath = [client localPathForFileId:thumbnailId];
        if (thumbnailPath.length > 0) {
            [self displayPath:thumbnailPath expectedFileId:expectedFileId];
        }
    }

    __weak typeof(self) weakSelf = self;
    [client downloadFileWithId:self.currentFileId priority:20 completion:^(NSString *downloadedPath, NSDictionary *file) {
        if (downloadedPath.length > 0 && weakSelf.currentFileId == expectedFileId) {
            [weakSelf displayPath:downloadedPath expectedFileId:expectedFileId];
            return;
        }
        if (thumbnailId <= 0 || weakSelf.currentFileId != expectedFileId) {
            return;
        }
        [client downloadFileWithId:thumbnailId priority:26 completion:^(NSString *thumbnailDownloadedPath, NSDictionary *thumbnailFile) {
            if (thumbnailDownloadedPath.length > 0 && weakSelf.currentFileId == expectedFileId) {
                [weakSelf displayPath:thumbnailDownloadedPath expectedFileId:expectedFileId];
            }
        }];
    }];
}

- (void)displayPath:(NSString *)path expectedFileId:(int32_t)fileId {
    if (path.length == 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;

    UIImage *cached = [TGWebPConverter cachedImageForPath:path];
    if (cached != nil) {
        [weakSelf showImage:cached expectedFileId:fileId];
        return;
    }

    if ([TGWebPConverter isWebPFile:path]) {
        [TGWebPConverter convertWebPAtPath:path completion:^(NSString *jpgPath, UIImage *image) {
            [weakSelf showImage:image expectedFileId:fileId];
        }];
    } else {
        [weakSelf showImage:[UIImage imageWithContentsOfFile:path] expectedFileId:fileId];
    }
}

- (void)showImage:(UIImage *)image expectedFileId:(int32_t)fileId {
    if (image == nil || self.currentFileId != fileId) {
        return;
    }
    self.imageView.image = image;
    self.emojiLabel.hidden = YES;
}

@end

#pragma mark - Section header

@interface TGStickerPickerHeader : UICollectionReusableView
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@end

@implementation TGStickerPickerHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.bounds, 12.0, 6.0)];
        _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _titleLabel.font = [TGTheme semiboldFontOfSize:13.0];
        _titleLabel.textColor = [TGTheme secondaryTextColor];
        [self addSubview:_titleLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.frame = CGRectInset(self.bounds, 12.0, 6.0);
}

@end

#pragma mark - Picker

@interface TGStickerPickerView () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) TGTDLibClient *client;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *topSeparator;
@property (nonatomic, strong) UIView *barSeparator;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@property (nonatomic) BOOL loading;
@end

@implementation TGStickerPickerView

- (instancetype)initWithClient:(TGTDLibClient *)client {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _client = client;
        _sections = @[];
        self.backgroundColor = [UIColor whiteColor];

        _topBar = [[UIView alloc] initWithFrame:CGRectZero];
        _topBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_topBar];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.text = @"Stickery";
        _titleLabel.font = [TGTheme semiboldFontOfSize:15.0];
        _titleLabel.textColor = [UIColor blackColor];
        [_topBar addSubview:_titleLabel];

        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
        _closeButton.titleLabel.font = [UIFont systemFontOfSize:17.0];
        [_closeButton setTitleColor:[TGTheme secondaryTextColor] forState:UIControlStateNormal];
        _closeButton.accessibilityLabel = @"Zamknij stickery";
        [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_topBar addSubview:_closeButton];

        _topSeparator = [[UIView alloc] initWithFrame:CGRectZero];
        _topSeparator.translatesAutoresizingMaskIntoConstraints = NO;
        _topSeparator.backgroundColor = [TGTheme separatorColor];
        [self addSubview:_topSeparator];

        _barSeparator = [[UIView alloc] initWithFrame:CGRectZero];
        _barSeparator.translatesAutoresizingMaskIntoConstraints = NO;
        _barSeparator.backgroundColor = [TGTheme separatorColor];
        [self addSubview:_barSeparator];

        UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
        layout.scrollDirection = UICollectionViewScrollDirectionVertical;
        layout.minimumInteritemSpacing = TGStickerPickerSpacing;
        layout.minimumLineSpacing = TGStickerPickerSpacing;
        layout.sectionInset = UIEdgeInsetsMake(TGStickerPickerInset, TGStickerPickerInset, TGStickerPickerInset, TGStickerPickerInset);
        layout.headerReferenceSize = CGSizeMake(0.0, TGStickerPickerHeaderHeight);

        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
        _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.alwaysBounceVertical = YES;
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        [_collectionView registerClass:[TGStickerPickerCell class] forCellWithReuseIdentifier:@"TGStickerPickerCell"];
        [_collectionView registerClass:[TGStickerPickerHeader class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:@"TGStickerPickerHeader"];
        [self addSubview:_collectionView];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];

        _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _emptyLabel.text = @"Brak stickerów\n\nZainstaluj paczkę w oficjalnej aplikacji Telegram,\na pojawi się tutaj.";
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        _emptyLabel.numberOfLines = 0;
        _emptyLabel.font = [TGTheme regularFontOfSize:14.0];
        _emptyLabel.textColor = [TGTheme secondaryTextColor];
        _emptyLabel.hidden = YES;
        [self addSubview:_emptyLabel];

        UILayoutGuide *safe = self.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [_topBar.topAnchor constraintEqualToAnchor:_topSeparator.bottomAnchor],
            [_topBar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_topBar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_topBar.heightAnchor constraintEqualToConstant:TGStickerPickerBarHeight],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_topBar.leadingAnchor constant:12.0],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],

            [_closeButton.trailingAnchor constraintEqualToAnchor:_topBar.trailingAnchor constant:-10.0],
            [_closeButton.centerYAnchor constraintEqualToAnchor:_topBar.centerYAnchor],
            [_closeButton.widthAnchor constraintEqualToConstant:36.0],
            [_closeButton.heightAnchor constraintEqualToConstant:36.0],

            [_topSeparator.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_topSeparator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_topSeparator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_topSeparator.heightAnchor constraintEqualToConstant:0.5],

            [_barSeparator.topAnchor constraintEqualToAnchor:_topBar.bottomAnchor],
            [_barSeparator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_barSeparator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_barSeparator.heightAnchor constraintEqualToConstant:0.5],

            [_collectionView.topAnchor constraintEqualToAnchor:_barSeparator.bottomAnchor],
            [_collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_spinner.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

            [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:24.0],
            [_emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-24.0]
        ]];
    }
    return self;
}

- (void)closeTapped {
    if (self.onClose != nil) {
        self.onClose();
    }
}

- (void)reloadFromServer {
    if (self.loading) {
        return;
    }
    self.loading = YES;
    self.emptyLabel.hidden = YES;
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [self.client loadStickerSectionsWithCompletion:^(NSArray<NSDictionary *> *sections, NSDictionary *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf.loading = NO;
            [strongSelf.spinner stopAnimating];
            strongSelf.sections = sections ?: @[];
            [strongSelf.collectionView reloadData];
            strongSelf.emptyLabel.hidden = strongSelf.sections.count > 0;
        });
    }];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSArray *stickers = self.sections[(NSUInteger)section][@"stickers"];
    return (NSInteger)stickers.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    TGStickerPickerCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"TGStickerPickerCell"
                                                                          forIndexPath:indexPath];
    NSArray *stickers = self.sections[(NSUInteger)indexPath.section][@"stickers"];
    if ((NSUInteger)indexPath.item < stickers.count) {
        [cell configureWithSticker:stickers[(NSUInteger)indexPath.item] client:self.client];
    }
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    TGStickerPickerHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                       withReuseIdentifier:@"TGStickerPickerHeader"
                                                                              forIndexPath:indexPath];
    NSDictionary *section = self.sections[(NSUInteger)indexPath.section];
    NSString *title = TGStringValue(section[@"title"]);
    header.titleLabel.text = title.length > 0 ? title : @"Stickery";
    return header;
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = CGRectGetWidth(collectionView.bounds);
    if (width <= 0.0) {
        width = CGRectGetWidth([UIScreen mainScreen].bounds);
    }
    NSInteger columns = (NSInteger)round((width + TGStickerPickerSpacing) / (78.0 + TGStickerPickerSpacing));
    columns = MAX(4, MIN(6, columns));
    CGFloat itemWidth = floor((width - TGStickerPickerInset * 2.0 - TGStickerPickerSpacing * (columns - 1)) / columns);
    itemWidth = MAX(48.0, itemWidth);
    return CGSizeMake(itemWidth, itemWidth);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout *)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(TGStickerPickerInset, TGStickerPickerInset, TGStickerPickerInset, TGStickerPickerInset);
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    NSArray *stickers = self.sections[(NSUInteger)indexPath.section][@"stickers"];
    if ((NSUInteger)indexPath.item >= stickers.count) {
        return;
    }
    NSDictionary *sticker = stickers[(NSUInteger)indexPath.item];
    if (self.onSelectSticker != nil) {
        self.onSelectSticker(sticker);
    }
}

@end
