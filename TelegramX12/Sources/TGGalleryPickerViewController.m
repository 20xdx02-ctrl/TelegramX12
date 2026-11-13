#import "TGGalleryPickerViewController.h"

#import "TGTheme.h"

#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>

@interface TGGalleryCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIView *selectionBorder;
@property (nonatomic, strong) UILabel *numberLabel;
@property (nonatomic, copy, nullable) NSString *representedAssetId;
@end

@implementation TGGalleryCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];

        _thumbnailView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _thumbnailView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        [self.contentView addSubview:_thumbnailView];

        _selectionBorder = [[UIView alloc] initWithFrame:self.contentView.bounds];
        _selectionBorder.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _selectionBorder.layer.borderWidth = 3.0;
        _selectionBorder.layer.borderColor = [TGTheme accentColor].CGColor;
        _selectionBorder.backgroundColor = [[TGTheme accentColor] colorWithAlphaComponent:0.18];
        _selectionBorder.hidden = YES;
        [self.contentView addSubview:_selectionBorder];

        _numberLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 22.0, 22.0)];
        _numberLabel.textAlignment = NSTextAlignmentCenter;
        _numberLabel.textColor = [UIColor whiteColor];
        _numberLabel.font = [TGTheme semiboldFontOfSize:12.0];
        _numberLabel.backgroundColor = [TGTheme accentColor];
        _numberLabel.layer.cornerRadius = 11.0;
        _numberLabel.layer.masksToBounds = YES;
        _numberLabel.hidden = YES;
        [self.contentView addSubview:_numberLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = CGRectGetWidth(self.contentView.bounds);
    self.numberLabel.frame = CGRectMake(side - 26.0, 4.0, 22.0, 22.0);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.thumbnailView.image = nil;
    self.representedAssetId = nil;
    self.selectionBorder.hidden = YES;
    self.numberLabel.hidden = YES;
}

- (void)setSelectedForSending:(BOOL)selected number:(NSInteger)number {
    self.selectionBorder.hidden = !selected;
    self.numberLabel.hidden = !selected;
    self.numberLabel.text = selected ? [NSString stringWithFormat:@"%ld", (long)number] : nil;
}

@end

@interface TGGalleryPickerViewController () <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UICollectionViewFlowLayout *collectionLayout;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) PHFetchResult<PHAsset *> *assets;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *selectedIndexes;
@property (nonatomic) NSInteger maxSelection;
@property (nonatomic) BOOL sending;

@end

static NSString *const TGGalleryCellIdentifier = @"TGGalleryCell";

@implementation TGGalleryPickerViewController

- (instancetype)initWithMaxSelection:(NSInteger)maxSelection {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _maxSelection = MAX(1, maxSelection);
        _selectedIndexes = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Zdjęcia";
    self.view.backgroundColor = [UIColor whiteColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Anuluj"
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Wyślij"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(sendTapped)];
    self.navigationItem.rightBarButtonItem.enabled = NO;

    self.collectionLayout = [[UICollectionViewFlowLayout alloc] init];
    self.collectionLayout.minimumInteritemSpacing = 2.0;
    self.collectionLayout.minimumLineSpacing = 2.0;
    self.collectionLayout.sectionInset = UIEdgeInsetsZero;

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:self.collectionLayout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.backgroundColor = [UIColor whiteColor];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[TGGalleryCell class] forCellWithReuseIdentifier:TGGalleryCellIdentifier];
    [self.view addSubview:self.collectionView];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [TGTheme regularFontOfSize:15.0];
    self.messageLabel.textColor = [TGTheme secondaryTextColor];
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    [self requestAccessAndLoadAssets];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.messageLabel.frame = CGRectInset(self.view.bounds, 32.0, 0.0);
    self.messageLabel.center = self.view.center;
    self.spinner.center = self.view.center;

    CGFloat width = CGRectGetWidth(self.collectionView.bounds);
    NSInteger columns = width >= 700.0 ? 5 : 4;
    CGFloat side = floor((width - 2.0 * (columns - 1)) / columns);
    if (self.collectionLayout.itemSize.width != side) {
        self.collectionLayout.itemSize = CGSizeMake(side, side);
        [self.collectionLayout invalidateLayout];
    }
}

#pragma mark - Photos

- (void)requestAccessAndLoadAssets {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized) {
        [self loadAssets];
        return;
    }
    if (status == PHAuthorizationStatusNotDetermined) {
        [self.spinner startAnimating];
        __weak typeof(self) weakSelf = self;
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus newStatus) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.spinner stopAnimating];
                if (newStatus == PHAuthorizationStatusAuthorized) {
                    [weakSelf loadAssets];
                } else {
                    [weakSelf showAccessDeniedMessage];
                }
            });
        }];
        return;
    }
    [self showAccessDeniedMessage];
}

- (void)showAccessDeniedMessage {
    self.messageLabel.hidden = NO;
    self.messageLabel.text = @"Brak dostępu do zdjęć.\nWłącz go w Ustawieniach systemowych.";
}

- (void)loadAssets {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO] ];
    self.assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
    [self.collectionView reloadData];
}

#pragma mark - Selection

- (NSInteger)selectionPositionForIndex:(NSInteger)index {
    NSUInteger position = [self.selectedIndexes indexOfObject:@(index)];
    return position == NSNotFound ? 0 : (NSInteger)position + 1;
}

- (void)toggleSelectionAtIndex:(NSInteger)index {
    NSNumber *key = @(index);
    NSUInteger position = [self.selectedIndexes indexOfObject:key];
    if (position != NSNotFound) {
        [self.selectedIndexes removeObjectAtIndex:position];
    } else {
        if ((NSInteger)self.selectedIndexes.count >= self.maxSelection) {
            [self flashSelectionLimit];
            return;
        }
        [self.selectedIndexes addObject:key];
    }
    self.navigationItem.rightBarButtonItem.enabled = self.selectedIndexes.count > 0;
    self.navigationItem.rightBarButtonItem.title = self.selectedIndexes.count > 0
        ? [NSString stringWithFormat:@"Wyślij (%lu)", (unsigned long)self.selectedIndexes.count]
        : @"Wyślij";
    [self.collectionView reloadData];
}

- (void)flashSelectionLimit {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    TGGalleryCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:TGGalleryCellIdentifier forIndexPath:indexPath];
    PHAsset *asset = self.assets[(NSUInteger)indexPath.item];
    cell.representedAssetId = asset.localIdentifier;
    cell.thumbnailView.image = nil;
    [cell setSelectedForSending:[self selectionPositionForIndex:indexPath.item] > 0
                         number:[self selectionPositionForIndex:indexPath.item]];

    __weak TGGalleryCell *weakCell = cell;
    CGSize targetSize = CGSizeMake(self.collectionLayout.itemSize.width * 2.0, self.collectionLayout.itemSize.height * 2.0);
    [[PHImageManager defaultManager] requestImageForAsset:asset
                                               targetSize:targetSize
                                              contentMode:PHImageContentModeAspectFill
                                                  options:[self thumbnailOptions]
                                            resultHandler:^(UIImage *result, NSDictionary *info) {
        if (weakCell.representedAssetId == asset.localIdentifier) {
            weakCell.thumbnailView.image = result;
        }
    }];
    return cell;
}

- (PHImageRequestOptions *)thumbnailOptions {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.networkAccessAllowed = NO;
    return options;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self toggleSelectionAtIndex:indexPath.item];
}

#pragma mark - Actions

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sendTapped {
    if (self.sending || self.selectedIndexes.count == 0) {
        return;
    }
    self.sending = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.navigationItem.leftBarButtonItem.enabled = NO;
    [self.spinner startAnimating];

    NSMutableArray<PHAsset *> *assets = [NSMutableArray array];
    for (NSNumber *index in self.selectedIndexes) {
        NSInteger item = index.integerValue;
        if (item >= 0 && item < (NSInteger)self.assets.count) {
            [assets addObject:self.assets[(NSUInteger)item]];
        }
    }

    __weak typeof(self) weakSelf = self;
    [self exportAssets:assets completion:^(NSArray<NSString *> *paths) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.spinner stopAnimating];
            void (^onSend)(NSArray<NSString *> *) = weakSelf.onSend;
            if (paths.count == 0) {
                weakSelf.sending = NO;
                weakSelf.navigationItem.rightBarButtonItem.enabled = YES;
                weakSelf.navigationItem.leftBarButtonItem.enabled = YES;
                [weakSelf showAccessDeniedMessage];
                weakSelf.messageLabel.text = @"Nie udało się odczytać wybranych zdjęć.";
                return;
            }
            UIViewController *presenter = weakSelf.presentingViewController;
            [presenter dismissViewControllerAnimated:YES completion:^{
                if (onSend != nil) {
                    onSend(paths);
                }
            }];
        });
    }];
}

/// Converts selected assets to temporary JPEGs (HEIC and iCloud originals
/// included), preserving the selection order.
- (void)exportAssets:(NSArray<PHAsset *> *)assets completion:(void (^)(NSArray<NSString *> *paths))completion {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeNone;
    options.version = PHImageRequestOptionsVersionCurrent;

    dispatch_queue_t exportQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(exportQueue, ^{
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        for (PHAsset *asset in assets) {
            @autoreleasepool {
                __block NSData *imageData = nil;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [[PHImageManager defaultManager] requestImageDataForAsset:asset
                                                                  options:options
                                                            resultHandler:^(NSData *data, NSString *uti, UIImageOrientation orientation, NSDictionary *info) {
                    imageData = data;
                    dispatch_semaphore_signal(semaphore);
                }];
                dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)));
                UIImage *image = imageData.length > 0 ? [UIImage imageWithData:imageData] : nil;
                if (image == nil) {
                    continue;
                }
                NSData *jpeg = UIImageJPEGRepresentation(image, 0.9);
                if (jpeg.length == 0) {
                    continue;
                }
                NSString *fileName = [NSString stringWithFormat:@"send_%llu_%lu.jpg",
                                      (unsigned long long)(CACurrentMediaTime() * 1000.0),
                                      (unsigned long)paths.count];
                NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
                if ([jpeg writeToFile:path atomically:YES]) {
                    [paths addObject:path];
                }
            }
        }
        completion(paths);
    });
}

@end
