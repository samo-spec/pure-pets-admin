// PPBannerCell.m
#import "PPBannerCell.h"

@interface PPBannerCell ()
@property (nonatomic, strong) PPBannerView *bannerView;
@property (nonatomic, strong) CAGradientLayer *bgGradientLayer;
@end

@implementation PPBannerCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _bannerView = [[PPBannerView alloc] initWithFrame:CGRectZero];
        _bannerView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_bannerView];

        [NSLayoutConstraint activateConstraints:@[
            [_bannerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_bannerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_bannerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_bannerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
        
     
    }
    return self;
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    _bgGradientLayer.frame = _bannerView.bounds;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Reset visuals; the shared Kingfisher loader cancels its own pending image work.
    [_bannerView prepareForReuse];
}

- (void)configureWithModel:(PPBannerViewModel *)vm {
    [_bannerView configureWithModel:vm];
}



#pragma mark - Gradient setter (works with shadow)
- (void)setBackgroundGradientFrom:(UIColor *)startColor
                               to:(UIColor *)endColor
                            angle:(CGFloat)degrees
{
    _bgGradientLayer.colors = @[(__bridge id)startColor.CGColor,
                                (__bridge id)endColor.CGColor];
    _bgGradientLayer.locations = @[@0.0, @1.0];

    CGFloat theta = degrees * (CGFloat)M_PI / 180.0;
    CGPoint start = CGPointMake(0.5 - 0.5 * cos(theta), 0.5 - 0.5 * sin(theta));
    CGPoint end   = CGPointMake(0.5 + 0.5 * cos(theta), 0.5 + 0.5 * sin(theta));
    _bgGradientLayer.startPoint = start;
    _bgGradientLayer.endPoint   = end;
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




@end
