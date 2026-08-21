#import "PPPaymentManagementRecordCell.h"

#import "Language.h"
#import "Styling.h"

static NSString *PPPaymentManagementRecordCellTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static UIFont *PPPaymentManagementScaledFont(UIFont *baseFont, UIFontTextStyle textStyle)
{
    if (!baseFont) return [UIFont preferredFontForTextStyle:textStyle];
    return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
}

@implementation PPPaymentManagementRecordCell {
    UIView *_surfaceView;
    UILabel *_orderLabel;
    UILabel *_amountLabel;
    UILabel *_customerLabel;
    UILabel *_subtitleLabel;
    UIView *_statusContainer;
    UIImageView *_statusIconView;
    UILabel *_statusLabel;
    UIButton *_actionButton;
    UIStackView *_topRow;
    UIStackView *_bottomRow;
    NSLayoutConstraint *_actionMinimumWidthConstraint;
    NSLayoutConstraint *_actionMaximumWidthConstraint;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.layoutMargins = UIEdgeInsetsZero;
    self.separatorInset = UIEdgeInsetsZero;

    _surfaceView = [UIView new];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.backgroundColor = [UIColor ppElevatedSurface];
    PPApplyContinuousCorners(_surfaceView, PPCornerCard);
    _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _surfaceView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    [self.contentView addSubview:_surfaceView];

    _orderLabel = [UILabel new];
    _orderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _orderLabel.font = PPPaymentManagementScaledFont([Styling fontBold:16], UIFontTextStyleHeadline);
    _orderLabel.adjustsFontForContentSizeCategory = YES;
    _orderLabel.textColor = [UIColor ppTextPrimary];
    _orderLabel.numberOfLines = 0;

    _amountLabel = [UILabel new];
    _amountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _amountLabel.font = PPPaymentManagementScaledFont([Styling fontBold:16], UIFontTextStyleHeadline);
    _amountLabel.adjustsFontForContentSizeCategory = YES;
    _amountLabel.textColor = [UIColor ppTextPrimary];
    _amountLabel.numberOfLines = 0;
    [_amountLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _customerLabel = [UILabel new];
    _customerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _customerLabel.font = PPPaymentManagementScaledFont([Styling fontRegular:13], UIFontTextStyleSubheadline);
    _customerLabel.adjustsFontForContentSizeCategory = YES;
    _customerLabel.textColor = [UIColor ppTextSecondary];
    _customerLabel.numberOfLines = 0;

    _statusContainer = [UIView new];
    _statusContainer.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_statusContainer, PPCornerSmall);

    _statusIconView = [UIImageView new];
    _statusIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _statusIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_statusContainer addSubview:_statusIconView];

    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = PPPaymentManagementScaledFont([Styling fontBold:12], UIFontTextStyleCaption1);
    _statusLabel.adjustsFontForContentSizeCategory = YES;
    _statusLabel.numberOfLines = 0;
    [_statusContainer addSubview:_statusLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = PPPaymentManagementScaledFont([Styling fontRegular:12], UIFontTextStyleFootnote);
    _subtitleLabel.adjustsFontForContentSizeCategory = YES;
    _subtitleLabel.textColor = [UIColor ppTextTertiary];
    _subtitleLabel.numberOfLines = 0;

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    PPApplyContinuousCorners(_actionButton, PPCorner16);
    _actionButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _actionButton.titleLabel.font = PPPaymentManagementScaledFont([Styling fontBold:13], UIFontTextStyleCallout);
    _actionButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    _actionButton.titleLabel.numberOfLines = 0;
    _actionButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceMD, PPSpaceBase, PPSpaceMD, PPSpaceBase);
    [_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _topRow = [[UIStackView alloc] initWithArrangedSubviews:@[_orderLabel, _amountLabel]];
    _topRow.translatesAutoresizingMaskIntoConstraints = NO;
    _topRow.axis = UILayoutConstraintAxisHorizontal;
    _topRow.alignment = UIStackViewAlignmentFirstBaseline;
    _topRow.spacing = PPSpaceMD;

    UIStackView *metaStack = [[UIStackView alloc] initWithArrangedSubviews:@[_statusContainer, _subtitleLabel]];
    metaStack.translatesAutoresizingMaskIntoConstraints = NO;
    metaStack.axis = UILayoutConstraintAxisVertical;
    metaStack.alignment = UIStackViewAlignmentLeading;
    metaStack.spacing = PPSpaceSM;
    [metaStack setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    _bottomRow = [[UIStackView alloc] initWithArrangedSubviews:@[metaStack, _actionButton]];
    _bottomRow.translatesAutoresizingMaskIntoConstraints = NO;
    _bottomRow.axis = UILayoutConstraintAxisHorizontal;
    _bottomRow.alignment = UIStackViewAlignmentBottom;
    _bottomRow.spacing = PPSpaceMD;

    UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[_topRow, _customerLabel, _bottomRow]];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = PPSpaceMD;
    [_surfaceView addSubview:contentStack];

    _actionMinimumWidthConstraint = [_actionButton.widthAnchor constraintGreaterThanOrEqualToConstant:112.0];
    _actionMaximumWidthConstraint = [_actionButton.widthAnchor constraintLessThanOrEqualToConstant:152.0];

    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:PPSpaceSM],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-PPSpaceSM],

        [contentStack.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:PPSpaceBase],
        [contentStack.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:PPSpaceBase],
        [contentStack.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-PPSpaceBase],
        [contentStack.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-PPSpaceBase],

        [_statusIconView.leadingAnchor constraintEqualToAnchor:_statusContainer.leadingAnchor constant:PPSpaceSM],
        [_statusIconView.centerYAnchor constraintEqualToAnchor:_statusContainer.centerYAnchor],
        [_statusIconView.widthAnchor constraintEqualToConstant:16.0],
        [_statusIconView.heightAnchor constraintEqualToConstant:16.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_statusIconView.trailingAnchor constant:PPSpaceMDHalf],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_statusContainer.trailingAnchor constant:-PPSpaceSM],
        [_statusLabel.topAnchor constraintEqualToAnchor:_statusContainer.topAnchor constant:PPSpaceMDHalf],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:_statusContainer.bottomAnchor constant:-PPSpaceMDHalf],

        [_actionButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin],
        _actionMinimumWidthConstraint,
        _actionMaximumWidthConstraint,
    ]];

    [self pp_refreshAdaptiveLayout];
    return self;
}

- (UIButton *)actionButton
{
    return _actionButton;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self pp_refreshAdaptiveLayout];
}

- (void)pp_refreshAdaptiveLayout
{
    BOOL accessibilitySize = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    _topRow.axis = accessibilitySize ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    _topRow.alignment = accessibilitySize ? UIStackViewAlignmentFill : UIStackViewAlignmentFirstBaseline;
    _bottomRow.axis = accessibilitySize ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    _bottomRow.alignment = accessibilitySize ? UIStackViewAlignmentFill : UIStackViewAlignmentBottom;
    _actionMinimumWidthConstraint.active = !accessibilitySize;
    _actionMaximumWidthConstraint.active = !accessibilitySize;
    _amountLabel.textAlignment = accessibilitySize
        ? [Language alignmentForCurrentLanguage]
        : ([Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight);
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    [_actionButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    _surfaceView.transform = CGAffineTransformIdentity;
    _surfaceView.alpha = 1.0;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    [super setHighlighted:highlighted animated:animated];
    CGFloat targetAlpha = highlighted ? 0.78 : 1.0;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        _surfaceView.alpha = targetAlpha;
        _surfaceView.transform = CGAffineTransformIdentity;
        return;
    }

    CGAffineTransform targetTransform = highlighted
        ? CGAffineTransformMakeScale(PPTapCardScaleDown, PPTapCardScaleDown)
        : CGAffineTransformIdentity;
    [UIView animateWithDuration:(animated ? PPAnimDurationFast : 0.0)
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self->_surfaceView.alpha = targetAlpha;
        self->_surfaceView.transform = targetTransform;
    } completion:nil];
}

- (void)configureWithOrderTitle:(NSString *)orderTitle
                     amountText:(NSString *)amountText
                   customerText:(NSString *)customerText
                   subtitleText:(NSString *)subtitleText
                    statusTitle:(NSString *)statusTitle
                    statusColor:(UIColor *)statusColor
                   statusSymbol:(NSString *)statusSymbol
                    actionTitle:(NSString *)actionTitle
                     actionTint:(UIColor *)actionTint
                prominentAction:(BOOL)prominentAction
{
    UISemanticContentAttribute semantic = [Language semanticAttributeForCurrentLanguage];
    NSTextAlignment alignment = [Language alignmentForCurrentLanguage];
    self.semanticContentAttribute = semantic;
    self.contentView.semanticContentAttribute = semantic;
    _surfaceView.semanticContentAttribute = semantic;
    _orderLabel.textAlignment = alignment;
    _customerLabel.textAlignment = alignment;
    _subtitleLabel.textAlignment = alignment;
    _statusLabel.textAlignment = alignment;

    UIColor *resolvedStatusColor = statusColor ?: [UIColor ppPrimary];
    UIColor *resolvedActionTint = actionTint ?: [UIColor ppPrimary];

    _orderLabel.text = orderTitle;
    _amountLabel.text = amountText;
    _customerLabel.text = customerText;
    _subtitleLabel.text = subtitleText;
    _subtitleLabel.hidden = PPPaymentManagementRecordCellTrimmedString(subtitleText).length == 0;

    _statusLabel.text = statusTitle ?: @"--";
    _statusLabel.textColor = resolvedStatusColor;
    _statusContainer.backgroundColor = [resolvedStatusColor colorWithAlphaComponent:0.10];
    _statusContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _statusContainer.layer.borderColor = [resolvedStatusColor colorWithAlphaComponent:0.20].CGColor;
    _statusIconView.tintColor = resolvedStatusColor;
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                             weight:UIImageSymbolWeightSemibold];
    _statusIconView.image = [[UIImage systemImageNamed:statusSymbol ?: @"shippingbox.circle.fill"]
                             imageByApplyingSymbolConfiguration:iconConfig];

    [_actionButton setTitle:actionTitle forState:UIControlStateNormal];
    if (prominentAction) {
        _actionButton.backgroundColor = resolvedActionTint;
        _actionButton.layer.borderColor = UIColor.clearColor.CGColor;
        [_actionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        _actionButton.backgroundColor = [UIColor ppSurface];
        _actionButton.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        [_actionButton setTitleColor:[UIColor ppTextPrimary] forState:UIControlStateNormal];
    }

    [self pp_refreshAdaptiveLayout];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [@[orderTitle ?: @"", amountText ?: @"", customerText ?: @"", statusTitle ?: @""] componentsJoinedByString:@", "];
    self.accessibilityHint = actionTitle ?: @"";
    self.accessibilityTraits = UIAccessibilityTraitButton;
}

@end
