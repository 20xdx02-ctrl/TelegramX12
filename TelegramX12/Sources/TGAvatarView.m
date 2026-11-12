#import "TGAvatarView.h"
#import "TGCache.h"
#import "TGTheme.h"
#import "TGTDLibClient.h"

@interface TGAvatarView ()
@property (nonatomic, strong) UILabel *initialsLabel;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic) int32_t currentFileId;
@end

@implementation TGAvatarView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;

        _initialsLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _initialsLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _initialsLabel.textAlignment = NSTextAlignmentCenter;
        _initialsLabel.textColor = [UIColor whiteColor];
        _initialsLabel.font = [TGTheme semiboldFontOfSize:22.0];
        [self addSubview:_initialsLabel];

        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.hidden = YES;
        [self addSubview:_imageView];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
    self.layer.cornerRadius = side / 2.0;
    self.initialsLabel.font = [TGTheme semiboldFontOfSize:side * 0.40];
}

- (void)setTitle:(NSString *)title identifier:(int64_t)identifier {
    self.currentFileId = 0;
    self.imageView.hidden = YES;
    self.imageView.image = nil;
    self.initialsLabel.hidden = NO;
    self.initialsLabel.text = [TGTheme initialsForTitle:title];
    self.backgroundColor = [TGTheme avatarColorForIdentifier:identifier];
}

- (void)setImage:(nullable UIImage *)image {
    if (image != nil) {
        self.imageView.image = image;
        self.imageView.hidden = NO;
        self.initialsLabel.hidden = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    } else {
        self.imageView.image = nil;
        self.imageView.hidden = YES;
        self.initialsLabel.hidden = NO;
    }
}

- (void)loadAvatarWithFileId:(int32_t)fileId
                      client:(nullable TGTDLibClient *)client
                       title:(NSString *)title
                  identifier:(int64_t)identifier {
    [self setTitle:title identifier:identifier];
    if (fileId <= 0) {
        return;
    }
    self.currentFileId = fileId;

    // Our own snapshot is checked first so avatars appear instantly on a cold
    // start, before TDLib has re-registered its files.
    NSString *cachedPath = [[TGCache sharedCache] avatarPathForIdentifier:identifier fileId:fileId];
    if (cachedPath.length > 0) {
        UIImage *cachedImage = [UIImage imageWithContentsOfFile:cachedPath];
        if (cachedImage != nil) {
            [self setImage:cachedImage];
            return;
        }
    }
    if (client == nil) {
        return;
    }

    NSString *path = [client localPathForFileId:fileId];
    if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        if (img != nil) {
            [self setImage:img];
            [[TGCache sharedCache] storeAvatarFromPath:path identifier:identifier fileId:fileId];
            return;
        }
    }

    __weak typeof(self) weakSelf = self;
    [client downloadFileWithId:fileId priority:10 completion:^(NSString *downloadedPath, NSDictionary *file) {
        if (weakSelf.currentFileId == fileId && downloadedPath.length > 0) {
            UIImage *img = [UIImage imageWithContentsOfFile:downloadedPath];
            if (img != nil) {
                [weakSelf setImage:img];
                [[TGCache sharedCache] storeAvatarFromPath:downloadedPath identifier:identifier fileId:fileId];
            }
        }
    }];
}

@end
