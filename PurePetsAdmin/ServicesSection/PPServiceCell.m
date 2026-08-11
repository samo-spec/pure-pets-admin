//
//  PPServiceCell.m
//  PurePetsAdmin
//

#import "PPServiceCell.h"
#import "PPServiceModel.h"

static CGFloat const kPPServiceCellCardRadius = 22.0;
static CGFloat const kPPServiceCellImageSize = 58.0;
static CGFloat const kPPServiceCellHorizontalInset = 16.0;
static CGFloat const kPPServiceCellVerticalInset = 14.0;

@interface PPServiceCell ()
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *imageRingView;
@property (nonatomic, strong) UIImageView *serviceImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *priceLabel;
@property (nonatomic, strong) UIStackView *badgeStack;
@property (nonatomic, strong) PPPaddingLabel *statusBadge;
@property (nonatomic, strong) PPPaddingLabel *verificationBadge;
@property (nonatomic, strong) PPPaddingLabel *subscriptionBadge;
@property (nonatomic, strong) UIImageView *chevronView;
@end
 
@implementation PPServiceCell

+ (NSString *)reuseID {
    return @"PPServiceCell";
}

+ (CGFloat)preferredHeight {
    return 118.0;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self buildUI];
    }
    return self;
}

#pragma mark - UI

- (void)buildUI {
    self.cardView = [UIView new];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = AppForgroundColr;
    self.cardView.layer.cornerRadius = kPPServiceCellCardRadius;
    self.cardView.layer.cornerCurve = kCACornerCurveContinuous;
    self.cardView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.cardView.layer.shadowOpacity = 0.06;
    self.cardView.layer.shadowRadius = 14.0;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 6);
    [self.contentView addSubview:self.cardView];

    self.imageRingView = [UIView new];
    self.imageRingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageRingView.backgroundColor = UIColor.clearColor;
    self.imageRingView.layer.cornerRadius = (kPPServiceCellImageSize + 8.0) / 2.0;
    self.imageRingView.layer.borderWidth = 2.0;
    [self.cardView addSubview:self.imageRingView];

    self.serviceImageView = [UIImageView new];
    self.serviceImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.serviceImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.serviceImageView.layer.cornerRadius = kPPServiceCellImageSize / 2.0;
    self.serviceImageView.clipsToBounds = YES;
    self.serviceImageView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.08];
    [self.cardView addSubview:self.serviceImageView];

    self.titleLabel = [UILabel new];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [Styling fontBold:16];
    self.titleLabel.textColor = PrimaryTextClr;
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [self.cardView addSubview:self.titleLabel];

    self.priceLabel = [UILabel new];
    self.priceLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.priceLabel.font = [Styling fontBold:13];
    self.priceLabel.textAlignment = Language.isRTL ? NSTextAlignmentLeft : NSTextAlignmentRight;
    self.priceLabel.textColor = AppPrimaryClr;
    self.priceLabel.numberOfLines = 1;
    [self.cardView addSubview:self.priceLabel];

    self.subtitleLabel = [UILabel new];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.font = [Styling fontMedium:12];
    self.subtitleLabel.textColor = SeconderyTextClr;
    self.subtitleLabel.numberOfLines = 2;
    self.subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [self.cardView addSubview:self.subtitleLabel];

    self.statusBadge = [self pp_pillLabel];
    self.verificationBadge = [self pp_pillLabel];
    self.subscriptionBadge = [self pp_pillLabel];
    self.subscriptionBadge.font = [Styling fontMedium:10];

    self.badgeStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.statusBadge,
        self.verificationBadge,
        self.subscriptionBadge
    ]];
    self.badgeStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.badgeStack.axis = UILayoutConstraintAxisHorizontal;
    self.badgeStack.alignment = UIStackViewAlignmentLeading;
    self.badgeStack.spacing = 6.0;
    self.badgeStack.distribution = UIStackViewDistributionFillProportionally;
    [self.cardView addSubview:self.badgeStack];

    self.chevronView = [UIImageView new];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.contentMode = UIViewContentModeScaleAspectFit;
    self.chevronView.image = [UIImage systemImageNamed:(Language.isRTL ? @"chevron.left" : @"chevron.right")];
    self.chevronView.tintColor = [SeconderyTextClr colorWithAlphaComponent:0.45];
    [self.cardView addSubview:self.chevronView];

    CGFloat ringSize = kPPServiceCellImageSize + 8.0;
    CGFloat textLeading = kPPServiceCellHorizontalInset + ringSize + 14.0;

    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

        [self.imageRingView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:kPPServiceCellHorizontalInset],
        [self.imageRingView.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
        [self.imageRingView.widthAnchor constraintEqualToConstant:ringSize],
        [self.imageRingView.heightAnchor constraintEqualToConstant:ringSize],

        [self.serviceImageView.centerXAnchor constraintEqualToAnchor:self.imageRingView.centerXAnchor],
        [self.serviceImageView.centerYAnchor constraintEqualToAnchor:self.imageRingView.centerYAnchor],
        [self.serviceImageView.widthAnchor constraintEqualToConstant:kPPServiceCellImageSize],
        [self.serviceImageView.heightAnchor constraintEqualToConstant:kPPServiceCellImageSize],

        [self.chevronView.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-kPPServiceCellHorizontalInset],
        [self.chevronView.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
        [self.chevronView.widthAnchor constraintEqualToConstant:12],
        [self.chevronView.heightAnchor constraintEqualToConstant:18],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:kPPServiceCellVerticalInset],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:textLeading],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.priceLabel.leadingAnchor constant:-8],

        [self.priceLabel.firstBaselineAnchor constraintEqualToAnchor:self.titleLabel.firstBaselineAnchor],
        [self.priceLabel.trailingAnchor constraintEqualToAnchor:self.chevronView.leadingAnchor constant:-8],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:6],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.priceLabel.trailingAnchor],

        [self.badgeStack.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:10],
        [self.badgeStack.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.badgeStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.priceLabel.trailingAnchor],
        [self.badgeStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.cardView.bottomAnchor constant:-kPPServiceCellVerticalInset],
    ]];
}

- (UILabel *)pp_pillLabel {
    PPPaddingLabel *label = [PPPaddingLabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [Styling fontBold:10];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 1;
    label.layer.cornerRadius = 10.0;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.clipsToBounds = YES;
    label.textInsets = UIEdgeInsetsMake(6, 3, 6, 3);
    return label;
}

#pragma mark - Configure

- (void)configureWithService:(PPServiceModel *)service {
    self.titleLabel.text = service.title.length > 0 ? service.title : @"—";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *typeName = [service localizedTypeName];
    if (typeName.length > 0) {
        [parts addObject:typeName];
    }
    if (service.category.length > 0) {
        [parts addObject:service.category];
    } else if (service.categoryID.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"%@ %@", kLang(@"Service_Field_CategoryID"), service.categoryID]];
    }
    if (service.serviceOwnerID.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"%@ %@", kLang(@"Service_Field_OwnerID"), service.serviceOwnerID]];
    }
    self.subtitleLabel.text = parts.count > 0 ? [parts componentsJoinedByString:@"  ·  "] : service.serviceDescriptionText;

    self.priceLabel.text = [NSString stringWithFormat:@"%.2f %@", service.price, kLang(@"QAR")];
    self.statusBadge.text = [NSString stringWithFormat:@"  %@  ", [service localizedPrimaryStatusTitle]];
    self.verificationBadge.text = [NSString stringWithFormat:@"  %@  ", [service localizedVerificationTitle]];
    self.subscriptionBadge.text = [NSString stringWithFormat:@"  %@  ", [service localizedSubscriptionSummary]];

    UIColor *statusColor = [self pp_statusColorForService:service];
    self.statusBadge.backgroundColor = [statusColor colorWithAlphaComponent:0.16];
    self.statusBadge.textColor = statusColor;
    self.imageRingView.layer.borderColor = [statusColor colorWithAlphaComponent:0.36].CGColor;

    UIColor *verificationColor = [self pp_verificationColorForService:service];
    self.verificationBadge.backgroundColor = [verificationColor colorWithAlphaComponent:0.16];
    self.verificationBadge.textColor = verificationColor;

    self.subscriptionBadge.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.12];
    self.subscriptionBadge.textColor = AppPrimaryClr;

    self.cardView.alpha = service.isDeleted ? 0.68 : 1.0;

    if (service.imageURL.length > 0) {
        [self.serviceImageView setImageFromUrl:service.imageURL
                              placeholderImage:@"placeholder"
                                           Blr:YES
                                    Shimmering:YES
                                    completion:nil];
    } else {
        self.serviceImageView.image = [UIImage systemImageNamed:@"sparkles.rectangle.stack.fill"];
        self.serviceImageView.tintColor = AppPrimaryClr;
        self.serviceImageView.contentMode = UIViewContentModeCenter;
    }
}

- (UIColor *)pp_statusColorForService:(PPServiceModel *)service {
    if (service.isDeleted) {
        return [UIColor ppTextSecondary];
    }
    if (service.isBlocked) {
        return [UIColor ppError];
    }
    if (service.isDisabled) {
        return [UIColor ppWarning];
    }
    return [UIColor ppSuccess];
}

- (UIColor *)pp_verificationColorForService:(PPServiceModel *)service {
    NSString *normalized = [[PPSafeString(service.verificationStatus) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([normalized isEqualToString:@"verified"]) {
        return [UIColor ppSuccess];
    }
    if ([normalized isEqualToString:@"rejected"] || [normalized isEqualToString:@"blocked"]) {
        return [UIColor ppError];
    }
    if ([normalized isEqualToString:@"pending"] ||
        [normalized isEqualToString:@"pending_review"] ||
        [normalized isEqualToString:@"verification_pending"]) {
        return [UIColor ppWarning];
    }
    return [UIColor ppTextSecondary];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.serviceImageView.image = nil;
    self.serviceImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.priceLabel.text = nil;
    self.statusBadge.text = nil;
    self.verificationBadge.text = nil;
    self.subscriptionBadge.text = nil;
    self.cardView.alpha = 1.0;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CGFloat scale = highlighted ? 0.975 : 1.0;
    [UIView animateWithDuration:0.20 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.transform = CGAffineTransformMakeScale(scale, scale);
    } completion:nil];
}

@end
