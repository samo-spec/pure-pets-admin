//
//  PPVetCell.m
//  PurePetsAdmin
//

#import "PPVetCell.h"
#import "PPVetModel.h"
#import "UIImageView+WebCache.h"

static CGFloat const kCellCardRadius  = 20.0;
static CGFloat const kCellLogoSize    = 52.0;
static CGFloat const kCellHPad        = 16.0;
static CGFloat const kCellVPad        = 14.0;
static CGFloat const kCellBadgeH      = 20.0;
static CGFloat const kCellBadgeRadius = 10.0;
static CGFloat const kCellRingWidth   = 2.5;

@interface PPVetCell ()
@property (nonatomic, strong, readwrite) UIImageView *logoView;
@property (nonatomic, strong, readwrite) UILabel *titleLabel;
@property (nonatomic, strong, readwrite) UILabel *subtitleLabel;
@property (nonatomic, strong, readwrite) UILabel *statusBadge;
@property (nonatomic, strong, readwrite) UILabel *subscriptionLabel;
@property (nonatomic, strong, readwrite) UILabel *costLabel;
@property (nonatomic, strong, readwrite) UIView *cardView;
@property (nonatomic, strong) UIView *avatarRing;
@property (nonatomic, strong) UIView *onlineDot;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation PPVetCell

+ (NSString *)reuseID { return @"PPVetCell"; }

+ (CGFloat)preferredHeight { return 102.0; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        [self buildUI];
    }
    return self;
}

#pragma mark - Build UI

- (void)buildUI {
    // ── Card ──
    _cardView = [UIView new];
    _cardView.translatesAutoresizingMaskIntoConstraints = NO;
    _cardView.backgroundColor = AppForgroundColr;
    _cardView.layer.cornerRadius = kCellCardRadius;
    _cardView.layer.cornerCurve = kCACornerCurveContinuous;
    _cardView.layer.shadowColor = UIColor.blackColor.CGColor;
    _cardView.layer.shadowOpacity = 0.05;
    _cardView.layer.shadowRadius = 12;
    _cardView.layer.shadowOffset = CGSizeMake(0, 4);
    [self.contentView addSubview:_cardView];

    // ── Avatar ring (accent ring around logo when active) ──
    _avatarRing = [UIView new];
    _avatarRing.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat ringSize = kCellLogoSize + kCellRingWidth * 2;
    _avatarRing.layer.cornerRadius = ringSize / 2.0;
    _avatarRing.layer.borderWidth = kCellRingWidth;
    _avatarRing.layer.borderColor = AppPrimaryClr.CGColor;
    _avatarRing.backgroundColor = UIColor.clearColor;
    [_cardView addSubview:_avatarRing];

    // ── Logo ──
    _logoView = [UIImageView new];
    _logoView.translatesAutoresizingMaskIntoConstraints = NO;
    _logoView.contentMode = UIViewContentModeScaleAspectFill;
    _logoView.clipsToBounds = YES;
    _logoView.layer.cornerRadius = kCellLogoSize / 2.0;
    _logoView.backgroundColor = [AppPrimaryClr colorWithAlphaComponent:0.06];
    [_cardView addSubview:_logoView];

    // ── Online dot indicator ──
    _onlineDot = [UIView new];
    _onlineDot.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat dotSize = 12.0;
    _onlineDot.layer.cornerRadius = dotSize / 2.0;
    _onlineDot.layer.borderWidth = 2.0;
    _onlineDot.layer.borderColor = AppForgroundColr.CGColor;
    [_cardView addSubview:_onlineDot];

    // ── Title ──
    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [Styling fontBold:16];
    _titleLabel.textColor = PrimaryTextClr;
    _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_cardView addSubview:_titleLabel];

    // ── Subtitle (type + phone) ──
    _subtitleLabel = [UILabel new];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.font = [Styling fontMedium:12];
    _subtitleLabel.textColor = SeconderyTextClr;
    _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
    _subtitleLabel.numberOfLines = 1;
    [_cardView addSubview:_subtitleLabel];

    // ── Tags row: status badge + subscription pill + cost ──
    _statusBadge = [self _pillLabel];
    [_cardView addSubview:_statusBadge];

    _subscriptionLabel = [self _pillLabel];
    _subscriptionLabel.font = [Styling fontMedium:10];
    _subscriptionLabel.layer.borderWidth = 1.0;
    _subscriptionLabel.backgroundColor = UIColor.clearColor;
    [_cardView addSubview:_subscriptionLabel];

    _costLabel = [UILabel new];
    _costLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _costLabel.font = [Styling fontBold:12];
    _costLabel.textColor = PrimaryTextClr;
    _costLabel.textAlignment = Language.isRTL ? NSTextAlignmentLeft : NSTextAlignmentRight;
    [_cardView addSubview:_costLabel];

    // ── Chevron ──
    _chevronView = [UIImageView new];
    _chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    _chevronView.image = [UIImage systemImageNamed:Language.isRTL ? @"chevron.left" : @"chevron.right"];
    _chevronView.tintColor = [SeconderyTextClr colorWithAlphaComponent:0.4];
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    [_cardView addSubview:_chevronView];

    // ── Layout ──
    CGFloat textLeading = kCellHPad + kCellRingWidth * 2 + kCellLogoSize + 14;
    CGFloat dotSz = 12.0;

    [NSLayoutConstraint activateConstraints:@[
        // Card
        [_cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
        [_cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],

        // Avatar ring
        [_avatarRing.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:kCellHPad],
        [_avatarRing.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_avatarRing.widthAnchor constraintEqualToConstant:ringSize],
        [_avatarRing.heightAnchor constraintEqualToConstant:ringSize],

        // Logo (inside ring)
        [_logoView.centerXAnchor constraintEqualToAnchor:_avatarRing.centerXAnchor],
        [_logoView.centerYAnchor constraintEqualToAnchor:_avatarRing.centerYAnchor],
        [_logoView.widthAnchor constraintEqualToConstant:kCellLogoSize],
        [_logoView.heightAnchor constraintEqualToConstant:kCellLogoSize],

        // Online dot (bottom-trailing of avatar)
        [_onlineDot.bottomAnchor constraintEqualToAnchor:_avatarRing.bottomAnchor constant:-1],
        [_onlineDot.trailingAnchor constraintEqualToAnchor:_avatarRing.trailingAnchor constant:-1],
        [_onlineDot.widthAnchor constraintEqualToConstant:dotSz],
        [_onlineDot.heightAnchor constraintEqualToConstant:dotSz],

        // Title
        [_titleLabel.topAnchor constraintEqualToAnchor:_cardView.topAnchor constant:kCellVPad],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_cardView.leadingAnchor constant:textLeading],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-6],

        // Subtitle
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:3],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],

        // Status badge
        [_statusBadge.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:7],
        [_statusBadge.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_statusBadge.heightAnchor constraintEqualToConstant:kCellBadgeH],

        // Subscription pill
        [_subscriptionLabel.centerYAnchor constraintEqualToAnchor:_statusBadge.centerYAnchor],
        [_subscriptionLabel.leadingAnchor constraintEqualToAnchor:_statusBadge.trailingAnchor constant:6],
        [_subscriptionLabel.heightAnchor constraintEqualToConstant:kCellBadgeH],

        // Cost (right-aligned)
        [_costLabel.centerYAnchor constraintEqualToAnchor:_statusBadge.centerYAnchor],
        [_costLabel.trailingAnchor constraintEqualToAnchor:_chevronView.leadingAnchor constant:-6],
        [_costLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_subscriptionLabel.trailingAnchor constant:6],

        // Bottom pin
        [_statusBadge.bottomAnchor constraintLessThanOrEqualToAnchor:_cardView.bottomAnchor constant:-kCellVPad],

        // Chevron
        [_chevronView.trailingAnchor constraintEqualToAnchor:_cardView.trailingAnchor constant:-kCellHPad],
        [_chevronView.centerYAnchor constraintEqualToAnchor:_cardView.centerYAnchor],
        [_chevronView.widthAnchor constraintEqualToConstant:12],
        [_chevronView.heightAnchor constraintEqualToConstant:16],
    ]];
}

- (UILabel *)_pillLabel {
    UILabel *lbl = [UILabel new];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.font = [Styling fontBold:10];
    lbl.textColor = UIColor.whiteColor;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.layer.cornerRadius = kCellBadgeRadius;
    lbl.clipsToBounds = YES;
    return lbl;
}

#pragma mark - Configure

- (void)configureWithVet:(PPVetModel *)vet {
    // ── Title ──
    self.titleLabel.text = vet.title.length ? vet.title : @"—";

    // ── Subtitle ──
    NSMutableArray *parts = [NSMutableArray array];
    NSString *typeName = [vet localizedTypeName];
    if (typeName.length) [parts addObject:typeName];
    if (vet.phone.length) [parts addObject:vet.phone];
    self.subtitleLabel.text = [parts componentsJoinedByString:@"  ·  "];

    // ── Status badge ──
    BOOL disabled = vet.isDisabled;
    self.statusBadge.text = [NSString stringWithFormat:@"  %@  ", disabled ? kLang(@"Vet_Status_Disabled") : kLang(@"Vet_Status_Active")];
    self.statusBadge.backgroundColor = disabled ? [UIColor.systemRedColor colorWithAlphaComponent:0.85] : [UIColor.systemGreenColor colorWithAlphaComponent:0.85];

    // ── Online dot ──
    self.onlineDot.backgroundColor = disabled ? UIColor.systemRedColor : UIColor.systemGreenColor;

    // ── Avatar ring ──
    self.avatarRing.layer.borderColor = disabled ? [SeconderyTextClr colorWithAlphaComponent:0.15].CGColor : AppPrimaryClr.CGColor;
    self.avatarRing.alpha = disabled ? 0.5 : 1.0;

    // ── Subscription pill ──
    NSString *tierName = [vet localizedSubscriptionTierName];
    BOOL expired = [vet isSubscriptionExpired];
    self.subscriptionLabel.text = [NSString stringWithFormat:@"  %@  ", tierName];
    if (expired) {
        self.subscriptionLabel.textColor = UIColor.systemRedColor;
        self.subscriptionLabel.layer.borderColor = UIColor.systemRedColor.CGColor;
    } else {
        self.subscriptionLabel.textColor = AppPrimaryClr;
        self.subscriptionLabel.layer.borderColor = [AppPrimaryClr colorWithAlphaComponent:0.3].CGColor;
    }

    // ── Cost ──
    if (vet.vetCost > 0) {
        self.costLabel.text = [NSString stringWithFormat:@"%.0f %@", vet.vetCost, kLang(@"QAR")];
        self.costLabel.hidden = NO;
    } else {
        self.costLabel.hidden = YES;
    }

    // ── Disabled dimming ──
    self.cardView.alpha = disabled ? 0.7 : 1.0;

    // ── Logo ──
    if (vet.logoURL.length > 0) {
        [self.logoView setImageFromUrl:vet.logoURL
                      placeholderImage:@"veterinary"
                                   Blr:YES
                            Shimmering:YES
                            completion:nil];
    } else {
        self.logoView.image = [UIImage systemImageNamed:@"stethoscope.circle.fill"];
        self.logoView.tintColor = AppPrimaryClr;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.logoView.image = nil;
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.statusBadge.text = nil;
    self.subscriptionLabel.text = nil;
    self.costLabel.text = nil;
    self.costLabel.hidden = NO;
    self.cardView.alpha = 1.0;
    self.avatarRing.alpha = 1.0;
}

#pragma mark - Selection feedback

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    CGFloat scale = highlighted ? 0.97 : 1.0;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.cardView.transform = CGAffineTransformMakeScale(scale, scale);
    } completion:nil];
}

@end
