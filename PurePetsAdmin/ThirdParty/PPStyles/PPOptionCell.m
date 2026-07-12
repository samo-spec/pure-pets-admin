//
//  PPOptionCell.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// PPOptionCell.m
#import "PPOptionCell.h"
#import "Language.h"
#import "Styling.h"

@interface PPOptionCell ()
@property (nonatomic, strong) NSLayoutConstraint *titleTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleCenterConstraint;
@property (nonatomic, strong) NSLayoutConstraint *subtitleTopConstraint;
@property (nonatomic, strong) NSLayoutConstraint *subtitleBottomConstraint;
@end

@implementation PPOptionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _circleImageView = [[UIImageView alloc] init];
        _circleImageView.translatesAutoresizingMaskIntoConstraints = NO;
        _circleImageView.layer.cornerRadius = 20; // circle (40x40)
        _circleImageView.layer.masksToBounds = YES;
        _circleImageView.contentMode = UIViewContentModeScaleAspectFill;
        [self.contentView addSubview:_circleImageView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [Styling fontMedium:16];
        _titleLabel.textColor = PrimaryTextClr;
        _titleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _titleLabel.numberOfLines = 1;
        [self.contentView addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [Styling fontRegular:14];
        _subtitleLabel.textColor = SeconderyTextClr;
        _subtitleLabel.textAlignment = [Language alignmentForCurrentLanguage];
        _subtitleLabel.numberOfLines = 1;
        [self.contentView addSubview:_subtitleLabel];

        self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        self.titleTopConstraint = [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10];
        self.titleCenterConstraint = [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor];
        self.subtitleTopConstraint = [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2];
        self.subtitleBottomConstraint = [_subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8];

        [NSLayoutConstraint activateConstraints:@[
            [_circleImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_circleImageView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_circleImageView.widthAnchor constraintEqualToConstant:40],
            [_circleImageView.heightAnchor constraintEqualToConstant:40],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_circleImageView.trailingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            self.titleTopConstraint,
            self.subtitleTopConstraint,
            self.subtitleBottomConstraint
        ]];

        self.titleCenterConstraint.active = NO;
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.titleLabel.text = @"";
    self.subtitleLabel.text = @"";
    self.subtitleLabel.hidden = NO;
    self.titleTopConstraint.active = YES;
    self.subtitleTopConstraint.active = YES;
    self.subtitleBottomConstraint.active = YES;
    self.titleCenterConstraint.active = NO;
    self.circleImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
}

- (void)pp_applyTitle:(NSString *)title subtitle:(NSString *)subtitle {
    NSString *safeTitle = title ?: @"";
    NSString *safeSubtitle = subtitle ?: @"";
    BOOL hasSubtitle = safeSubtitle.length > 0;

    self.titleLabel.text = safeTitle;
    self.subtitleLabel.text = safeSubtitle;
    self.subtitleLabel.hidden = !hasSubtitle;

    self.titleTopConstraint.active = hasSubtitle;
    self.subtitleTopConstraint.active = hasSubtitle;
    self.subtitleBottomConstraint.active = hasSubtitle;
    self.titleCenterConstraint.active = !hasSubtitle;

    if (safeTitle.length == 0) {
        self.titleLabel.text = @"-";
    }
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(UIImage *)image {
    [self pp_applyTitle:title subtitle:subtitle];
    self.circleImageView.image = image ?: [UIImage systemImageNamed:@"person.crop.circle.fill"];
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle imageUrl:(NSString *)imageUrl {
    [self pp_applyTitle:title subtitle:subtitle];
    if (imageUrl.length > 0) {
        [self.circleImageView setImageFromUrl:imageUrl placeholderImage:PPUserPlaceholderImageName];
    } else {
        self.circleImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    }
    self.circleImageView.tintColor = AppPrimaryClr;
}

@end


