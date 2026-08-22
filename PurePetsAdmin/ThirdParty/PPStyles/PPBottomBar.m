//
//  PPBottomBar 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 12/09/2025.
//


#import "PPBottomBar.h"

@interface PPBottomBar()
@property (nonatomic, strong) UIStackView *leftStackView;
@property (nonatomic, strong) UIStackView *rightStackView;
- (void)pp_styleSideButton:(UIButton *)button;
- (void)pp_styleCenterButton;
- (void)pp_applySquareSize:(CGFloat)size toButton:(UIButton *)button;
@end

@implementation PPBottomBar

- (instancetype)initWithLayout:(BarLayout)layout {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _layout = layout;
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [[UIColor ppSurface] colorWithAlphaComponent:0.96];
    self.clipsToBounds = NO;
    self.layer.cornerRadius = 30.0;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 12);
    self.layer.shadowRadius = 24;
    self.layer.shadowOpacity = 0.08;
    
    // Setup center button
    _centerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    
    // Setup stack views
    _leftStackView = [self createStackView];
    _rightStackView = [self createStackView];
    
    [self addSubview:_leftStackView];
    [self addSubview:_centerButton];
    [self addSubview:_rightStackView];
}

- (UIStackView *)createStackView {
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.axis = UILayoutConstraintAxisHorizontal;
    stackView.distribution = UIStackViewDistributionEqualSpacing;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 14;
    return stackView;
}

- (void)setLeftButtons:(NSArray<UIButton *> *)leftButtons {
    for (UIView *view in self.leftStackView.arrangedSubviews) {
        [view removeFromSuperview];
    }
    
    _leftButtons = leftButtons;
    for (UIButton *button in leftButtons) {
        [self pp_styleSideButton:button];
        [self.leftStackView addArrangedSubview:button];
    }
}

- (void)setRightButtons:(NSArray<UIButton *> *)rightButtons {
    for (UIView *view in self.rightStackView.arrangedSubviews) {
        [view removeFromSuperview];
    }
    
    _rightButtons = rightButtons;
    for (UIButton *button in rightButtons) {
        [self pp_styleSideButton:button];
        [self.rightStackView addArrangedSubview:button];
    }
}

- (void)setCenterButton:(UIButton *)centerButton {
    if (_centerButton == centerButton) return;
    [_centerButton removeFromSuperview];
    _centerButton = centerButton ?: [UIButton buttonWithType:UIButtonTypeCustom];
    [self pp_styleCenterButton];
    [self addSubview:_centerButton];
}

- (void)setThemeColor:(UIColor *)themeColor {
    _themeColor = themeColor;
    [self pp_styleCenterButton];
    for (UIButton *button in self.leftButtons) {
        [button setNeedsUpdateConfiguration];
    }
    for (UIButton *button in self.rightButtons) {
        [button setNeedsUpdateConfiguration];
    }
}

- (void)pp_applySquareSize:(CGFloat)size toButton:(UIButton *)button {
    if (!button) return;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    NSLayoutConstraint *widthConstraint = nil;
    NSLayoutConstraint *heightConstraint = nil;
    for (NSLayoutConstraint *constraint in button.constraints) {
        BOOL matchesButton = constraint.firstItem == button && constraint.secondItem == nil && constraint.relation == NSLayoutRelationEqual;
        if (!matchesButton) continue;
        if (constraint.firstAttribute == NSLayoutAttributeWidth) widthConstraint = constraint;
        if (constraint.firstAttribute == NSLayoutAttributeHeight) heightConstraint = constraint;
    }

    if (!widthConstraint) {
        widthConstraint = [button.widthAnchor constraintEqualToConstant:size];
        widthConstraint.active = YES;
    } else {
        widthConstraint.constant = size;
    }

    if (!heightConstraint) {
        heightConstraint = [button.heightAnchor constraintEqualToConstant:size];
        heightConstraint.active = YES;
    } else {
        heightConstraint.constant = size;
    }
}

- (void)pp_styleSideButton:(UIButton *)button {
    if (!button) return;

    [self pp_applySquareSize:48.0 toButton:button];
    button.backgroundColor = UIColor.clearColor;
    button.layer.cornerRadius = 24.0;
    button.layer.masksToBounds = NO;
    button.layer.borderWidth = 0.0;
    button.layer.shadowOpacity = 0.0;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsZero;
    button.imageEdgeInsets = UIEdgeInsetsZero;
    button.tintColor = [UIColor ppTextSecondary];
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;

    UIImageSymbolConfiguration *iconConfig = [UIImageSymbolConfiguration configurationWithPointSize:22.0
                                                                                             weight:UIImageSymbolWeightSemibold
                                                                                              scale:UIImageSymbolScaleMedium];
    [button setPreferredSymbolConfiguration:iconConfig forImageInState:UIControlStateNormal];
    [button setPreferredSymbolConfiguration:iconConfig forImageInState:UIControlStateSelected];
    [button setPreferredSymbolConfiguration:iconConfig forImageInState:UIControlStateHighlighted];

    if (@available(iOS 15.0, *)) {
        __weak typeof(self) weakSelf = self;
        button.configurationUpdateHandler = ^(__kindof UIButton * _Nonnull updatedButton) {
            UIColor *accent = weakSelf.themeColor ?: [UIColor ppPrimary];
            BOOL selected = updatedButton.selected;
            updatedButton.tintColor = selected ? accent : [UIColor ppTextSecondary];
            updatedButton.backgroundColor = selected ? [[UIColor ppSurface] colorWithAlphaComponent:0.98] : UIColor.clearColor;
            updatedButton.layer.borderWidth = selected ? 1.0 : 0.0;
            updatedButton.layer.borderColor = selected ? [accent colorWithAlphaComponent:0.16].CGColor : UIColor.clearColor.CGColor;
            updatedButton.layer.shadowColor = [UIColor blackColor].CGColor;
            updatedButton.layer.shadowOffset = CGSizeMake(0.0, 6.0);
            updatedButton.layer.shadowRadius = 12.0;
            updatedButton.layer.shadowOpacity = selected ? 0.06f : 0.0f;
        };
        [button setNeedsUpdateConfiguration];
    }
}

- (void)pp_styleCenterButton {
    if (!_centerButton) return;

    [self pp_applySquareSize:68.0 toButton:_centerButton];
    _centerButton.backgroundColor = _themeColor ?: [UIColor ppPrimary];
    _centerButton.tintColor = UIColor.whiteColor;
    _centerButton.layer.cornerRadius = 34.0;
    _centerButton.layer.shadowColor = (_themeColor ?: [UIColor ppPrimary]).CGColor;
    _centerButton.layer.shadowOffset = CGSizeMake(0, 10);
    _centerButton.layer.shadowRadius = 20;
    _centerButton.layer.shadowOpacity = 0.24;
    _centerButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    _centerButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _centerButton.contentEdgeInsets = UIEdgeInsetsZero;
    _centerButton.imageEdgeInsets = UIEdgeInsetsZero;
    _centerButton.imageView.contentMode = UIViewContentModeScaleAspectFit;

    UIImageSymbolConfiguration *plusConfig = [UIImageSymbolConfiguration configurationWithPointSize:30.0
                                                                                             weight:UIImageSymbolWeightBold
                                                                                              scale:UIImageSymbolScaleLarge];
    [_centerButton setPreferredSymbolConfiguration:plusConfig forImageInState:UIControlStateNormal];
    [_centerButton setPreferredSymbolConfiguration:plusConfig forImageInState:UIControlStateHighlighted];
}

- (void)setupConstraintsInView:(UIView *)superview {
    [superview addSubview:self];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Height constraint
    [NSLayoutConstraint activateConstraints:@[
        [self.heightAnchor constraintEqualToConstant:88]
    ]];
    
    // Horizontal constraints
    UILayoutGuide *safeArea = superview.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:16],
        [self.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-16]
    ]];
    
    // Bottom constraint based on layout
    if (self.layout == BarLayoutStickToBottom) {
        [self.bottomAnchor constraintEqualToAnchor:superview.bottomAnchor].active = YES;
    } else {
        [self.bottomAnchor constraintEqualToAnchor:superview.bottomAnchor].active = YES;
    }
    
    if (self.centerButton) {
        [self.centerButton removeFromSuperview];
        [self addSubview:self.centerButton];
    }
    
    [self pp_styleCenterButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.centerButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.centerButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:4.0]
    ]];
    
    // Internal constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.leftStackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:24],
        [self.leftStackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        
        [self.rightStackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-24],
        [self.rightStackView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    
    self.layer.cornerRadius = 30.0;
    
    [self setNeedsLayout];
    [self layoutIfNeeded];
}



@end
