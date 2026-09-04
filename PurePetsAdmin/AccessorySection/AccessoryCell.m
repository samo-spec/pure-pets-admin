//
//  AccessoryCell.m
//  PurePetsAdmin
//
//  Created by Admin on 22/08/2025.
//

#import "AccessoryCell.h"
#import "PetAccessory.h"

// Self-contained padded label for badges
@interface PPCellBadgeLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets insets;
@end

@implementation PPCellBadgeLabel
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.insets = UIEdgeInsetsMake(3, 8, 3, 8);
        self.layer.cornerRadius = 6;
        self.clipsToBounds = YES;
        self.font = [UIFont fontWithName:@"Beiruti-Medium" size:11] ?: [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    }
    return self;
}
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.insets)];
}
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width += self.insets.left + self.insets.right;
    size.height += self.insets.top + self.insets.bottom;
    return size;
}
@end

@interface AccessoryCell ()

@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIStackView *badgeStackView;
@property (nonatomic, strong) PPCellBadgeLabel *kindBadge;
@property (nonatomic, strong) PPCellBadgeLabel *speciesBadge;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIStackView *priceStackView;
@property (nonatomic, strong) UILabel *finalPriceLabel;
@property (nonatomic, strong) UILabel *originalPriceLabel;

@property (nonatomic, strong) UIView *stepperContainer;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UILabel *qtyLabel;

@property (nonatomic, strong, readwrite, nullable) PetAccessory *accessory;

@end

@implementation AccessoryCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _hasAnimated = NO;

        [self setupSubviews];
        [self setupConstraints];
    }
    return self;
}

- (void)setupSubviews {
    // 1. Card Container View
    _cardView = [[UIView alloc] init];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = AppForgroundColr;
    _cardView.layer.cornerRadius = 16.0;
    
    // Premium soft shadow
    _cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    _cardView.layer.shadowOpacity = 0.04;
    _cardView.layer.shadowRadius = 8.0;
    _cardView.layer.shadowOffset = CGSizeMake(0, 4);
    _cardView.layer.masksToBounds = NO;
    [self.contentView addSubview:_cardView];

    // 2. Thumbnail ImageView
    _thumbView = [[UIImageView alloc] init];
    _thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    _thumbView.contentMode = UIViewContentModeScaleAspectFill;
    _thumbView.clipsToBounds = YES;
    _thumbView.layer.cornerRadius = 12.0;
    _thumbView.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.06].CGColor;
    _thumbView.layer.borderWidth = 1.0;
    [_cardView addSubview:_thumbView];

    // 3. Badges Stack
    _badgeStackView = [[UIStackView alloc] init];
    _badgeStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _badgeStackView.axis = UILayoutConstraintAxisHorizontal;
    _badgeStackView.spacing = 6.0;
    _badgeStackView.alignment = UIStackViewAlignmentCenter;
    [_cardView addSubview:_badgeStackView];

    _kindBadge = [[PPCellBadgeLabel alloc] init];
    _kindBadge.textColor = SeconderyTextClr;
    _kindBadge.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.08];
    [_badgeStackView addArrangedSubview:_kindBadge];

    _speciesBadge = [[PPCellBadgeLabel alloc] init];
    _speciesBadge.textColor = AppPrimaryClr;
    _speciesBadge.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.08];
    [_badgeStackView addArrangedSubview:_speciesBadge];

    // 4. Title/Name Label
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _nameLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:16] ?: [UIFont boldSystemFontOfSize:16];
    _nameLabel.textColor = PrimaryTextClr;
    _nameLabel.textAlignment = NSTextAlignmentNatural;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_cardView addSubview:_nameLabel];

    // 5. Price Stack
    _priceStackView = [[UIStackView alloc] init];
    _priceStackView.translatesAutoresizingMaskIntoConstraints = NO;
    _priceStackView.axis = UILayoutConstraintAxisHorizontal;
    _priceStackView.spacing = 8.0;
    _priceStackView.alignment = UIStackViewAlignmentCenter;
    [_cardView addSubview:_priceStackView];

    _finalPriceLabel = [[UILabel alloc] init];
    _finalPriceLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:15] ?: [UIFont boldSystemFontOfSize:15];
    _finalPriceLabel.textColor = AppPrimaryClr;
    [_priceStackView addArrangedSubview:_finalPriceLabel];

    _originalPriceLabel = [[UILabel alloc] init];
    _originalPriceLabel.font = [UIFont fontWithName:@"Beiruti-Regular" size:13] ?: [UIFont systemFontOfSize:13];
    _originalPriceLabel.textColor = SeconderyTextClr;
    [_priceStackView addArrangedSubview:_originalPriceLabel];

    // 6. Stepper Container
    _stepperContainer = [[UIView alloc] init];
    _stepperContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _stepperContainer.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.06];
    _stepperContainer.layer.cornerRadius = 10.0;
    _stepperContainer.clipsToBounds = YES;
    [_cardView addSubview:_stepperContainer];

    // Stepper buttons
    _minusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _minusButton.translatesAutoresizingMaskIntoConstraints = NO;
    _minusButton.tintColor = PrimaryTextClr;
    [_minusButton setImage:[UIImage systemImageNamed:@"minus" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    [_minusButton addTarget:self action:@selector(minusTapped) forControlEvents:UIControlEventTouchUpInside];
    [_stepperContainer addSubview:_minusButton];

    _plusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _plusButton.translatesAutoresizingMaskIntoConstraints = NO;
    _plusButton.tintColor = PrimaryTextClr;
    [_plusButton setImage:[UIImage systemImageNamed:@"plus" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    [_plusButton addTarget:self action:@selector(plusTapped) forControlEvents:UIControlEventTouchUpInside];
    [_stepperContainer addSubview:_plusButton];

    _qtyLabel = [[UILabel alloc] init];
    _qtyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _qtyLabel.font = [UIFont fontWithName:@"Beiruti-Bold" size:15] ?: [UIFont boldSystemFontOfSize:15];
    _qtyLabel.textColor = PrimaryTextClr;
    _qtyLabel.textAlignment = NSTextAlignmentCenter;
    [_stepperContainer addSubview:_qtyLabel];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // CardView
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12.0],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],

        // Thumbnail
        [_thumbView.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:12.0],
        [_thumbView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_thumbView.widthAnchor constraintEqualToConstant:76.0],
        [_thumbView.heightAnchor constraintEqualToConstant:76.0],

        // Badge Stack
        [_badgeStackView.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:12.0],
        [_badgeStackView.leadingAnchor constraintEqualToAnchor:_thumbView.trailingAnchor constant:12.0],
        [_badgeStackView.trailingAnchor constraintLessThanOrEqualToAnchor:_stepperContainer.leadingAnchor constant:-8.0],

        // Title/Name Label
        [_nameLabel.topAnchor constraintEqualToAnchor:_badgeStackView.bottomAnchor constant:4.0],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:_thumbView.trailingAnchor constant:12.0],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_stepperContainer.leadingAnchor constant:-8.0],

        // Price Stack
        [_priceStackView.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:4.0],
        [_priceStackView.leadingAnchor constraintEqualToAnchor:_thumbView.trailingAnchor constant:12.0],
        [_priceStackView.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-12.0],

        // Stepper Container
        [_stepperContainer.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-12.0],
        [_stepperContainer.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_stepperContainer.widthAnchor constraintEqualToConstant:104.0],
        [_stepperContainer.heightAnchor constraintEqualToConstant:36.0],

        // Stepper elements
        [_minusButton.leadingAnchor constraintEqualToAnchor:_stepperContainer.leadingAnchor],
        [_minusButton.topAnchor constraintEqualToAnchor:_stepperContainer.topAnchor],
        [_minusButton.bottomAnchor constraintEqualToAnchor:_stepperContainer.bottomAnchor],
        [_minusButton.widthAnchor constraintEqualToConstant:32.0],

        [_plusButton.trailingAnchor constraintEqualToAnchor:_stepperContainer.trailingAnchor],
        [_plusButton.topAnchor constraintEqualToAnchor:_stepperContainer.topAnchor],
        [_plusButton.bottomAnchor constraintEqualToAnchor:_stepperContainer.bottomAnchor],
        [_plusButton.widthAnchor constraintEqualToConstant:32.0],

        [_qtyLabel.leadingAnchor constraintEqualToAnchor:_minusButton.trailingAnchor],
        [_qtyLabel.trailingAnchor constraintEqualToAnchor:_plusButton.leadingAnchor],
        [_qtyLabel.topAnchor constraintEqualToAnchor:_stepperContainer.topAnchor],
        [_qtyLabel.bottomAnchor constraintEqualToAnchor:_stepperContainer.bottomAnchor]
    ]];
}

#pragma mark - Configure

- (void)configureWithAccessory:(PetAccessory *)accessory {
    self.accessory = accessory;

    // Set name
    _nameLabel.text = accessory.name.length > 0 ? accessory.name : @"-";

    // Prices and discount state
    _finalPriceLabel.text = [PetAccessory formatCurrency:accessory.finalPrice];
    
    BOOL hasDiscount = (accessory.discountPercent.floatValue > 0.0 || accessory.discountAmount.floatValue > 0.0);
    if (hasDiscount && accessory.price) {
        NSString *originalText = [PetAccessory formatCurrency:accessory.price];
        NSMutableAttributedString *strikeText = [[NSMutableAttributedString alloc] initWithString:originalText];
        [strikeText addAttribute:NSStrikethroughStyleAttributeName
                           value:@(NSUnderlineStyleSingle)
                           range:NSMakeRange(0, strikeText.length)];
        _originalPriceLabel.attributedText = strikeText;
        _originalPriceLabel.hidden = NO;
    } else {
        _originalPriceLabel.attributedText = nil;
        _originalPriceLabel.hidden = YES;
    }

    // Kind Badge Text
    NSString *kindText = @"";
    switch (accessory.accessKindType) {
        case AccessTypeAccessory:
            kindText = kLang(@"Accessory");
            if (kindText.length == 0 || [kindText isEqualToString:@"Accessory"]) kindText = @"إكسسوار";
            break;
        case AccessTypeFood:
            kindText = kLang(@"Food");
            if (kindText.length == 0 || [kindText isEqualToString:@"Food"]) kindText = @"طعام";
            break;
        case AccessTypeLivePets:
            kindText = kLang(@"Live pets");
            if (kindText.length == 0 || [kindText isEqualToString:@"Live pets"]) kindText = @"أليف";
            break;
        default:
            kindText = @"-";
            break;
    }
    _kindBadge.text = kindText;

    // Species/Category Badge Text
    NSString *speciesName = [MainKindsModel kindNameForID:accessory.petMainCategoryID];
    if (speciesName.length > 0) {
        _speciesBadge.text = speciesName;
        _speciesBadge.hidden = NO;
    } else {
        _speciesBadge.hidden = YES;
    }

    // Quantity state and styling
    NSInteger qty = MAX(0, accessory.quantity);
    _qtyLabel.text = @(qty).stringValue;

    if (qty == 0) {
        _qtyLabel.textColor = [UIColor ppError];
        _stepperContainer.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.06];
    } else if (qty <= 5) {
        _qtyLabel.textColor = [UIColor ppWarning];
        _stepperContainer.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.06];
    } else {
        _qtyLabel.textColor = PrimaryTextClr;
        _stepperContainer.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.06];
    }

    // Set Image
    if (accessory.imageURLsArray.count > 0) {
        NSString *url = accessory.imageURLsArray.firstObject;
        [_thumbView setImageFromUrl:[NSURL URLWithString:url].absoluteString placeholderImage:@"placeholder" Blr:YES Shimmering:YES completion:nil];
    } else {
        _thumbView.image = [UIImage imageNamed:@"placeholder"];
    }
}

#pragma mark - Actions

- (void)minusTapped {
    // Subtle button compress feedback
    [self animateButtonPress:self.minusButton];
    if ([self.delegate respondsToSelector:@selector(accessoryCell:didTapAdjustQuantityBy:)]) {
        [self.delegate accessoryCell:self didTapAdjustQuantityBy:-1];
    }
}

- (void)plusTapped {
    [self animateButtonPress:self.plusButton];
    if ([self.delegate respondsToSelector:@selector(accessoryCell:didTapAdjustQuantityBy:)]) {
        [self.delegate accessoryCell:self didTapAdjustQuantityBy:1];
    }
}

- (void)animateButtonPress:(UIView *)view {
    view.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}

#pragma mark - Highlight / Touch Scale Animation

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (highlighted) {
            self.cardView.transform = CGAffineTransformMakeScale(0.97, 0.97);
            self.cardView.backgroundColor = [AppForgroundColr colorWithAlphaComponent:0.8];
        } else {
            self.cardView.transform = CGAffineTransformIdentity;
            self.cardView.backgroundColor = AppForgroundColr;
        }
    } completion:nil];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _thumbView.image = nil;
    _hasAnimated = NO;
    _accessory = nil;
}

@end
