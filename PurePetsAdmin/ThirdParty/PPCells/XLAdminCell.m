//
//  XLAdminCell.m
//  PurePetsAdmin
//

#import "XLAdminCell.h"

@interface XLAdminCell ()
@property (nonatomic, strong) UIView *surfaceView;
@property (nonatomic, strong) UIView *accentRailView;
@property (nonatomic, strong) UIView *iconContainerView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *trailingPlateView;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIView *dividerView;
@property (nonatomic, strong) UIView *highlightOverlayView;
@property (nonatomic, strong) NSLayoutConstraint *surfaceTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *surfaceBottomConstraint;
@end

@implementation XLAdminCell

- (void)configure {
    [super configure];

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.contentView.opaque = NO;
    self.layoutMargins = UIEdgeInsetsZero;
    self.preservesSuperviewLayoutMargins = NO;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.contentView.semanticContentAttribute = self.semanticContentAttribute;

    if (self.surfaceView) return;

    self.surfaceView = [UIView new];
    self.surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    self.surfaceView.opaque = NO;
    self.surfaceView.layer.cornerRadius = 22.0;
    self.surfaceView.layer.cornerCurve = kCACornerCurveContinuous;
    self.surfaceView.clipsToBounds = YES;
    [self.contentView addSubview:self.surfaceView];

    self.highlightOverlayView = [UIView new];
    self.highlightOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.highlightOverlayView.alpha = 0.0;
    self.highlightOverlayView.userInteractionEnabled = NO;
    [self.surfaceView addSubview:self.highlightOverlayView];

    self.accentRailView = [UIView new];
    self.accentRailView.translatesAutoresizingMaskIntoConstraints = NO;
    self.accentRailView.layer.cornerRadius = 1.5;
    self.accentRailView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.surfaceView addSubview:self.accentRailView];

    self.iconContainerView = [UIView new];
    self.iconContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconContainerView.layer.cornerRadius = 15.0;
    self.iconContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    self.iconContainerView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    [self.surfaceView addSubview:self.iconContainerView];

    self.iconView = [UIImageView new];
    self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:18.0
                                                                                                   weight:UIImageSymbolWeightSemibold];
    [self.iconContainerView addSubview:self.iconView];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline]
                            scaledFontForFont:[Styling fontBold:16]];
    self.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.titleLabel.textColor = PrimaryTextClr;
    self.titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.surfaceView addSubview:self.titleLabel];

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote]
                               scaledFontForFont:[Styling fontRegular:12]];
    self.subtitleLabel.adjustsFontForContentSizeCategory = YES;
    self.subtitleLabel.textColor = SeconderyTextClr;
    self.subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.subtitleLabel.numberOfLines = 2;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.surfaceView addSubview:self.subtitleLabel];

    self.trailingPlateView = [UIView new];
    self.trailingPlateView.translatesAutoresizingMaskIntoConstraints = NO;
    self.trailingPlateView.layer.cornerRadius = 16.0;
    self.trailingPlateView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.surfaceView addSubview:self.trailingPlateView];

    self.chevronView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.contentMode = UIViewContentModeScaleAspectFit;
    self.chevronView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:11.0
                                                                                                      weight:UIImageSymbolWeightSemibold];
    [self.trailingPlateView addSubview:self.chevronView];

    self.dividerView = [UIView new];
    self.dividerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.surfaceView addSubview:self.dividerView];

    self.surfaceTopConstraint = [self.surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor];
    self.surfaceBottomConstraint = [self.surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor];
    [NSLayoutConstraint activateConstraints:@[
        self.surfaceTopConstraint,
        self.surfaceBottomConstraint,
        [self.surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
        [self.surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],

        [self.highlightOverlayView.topAnchor constraintEqualToAnchor:self.surfaceView.topAnchor],
        [self.highlightOverlayView.leadingAnchor constraintEqualToAnchor:self.surfaceView.leadingAnchor],
        [self.highlightOverlayView.trailingAnchor constraintEqualToAnchor:self.surfaceView.trailingAnchor],
        [self.highlightOverlayView.bottomAnchor constraintEqualToAnchor:self.surfaceView.bottomAnchor],

        [self.accentRailView.leadingAnchor constraintEqualToAnchor:self.surfaceView.leadingAnchor constant:12.0],
        [self.accentRailView.centerYAnchor constraintEqualToAnchor:self.surfaceView.centerYAnchor],
        [self.accentRailView.widthAnchor constraintEqualToConstant:3.0],
        [self.accentRailView.heightAnchor constraintEqualToConstant:24.0],

        [self.iconContainerView.leadingAnchor constraintEqualToAnchor:self.accentRailView.trailingAnchor constant:11.0],
        [self.iconContainerView.centerYAnchor constraintEqualToAnchor:self.surfaceView.centerYAnchor],
        [self.iconContainerView.widthAnchor constraintEqualToConstant:44.0],
        [self.iconContainerView.heightAnchor constraintEqualToConstant:44.0],

        [self.iconView.centerXAnchor constraintEqualToAnchor:self.iconContainerView.centerXAnchor],
        [self.iconView.centerYAnchor constraintEqualToAnchor:self.iconContainerView.centerYAnchor],
        [self.iconView.widthAnchor constraintEqualToConstant:19.0],
        [self.iconView.heightAnchor constraintEqualToConstant:19.0],

        [self.trailingPlateView.trailingAnchor constraintEqualToAnchor:self.surfaceView.trailingAnchor constant:-14.0],
        [self.trailingPlateView.centerYAnchor constraintEqualToAnchor:self.surfaceView.centerYAnchor],
        [self.trailingPlateView.widthAnchor constraintEqualToConstant:32.0],
        [self.trailingPlateView.heightAnchor constraintEqualToConstant:32.0],

        [self.chevronView.centerXAnchor constraintEqualToAnchor:self.trailingPlateView.centerXAnchor],
        [self.chevronView.centerYAnchor constraintEqualToAnchor:self.trailingPlateView.centerYAnchor],
        [self.chevronView.widthAnchor constraintEqualToConstant:8.0],
        [self.chevronView.heightAnchor constraintEqualToConstant:13.0],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconContainerView.trailingAnchor constant:14.0],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingPlateView.leadingAnchor constant:-12.0],
        [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.surfaceView.centerYAnchor constant:-2.0],

        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.surfaceView.centerYAnchor constant:3.0],
        [self.subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.surfaceView.bottomAnchor constant:-10.0],

        [self.dividerView.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.dividerView.trailingAnchor constraintEqualToAnchor:self.surfaceView.trailingAnchor constant:-16.0],
        [self.dividerView.bottomAnchor constraintEqualToAnchor:self.surfaceView.bottomAnchor],
        [self.dividerView.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
    ]];
}

- (void)update {
    [super update];

    NSDictionary *value = [self.rowDescriptor.value isKindOfClass:NSDictionary.class]
    ? (NSDictionary *)self.rowDescriptor.value
    : @{};
    UIColor *tint = [value[@"tint"] isKindOfClass:UIColor.class] ? value[@"tint"] : [UIColor ppPrimary];
    self.iconView.image = [value[@"icon"] isKindOfClass:UIImage.class] ? value[@"icon"] : nil;
    self.titleLabel.text = [value[@"title"] isKindOfClass:NSString.class] ? value[@"title"] : @"";
    self.subtitleLabel.text = [value[@"subtitle"] isKindOfClass:NSString.class] ? value[@"subtitle"] : @"";

    BOOL reduceTransparency = UIAccessibilityIsReduceTransparencyEnabled();
    BOOL isDark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    UIColor *surface = isDark
    ? [UIColor colorWithRed:0.070 green:0.078 blue:0.075 alpha:reduceTransparency ? 1.0 : 0.94]
    : [UIColor colorWithWhite:1.0 alpha:reduceTransparency ? 1.0 : 0.86];
    self.surfaceView.backgroundColor = surface;
    self.highlightOverlayView.backgroundColor = [tint colorWithAlphaComponent:isDark ? 0.10 : 0.055];
    self.accentRailView.backgroundColor = [tint colorWithAlphaComponent:0.88];
    self.iconContainerView.backgroundColor = [tint colorWithAlphaComponent:isDark ? 0.16 : 0.10];
    self.iconContainerView.layer.borderColor = [tint colorWithAlphaComponent:isDark ? 0.20 : 0.12].CGColor;
    self.iconView.tintColor = tint;
    self.trailingPlateView.backgroundColor = [AppBackgroundClr colorWithAlphaComponent:isDark ? 0.34 : 0.42];
    self.chevronView.tintColor = [SeconderyTextClr colorWithAlphaComponent:0.50];
    self.dividerView.backgroundColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:isDark ? 0.22 : 0.34];
    self.titleLabel.textColor = PrimaryTextClr;
    self.subtitleLabel.textColor = [SeconderyTextClr colorWithAlphaComponent:0.82];
    self.titleLabel.numberOfLines = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ? 2 : 1;
    self.titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
    self.chevronView.image = [UIImage systemImageNamed:(Language.languageVal == 1 ? @"chevron.left" : @"chevron.right")];
    self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.surfaceView.semanticContentAttribute = self.contentView.semanticContentAttribute;

    [self pp_updateGroupedCorners];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityIdentifier = self.rowDescriptor.tag;
    self.accessibilityLabel = self.titleLabel.text;
    self.accessibilityValue = self.subtitleLabel.text;
    self.contentView.accessibilityElementsHidden = YES;
}

- (void)pp_updateGroupedCorners {
    NSArray<XLFormRowDescriptor *> *rows = self.rowDescriptor.sectionDescriptor.formRows ?: @[];
    NSUInteger index = [rows indexOfObjectIdenticalTo:self.rowDescriptor];
    BOOL isFirst = (index == 0 || index == NSNotFound);
    BOOL isLast = (index == rows.count - 1 || index == NSNotFound);

    self.surfaceTopConstraint.constant = isFirst ? 4.0 : 0.0;
    self.surfaceBottomConstraint.constant = isLast ? -4.0 : 0.0;
    self.dividerView.hidden = isLast;

    if (isFirst && isLast) {
        self.surfaceView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner |
        kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else if (isFirst) {
        self.surfaceView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    } else if (isLast) {
        self.surfaceView.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    } else {
        self.surfaceView.layer.maskedCorners = 0;
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    void (^changes)(void) = ^{
        self.highlightOverlayView.alpha = highlighted ? 1.0 : 0.0;
        self.surfaceView.transform = highlighted ? CGAffineTransformMakeScale(0.988, 0.988) : CGAffineTransformIdentity;
    };
    if (!animated || UIAccessibilityIsReduceMotionEnabled()) {
        changes();
        return;
    }
    [UIView animateWithDuration:highlighted ? 0.09 : 0.18
                          delay:0.0
         usingSpringWithDamping:0.92
          initialSpringVelocity:0.20
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:changes
                     completion:nil];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.iconView.image = nil;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.highlightOverlayView.alpha = 0.0;
    self.surfaceView.transform = CGAffineTransformIdentity;
    self.alpha = 1.0;
    self.transform = CGAffineTransformIdentity;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self update];
    }
}

- (void)formDescriptorCellDidSelectedWithFormController:(XLFormViewController *)controller {
    if (self.rowDescriptor.action.formBlock) {
        self.rowDescriptor.action.formBlock(self.rowDescriptor);
    }
}

@end
