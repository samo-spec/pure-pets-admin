#import "PPPaymentManagementRecordCell.h"

#import "Language.h"
#import "PPButtonHelper.h"
#import "Styling.h"

static NSString *PPPaymentManagementRecordCellTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@implementation PPPaymentManagementRecordCell {
    UIView *_surfaceView;
    UIView *_surfaceContentView;
    CAGradientLayer *_gradientLayer;
    UIView *_haloView;
    UILabel *_orderLabel;
    UILabel *_amountLabel;
    UILabel *_customerLabel;
    UILabel *_subtitleLabel;
    UIView *_statusIconWrapView;
    UIImageView *_statusIconView;
    UILabel *_statusLabel;
    UIButton *_actionButton;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.clipsToBounds = NO;
    self.contentView.clipsToBounds = NO;
    self.layoutMargins = UIEdgeInsetsZero;
    self.separatorInset = UIEdgeInsetsZero;

    _surfaceView = [UIView new];
    _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceView.backgroundColor = UIColor.clearColor;
    _surfaceView.layer.shadowColor = AppClearClr.CGColor;
    _surfaceView.layer.shadowOpacity = 0.00f;
    _surfaceView.layer.shadowOffset = CGSizeMake(0.0, 00.0);
    _surfaceView.layer.shadowRadius = 0.0f;
    [self.contentView addSubview:_surfaceView];

    _surfaceContentView = [UIView new];
    _surfaceContentView.translatesAutoresizingMaskIntoConstraints = NO;
    _surfaceContentView.backgroundColor = [UIColor ppElevatedSurface];
    _surfaceContentView.layer.cornerRadius = 22.0;
    _surfaceContentView.layer.masksToBounds = YES;
    _surfaceContentView.layer.borderWidth = 1.0;
    _surfaceContentView.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.18].CGColor;
    [_surfaceView addSubview:_surfaceContentView];

    _gradientLayer = [CAGradientLayer layer];
    _gradientLayer.startPoint = CGPointMake(0.0, 0.0);
    _gradientLayer.endPoint = CGPointMake(1.0, 1.0);
    [_surfaceContentView.layer insertSublayer:_gradientLayer atIndex:0];

    _haloView = [UIView new];
    _haloView.translatesAutoresizingMaskIntoConstraints = NO;
    _haloView.userInteractionEnabled = NO;
    _haloView.alpha = 0.10;
    _haloView.layer.cornerRadius = 56.0;
    [_surfaceContentView addSubview:_haloView];

    _orderLabel = [UILabel new];
    _orderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _orderLabel.font = [Styling fontBold:16];
    _orderLabel.textColor = [UIColor ppTextPrimary];
    _orderLabel.numberOfLines = 2;

    _amountLabel = [UILabel new];
    _amountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _amountLabel.font = [Styling fontBold:16];
    _amountLabel.textColor = [UIColor ppTextPrimary];
    _amountLabel.textAlignment = NSTextAlignmentRight;
    _amountLabel.numberOfLines = 2;
    [_amountLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _customerLabel = [UILabel new];
    _customerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _customerLabel.font = [Styling fontRegular:13];
    _customerLabel.textColor = [UIColor ppTextSecondary];
    _customerLabel.numberOfLines = 2;

    _statusIconWrapView = [UIView new];
    _statusIconWrapView.translatesAutoresizingMaskIntoConstraints = NO;
    _statusIconWrapView.layer.cornerRadius = 13.0;
    _statusIconWrapView.layer.masksToBounds = YES;

    _statusIconView = [UIImageView new];
    _statusIconView.translatesAutoresizingMaskIntoConstraints = NO;
    _statusIconView.contentMode = UIViewContentModeScaleAspectFit;
    [_statusIconWrapView addSubview:_statusIconView];

    _statusLabel = [UILabel new];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [Styling fontBold:12];
    _statusLabel.numberOfLines = 1;
    _statusLabel.layer.cornerRadius = 12.0;
    _statusLabel.layer.masksToBounds = YES;
    _statusLabel.layer.borderWidth = 1.0;
    _statusLabel.textAlignment = NSTextAlignmentCenter;

    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [Styling fontRegular:11];
    _subtitleLabel.textColor = [UIColor ppTextTertiary];
    _subtitleLabel.numberOfLines = 2;

    _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    _actionButton.layer.cornerRadius = 16.0;
    _actionButton.layer.masksToBounds = NO;
    _actionButton.layer.borderWidth = 1.0;
    _actionButton.titleLabel.font = [Styling fontBold:12];
    _actionButton.titleLabel.numberOfLines = 2;
    _actionButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    _actionButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _actionButton.titleLabel.minimumScaleFactor = 0.80;
    _actionButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _actionButton.contentEdgeInsets = UIEdgeInsetsMake(10.0, 14.0, 10.0, 14.0);
    _actionButton.layer.shadowColor = AppShadowColor.CGColor;
    _actionButton.layer.shadowOffset = CGSizeMake(0.0, 3.0);
    _actionButton.layer.shadowRadius = 06.0f;
    [_actionButton setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_actionButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [PPButtonHelper attachTapAnimationToButton:_actionButton style:PPButtonAnimationStylePulse];

    UIStackView *topRow = [[UIStackView alloc] initWithArrangedSubviews:@[_orderLabel, _amountLabel]];
    topRow.translatesAutoresizingMaskIntoConstraints = NO;
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.alignment = UIStackViewAlignmentTop;
    topRow.spacing = 10.0;

    UIStackView *statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[_statusIconWrapView, _statusLabel]];
    statusRow.translatesAutoresizingMaskIntoConstraints = NO;
    statusRow.axis = UILayoutConstraintAxisHorizontal;
    statusRow.alignment = UIStackViewAlignmentCenter;
    statusRow.spacing = 8.0;

    UIStackView *metaStack = [[UIStackView alloc] initWithArrangedSubviews:@[statusRow, _subtitleLabel]];
    metaStack.translatesAutoresizingMaskIntoConstraints = NO;
    metaStack.axis = UILayoutConstraintAxisVertical;
    metaStack.alignment = UIStackViewAlignmentLeading;
    metaStack.spacing = 6.0;
    [metaStack setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [metaStack setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *bottomRow = [[UIStackView alloc] initWithArrangedSubviews:@[metaStack, _actionButton]];
    bottomRow.translatesAutoresizingMaskIntoConstraints = NO;
    bottomRow.axis = UILayoutConstraintAxisHorizontal;
    bottomRow.alignment = UIStackViewAlignmentBottom;
    bottomRow.spacing = 12.0;

    UIStackView *contentStack = [[UIStackView alloc] initWithArrangedSubviews:@[topRow, _customerLabel, bottomRow]];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.axis = UILayoutConstraintAxisVertical;
    contentStack.spacing = 10.0;
    [_surfaceContentView addSubview:contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
        [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:0.0],
        [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-0.0],
        [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

        [_surfaceContentView.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor],
        [_surfaceContentView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor],
        [_surfaceContentView.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor],
        [_surfaceContentView.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor],

        [_haloView.widthAnchor constraintEqualToConstant:0.0],
        [_haloView.heightAnchor constraintEqualToConstant:0.0],
        [_haloView.trailingAnchor constraintEqualToAnchor:_surfaceContentView.trailingAnchor constant:28.0],
        [_haloView.topAnchor constraintEqualToAnchor:_surfaceContentView.topAnchor constant:-36.0],

        [contentStack.topAnchor constraintEqualToAnchor:_surfaceContentView.topAnchor constant:16.0],
        [contentStack.leadingAnchor constraintEqualToAnchor:_surfaceContentView.leadingAnchor constant:16.0],
        [contentStack.trailingAnchor constraintEqualToAnchor:_surfaceContentView.trailingAnchor constant:-16.0],
        [contentStack.bottomAnchor constraintEqualToAnchor:_surfaceContentView.bottomAnchor constant:-16.0],

        [_statusIconWrapView.widthAnchor constraintEqualToConstant:26.0],
        [_statusIconWrapView.heightAnchor constraintEqualToConstant:26.0],
        [_statusIconView.centerXAnchor constraintEqualToAnchor:_statusIconWrapView.centerXAnchor],
        [_statusIconView.centerYAnchor constraintEqualToAnchor:_statusIconWrapView.centerYAnchor],
        [_statusIconView.widthAnchor constraintEqualToConstant:14.0],
        [_statusIconView.heightAnchor constraintEqualToConstant:14.0],

        [_actionButton.widthAnchor constraintGreaterThanOrEqualToConstant:108.0],
        [_actionButton.widthAnchor constraintLessThanOrEqualToConstant:132.0],
        [_actionButton.heightAnchor constraintGreaterThanOrEqualToConstant:42.0],

        [_statusLabel.heightAnchor constraintEqualToConstant:26.0],
        [_statusLabel.widthAnchor constraintEqualToConstant:64.0],
    ]];

    return self;
}

- (UIButton *)actionButton
{
    return _actionButton;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    _gradientLayer.frame = _surfaceContentView.bounds;
    _surfaceView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_surfaceView.bounds cornerRadius:22.0].CGPath;
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
    CGFloat targetAlpha = highlighted ? 0.92 : 1.0;
    CGAffineTransform targetTransform = highlighted ? CGAffineTransformMakeScale(0.988, 0.988) : CGAffineTransformIdentity;
    NSTimeInterval duration = animated ? 0.18 : 0.0;
    [UIView animateWithDuration:duration delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
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
    _surfaceContentView.semanticContentAttribute = semantic;
    _orderLabel.textAlignment = alignment;
    _customerLabel.textAlignment = alignment;
    _subtitleLabel.textAlignment = alignment;
    _amountLabel.textAlignment = [Language isRTL] ? NSTextAlignmentLeft : NSTextAlignmentRight;

    UIColor *resolvedStatusColor = statusColor ?: [UIColor ppPrimary];
    UIColor *resolvedActionTint = actionTint ?: [UIColor ppPrimary];

    _surfaceContentView.layer.borderColor = [resolvedStatusColor colorWithAlphaComponent:0.16].CGColor;
    _gradientLayer.colors = @[
        (id)[resolvedStatusColor colorWithAlphaComponent:0.01].CGColor,
        (id)[[UIColor ppElevatedSurface] colorWithAlphaComponent:0.16].CGColor,
        (id)[[UIColor ppSurface] colorWithAlphaComponent:0.24].CGColor
    ];
    _haloView.backgroundColor = resolvedStatusColor;

    _orderLabel.text = orderTitle;
    _amountLabel.text = amountText;
    _customerLabel.text = customerText;
    _subtitleLabel.text = subtitleText;
    _subtitleLabel.hidden = PPPaymentManagementRecordCellTrimmedString(subtitleText).length == 0;

    _statusLabel.text = [NSString stringWithFormat:@" %@ ", statusTitle ?: @"--"];
    _statusLabel.textColor = resolvedStatusColor;
    _statusLabel.backgroundColor = [resolvedStatusColor colorWithAlphaComponent:0.13];
    _statusLabel.layer.borderColor = [resolvedStatusColor colorWithAlphaComponent:0.24].CGColor;

    _statusIconWrapView.backgroundColor = [resolvedStatusColor colorWithAlphaComponent:0.14];
    _statusIconView.tintColor = resolvedStatusColor;
    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                             weight:UIImageSymbolWeightBold
                                                                                              scale:UIImageSymbolScaleSmall];
    _statusIconView.image = [[UIImage systemImageNamed:statusSymbol ?: @"shippingbox.circle.fill"] imageByApplyingSymbolConfiguration:iconConfig];

    [_actionButton setTitle:actionTitle forState:UIControlStateNormal];
    if (prominentAction) {
        _actionButton.backgroundColor = resolvedActionTint;
        _actionButton.layer.borderColor = UIColor.clearColor.CGColor;
        _actionButton.layer.shadowOpacity = 0.16f;
        [_actionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        _actionButton.backgroundColor = [[UIColor ppSurface] colorWithAlphaComponent:0.74];
        _actionButton.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.30].CGColor;
        _actionButton.layer.shadowOpacity = 0.04f;
        [_actionButton setTitleColor:[UIColor ppTextPrimary] forState:UIControlStateNormal];
    }
}

@end
