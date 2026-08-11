#import "PPQAccessBar.h"

// Constants
static const CGFloat kItemSpacing = 16.0f;
static const CGFloat kItemCornerRadius = 14.0f;
static const CGFloat kBarPadding = 16.0f;
static const CGFloat kAnimationDuration = 0.2f;
static const CGFloat kShadowOpacity = 0.15f;
static const CGFloat kShadowRadius = 8.0f;
static const CGSize kShadowOffset = {0, 2};

// Private interface
@interface PPQAccessBar ()

@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) NSArray<UIButton *> *itemButtons;

@end

@implementation PPQAccessBarItem

+ (instancetype)itemWithImage:(UIImage *)image title:(NSString *)title subtitle:(NSString *)subtitle {
    PPQAccessBarItem *item = [[PPQAccessBarItem alloc] init];
    item.image = image;
    item.title = title;
    item.subtitle = subtitle;
    return item;
}

@end

// Custom button for accessory items
@interface PPQAccessBarButton : UIControl

@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIStackView *contentStackView;

- (void)setSelected:(BOOL)selected animated:(BOOL)animated;

@end

@implementation PPQAccessBarButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    // Setup appearance
    self.backgroundColor = [UIColor ppSurface];
    self.layer.cornerRadius = kItemCornerRadius;
    
    // For continuous corner curve (iOS 13+), we need to check availability
    if (@available(iOS 13.0, *)) {
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
    
    // Add subtle shadow
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = kShadowOffset;
    self.layer.shadowRadius = kShadowRadius;
    self.layer.shadowOpacity = kShadowOpacity;
    
    // Create content stack
    self.contentStackView = [[UIStackView alloc] init];
    self.contentStackView.axis = UILayoutConstraintAxisVertical;
    self.contentStackView.alignment = UIStackViewAlignmentCenter;
    self.contentStackView.distribution = UIStackViewDistributionEqualSpacing;
    self.contentStackView.spacing = 4;
    self.contentStackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.contentStackView];
    
    // Create icon image view
    self.iconImageView = [[UIImageView alloc] init];
    self.iconImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentStackView addArrangedSubview:self.iconImageView];
    
    // Create title label
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor ppTextPrimary];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentStackView addArrangedSubview:self.titleLabel];
    
    // Create subtitle label
    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.subtitleLabel.textColor = [UIColor ppTextSecondary];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentStackView addArrangedSubview:self.subtitleLabel];
    
    // Set constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.contentStackView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.contentStackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.contentStackView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:8],
        [self.contentStackView.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8],
        [self.iconImageView.heightAnchor constraintEqualToConstant:24],
        [self.iconImageView.widthAnchor constraintEqualToConstant:24]
    ]];
}

- (void)setSelected:(BOOL)selected {
    [self setSelected:selected animated:NO];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected];
    
    void (^updateBlock)(void) = ^{
        if (selected) {
            self.backgroundColor = [UIColor ppBackground];
            self.layer.shadowOpacity = kShadowOpacity * 2;
            self.transform = CGAffineTransformMakeScale(1.05, 1.05);
        } else {
            self.backgroundColor = [UIColor ppSurface];
            self.layer.shadowOpacity = kShadowOpacity;
            self.transform = CGAffineTransformIdentity;
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:kAnimationDuration
                              delay:0
             usingSpringWithDamping:0.6
              initialSpringVelocity:0.8
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:updateBlock
                         completion:nil];
    } else {
        updateBlock();
    }
}

@end

@implementation PPQAccessBar

#pragma mark - Initialization

- (instancetype)initWithItems:(NSArray<PPQAccessBarItem *> *)items {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _items = items;
        _shouldAnimateSelection = YES;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame items:(NSArray<PPQAccessBarItem *> *)items {
    self = [super initWithFrame:frame];
    if (self) {
        _items = items;
        _shouldAnimateSelection = YES;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame items:@[]];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _items = @[];
        _shouldAnimateSelection = YES;
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    // Setup bar appearance
    self.backgroundColor = [UIColor ppBackground];
    
    // Setup stack view for items
    self.stackView = [[UIStackView alloc] init];
    self.stackView.axis = UILayoutConstraintAxisHorizontal;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    self.stackView.distribution = UIStackViewDistributionEqualSpacing;
    self.stackView.spacing = kItemSpacing;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.stackView];
    
    // Set default appearance
    _itemTintColor = [UIColor ppPrimary];
    _selectedItemTintColor = [UIColor ppPrimary];
    _titleColor = [UIColor ppTextPrimary];
    _subtitleColor = [UIColor ppTextSecondary];
    _titleFont = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _subtitleFont = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    
    // Add constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:kBarPadding],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-kBarPadding],
        [self.stackView.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12]
    ]];
    
    // Create items if we have them
    if (self.items.count > 0) {
        [self createItems];
    }
}

#pragma mark - Item Creation

- (void)createItems {
    // Remove existing items
    for (UIView *view in self.stackView.arrangedSubviews) {
        [self.stackView removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    
    NSMutableArray *buttons = [NSMutableArray array];
    
    for (NSInteger i = 0; i < self.items.count; i++) {
        PPQAccessBarItem *item = self.items[i];
        
        PPQAccessBarButton *button = [[PPQAccessBarButton alloc] init];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tag = i;
        
        // Configure button content
        button.iconImageView.image = [item.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        button.iconImageView.tintColor = self.itemTintColor;
        button.titleLabel.text = item.title;
        button.titleLabel.textColor = self.titleColor;
        button.titleLabel.font = self.titleFont;
        button.subtitleLabel.text = item.subtitle;
        button.subtitleLabel.textColor = self.subtitleColor;
        button.subtitleLabel.font = self.subtitleFont;
        
        // Add tap action
        [button addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        [self.stackView addArrangedSubview:button];
        [buttons addObject:button];
        
        // Set equal width for all buttons
        if (i > 0) {
            [button.widthAnchor constraintEqualToAnchor:((UIView *)buttons[0]).widthAnchor].active = YES;
        }
    }
    
    self.itemButtons = [buttons copy];
}

#pragma mark - Actions

- (void)itemTapped:(PPQAccessBarButton *)sender {
    [self setSelectedIndex:sender.tag];
    
    if ([self.delegate respondsToSelector:@selector(accessBar:didSelectItemAtIndex:)]) {
        [self.delegate accessBar:self didSelectItemAtIndex:sender.tag];
    }
}

- (void)setSelectedIndex:(NSInteger)index {
    for (NSInteger i = 0; i < self.itemButtons.count; i++) {
        PPQAccessBarButton *button = (PPQAccessBarButton *)self.itemButtons[i];
        BOOL isSelected = (i == index);
        
        [button setSelected:isSelected animated:self.shouldAnimateSelection];
        
        if (isSelected) {
            button.iconImageView.tintColor = self.selectedItemTintColor;
            button.titleLabel.textColor = self.selectedItemTintColor;
        } else {
            button.iconImageView.tintColor = self.itemTintColor;
            button.titleLabel.textColor = self.titleColor;
        }
    }
}

#pragma mark - Custom Accessors

- (void)setItems:(NSArray<PPQAccessBarItem *> *)items {
    _items = [items copy];
    [self createItems];
}

- (void)setItemTintColor:(UIColor *)itemTintColor {
    _itemTintColor = itemTintColor;
    for (PPQAccessBarButton *button in self.itemButtons) {
        if (!button.isSelected) {
            button.iconImageView.tintColor = itemTintColor;
        }
    }
}

- (void)setSelectedItemTintColor:(UIColor *)selectedItemTintColor {
    _selectedItemTintColor = selectedItemTintColor;
    for (PPQAccessBarButton *button in self.itemButtons) {
        if (button.isSelected) {
            button.iconImageView.tintColor = selectedItemTintColor;
            button.titleLabel.textColor = selectedItemTintColor;
        }
    }
}

- (void)setTitleColor:(UIColor *)titleColor {
    _titleColor = titleColor;
    for (PPQAccessBarButton *button in self.itemButtons) {
        button.titleLabel.textColor = button.isSelected ? self.selectedItemTintColor : titleColor;
    }
}

- (void)setSubtitleColor:(UIColor *)subtitleColor {
    _subtitleColor = subtitleColor;
    for (PPQAccessBarButton *button in self.itemButtons) {
        button.subtitleLabel.textColor = subtitleColor;
    }
}

- (void)setTitleFont:(UIFont *)titleFont {
    _titleFont = titleFont;
    for (PPQAccessBarButton *button in self.itemButtons) {
        button.titleLabel.font = titleFont;
    }
}

- (void)setSubtitleFont:(UIFont *)subtitleFont {
    _subtitleFont = subtitleFont;
    for (PPQAccessBarButton *button in self.itemButtons) {
        button.subtitleLabel.font = subtitleFont;
    }
}

@end
