#import "QBAlbumCell.h"

@interface QBAlbumCell ()

@property (nonatomic, strong) UIView *container;     // NEW – main wrapper view

@end

@implementation QBAlbumCell

+ (NSString *)reuseIdentifier {
    return NSStringFromClass([self class]);
}

#pragma mark - Init

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {

    self.selectionStyle = UITableViewCellSelectionStyleNone;
  
    // -----------------------------
    // 1) CONTAINER VIEW
    // -----------------------------
    _container = [[UIView alloc] init];
    _container.translatesAutoresizingMaskIntoConstraints = NO;
   
    _container.layer.cornerRadius = 16;
 
    [self.contentView addSubview:_container];
    float pad = 8;
    float minusFromWidth = 16;
    [NSLayoutConstraint activateConstraints:@[
        
        [_container.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [_container.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad],
        [_container.widthAnchor constraintEqualToAnchor:self.contentView.heightAnchor constant:-minusFromWidth],
        [_container.heightAnchor constraintEqualToAnchor:self.contentView.heightAnchor constant:-minusFromWidth]
    ]];

    // -----------------------------
    // 2) CREATE SUBVIEWS
    // -----------------------------
    _imageView1 = [self makeImageView];
    _imageView2 = [self makeImageView];
    _imageView3 = [self makeImageView];

    [_container addSubview:_imageView1];
    [_container addSubview:_imageView2];
    [_container addSubview:_imageView3];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:19];
    _titleLabel.numberOfLines = 1;

    _countLabel = [[UILabel alloc] init];
    _countLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _countLabel.font = [UIFont fontWithName:@"Beiruti-Medium" size:16];
    _countLabel.textColor = UIColor.secondaryLabelColor;

    [self.contentView addSubview:_titleLabel];
    [self.contentView addSubview:_countLabel];
 

    [self setupConstraints];
    
    
    self.containerSep = [[UIView alloc] init];
    self.containerSep.translatesAutoresizingMaskIntoConstraints = NO;
    self.containerSep.backgroundColor = AppBackgroundClr;
    self.containerSep.layer.cornerRadius = 0;
    self.containerSep.layer.masksToBounds = YES;

    [self.contentView addSubview:self.containerSep];

    [NSLayoutConstraint activateConstraints:@[
        [self.containerSep.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:10],
        [self.containerSep.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [self.containerSep.heightAnchor constraintEqualToConstant:1.0],
        [self.containerSep.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-2.0]
    ]];
}

#pragma mark - Helpers

- (UIImageView *)makeImageView {
    UIImageView *iv = [[UIImageView alloc] init];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.layer.cornerRadius = 16;
    iv.backgroundColor = AppBackgroundClrLigter;
    iv.layer.masksToBounds = YES;
    iv.clipsToBounds = YES;

    return iv;
}

#pragma mark - Layout

- (void)setupConstraints {
 
    float pad = 8;
    float minusFromWidth = 16;
    
    [NSLayoutConstraint activateConstraints:@[
        
        [_container.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
        [_container.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad],
        [_container.widthAnchor constraintEqualToAnchor:self.contentView.heightAnchor constant:-minusFromWidth],
        [_container.heightAnchor constraintEqualToAnchor:self.contentView.heightAnchor constant:-minusFromWidth]
    ]];
    
    
    //float imageSide = self.container.hx_h - minusFromWidth;
    // imageView1
    [NSLayoutConstraint activateConstraints:@[
        [_imageView1.centerYAnchor constraintEqualToAnchor:_container.centerYAnchor constant:0],
        [_imageView1.centerXAnchor constraintEqualToAnchor:_container.centerXAnchor constant:0],
        [_imageView1.widthAnchor constraintEqualToAnchor:_container.widthAnchor constant:-1],
        [_imageView1.heightAnchor constraintEqualToAnchor:_container.heightAnchor constant:-1]
    ]];

    // imageView2
    [NSLayoutConstraint activateConstraints:@[
        [_imageView2.centerYAnchor constraintEqualToAnchor:_container.centerYAnchor constant:0],
        [_imageView2.centerXAnchor constraintEqualToAnchor:_container.centerXAnchor constant:0],
        [_imageView2.widthAnchor constraintEqualToAnchor:_container.widthAnchor constant:-1],
        [_imageView2.heightAnchor constraintEqualToAnchor:_container.heightAnchor constant:-1]
    ]];


    // imageView3
    [NSLayoutConstraint activateConstraints:@[
        [_imageView3.centerYAnchor constraintEqualToAnchor:_container.centerYAnchor constant:0],
        [_imageView3.centerXAnchor constraintEqualToAnchor:_container.centerXAnchor constant:0],
        [_imageView3.widthAnchor constraintEqualToAnchor:_container.widthAnchor constant:-1],
        [_imageView3.heightAnchor constraintEqualToAnchor:_container.heightAnchor constant:-1]
    ]];


    // TITLE
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_imageView1.trailingAnchor constant:12],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
        [_titleLabel.topAnchor constraintEqualToAnchor:_imageView1.topAnchor constant:12]
    ]];

    // COUNT
    [NSLayoutConstraint activateConstraints:@[
        [_countLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_countLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_countLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
        [_countLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12]
    ]];
    
    [self layoutSubviews];
    
}

#pragma mark - Reuse

- (void)prepareForReuse {
    [super prepareForReuse];
    _imageView1.image = nil;
    _imageView2.image = nil;
    _imageView3.image = nil;
     
    
    [Styling addLiquidGlassBorderToView:_container cornerRadius:16];
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    [Styling addLiquidGlassBorderToView:_container cornerRadius:16];
}

#pragma mark - Border setter

- (void)setBorderWidth:(CGFloat)borderWidth {
   
}


- (void)addLiquidGlassBorderToView:(UIView *)view cornerRadius:(float)cornerRadius{
    // Remove any old effect
    for (CALayer *layer in view.layer.sublayers.copy) {
        if ([layer.name isEqualToString:@"liquidGlassBorder"]) {
            [layer removeFromSuperlayer];
        }
    }
    
    // Outer glow
    CALayer *glow = [CALayer layer];
    glow.name = @"liquidGlassBorder";
    glow.frame = view.bounds;
    glow.cornerRadius = cornerRadius;
    glow.borderWidth = 0.5;
    glow.borderColor = [[PPColorUtils pp_selectedCellColorFromPrimaryWithAlpha:0.5]  CGColor];
    glow.shadowColor = AppShadowClr.CGColor;
    glow.shadowOpacity = 0.0;
    glow.shadowRadius = 0;
    glow.shadowOffset = CGSizeMake(0, 0);
    glow.shouldRasterize = YES;
    glow.rasterizationScale = UIScreen.mainScreen.scale;
    [view.layer addSublayer:glow];
    
    // Keep it updated on layout
    glow.needsDisplayOnBoundsChange = YES;
    
    
    
    /*
     // Animate shimmer (slow)
     CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
     anim.fromValue = @0;
     anim.toValue = @(M_PI * 2);
     anim.duration = 12.0;
     anim.repeatCount = HUGE_VALF;
     [gradient addAnimation:anim forKey:@"liquidShimmer"];
     */
}
@end
