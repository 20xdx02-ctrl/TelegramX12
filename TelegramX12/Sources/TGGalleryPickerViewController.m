#import "TGGalleryPickerViewController.h"

#import "TGLog.h"
#import "TGPhotoExport.h"
#import "TGTheme.h"

#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>

@interface TGGalleryCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIView *selectionBorder;
@property (nonatomic, strong) UILabel *numberLabel;
@property (nonatomic, copy, nullable) NSString *representedAssetId;
@property (nonatomic) PHImageRequestID thumbnailRequestId;
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
    [self cancelThumbnailRequest];
    self.thumbnailView.image = nil;
    self.representedAssetId = nil;
    self.selectionBorder.hidden = YES;
    self.numberLabel.hidden = YES;
}

- (void)cancelThumbnailRequest {
    if (self.thumbnailRequestId != 0) {
        [[PHImageManager defaultManager] cancelImageRequest:self.thumbnailRequestId];
        self.thumbnailRequestId = 0;
    }
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
    TGXLogLine(@"gallery: photo authorization status %ld", (long)status);
    if (status == PHAuthorizationStatusAuthorized) {
        [self loadAssets];
        return;
    }
    if (status == PHAuthorizationStatusNotDetermined) {
        [self.spinner startAnimating];
        __weak typeof(self) weakSelf = self;
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus newStatus) {
            TGXLogLine(@"gallery: photo authorization resolved to %ld", (long)newStatus);
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
    [self removeStaleExportFiles];
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO] ];
    self.assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
    TGXLogLine(@"gallery: loaded %lu photo assets", (unsigned long)self.assets.count);
    if (self.assets.count == 0) {
        self.messageLabel.hidden = NO;
        self.messageLabel.text = @"Brak zdjęć w bibliotece.";
    } else {
        self.messageLabel.hidden = YES;
    }
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
    // Keep the identifier in a local: every call to -localIdentifier returns a
    // fresh string instance, so pointer comparison against the cell's copy
    // would always fail and leave the tile as an empty grey square.
    NSString *assetIdentifier = asset.localIdentifier;
    [cell cancelThumbnailRequest];
    cell.representedAssetId = assetIdentifier;
    cell.thumbnailView.image = nil;
    NSInteger position = [self selectionPositionForIndex:indexPath.item];
    [cell setSelectedForSending:position > 0 number:position];

    CGSize targetSize = CGSizeMake(MAX(1.0, self.collectionLayout.itemSize.width * 2.0),
                                   MAX(1.0, self.collectionLayout.itemSize.height * 2.0));
    __weak TGGalleryCell *weakCell = cell;
    __block BOOL retriedWithNetwork = NO;
    PHImageRequestOptions *options = [self thumbnailOptions];

    __block PHImageRequestID requestId = 0;
    void (^applyResult)(UIImage *, NSDictionary *) = ^(UIImage *result, NSDictionary *info) {
        if (result == nil) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            TGGalleryCell *strongCell = weakCell;
            if (strongCell == nil || ![strongCell.representedAssetId isEqualToString:assetIdentifier]) {
                return;
            }
            strongCell.thumbnailView.image = result;
        });
    };

    requestId = [[PHImageManager defaultManager] requestImageForAsset:asset
                                                          targetSize:targetSize
                                                         contentMode:PHImageContentModeAspectFill
                                                             options:options
                                                       resultHandler:^(UIImage *result, NSDictionary *info) {
        if ([info[PHImageResultIsDegradedKey] boolValue]) {
            // Low-quality pass: useful immediately, but keep the request alive
            // for the full thumbnail.
            applyResult(result, info);
            return;
        }
        if (result != nil) {
            applyResult(result, info);
            return;
        }
        if (retriedWithNetwork) {
            TGXLogLine(@"gallery: thumbnail failed for %@ info=%@", assetIdentifier, info);
            return;
        }
        // iCloud-only originals: the fast, offline request returns nil. Retry
        // once with network access instead of leaving the tile grey.
        retriedWithNetwork = YES;
        BOOL inCloud = [info[PHImageResultIsInCloudKey] boolValue];
        PHImageRequestOptions *networkOptions = [self thumbnailOptions];
        networkOptions.networkAccessAllowed = YES;
        if (!inCloud) {
            TGXLogLine(@"gallery: thumbnail nil for %@, retrying with network; info=%@", assetIdentifier, info);
        }
        requestId = [[PHImageManager defaultManager] requestImageForAsset:asset
                                                              targetSize:targetSize
                                                             contentMode:PHImageContentModeAspectFill
                                                                 options:networkOptions
                                                           resultHandler:^(UIImage *networkResult, NSDictionary *networkInfo) {
            if (networkResult != nil) {
                applyResult(networkResult, networkInfo);
            } else if (![networkInfo[PHImageResultIsDegradedKey] boolValue]) {
                TGXLogLine(@"gallery: thumbnail network fetch failed for %@ info=%@", assetIdentifier, networkInfo);
            }
        }];
    }];
    cell.thumbnailRequestId = requestId;
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
    TGXLogLine(@"gallery: exporting %lu selected photos", (unsigned long)assets.count);

    __weak typeof(self) weakSelf = self;
    [self exportAssets:assets completion:^(NSArray<NSString *> *paths) {
        TGXLogLine(@"gallery: export produced %lu/%lu files", (unsigned long)paths.count, (unsigned long)assets.count);
        dispatch_async(dispatch_get_main_queue(), ^{
            TGGalleryPickerViewController *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf.spinner stopAnimating];
            void (^onSend)(NSArray<NSString *> *) = strongSelf.onSend;
            if (paths.count == 0) {
                strongSelf.sending = NO;
                strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
                strongSelf.navigationItem.leftBarButtonItem.enabled = YES;
                strongSelf.messageLabel.hidden = NO;
                strongSelf.messageLabel.text = @"Nie udało się odczytać wybranych zdjęć.";
                return;
            }
            UIViewController *presenter = strongSelf.presentingViewController;
            [presenter dismissViewControllerAnimated:YES completion:^{
                if (onSend != nil) {
                    onSend(paths);
                }
            }];
        });
    }];
}

/// Converts selected assets to temporary JPEGs (HEIC and iCloud originals
/// included), preserving the selection order. Photos requests are chained
/// asynchronously: blocking a thread on a semaphore while the Photos framework
/// wants to deliver on its own queue is what made exports come back empty.
- (void)exportAssets:(NSArray<PHAsset *> *)assets completion:(void (^)(NSArray<NSString *> *paths))completion {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    [self exportAssetAtIndex:0 assets:assets paths:paths completion:completion];
}

- (void)exportAssetAtIndex:(NSUInteger)index
                    assets:(NSArray<PHAsset *> *)assets
                     paths:(NSMutableArray<NSString *> *)paths
                completion:(void (^)(NSArray<NSString *> *paths))completion {
    if (index >= assets.count) {
        completion(paths);
        return;
    }
    PHAsset *asset = assets[index];
    __weak typeof(self) weakSelf = self;
    __block BOOL finished = NO;

    void (^advance)(void) = ^{
        [weakSelf exportAssetAtIndex:index + 1 assets:assets paths:paths completion:completion];
    };

    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.resizeMode = PHImageRequestOptionsResizeModeNone;
    options.version = PHImageRequestOptionsVersionCurrent;

    [[PHImageManager defaultManager] requestImageDataForAsset:asset
                                                     options:options
                                               resultHandler:^(NSData *data, NSString *uti, UIImageOrientation orientation, NSDictionary *info) {
        if ([info[PHImageResultIsDegradedKey] boolValue]) {
            return;
        }
        if (finished) {
            return;
        }
        finished = YES;
        NSData *jpeg = TGMaximumQualityJPEGForImageData(data, uti);
        if (jpeg.length > 0 && [weakSelf appendJPEGData:jpeg toPaths:paths asset:asset]) {
            advance();
            return;
        }
        TGXLogLine(@"gallery: no image data for %@ (%lu bytes), info=%@",
                   asset.localIdentifier, (unsigned long)data.length, info);
        // Some assets (HEIC, edited or iCloud-only) come back without raw data;
        // ask for a decoded full-size image instead.
        [weakSelf exportDecodedImageForAsset:asset paths:paths completion:^{
            advance();
        }];
    }];

    // A Photos request that never calls back must not wedge the whole export.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!finished) {
            finished = YES;
            TGXLogLine(@"gallery: export timed out for %@", asset.localIdentifier);
            advance();
        }
    });
}

- (void)exportDecodedImageForAsset:(PHAsset *)asset
                             paths:(NSMutableArray<NSString *> *)paths
                        completion:(void (^)(void))completion {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.version = PHImageRequestOptionsVersionCurrent;

    __weak typeof(self) weakSelf = self;
    __block BOOL finished = NO;
    [[PHImageManager defaultManager] requestImageForAsset:asset
                                               targetSize:PHImageManagerMaximumSize
                                              contentMode:PHImageContentModeDefault
                                                  options:options
                                            resultHandler:^(UIImage *result, NSDictionary *info) {
        if ([info[PHImageResultIsDegradedKey] boolValue]) {
            return;
        }
        if (finished) {
            return;
        }
        finished = YES;
        if (result != nil) {
            NSData *jpeg = TGMaximumQualityJPEGForImage(result);
            if (jpeg.length > 0) {
                [weakSelf appendJPEGData:jpeg toPaths:paths asset:asset];
            }
        } else {
            TGXLogLine(@"gallery: decoded image fetch failed for %@ info=%@", asset.localIdentifier, info);
        }
        completion();
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!finished) {
            finished = YES;
            TGXLogLine(@"gallery: decoded image fetch timed out for %@", asset.localIdentifier);
            completion();
        }
    });
}

/// Temporary JPEGs live for two hours because TDLib may still be uploading
/// them; clean leftovers from earlier sessions when the picker opens.
- (void)removeStaleExportFiles {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *directory = NSTemporaryDirectory();
        NSArray<NSString *> *names = [fileManager contentsOfDirectoryAtPath:directory error:NULL];
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-24.0 * 60.0 * 60.0];
        for (NSString *name in names) {
            if (![name hasPrefix:@"send_"] || ![name hasSuffix:@".jpg"]) {
                continue;
            }
            NSString *path = [directory stringByAppendingPathComponent:name];
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:NULL];
            NSDate *modified = attributes[NSFileModificationDate];
            if (modified != nil && [modified compare:cutoff] == NSOrderedAscending) {
                [fileManager removeItemAtPath:path error:NULL];
            }
        }
    });
}

- (BOOL)appendJPEGData:(NSData *)jpeg
               toPaths:(NSMutableArray<NSString *> *)paths
                 asset:(PHAsset *)asset {
    if (jpeg.length == 0) {
        TGXLogLine(@"gallery: JPEG encoding produced no data");
        return NO;
    }
    NSString *fileName = [NSString stringWithFormat:@"send_%llu_%lu.jpg",
                          (unsigned long long)(CACurrentMediaTime() * 1000.0),
                          (unsigned long)paths.count];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    if (![jpeg writeToFile:path atomically:YES]) {
        TGXLogLine(@"gallery: failed to write %@", path);
        return NO;
    }
    CGSize pixelSize = TGPhotoPixelSizeForImageData(jpeg);
    TGXLogLine(@"gallery: exported %@ as %.0fx%.0f, %lu bytes",
               asset.localIdentifier, pixelSize.width, pixelSize.height, (unsigned long)jpeg.length);
    [paths addObject:path];
    return YES;
}

@end
