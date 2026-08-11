//
//  RoleSummaryCell 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


// RoleSummaryCell.m
#import "RoleSummaryCell.h"

@interface RoleSummaryCell ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end

@implementation RoleSummaryCell

+ (void)load {
    // Register our custom row type
    [XLFormViewController.cellClassesForRowDescriptorTypes setObject:self forKey:@"RoleSummaryPush"];
}


- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier]) {
        
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font =[Styling fontMedium:15];;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:13];
        _subtitleLabel.textColor = [UIColor ppTextSecondary];
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_subtitleLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:15],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-30],
            
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8]
        ]];
    }
    return self;
}

- (void)update {
    [super update];
    
    XLFormOptionsObject *option = self.rowDescriptor.value;
    if ([option isKindOfClass:[XLFormOptionsObject class]]) {
        self.titleLabel.text = option.displayText;
        self.subtitleLabel.text = option.displayText; //option.userInfo[@"desc"] ?: @"";
    }
    else {
        self.titleLabel.text = @"";
        self.subtitleLabel.text = @"";
    }
}
@end
