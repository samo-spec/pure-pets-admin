// In PPBannerView.m
//
//  PPBannerView.m
//  PurePets
//
//  Manual CGRect layout (no Auto Layout):
//  - We compute frames in layoutSubviews for tight control & speed
//  - Right column (badge + sample) stays on the visual trailing side (RTL/LTR)
//  - Labels are measured with sizeThatFits
//  - Sample image size adapts for compact/regular width
//

#import "PPBannerView.h"
// #import "PPBannerViewModel.h"              // Uncomment if you want direct property access
 #import "UIImageView+WebCache.h"

#pragma mark - Private Interface

@interface PPBannerView ()
@property (nonatomic, strong) CAGradientLayer *bgGradientLayer;
// Card container (rounded + clips). We draw everything inside this.
@property (nonatomic, strong) UIView *cardView;

// Background image behind content + gradient overlay for text readability
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UIImageView *badgeImageView;   // Small icon above sample (optional)
@property (nonatomic, strong) UIImageView *sampleImageView;  // Product/sample image

@property (nonatomic, strong) CAGradientLayer *gradientLayer;

// Foreground content: three labels on the text side, two images on the trailing side
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *dateLabel;

// If you don't import PPBannerViewModel.h, we cache URLs via KVC here
@property (nonatomic, strong, nullable) NSURL *bgURL;
@property (nonatomic, strong, nullable) NSURL *sampleURL;
@property (nonatomic, strong, nullable) NSURL *badgeURL;

// Layout tuning knobs
@property (nonatomic, assign) CGFloat hSpacing;      // gap between text column and image column
@property (nonatomic, assign) CGFloat vSpacingText;  // vertical spacing between title/desc/date
@property (nonatomic, assign) CGFloat vSpacingRight; // vertical spacing between badge and sample

@end

@implementation PPBannerView {
    // Styling state
    UIEdgeInsets _contentInsets;  // inner padding for all content
    CGFloat _cornerRadius;        // card corner radius
    BOOL _showsShadow;            // shadow toggle (applied to self, not card)
}

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInit_PPBannerView]; // centralizes setup
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self commonInit_PPBannerView]; // same setup when loaded from nib/storyboard
    }
    return self;
}

- (void)commonInit_PPBannerView {
    // ---- Default styling & spacing ----
    _cornerRadius = 22;                         // banner corner radius (also applied to card)
    self.backgroundColor = AppForgroundColr;  // let card/gradient handle visuals
    _contentInsets = UIEdgeInsetsMake(6, 6, 6, 6);
    _cornerRadius  = 22.0;
    _showsShadow   = YES;

    _hSpacing      = 12.0;
    _vSpacingText  = 4.0;
    _vSpacingRight = 6.0;

    // ---- Card container ----
    // We clip inside the card so the background image (and gradient) respect corners.
    _cardView = [[UIView alloc] initWithFrame:CGRectZero];
    _cardView.layer.cornerCurve = kCACornerCurveContinuous;
    _cardView.layer.cornerRadius = _cornerRadius;
    _cardView.clipsToBounds = YES;
    [self addSubview:_cardView];

    // Shadow is applied on self, not card, so it's not clipped.
    [self applyShadowIfNeeded];

    // ---- Background image + gradient overlay ----
    _backgroundImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _backgroundImageView.contentMode = UIViewContentModeScaleToFill;
    _backgroundImageView.clipsToBounds = YES;
    [_cardView addSubview:_backgroundImageView];

    // Gradient darkens bottom area slightly → better text contrast on photos.
    _gradientLayer = [CAGradientLayer layer];
    _gradientLayer.colors = @[
        (id)[UIColor ppMineralBeige].CGColor,
        (id)[UIColor ppWarmPorcelain].CGColor
    ];
    _gradientLayer.locations = @[@0.0, @1.0];
    _gradientLayer.startPoint = CGPointMake(0.5, 1.0);
    _gradientLayer.endPoint   = CGPointMake(0.5, 0.0);
    _gradientLayer.cornerRadius = 20; // NOTE: we update frame in layoutSubviews; keep radius in sync if you change _cornerRadius
    //[_backgroundImageView.layer addSublayer:_gradientLayer];

    // ---- Labels (text column) ----
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLabel.numberOfLines = 2;                                // allow two lines
    _titleLabel.adjustsFontForContentSizeCategory = YES;          // Dynamic Type
    _titleLabel.font = [Styling fontBold:18];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;                       // your helper: LTR/RTL alignment
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_cardView addSubview:_titleLabel];

    _descLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _descLabel.numberOfLines = 2;
    _descLabel.adjustsFontForContentSizeCategory = YES;
    _descLabel.font = [Styling fontMedium:16];
    _descLabel.textColor = [UIColor colorWithWhite:1 alpha:0.92];
    _descLabel.textAlignment = Language.alignmentForCurrentLanguage;                    // your helper: LTR/RTL alignment
    _descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_cardView addSubview:_descLabel];

    _dateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _dateLabel.numberOfLines = 1;                                 // single line
    _dateLabel.adjustsFontForContentSizeCategory = YES;
    _dateLabel.font = [Styling fontRegular:14];
    _dateLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _dateLabel.textAlignment = Language.alignmentForCurrentLanguage;                      // your helper: LTR/RTL alignment
    _dateLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_cardView addSubview:_dateLabel];

    // ---- Right column (badge + sample) ----
    _badgeImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _badgeImageView.contentMode = UIViewContentModeScaleAspectFit;
    _badgeImageView.clipsToBounds = YES;
    _badgeImageView.hidden = YES;                                 // hidden if no URL provided
    [_cardView addSubview:_badgeImageView];

    _sampleImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _sampleImageView.contentMode = UIViewContentModeScaleAspectFill;
    _sampleImageView.clipsToBounds = YES;
    _sampleImageView.layer.cornerRadius = 22.0;                   // sample corner
    _sampleImageView.backgroundColor = AppClearClr;
    
    [_cardView addSubview:_sampleImageView];

    // ---- Accessibility ----
    // Make the whole banner behave like a tappable card.
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    // If you want outer rounded corners on the banner view itself (not just card):
    self.layer.cornerRadius = _cornerRadius;
    self.clipsToBounds = YES;      // NOTE: this will clip shadow if you also set shadow on self
    self.layer.masksToBounds = YES;// (We apply shadow on self earlier; if you want shadow visible, remove this line.)
}

#pragma mark - Public API

// Updating content padding → request a relayout
- (void)setContentInsets:(UIEdgeInsets)contentInsets {
    _contentInsets = contentInsets;
    [self setNeedsLayout];
}

// Change corner radius at runtime
- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    _cardView.layer.cornerRadius = cornerRadius;
    // Tip: also mirror to self.layer.cornerRadius and _gradientLayer.cornerRadius if you want perfect match
}

// Toggle shadow on/off and re-apply params
- (void)setShowsShadow:(BOOL)showsShadow {
    _showsShadow = showsShadow;
    [self applyShadowIfNeeded];
}

// Main entry to fill the banner
- (void)configureWithModel:(PPBannerViewModel *)model {
    // If PPBannerViewModel.h isn’t imported, we use KVC (valueForKey:) safely.
    _titleLabel.text =   model.localizedTitleText ?: @"";
    _descLabel.text  = model.localizedDescText ?: @"";
    _dateLabel.text  = model.postDateText ?: @"";
    
  
    // Accessibility announcement text
    self.accessibilityLabel = [@[
        _titleLabel.text ?: @"",
        _descLabel.text  ?: @"",
        _dateLabel.text  ?: @""
    ] componentsJoinedByString:@". "];
    self.accessibilityHint = NSLocalizedString(@"Double-tap to open details.", @"Banner accessibility hint");

    // Cache URLs for loaders
    _bgURL     = model.backgroundImageURL ;
    _sampleURL = model.sampleImageURL ;
    _badgeURL  = model.badgeImageURL ;

    // Local placeholders
    UIImage *bgPlaceholder     = [self.class pp_placeholderBackground];
    //UIImage *samplePlaceholder = [self.class pp_placeholderSample];

     
    if (_bgURL) {
        _backgroundImageView.hidden = NO;
        [_backgroundImageView setImageFromUrl:_bgURL.absoluteString];
    } else {
        _backgroundImageView.hidden = YES;
        _backgroundImageView.image = nil;
    }
    
    
    __weak typeof(self) weakSelf = self;
    [_sampleImageView setImageFromUrl:_sampleURL.absoluteString completion:^(UIImage *image) {
        dispatch_async(dispatch_get_main_queue(), ^{
              __strong typeof(weakSelf) strongSelf = weakSelf;
              if (!strongSelf || !image) return;
            
            [PPColorUtils applyGradientFromImage:strongSelf.sampleImageView
                                         toView:strongSelf.cardView
                              withToneAdjustment:PPColorToneAdjustmentLighten
                                         degree:90];
          });
    }];
   
    
    if (_sampleURL) {
        _sampleImageView.hidden = NO;
        [_sampleImageView setImageFromUrl:_sampleURL.absoluteString];
    } else {
        _sampleImageView.hidden = YES;
        _sampleImageView.image = nil;
    }
    
    
    
    if (_badgeURL) {
        _badgeImageView.hidden = NO;
        [_badgeImageView setImageFromUrl:_badgeURL.absoluteString];
    } else {
        _badgeImageView.hidden = YES;
        _badgeImageView.image = nil;
    }
    
    /* If using SDWebImage, uncomment to load remote images:
    [_backgroundImageView sd_setImageWithURL:_bgURL
                            placeholderImage:bgPlaceholder
                                     options:SDWebImageHighPriority
                                   completed:nil];

    [_sampleImageView sd_setImageWithURL:_sampleURL
                        placeholderImage:samplePlaceholder
                                 options:SDWebImageHighPriority
                               completed:nil];

    if (_badgeURL) {
        _badgeImageView.hidden = NO;
        [_badgeImageView sd_setImageWithURL:_badgeURL placeholderImage:nil options:0 completed:nil];
    } else {
        _badgeImageView.hidden = YES;
        _badgeImageView.image = nil;
    }
    */

    // If not using a loader, ensure we at least show a placeholder
    if (!_backgroundImageView.image) _backgroundImageView.image = bgPlaceholder;
    if (!_sampleImageView.image)     _sampleImageView.image     = nil;
    _badgeImageView.hidden = (_badgeURL == nil);

    NSLog(@"childDict in cell : pannerTextStyle is  %@",model.pannerTextStyle  == 1 ? @"Panner Model Text Style Black" : @"Panner Model Text Style white");
   

    
    NSLog(@"[Banner] pannerTextStyle raw = %ld", (long)model.pannerTextStyle);
    [self applyTextColorsForStyle:(PPBannerTextStyle)model.pannerTextStyle];

    
    
    [self setNeedsLayout]; // trigger relayout with new content
}

// Reset visuals when cells reuse this view
- (void)prepareForReuse {
    _titleLabel.text = @"";
    _descLabel.text  = @"";
    _dateLabel.text  = @"";
    _badgeImageView.image = nil;
    _badgeImageView.hidden = YES;
    _backgroundImageView.image = [self.class pp_placeholderBackground];
    _sampleImageView.image     = [self.class pp_placeholderSample];
    _sampleImageView.hidden = YES;
    
    [self setNeedsLayout];
}

#pragma mark - Layout (CGRect)

// Determine RTL/LTR. You use a custom Language helper here:
// Language.languageVal == 1 → RTL, else LTR.
// If you’d rather follow system layout direction, use:
// return (self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);
- (BOOL)_isRTL {
    return (Language.languageVal == 1);
}

// Decide sample image size depending on horizontal size class
- (CGSize)_sampleImageSize {
    BOOL compact = (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact);
    CGFloat side = compact ? 72.0 : 88.0;
    return CGSizeMake(side, side);
}

// Apply content insets to any rect
- (CGRect)_contentRectForBounds:(CGRect)b {
    return UIEdgeInsetsInsetRect(b, _contentInsets);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect cardFrame = self.bounds;
    cardFrame.origin.x = 5;
    cardFrame.size.width = self.bounds.size.width - 10;
    _cardView.frame = cardFrame;
    
    
    _backgroundImageView.frame = _cardView.bounds;
    _gradientLayer.frame = _backgroundImageView.bounds;
    _gradientLayer.cornerRadius = _cardView.layer.cornerRadius;

    CGRect content = [self _contentRectForBounds:_cardView.bounds];

    // ---- trailing (images) column ----
    CGSize  sampleSize    = [self _sampleImageSize];
    CGFloat badgeSide     = 0.0;
    CGFloat rightColWidth = MAX(sampleSize.width, badgeSide);
    CGFloat pad     = 12.0;
    BOOL rtl = [self _isRTL];

    CGFloat rightColX, textMinX, textMaxX;
    if (!rtl) {
        // LTR: [ text | images ]
        rightColX = CGRectGetMaxX(content) - rightColWidth - pad;
        textMinX  = CGRectGetMinX(content) + pad;            // left padding
        textMaxX  = rightColX - _hSpacing;             // stop before images
    } else {
        // RTL: [ images | text ]
        rightColX = CGRectGetMinX(content) + pad;
        textMinX  = rightColX + rightColWidth + _hSpacing; // start after images
        textMaxX  = CGRectGetMaxX(content) - pad;                 // right padding edge
    }

    // Sample vertically centered
    CGFloat cx = rightColX + (rightColWidth - sampleSize.width) * 0.5;
    CGFloat cy = CGRectGetMidY(content) - sampleSize.height * 0.5;
    
    _sampleImageView.frame = (CGRect){ .origin = CGPointMake(cx, cy), .size = sampleSize };

    if (!_badgeImageView.hidden) {
        CGFloat bx = rightColX + (rightColWidth - badgeSide) * 0.5;
        CGFloat by = CGRectGetMinY(_sampleImageView.frame) - _vSpacingRight - badgeSide;
        _badgeImageView.frame = CGRectMake(bx, by, badgeSide, badgeSide);
    } else {
        _badgeImageView.frame = CGRectZero;
    }

    // ---- text area & label frames ----
    CGFloat textAreaMinX   = textMinX;
    CGFloat textAreaMaxX   = textMaxX;
    CGFloat textAreaWidth  = MAX(0.0, textAreaMaxX - textAreaMinX);
    CGFloat y = CGRectGetMinY(content) + pad;

    // Helper to place a label with your rule:
    // RTL  -> x = textAreaMaxX - labelWidth - (0)  (padding already accounted by textArea)
    // LTR  -> x = textAreaMinX
    void (^placeLabel)(UILabel *, CGFloat *) = ^(UILabel *label, CGFloat *cursorY){
        CGSize maxSize  = CGSizeMake(textAreaWidth, CGFLOAT_MAX);
        CGSize fit      = [label sizeThatFits:maxSize];
        CGFloat w       = MIN(textAreaWidth, fit.width);
        CGFloat x       = rtl ? (textAreaMaxX - w) : textAreaMinX;   // <-- your rule
        label.preferredMaxLayoutWidth = textAreaWidth;
        label.frame = CGRectMake(x, *cursorY, w, fit.height);
        *cursorY = CGRectGetMaxY(label.frame) + self.vSpacingText;
    };

    placeLabel(_titleLabel, &y);
    placeLabel(_descLabel,  &y);

    // Date (single line) — same x rule
    CGSize dateFit = [_dateLabel sizeThatFits:CGSizeMake(textAreaWidth, CGFLOAT_MAX)];
    CGFloat dateW  = MIN(textAreaWidth, dateFit.width);
    CGFloat dateX  = rtl ? (textAreaMaxX - dateW) : textAreaMinX;
    _dateLabel.frame = CGRectMake(dateX, y, dateW, dateFit.height);
    
    
    CGFloat imgSide = self.frame.size.height - 10;
    CGFloat imgX = Language.isRTL ? 10.0 : self.frame.size.width - self.frame.size.height - 20;
    _sampleImageView.frame = CGRectMake(imgX, 5, imgSide, imgSide);
}


// Let containers ask for a “natural” height for a given width (helps Auto Layout & self-sizing cells)
- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat width = size.width > 0 ? size.width : UIScreen.mainScreen.bounds.size.width;
    CGRect content = [self _contentRectForBounds:CGRectMake(0, 0, width, 1000)];

    // Width for text after reserving trailing column and spacing
    CGSize sampleSize = [self _sampleImageSize];
    CGFloat rightColWidth = MAX(sampleSize.width, 24.0);
    CGFloat textWidth = content.size.width - rightColWidth - _hSpacing;

    // Measure three labels stacked
    CGSize maxText = CGSizeMake(MAX(0.0, textWidth), CGFLOAT_MAX);
    CGFloat h = 0;
    h += [_titleLabel sizeThatFits:maxText].height + _vSpacingText;
    h += [_descLabel  sizeThatFits:maxText].height + _vSpacingText;
    h += [_dateLabel  sizeThatFits:maxText].height;

    // Ensure minimum inner height is at least the sample column (plus room for badge)
    CGFloat innerHeight = MAX(h, sampleSize.height + 24.0 /* badge room */);
    innerHeight = MAX(innerHeight, 64.0); // safety floor so it never collapses

    // Add top/bottom insets
    innerHeight += _contentInsets.top + _contentInsets.bottom;
    return CGSizeMake(width, ceil(innerHeight));
}

#pragma mark - Trait / Theme Changes

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];

    // Slightly stronger gradient in dark mode for readability
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        _gradientLayer.colors = @[
            (id)[UIColor colorWithWhite:0 alpha:0.45].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.10].CGColor
        ];
    } else {
        _gradientLayer.colors = @[
            (id)[UIColor colorWithWhite:0 alpha:0.35].CGColor,
            (id)[UIColor colorWithWhite:0 alpha:0.05].CGColor
        ];
    }

    // Any size class or layout direction changes → relayout
    [self setNeedsLayout];
}

#pragma mark - Helpers

// Apply (or clear) drop shadow on the outer view (not clipped)
- (void)applyShadowIfNeeded {
    if (_showsShadow) {
        self.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.45].CGColor;
        self.layer.shadowOpacity = 0.25;
        self.layer.shadowRadius = 10;
        self.layer.shadowOffset = CGSizeMake(0, 6);
        self.layer.masksToBounds = NO; // IMPORTANT for visible shadow
    } else {
        self.layer.shadowOpacity = 0.0;
    }
}

// Simple solid placeholder used if no background URL
+ (UIImage *)pp_placeholderBackground {
    CGSize sz = CGSizeMake(8, 8);
    UIGraphicsBeginImageContextWithOptions(sz, YES, 0);
    [[UIColor ppPrimary] setFill];
    UIRectFill((CGRect){.origin = CGPointZero, .size = sz});
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Neutral sample placeholder (light gray)
+ (UIImage *)pp_placeholderSample {
    CGSize sz = CGSizeMake(40, 40);
    UIGraphicsBeginImageContextWithOptions(sz, YES, 0);
    [[UIColor colorWithWhite:0.95 alpha:1.0] setFill];
    UIRectFill((CGRect){.origin = CGPointZero, .size = sz});
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

// Provide an intrinsic height so Auto Layout can size the banner without you hardcoding a height
- (CGSize)intrinsicContentSize {
    CGFloat width = (self.bounds.size.width > 0) ? self.bounds.size.width : UIScreen.mainScreen.bounds.size.width;
    return [self sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
}


#pragma mark - Gradient setter (works with shadow)
- (void)setBackgroundGradientFrom:(UIColor *)startColor
                               to:(UIColor *)endColor
                            angle:(CGFloat)degrees
{
    // 3) Gradient behind everything inside cardView
    _bgGradientLayer = [CAGradientLayer layer];
    _bgGradientLayer.cornerRadius = 22;
    [_cardView.layer insertSublayer:_bgGradientLayer atIndex:0];
    
    
    _gradientLayer.colors = @[(__bridge id)startColor.CGColor,
                                (__bridge id)endColor.CGColor];
    _gradientLayer.locations = @[@0.0, @1.0];

    CGFloat theta = degrees * (CGFloat)M_PI / 180.0;
    CGPoint start = CGPointMake(0.5 - 0.5 * cos(theta), 0.5 - 0.5 * sin(theta));
    CGPoint end   = CGPointMake(0.5 + 0.5 * cos(theta), 0.5 + 0.5 * sin(theta));
    _gradientLayer.startPoint = start;
    _gradientLayer.endPoint   = end;
}



- (UIColor *)pastel:(CGFloat)brightness { // brightness ~0.9 looks airy
    CGFloat h = arc4random_uniform(256)/255.0;
    CGFloat s = 0.20 + arc4random_uniform(30)/255.0; // 0.20–0.32
    return [UIColor colorWithHue:h saturation:s brightness:brightness alpha:1];
}
- (NSArray<UIColor *> *)extractTwoMainColorsFromImage:(UIImage *)image andLightenAmount:(float)amount {
    if (!image) return @[[UIColor colorWithWhite:1 alpha:0.1], [UIColor colorWithWhite:0.95 alpha:0.1]];
    
    // Downscale for speed
    CGSize thumbSize = CGSizeMake(20, 20);
    UIGraphicsBeginImageContext(thumbSize);
    [image drawInRect:CGRectMake(0, 0, thumbSize.width, thumbSize.height)];
    UIImage *thumbImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGImageRef cgImage = thumbImage.CGImage;
    NSUInteger width = CGImageGetWidth(cgImage);
    NSUInteger height = CGImageGetHeight(cgImage);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);
    
    NSMutableDictionary<NSString *, NSNumber *> *colorCounts = [NSMutableDictionary dictionary];
    
    for (NSUInteger y = 0; y < height; y++) {
        for (NSUInteger x = 0; x < width; x++) {
            NSUInteger byteIndex = (bytesPerRow * y) + x * bytesPerPixel;
            CGFloat r = rawData[byteIndex] / 255.0;
            CGFloat g = rawData[byteIndex + 1] / 255.0;
            CGFloat b = rawData[byteIndex + 2] / 255.0;
            
            // Brightness filter — skip very dark colors
            CGFloat brightness = (r + g + b) / 3.0;
            if (brightness < 0.3) continue; // exclude dark shades
            
            // Quantize to reduce small variations
            int qr = (int)(r * 10);
            int qg = (int)(g * 10);
            int qb = (int)(b * 10);
            
            NSString *key = [NSString stringWithFormat:@"%d_%d_%d", qr, qg, qb];
            NSNumber *count = colorCounts[key] ?: @0;
            colorCounts[key] = @(count.integerValue + 1);
        }
    }
    free(rawData);
    
    NSArray *sortedKeys = [colorCounts keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj2 compare:obj1];
    }];
    
    NSMutableArray<UIColor *> *colors = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        NSArray *parts = [key componentsSeparatedByString:@"_"];
        CGFloat r = [parts[0] intValue] / 10.0;
        CGFloat g = [parts[1] intValue] / 10.0;
        CGFloat b = [parts[2] intValue] / 10.0;
        
        UIColor *color = [UIColor colorWithRed:r green:g blue:b alpha:0.9]; // softer alpha
        [colors addObject:[self lightenColor:color amount:amount]]; // pastel effect
        
        if (colors.count >= 2) break;
    }
    
    if (colors.count < 2) {
        return @[[UIColor colorWithWhite:1 alpha:0.6], [UIColor colorWithWhite:0.95 alpha:0.6]];
    }
    
    return colors;
}

- (UIColor *)lightenColor:(UIColor *)color amount:(CGFloat)amount {
    CGFloat r, g, b, a;
    if ([color getRed:&r green:&g blue:&b alpha:&a]) {
        return [UIColor colorWithRed:MIN(r + amount, 1.0)
                               green:MIN(g + amount, 1.0)
                                blue:MIN(b + amount, 1.0)
                               alpha:a];
    }
    return color;
}


- (NSArray<UIColor *> *)extractThreeMainColorsFromImage:(UIImage *)image lightenAmount:(CGFloat)amount {
    if (!image) return @[[UIColor whiteColor], [UIColor lightGrayColor], [UIColor darkGrayColor]];
    
    // Downscale to speed things up
    CGSize thumbSize = CGSizeMake(30, 30);
    UIGraphicsBeginImageContext(thumbSize);
    [image drawInRect:CGRectMake(0, 0, thumbSize.width, thumbSize.height)];
    UIImage *thumbImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGImageRef cgImage = thumbImage.CGImage;
    NSUInteger width = CGImageGetWidth(cgImage);
    NSUInteger height = CGImageGetHeight(cgImage);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = (unsigned char*) calloc(height * width * 4, sizeof(unsigned char));
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    
    CGContextRef context = CGBitmapContextCreate(rawData, width, height,
                                                 bitsPerComponent, bytesPerRow,
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);
    
    NSMutableDictionary<NSString *, NSNumber *> *colorCounts = [NSMutableDictionary dictionary];
    
    for (NSUInteger y = 0; y < height; y++) {
        for (NSUInteger x = 0; x < width; x++) {
            NSUInteger byteIndex = (bytesPerRow * y) + x * bytesPerPixel;
            CGFloat r = rawData[byteIndex] / 255.0;
            CGFloat g = rawData[byteIndex + 1] / 255.0;
            CGFloat b = rawData[byteIndex + 2] / 255.0;
            
            CGFloat brightness = (r + g + b) / 3.0;
            if (brightness < 0.25) continue; // ignore very dark pixels
            
            int qr = (int)(r * 15);
            int qg = (int)(g * 15);
            int qb = (int)(b * 15);
            
            NSString *key = [NSString stringWithFormat:@"%d_%d_%d", qr, qg, qb];
            NSNumber *count = colorCounts[key] ?: @0;
            colorCounts[key] = @(count.integerValue + 1);
        }
    }
    free(rawData);
    
    NSArray *sortedKeys = [colorCounts keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj2 compare:obj1];
    }];
    
    NSMutableArray<UIColor *> *colors = [NSMutableArray array];
    for (NSString *key in sortedKeys) {
        NSArray *parts = [key componentsSeparatedByString:@"_"];
        CGFloat r = [parts[0] intValue] / 15.0;
        CGFloat g = [parts[1] intValue] / 15.0;
        CGFloat b = [parts[2] intValue] / 15.0;
        
        UIColor *c = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
        [colors addObject:[self lightenColor:c amount:amount]];
        if (colors.count >= 3) break;
    }
    
    if (colors.count < 3) {
        [colors addObject:[UIColor whiteColor]];
        [colors addObject:[UIColor lightGrayColor]];
        [colors addObject:[UIColor darkGrayColor]];
    }
    
    return colors;
}



// Call this whenever the style or theme changes
- (void)applyTextColorsForStyle:(PPBannerTextStyle)style {
    // Fallback: use white if your app color is nil
    UIColor *brandFG = PPColorOr(AppForgroundColr, UIColor.whiteColor);

    UIColor *titleColor = (style == PPBannerTextStyleBlack) ? UIColor.blackColor : brandFG;
    UIColor *subColor   = (style == PPBannerTextStyleBlack) ? UIColor.darkGrayColor : brandFG;

    // Always on main thread to be safe
    dispatch_async(dispatch_get_main_queue(), ^{
        self.titleLabel.textColor = titleColor;
        self.descLabel.textColor  = subColor;
        self.dateLabel.textColor  = subColor;
    });
}




@end


/*
 NSString *remain = [vm countdownTimeRemaining]; // e.g. "2d 4h 12m" or nil
 self.countdownLabel.hidden = (remain.length == 0);
 self.countdownLabel.text   = remain;

 // (Optional) refresh every minute:
 [self.countdownTimer invalidate];
 self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                        repeats:YES
                                                          block:^(__unused NSTimer *t){
     self.countdownLabel.text = [vm countdownTimeRemaining];
 }];

 */
