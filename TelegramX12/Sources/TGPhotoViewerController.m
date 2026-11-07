#import "TGPhotoViewerController.h"

@interface TGPhotoViewerController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIButton *closeButton;
@end

@implementation TGPhotoViewerController

- (instancetype)initWithImage:(UIImage *)image {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _image = image;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (instancetype)initWithImagePath:(NSString *)imagePath {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _imagePath = [imagePath copy];
        _image = [UIImage imageWithContentsOfFile:imagePath];
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.clipsToBounds = YES;
    [self.view addSubview:self.scrollView];

    self.imageView = [[UIImageView alloc] initWithImage:self.image];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.userInteractionEnabled = YES;
    [self.scrollView addSubview:self.imageView];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.frame = CGRectMake(16.0, 36.0, 36.0, 36.0);
    self.closeButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    self.closeButton.layer.cornerRadius = 18.0;
    self.closeButton.clipsToBounds = YES;
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];

    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [self.view addGestureRecognizer:singleTap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.view addGestureRecognizer:pan];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutImage];
}

- (void)layoutImage {
    if (self.image == nil || self.image.size.width <= 0 || self.image.size.height <= 0) {
        return;
    }
    CGSize boundsSize = self.scrollView.bounds.size;
    CGFloat scaleWidth = boundsSize.width / self.image.size.width;
    CGFloat scaleHeight = boundsSize.height / self.image.size.height;
    CGFloat minScale = MIN(scaleWidth, scaleHeight);

    CGSize fittedSize = CGSizeMake(floor(self.image.size.width * minScale), floor(self.image.size.height * minScale));
    self.imageView.frame = CGRectMake(0, 0, fittedSize.width, fittedSize.height);
    self.scrollView.contentSize = fittedSize;
    [self centerImage];
}

- (void)centerImage {
    CGSize boundsSize = self.scrollView.bounds.size;
    CGRect frameToCenter = self.imageView.frame;

    if (frameToCenter.size.width < boundsSize.width) {
        frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2.0;
    } else {
        frameToCenter.origin.x = 0;
    }

    if (frameToCenter.size.height < boundsSize.height) {
        frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2.0;
    } else {
        frameToCenter.origin.y = 0;
    }

    self.imageView.frame = frameToCenter;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self centerImage];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer {
    self.closeButton.hidden = !self.closeButton.hidden;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
    if (self.scrollView.zoomScale > 1.0) {
        [self.scrollView setZoomScale:1.0 animated:YES];
    } else {
        CGPoint point = [recognizer locationInView:self.imageView];
        CGRect zoomRect = CGRectMake(point.x - 50.0, point.y - 50.0, 100.0, 100.0);
        [self.scrollView zoomToRect:zoomRect animated:YES];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    if (self.scrollView.zoomScale > 1.0) {
        return;
    }
    CGPoint translation = [recognizer translationInView:self.view];
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        self.view.transform = CGAffineTransformMakeTranslation(0, translation.y);
        CGFloat progress = MIN(1.0, fabs(translation.y) / 250.0);
        self.view.alpha = 1.0 - progress * 0.5;
    } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
        if (fabs(translation.y) > 120.0) {
            [self dismissViewControllerAnimated:YES completion:nil];
        } else {
            [UIView animateWithDuration:0.25 animations:^{
                self.view.transform = CGAffineTransformIdentity;
                self.view.alpha = 1.0;
            }];
        }
    }
}

@end
