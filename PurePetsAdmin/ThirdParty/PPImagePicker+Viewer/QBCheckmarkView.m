#import "QBCheckmarkView.h"

@implementation QBCheckmarkView {
    BOOL _isChecked;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self setupView];
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self setupView];
}

- (void)setupView {
    self.backgroundColor = UIColor.clearColor;

    // Create SF Symbol
    UIImageSymbolConfiguration *config =
        [UIImageSymbolConfiguration configurationWithPointSize:20
                                                        weight:UIImageSymbolWeightSemibold];

    UIImage *img = [UIImage systemImageNamed:@"checkmark.circle.fill"
                         withConfiguration:config];

    _imageView = [[UIImageView alloc] initWithImage:img];
    _imageView.tintColor = [AppPrimaryClr colorWithAlphaComponent:0.5];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.alpha = 0.0;            // Hidden initially
    _imageView.transform = CGAffineTransformMakeScale(0.4, 0.4);

    [self addSubview:_imageView];

    // Center constraints
    [NSLayoutConstraint activateConstraints:@[
        [_imageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_imageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];

    self.userInteractionEnabled = NO;
}

#pragma mark - Public

- (void)setChecked:(BOOL)checked animated:(BOOL)animated {
    if (_isChecked == checked) return;
    _isChecked = checked;

    if (checked) {
        [self showAnimated:animated];
    } else {
        [self hideAnimated:animated];
    }
}

#pragma mark - Animations

- (void)showAnimated:(BOOL)animated {
    if (!animated) {
        self.imageView.alpha = 1.0;
        self.imageView.transform = CGAffineTransformIdentity;
        return;
    }

    self.imageView.alpha = 0.0;
    self.imageView.transform = CGAffineTransformMakeScale(0.4, 0.4);

    [UIView animateWithDuration:0.22
                          delay:0
         usingSpringWithDamping:0.75
          initialSpringVelocity:0.8
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.imageView.alpha = 1.0;
        self.imageView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)hideAnimated:(BOOL)animated {
    if (!animated) {
        self.imageView.alpha = 0.0;
        self.imageView.transform = CGAffineTransformMakeScale(0.4, 0.4);
        return;
    }

    [UIView animateWithDuration:0.18 animations:^{
        self.imageView.alpha = 0.0;
        self.imageView.transform = CGAffineTransformMakeScale(0.4, 0.4);
    }];
}

@end
