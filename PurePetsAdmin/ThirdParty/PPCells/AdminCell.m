//
//  AdminCell 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


// AdminCell.m
#import "AdminCell.h"

@interface AdminCell ()
@property (nonatomic, strong) UIView *bgCardView;
@end

@implementation AdminCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        
        // Card container
        _bgCardView = [[UIView alloc] init];
        _bgCardView.translatesAutoresizingMaskIntoConstraints = NO;
        _bgCardView.backgroundColor = UIColor.whiteColor;
        _bgCardView.layer.cornerRadius = 12;
        _bgCardView.layer.shadowColor = [UIColor blackColor].CGColor;
        _bgCardView.layer.shadowOpacity = 0.1;
        _bgCardView.layer.shadowRadius = 6;
        _bgCardView.layer.shadowOffset = CGSizeMake(0, 3);
        _bgCardView.layer.masksToBounds = NO;
        [self.contentView addSubview:_bgCardView];
        
        [NSLayoutConstraint activateConstraints:@[
            [_bgCardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
            [_bgCardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],
            [_bgCardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_bgCardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        ]];
        
        // Icon
        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [_bgCardView addSubview:_iconView];
        
        // Title
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _titleLabel.textColor = [UIColor ppTextPrimary];
        [_bgCardView addSubview:_titleLabel];
        
        // Subtitle
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [UIFont systemFontOfSize:14];
        _subtitleLabel.textColor = [UIColor ppTextSecondary];
        _subtitleLabel.numberOfLines = 1;
        [_bgCardView addSubview:_subtitleLabel];
        
        // Layout
        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:_bgCardView.leadingAnchor constant:12],
            [_iconView.centerYAnchor constraintEqualToAnchor:_bgCardView.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:28],
            [_iconView.heightAnchor constraintEqualToConstant:28],
            
            [_titleLabel.topAnchor constraintEqualToAnchor:_bgCardView.topAnchor constant:10],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_bgCardView.trailingAnchor constant:-12],
            
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:4],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:_bgCardView.bottomAnchor constant:-10]
        ]];
    }
    return self;
}

- (void)configureWithIcon:(UIImage *)icon
                    title:(NSString *)title
                 subtitle:(NSString *)subtitle {
    self.iconView.image = icon;
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
}

@end
