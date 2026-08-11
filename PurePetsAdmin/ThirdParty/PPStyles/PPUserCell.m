//
//  PPUserCell.m
//

#import "PPUserCell.h"

static NSString *PPUserCellLTRIsolate(NSString *value) {
    NSString *safe = [value isKindOfClass:NSString.class] ? value : @"";
    return safe.length ? [NSString stringWithFormat:@"\u2066%@\u2069", safe] : @"";
}

@interface PPUserCell ()
@property (nonatomic, strong) UIStackView *identityStack;
@property (nonatomic, strong) NSLayoutConstraint *setAdminWidthConstraint;
@end

@implementation PPUserCell

+ (NSString *)reuseIdentifier { return @"PPUserCell"; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier ?: PPUserCell.reuseIdentifier]) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _surfaceView = [[UIView alloc] init];
        _surfaceView.translatesAutoresizingMaskIntoConstraints = NO;
        _surfaceView.backgroundColor = [UIColor ppSurface];
        _surfaceView.layer.cornerRadius = PPCorner16;
        _surfaceView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _surfaceView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
        _surfaceView.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            _surfaceView.layer.cornerCurve = kCACornerCurveContinuous;
        }

        _avatarImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarImageView.layer.cornerRadius = 24.0;
        _avatarImageView.clipsToBounds = YES;
        _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarImageView.tintColor = AppPrimaryClr;
        _avatarImageView.backgroundColor = [UIColor ppSecondarySurface];
        _avatarImageView.isAccessibilityElement = NO;

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:16.0]];
        _titleLabel.textColor = PrimaryTextClr;
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _titleLabel.numberOfLines = 2;
        _titleLabel.adjustsFontForContentSizeCategory = YES;

        _verifiedBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"
                                                                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0
                                                                                                                                        weight:UIImageSymbolWeightSemibold]]];
        _verifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _verifiedBadge.tintColor = [UIColor ppSuccess];
        _verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
        _verifiedBadge.hidden = YES;
        _verifiedBadge.isAccessibilityElement = YES;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontRegular:12.0]];
        _subtitleLabel.textColor = SeconderyTextClr;
        _subtitleLabel.textAlignment = NSTextAlignmentNatural;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

        _statusPill = [[UILabel alloc] init];
        _statusPill.translatesAutoresizingMaskIntoConstraints = NO;
        _statusPill.font = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontMedium:11.0]];
        _statusPill.textAlignment = NSTextAlignmentCenter;
        _statusPill.layer.cornerRadius = 10.0;
        _statusPill.layer.masksToBounds = YES;
        _statusPill.adjustsFontForContentSizeCategory = YES;
        _statusPill.numberOfLines = 2;

        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _actionButton.tintColor = SeconderyTextClr;
        _actionButton.backgroundColor = [UIColor ppElevatedSurface];
        _actionButton.layer.cornerRadius = PPCornerSmall;
        _actionButton.layer.masksToBounds = YES;
        _actionButton.accessibilityTraits = UIAccessibilityTraitButton;
        [_actionButton addTarget:self action:@selector(onTapAction) forControlEvents:UIControlEventTouchUpInside];

        _setAdminButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _setAdminButton.translatesAutoresizingMaskIntoConstraints = NO;
        _setAdminButton.tintColor = SeconderyTextClr;
        _setAdminButton.accessibilityTraits = UIAccessibilityTraitButton;
        [_setAdminButton addTarget:self action:@selector(onTapSetAdmin) forControlEvents:UIControlEventTouchUpInside];
        [_setAdminButton setImage:[UIImage systemImageNamed:@"key"] forState:UIControlStateNormal];
        [PPButtonHelper attachTapAnimationToButton:_setAdminButton style:PPButtonAnimationStyleGlow];

        _identityStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _verifiedBadge]];
        _identityStack.translatesAutoresizingMaskIntoConstraints = NO;
        _identityStack.axis = UILayoutConstraintAxisHorizontal;
        _identityStack.alignment = UIStackViewAlignmentCenter;
        _identityStack.spacing = 4.0;
        _identityStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        [_identityStack setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

        [self.contentView addSubview:_surfaceView];
        [_surfaceView addSubview:_avatarImageView];
        [_surfaceView addSubview:_identityStack];
        [_surfaceView addSubview:_subtitleLabel];
        [_surfaceView addSubview:_statusPill];
        [_surfaceView addSubview:_actionButton];
        [_surfaceView addSubview:_setAdminButton];

        CGFloat pad = 12.0;
        self.setAdminWidthConstraint = [_setAdminButton.widthAnchor constraintEqualToConstant:PPTouchTargetMin];
        [NSLayoutConstraint activateConstraints:@[
            [_surfaceView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3.0],
            [_surfaceView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [_surfaceView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [_surfaceView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-3.0],
            [_surfaceView.heightAnchor constraintGreaterThanOrEqualToConstant:72.0],

            [_avatarImageView.leadingAnchor constraintEqualToAnchor:_surfaceView.leadingAnchor constant:pad],
            [_avatarImageView.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_avatarImageView.widthAnchor constraintEqualToConstant:48.0],
            [_avatarImageView.heightAnchor constraintEqualToConstant:48.0],

            [_actionButton.trailingAnchor constraintEqualToAnchor:_surfaceView.trailingAnchor constant:-pad],
            [_actionButton.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            [_actionButton.widthAnchor constraintEqualToConstant:44.0],
            [_actionButton.heightAnchor constraintEqualToConstant:44.0],

            [_setAdminButton.trailingAnchor constraintEqualToAnchor:_actionButton.leadingAnchor constant:-8.0],
            [_setAdminButton.centerYAnchor constraintEqualToAnchor:_surfaceView.centerYAnchor],
            self.setAdminWidthConstraint,
            [_setAdminButton.heightAnchor constraintEqualToConstant:44.0],

            [_identityStack.leadingAnchor constraintEqualToAnchor:_avatarImageView.trailingAnchor constant:10.0],
            [_identityStack.trailingAnchor constraintLessThanOrEqualToAnchor:_statusPill.leadingAnchor constant:-8.0],
            [_identityStack.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:10.0],
            [_identityStack.heightAnchor constraintGreaterThanOrEqualToConstant:22.0],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_identityStack.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_setAdminButton.leadingAnchor constant:-8.0],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_identityStack.bottomAnchor constant:2.0],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_surfaceView.bottomAnchor constant:-10.0],

            [_statusPill.topAnchor constraintEqualToAnchor:_surfaceView.topAnchor constant:10.0],
            [_statusPill.heightAnchor constraintGreaterThanOrEqualToConstant:24.0],
            [_statusPill.bottomAnchor constraintLessThanOrEqualToAnchor:_surfaceView.bottomAnchor constant:-10.0],
            [_statusPill.widthAnchor constraintGreaterThanOrEqualToConstant:64.0],
            [_statusPill.trailingAnchor constraintEqualToAnchor:_setAdminButton.leadingAnchor constant:-8.0]
        ]];
    }
    return self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        self.surfaceView.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.contentView.alpha = 1.0;
    self.contentView.transform = CGAffineTransformIdentity;
    self.surfaceView.alpha = 1.0;
    self.surfaceView.transform = CGAffineTransformIdentity;
    self.cellUser = nil;
    self.representedUID = nil;
    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.titleLabel.text = nil;
    self.subtitleLabel.text = nil;
    self.statusPill.text = nil;
    self.statusPill.backgroundColor = UIColor.clearColor;
    self.statusPill.accessibilityLabel = nil;
    self.verifiedBadge.hidden = YES;
    self.verifiedBadge.accessibilityLabel = nil;
    self.actionButton.accessibilityLabel = nil;
    self.setAdminButton.accessibilityLabel = nil;
    self.setAdminButton.hidden = NO;
    self.actionButton.hidden = NO;
    self.setAdminWidthConstraint.constant = PPTouchTargetMin;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    if (UIAccessibilityIsReduceMotionEnabled()) {
        self.surfaceView.alpha = highlighted ? 0.84 : 1.0;
        return;
    }

    [UIView animateWithDuration:0.12
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.surfaceView.alpha = highlighted ? 0.84 : 1.0;
    } completion:nil];
}

- (void)configureWithUser:(UserModel *)user indexPath:(NSIndexPath *)indexPath {
    [self configureWithUser:user indexPath:indexPath viewFor:ViewForDefault];
}

- (void)configureWithUser:(UserModel *)user
                 indexPath:(NSIndexPath *)indexPath
                   viewFor:(ViewFor)viewFor {
    self.cellUser = user;
    self.indexPath = indexPath;
    self.representedUID = user.uid;
    self.viewFor = viewFor;
    self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.identityStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self.actionButton setImage:[UIImage systemImageNamed:Language.isRTL ? @"chevron.left" : @"chevron.right"] forState:UIControlStateNormal];

    BOOL customerMode = viewFor == ViewForEditAccount;
    NSString *fallbackIdentity = customerMode ? kLang(@"MissionControl_Customers_Unknown_Identity") : @"—";
    self.titleLabel.text = user.UserName.length ? user.UserName : (user.UserEmail.length ? user.UserEmail : fallbackIdentity);
    self.titleLabel.accessibilityLabel = self.titleLabel.text;
    self.verifiedBadge.hidden = !user.isVerified;
    self.verifiedBadge.accessibilityLabel = customerMode ? kLang(@"MissionControl_Customers_Verified") : kLang(@"Verified_Users");

    NSString *email = ([user.UserEmail isKindOfClass:NSString.class] ? user.UserEmail : @"");
    NSString *mobile = ([user.MobileNo isKindOfClass:NSString.class] ? user.MobileNo : @"");
    NSString *contact = (email.length && mobile.length)
        ? [NSString stringWithFormat:@"%@  •  %@", email, mobile]
        : (email.length ? email : mobile);
    if (contact.length && user.uid.length) {
        self.subtitleLabel.text = [NSString stringWithFormat:@"%@\n%@", contact, user.uid];
    } else {
        self.subtitleLabel.text = contact.length ? contact : user.uid;
    }
    NSMutableArray<NSString *> *identityDetails = [NSMutableArray array];
    if (contact.length) [identityDetails addObject:PPUserCellLTRIsolate(contact)];
    if (user.uid.length) [identityDetails addObject:PPUserCellLTRIsolate(user.uid)];
    self.subtitleLabel.accessibilityLabel = [identityDetails componentsJoinedByString:@", "];

    [self pp_updateStatusPillForUser:user];

    if (viewFor == ViewForAdminToggle) {
        self.setAdminButton.hidden = NO;
        self.actionButton.hidden = YES;
    } else if (viewFor == ViewForEditRoleAndPermissions || viewFor == ViewForEditAccount) {
        self.setAdminButton.hidden = YES;
        self.actionButton.hidden = NO;
    } else if (viewFor == ViewForPicker) {
        self.setAdminButton.hidden = YES;
        self.actionButton.hidden = NO;
    } else {
        self.setAdminButton.hidden = NO;
        self.actionButton.hidden = NO;
    }
    self.setAdminWidthConstraint.constant = self.setAdminButton.hidden ? 0.0 : PPTouchTargetMin;

    if (viewFor == ViewForEditAccount) {
        self.actionButton.accessibilityLabel = [NSString stringWithFormat:kLang(@"MissionControl_Customers_Open_Record_Format"),
                                                 PPUserCellLTRIsolate(self.titleLabel.text)];
    } else if (viewFor == ViewForEditRoleAndPermissions) {
        self.actionButton.accessibilityLabel = kLang(@"EditUsersRolePerms_List_Title");
    } else if (viewFor == ViewForPicker) {
        self.actionButton.accessibilityLabel = kLang(@"Staff_Select_Existing_User");
    } else {
        self.actionButton.accessibilityLabel = kLang(@"UsersSection");
    }
    self.setAdminButton.accessibilityLabel = user.isAdmin
        ? kLang(@"SetPermissions_RevokeAdmin")
        : kLang(@"SetPermissions_MakeAdmin");

    UIColor *adminTint = user.isAdmin ? AppPrimaryClr : SeconderyTextClr;
    [Styling applyIconButtonStyle:self.setAdminButton tintColor:adminTint backgroundColor:AppBackgroundClr];
    [self.setAdminButton setImage:[UIImage systemImageNamed:user.isAdmin ? @"key.fill" : @"key"] forState:UIControlStateNormal];

    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    if (user.UserImageUrl.absoluteString.length > 0) {
        [self.avatarImageView setImageFromUrl:user.UserImageUrl.absoluteString Blr:NO Shimmering:YES];
    }
}

- (void)pp_updateStatusPillForUser:(UserModel *)user {
    NSString *status = [[user.accountStatus ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (status.length == 0) status = user.isBlocked ? @"blocked" : @"active";
    BOOL customerMode = self.viewFor == ViewForEditAccount;
    UIColor *statusColor = nil;
    if ([status isEqualToString:@"blocked"]) {
        self.statusPill.text = customerMode ? kLang(@"MissionControl_Customers_Status_Blocked") : kLang(@"Blocked");
        statusColor = [UIColor ppError];
    } else if ([status isEqualToString:@"disabled"]) {
        self.statusPill.text = customerMode ? kLang(@"MissionControl_Customers_Status_Disabled") : kLang(@"Disabled");
        statusColor = [UIColor ppTextTertiary];
    } else if ([status isEqualToString:@"pending_review"]) {
        self.statusPill.text = customerMode ? kLang(@"MissionControl_Customers_Status_PendingReview") : kLang(@"Pending Review");
        statusColor = [UIColor ppWarning];
    } else {
        self.statusPill.text = customerMode ? kLang(@"MissionControl_Customers_Status_Active") : kLang(@"Active");
        statusColor = [UIColor ppSuccess];
    }
    self.statusPill.textColor = statusColor;
    self.statusPill.backgroundColor = [statusColor colorWithAlphaComponent:0.12];
    self.statusPill.accessibilityLabel = self.statusPill.text;
}

#pragma mark - Actions (delegate -> VC)

- (void)onTapAction {
    if ([self.delegate respondsToSelector:@selector(userCellDidTapAction:user:)]) {
        [self.delegate userCellDidTapAction:self user:self.cellUser];
    }
}

- (void)onTapSetAdmin {
    if ([self.delegate respondsToSelector:@selector(userCellDidTapSetAdmin:user:)]) {
        [self.delegate userCellDidTapSetAdmin:self user:self.cellUser];
    }
}

@end
