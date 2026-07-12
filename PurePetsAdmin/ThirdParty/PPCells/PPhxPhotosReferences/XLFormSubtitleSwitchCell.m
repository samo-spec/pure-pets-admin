#import "XLFormSubtitleSwitchCell.h"
#import "Styling.h"
#import "Language.h"

@implementation XLFormSubtitleSwitchCell

+ (void)load {
    // Register for BooleanSwitch rows
    [[XLFormViewController cellClassesForRowDescriptorTypes] setObject:[self class]
                                                               forKey:XLFormRowDescriptorTypeBooleanSwitch];
}



- (void)configure {
    [super configure];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = AppForgroundColr;
    // Card background
    if (!self.bgCardView) {
        self.bgCardView = [[UIView alloc] init];
        self.bgCardView.translatesAutoresizingMaskIntoConstraints = NO;
        self.bgCardView.backgroundColor = [UIColor clearColor];
        self.bgCardView.layer.cornerRadius = 16;
        self.bgCardView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.bgCardView.layer.shadowOpacity = 0.2;
        self.bgCardView.layer.shadowRadius = 6;
        self.bgCardView.layer.shadowOffset = CGSizeMake(-4,4);
        [self.contentView addSubview:self.bgCardView];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.bgCardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            [self.bgCardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-5],
            [self.bgCardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:3],
            [self.bgCardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-3],
        ]];
    }
    
    // Title
    if (!self.titleLabel) {
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [Styling fontMedium:16];
        self.titleLabel.textColor = PrimaryTextClr;
        self.titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        [self.bgCardView addSubview:self.titleLabel];
    }
    
    // Subtitle
    if (!self.subtitleLabel) {
        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.subtitleLabel.font = [Styling fontRegular:13];
        self.subtitleLabel.textColor = SeconderyTextClr;
        self.subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        self.subtitleLabel.numberOfLines = 2;
        [self.bgCardView addSubview:self.subtitleLabel];
    }
    
    // Switch
    if (!self.toggleSwitch) {
        self.toggleSwitch = [[UISwitch alloc] init];
        self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
        self.toggleSwitch.onTintColor = AppPrimaryClr;
       // self.toggleSwitch.title = @"UISwitchStyleSliding";
        
        [self.toggleSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [self.bgCardView addSubview:self.toggleSwitch];
    }
    
    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.bgCardView.trailingAnchor constant:-12],
        [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.bgCardView.centerYAnchor],
        
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.bgCardView.topAnchor constant:10],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.bgCardView.leadingAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.toggleSwitch.leadingAnchor constant:-12],
        
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
        [self.subtitleLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bgCardView.bottomAnchor constant:-10],
    ]];
}

- (void)update {
    [super update];
    self.titleLabel.text = self.rowDescriptor.title;
    self.toggleSwitch.on = [self.rowDescriptor.value boolValue];

    NSString *desc = self.rowDescriptor.extraInfo[@"subtitle"];

    self.subtitleLabel.text = desc;
    self.subtitleLabel.hidden = (desc.length == 0);
    
    
    // Toggle visibility from config
    id rawUserModel = [self safeConfigForKey:@"ppUser"];
    if (rawUserModel){
        self.ppUser = (UserModel *)rawUserModel;
        DLog(@"CATECHED ppUser %@",[self.ppUser modelToJSONString]);
    }
    
    
    
}

- (void)switchChanged:(UISwitch *)sender {
    id oldValue = self.rowDescriptor.value;
    id newValue = @(sender.isOn);
    self.rowDescriptor.value = newValue;
    
    if (self.rowDescriptor.onChangeBlock) {
        self.rowDescriptor.onChangeBlock(oldValue, newValue, self.rowDescriptor);
    }
}



// Safe read that checks both live config and configure-time config
- (id)safeConfigForKey:(NSString *)key {
    id val = self.rowDescriptor.cellConfig[key];
    if (val) return val;
    val = self.rowDescriptor.cellConfigAtConfigure[key];
    if (val) return val;
    return nil;
}

@end
