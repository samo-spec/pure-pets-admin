//
//  PPUserCell.m
//

#import "PPUserCell.h"

@implementation PPUserCell

+ (NSString *)reuseIdentifier { return @"PPUserCell"; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier ?: PPUserCell.reuseIdentifier]) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _avatarImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
        _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _avatarImageView.layer.cornerRadius = 27;
        _avatarImageView.clipsToBounds = YES;
        _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarImageView.tintColor = AppPrimaryClr;
        
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontMedium:17];
        _titleLabel.textColor = PrimaryTextClr;
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        
        _verifiedBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
        _verifiedBadge.translatesAutoresizingMaskIntoConstraints = NO;
        _verifiedBadge.tintColor = [UIColor systemBlueColor];
        _verifiedBadge.contentMode = UIViewContentModeScaleAspectFit;
        _verifiedBadge.hidden = YES;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontMedium:13];
        _subtitleLabel.textColor = SeconderyTextClr;
        _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;

        _statusPill = [[UILabel alloc] init];
        _statusPill.translatesAutoresizingMaskIntoConstraints = NO;
        _statusPill.font = [Styling fontMedium:11];
        _statusPill.textAlignment = NSTextAlignmentCenter;
        _statusPill.layer.cornerRadius = 10;
        _statusPill.layer.masksToBounds = YES;
        _statusPill.textColor = [UIColor whiteColor];

        _actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        _actionButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_actionButton setImage:[UIImage systemImageNamed:Language.languageVal == 0 ? @"chevron.right" : @"chevron.left"] forState:UIControlStateNormal];
        _actionButton.tintColor = SeconderyTextClr;
        [_actionButton addTarget:self action:@selector(onTapAction) forControlEvents:UIControlEventTouchUpInside];

        _setAdminButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _setAdminButton.translatesAutoresizingMaskIntoConstraints = NO;
        _setAdminButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [_setAdminButton addTarget:self action:@selector(onTapSetAdmin) forControlEvents:UIControlEventTouchUpInside];
        [_setAdminButton setImage:[UIImage systemImageNamed:@"key"] forState:UIControlStateNormal];
        [PPButtonHelper attachTapAnimationToButton:_setAdminButton style:PPButtonAnimationStyleGlow];
        
        [self.contentView addSubview:_avatarImageView];
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_verifiedBadge];
        [self.contentView addSubview:_subtitleLabel];
        [self.contentView addSubview:_statusPill];
        [self.contentView addSubview:_actionButton];
        [self.contentView addSubview:_setAdminButton];

        CGFloat pad = 12.0;

        [NSLayoutConstraint activateConstraints:@[
            [_avatarImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:pad],
            [_avatarImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_avatarImageView.widthAnchor constraintEqualToConstant:54],
            [_avatarImageView.heightAnchor constraintEqualToConstant:54],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_avatarImageView.trailingAnchor constant:12],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad + 2],

            [_verifiedBadge.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:4],
            [_verifiedBadge.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
            [_verifiedBadge.widthAnchor constraintEqualToConstant:15],
            [_verifiedBadge.heightAnchor constraintEqualToConstant:15],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_actionButton.leadingAnchor constant:-8],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],

            [_statusPill.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_statusPill.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:4],
            [_statusPill.heightAnchor constraintEqualToConstant:20],
            [_statusPill.widthAnchor constraintGreaterThanOrEqualToConstant:60],

            [_actionButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
            [_actionButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_actionButton.widthAnchor constraintEqualToConstant:36],
            [_actionButton.heightAnchor constraintEqualToConstant:36],

            [_setAdminButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad],
            [_setAdminButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_setAdminButton.widthAnchor constraintEqualToConstant:36],
            [_setAdminButton.heightAnchor constraintEqualToConstant:36]
        ]];
    }
    return self;
}

- (void)configureWithUser:(UserModel *)user
                indexPath:(NSIndexPath *)indexPath
                  viewFor:(ViewFor)viewFor
{
    self.cellUser = user;
    self.indexPath = indexPath;
    self.representedUID = user.uid;
    self.viewFor = viewFor;

    // Texts
    self.titleLabel.text = user.UserName.length ? user.UserName : (user.UserEmail ?: @"—");
    self.verifiedBadge.hidden = !user.isVerified;

    NSString *email = ([user.UserEmail isKindOfClass:NSString.class] ? user.UserEmail : @"");
    NSString *mobile = ([user.MobileNo isKindOfClass:NSString.class] ? user.MobileNo : @"");
    self.subtitleLabel.text = (email.length && mobile.length) ? [NSString stringWithFormat:@"%@  •  %@", email, mobile] : (email.length ? email : mobile);

    // Status Pill
    [self pp_updateStatusPillForUser:user];

    // Buttons visibility per viewFor
    if (viewFor == ViewForAdminToggle) {
        self.setAdminButton.hidden = NO;
        self.actionButton.hidden = NO;
        // Adjust constraints if needed
    } else if (viewFor == ViewForEditRoleAndPermissions || viewFor == ViewForEditAccount) {
        self.setAdminButton.hidden = YES;
        self.actionButton.hidden = NO;
    } else {
        self.setAdminButton.hidden = NO;
        self.actionButton.hidden = NO;
    }

    UIColor *adminTint = user.isAdmin ? AppPrimaryClr : SeconderyTextClr;
    [Styling applyIconButtonStyle:self.setAdminButton tintColor:adminTint backgroundColor:AppBackgroundClr];
    [self.setAdminButton setImage:[UIImage systemImageNamed:user.isAdmin ? @"key.fill" : @"key"] forState:UIControlStateNormal];

    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    if (user.UserImageUrl.absoluteString.length > 0) {
         [self.avatarImageView setImageFromUrl:user.UserImageUrl.absoluteString Blr:NO Shimmering:YES];
    }
}

- (void)pp_updateStatusPillForUser:(UserModel *)user {
    NSString *status = user.accountStatus ?: (user.isBlocked ? @"blocked" : @"active");
    if ([status isEqualToString:@"blocked"] || user.isBlocked) {
        self.statusPill.text = kLang(@"Blocked");
        self.statusPill.backgroundColor = [UIColor systemRedColor];
    } else if ([status isEqualToString:@"disabled"]) {
        self.statusPill.text = kLang(@"Disabled");
        self.statusPill.backgroundColor = [UIColor systemGrayColor];
    } else if ([status isEqualToString:@"pending_review"]) {
        self.statusPill.text = kLang(@"Pending Review");
        self.statusPill.backgroundColor = [UIColor systemOrangeColor];
    } else {
        self.statusPill.text = kLang(@"Active");
        self.statusPill.backgroundColor = [UIColor systemGreenColor];
    }
    
    // Add horizontal padding to pill
    CGSize size = [self.statusPill sizeThatFits:CGSizeMake(CGFLOAT_MAX, 20)];
    // Update width constraint if needed, or just let intrinsic content size work with margins if stack view was used.
    // Since we used constraints, we can update the width constant or use content compression resistance.
}



#pragma mark - Actions (delegate → VC)

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
