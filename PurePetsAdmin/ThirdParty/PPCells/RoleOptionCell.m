//
//  RoleOptionCell.m
//  PurePetsAdmin
//

#import "RoleOptionCell.h"

@interface RoleOptionCell ()
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIView *iconShellView;
@property (nonatomic, strong) UIImageView *checkIconView;
@property (nonatomic, strong) UIStackView *textStackView;
@end

@implementation RoleOptionCell

+ (void)load {
    [XLFormViewController.cellClassesForRowDescriptorTypes setObject:self forKey:@"RoleOptionCell"];
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier]) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        _containerView = [[UIView alloc] init];
        _containerView.translatesAutoresizingMaskIntoConstraints = NO;
        _containerView.backgroundColor = [UIColor ppElevatedSurface];
        _containerView.layer.cornerRadius = 24.0;
        _containerView.layer.borderWidth = 1.0;
        _containerView.layer.borderColor = [AppPrimaryClr colorWithAlphaComponent:0.08].CGColor;
        if (@available(iOS 13.0, *)) {
            _containerView.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [self.contentView addSubview:_containerView];

        _iconShellView = [[UIView alloc] init];
        _iconShellView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconShellView.layer.cornerRadius = 14.0;
        if (@available(iOS 13.0, *)) {
            _iconShellView.layer.cornerCurve = kCACornerCurveContinuous;
        }
        [_containerView addSubview:_iconShellView];

        _checkIconView = [[UIImageView alloc] init];
        _checkIconView.translatesAutoresizingMaskIntoConstraints = NO;
        _checkIconView.contentMode = UIViewContentModeScaleAspectFit;
        [_iconShellView addSubview:_checkIconView];

        _textStackView = [[UIStackView alloc] init];
        _textStackView.translatesAutoresizingMaskIntoConstraints = NO;
        _textStackView.axis = UILayoutConstraintAxisVertical;
        _textStackView.alignment = UIStackViewAlignmentFill;
        _textStackView.spacing = 4.0;
        [_containerView addSubview:_textStackView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [Styling fontBold:16];
        _titleLabel.textColor = PrimaryTextClr;
        _titleLabel.numberOfLines = 1;
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [_textStackView addArrangedSubview:_titleLabel];
        
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [Styling fontMedium:13];
        _subtitleLabel.textColor = SeconderyTextClr;
        _subtitleLabel.numberOfLines = 0;
        _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [_textStackView addArrangedSubview:_subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_containerView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_containerView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:0],
            [_containerView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:0],
            [_containerView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],

            [_iconShellView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-16],
            [_iconShellView.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor],
            [_iconShellView.widthAnchor constraintEqualToConstant:28],
            [_iconShellView.heightAnchor constraintEqualToConstant:28],

            [_checkIconView.centerXAnchor constraintEqualToAnchor:_iconShellView.centerXAnchor],
            [_checkIconView.centerYAnchor constraintEqualToAnchor:_iconShellView.centerYAnchor],
            [_checkIconView.widthAnchor constraintEqualToConstant:14],
            [_checkIconView.heightAnchor constraintEqualToConstant:14],

            [_textStackView.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:16],
            [_textStackView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:18],
            [_textStackView.trailingAnchor constraintEqualToAnchor:_iconShellView.leadingAnchor constant:-16],
            [_textStackView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor constant:-16]
        ]];
    }
    return self;
}
- (void)update {
    [super update];

    XLFormOptionsObject *option = self.rowDescriptor.value;
    if ([option isKindOfClass:[XLFormOptionsObject class]]) {
        self.titleLabel.text = option.displayText;
        if ([option respondsToSelector:@selector(userInfo)]) {
            NSDictionary *info = [option performSelector:@selector(userInfo)];
            self.subtitleLabel.text = info[@"desc"] ?: @"";
        }
    }
}

- (void)pp_setSelectedState:(BOOL)selected {
    UIColor *accentColor = [UIColor ppPrimary];

    if (selected) {
        _containerView.layer.borderColor = [accentColor colorWithAlphaComponent:0.4].CGColor;
        _containerView.backgroundColor = [accentColor colorWithAlphaComponent:0.04];

        _iconShellView.backgroundColor = accentColor;
        _checkIconView.image = [[UIImage systemImageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _checkIconView.tintColor = UIColor.whiteColor;

        _titleLabel.textColor = accentColor;
    } else {
        _containerView.layer.borderColor = [accentColor colorWithAlphaComponent:0.08].CGColor;
        _containerView.backgroundColor = [UIColor ppElevatedSurface];

        _iconShellView.backgroundColor = [accentColor colorWithAlphaComponent:0.08];
        _checkIconView.image = nil;

        _titleLabel.textColor = PrimaryTextClr;
    }
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];

    [UIView animateWithDuration:0.15 animations:^{
        self->_containerView.transform = highlighted ? CGAffineTransformMakeScale(0.98, 0.98) : CGAffineTransformIdentity;
    }];
}

@end
