//
//  PPQuickActionsView.m
//  PurePetsAdmin
//

#import "PPQuickActionsView.h"

@interface PPQuickActionsView ()
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation PPQuickActionsView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _buttonHeight = 64.0;
        _cornerRadius = 16.0;
        _backgroundColorForButton = [AppBackgroundClrShiner colorWithAlphaComponent:0.8];
        _tintColorForIcon = AppPrimaryClr;

        self.stack = [UIStackView new];
        self.stack.axis = UILayoutConstraintAxisHorizontal;
        self.stack.alignment = UIStackViewAlignmentFill;
        self.stack.distribution = UIStackViewDistributionFillEqually;
        self.stack.spacing = 10;
        self.stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        [self addSubview:self.stack];
        self.stack.translatesAutoresizingMaskIntoConstraints = NO;

        [NSLayoutConstraint activateConstraints:@[
            [self.stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (void)setActions:(NSArray<PPQuickActionItem *> *)actions {
    for (UIView *v in self.stack.arrangedSubviews) {
        [self.stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    for (PPQuickActionItem *a in actions) {
        [self.stack addArrangedSubview:[self buildButtonFor:a]];
    }
}

- (UIView *)buildButtonFor:(PPQuickActionItem *)item {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.backgroundColor = self.backgroundColorForButton;
    btn.layer.cornerRadius = self.cornerRadius;
    btn.layer.masksToBounds = YES;
    btn.translatesAutoresizingMaskIntoConstraints = NO;

    [btn.heightAnchor constraintEqualToConstant:self.buttonHeight].active = YES;

    UIImage *img = [UIImage systemImageNamed:item.iconName] ?: [UIImage imageNamed:item.iconName];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.tintColor = self.tintColorForIcon;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *lbl = [UILabel new];
    lbl.text = kLang(item.titleKey);
    lbl.font = [Styling fontBold:11];
    lbl.textColor = PrimaryTextClr;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.numberOfLines = 1;
    lbl.translatesAutoresizingMaskIntoConstraints = NO;

    [btn addSubview:iv];
    [btn addSubview:lbl];

    [NSLayoutConstraint activateConstraints:@[
        [iv.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor constant:-8],
        [iv.heightAnchor constraintEqualToConstant:22],
        [iv.widthAnchor constraintEqualToConstant:22],

        [lbl.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4],
        [lbl.leadingAnchor constraintEqualToAnchor:btn.leadingAnchor constant:4],
        [lbl.trailingAnchor constraintEqualToAnchor:btn.trailingAnchor constant:-4],
    ]];

    [PPButtonHelper attachTapAnimationToButton:btn style:PPButtonAnimationStyleDefault];
    if (item.handler) {
        [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            item.handler();
        }] forControlEvents:UIControlEventTouchUpInside];
    }

    return btn;
}

- (void)onIconTapped:(UITapGestureRecognizer *)gr {
    void (^handler)(void) = objc_getAssociatedObject(gr.view, @"pp_action_handler");
    if (handler) handler();
}




/*
- (UIView *)buildButtonFor:(PPQuickActionItem *)item {
    
    self.buttonWidth = item.buttonWidth == 0 ? 80 : 140;
    
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];

    btn.backgroundColor = self.backgroundColorForButton;
    btn.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.1];

    btn.layer.cornerRadius = self.cornerRadius;
    btn.layer.masksToBounds = YES;

    UIImage *img = [UIImage systemImageNamed:item.iconName] ?: [UIImage imageNamed:item.iconName];
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.tintColor = self.tintColorForIcon;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.userInteractionEnabled = YES;
    btn.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.1];

    UILabel *lbl = [UILabel new];
    lbl.text = kLang(item.titleKey);
    lbl.font = [Styling fontMedium:14];
    lbl.textColor = [UIColor ppTextPrimary];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.numberOfLines = 1;
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.userInteractionEnabled = YES;
    [NSLayoutConstraint activateConstraints:@[ [lbl.widthAnchor constraintEqualToConstant:self.buttonWidth+30] ]];
    //[lbl sizeToFit];
    btn.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.1];

    UIStackView *sv = [[UIStackView alloc] initWithArrangedSubviews:@[iv, lbl]];
    sv.axis = UILayoutConstraintAxisVertical;
    sv.alignment = UIStackViewAlignmentFill;
    sv.spacing = 6;
    sv.userInteractionEnabled = YES;
    btn.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.1];

    [btn addSubview:sv];
    
    [PPButtonHelper attachTapAnimationToButton:btn style:PPButtonAnimationStyleDefault];

    
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [sv.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
        [sv.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],
        [sv.widthAnchor constraintEqualToConstant:self.buttonWidth],

        [btn.heightAnchor constraintEqualToConstant:self.buttonHeight],
        [btn.widthAnchor constraintEqualToConstant:self.buttonWidth],
        [iv.heightAnchor constraintEqualToConstant:26],
        [iv.widthAnchor constraintEqualToConstant:26],
    ]];

    if (item.handler) {
        [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            item.handler();
        }] forControlEvents:UIControlEventTouchUpInside];
    }
    
    
    btn.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.25].CGColor;
    btn.layer.shadowOpacity = 0.2;
    btn.layer.shadowRadius = 4.0;
    btn.layer.shadowOffset = CGSizeMake(0, 3);
    btn.layer.masksToBounds = NO;

    return btn;
}
 
 
 
 
 
 - (UIView *)buildButtonFor:(PPQuickActionItem *)item {
     
     CGFloat width = 0;
     if(item.buttonWidth == 0)
     {
         width  = self.buttonWidth =  80;
         
     }
    else
    {
       // width  = self.buttonWidth =  150;
    }

     self.buttonHeight =  80;
     UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
     btn.backgroundColor = self.backgroundColorForButton;
     btn.layer.cornerRadius = self.cornerRadius;
     btn.layer.masksToBounds = YES;

     // Icon
     UIImage *img = [UIImage systemImageNamed:item.iconName] ?: [UIImage imageNamed:item.iconName];
     UIImageView *iv = [[UIImageView alloc] initWithImage:img];
     iv.tintColor = self.tintColorForIcon;
     iv.contentMode = UIViewContentModeScaleAspectFit;
     iv.userInteractionEnabled = YES; // ✅ allow taps

     // Label
     UILabel *lbl = [UILabel new];
     lbl.text = kLang(item.titleKey);
     lbl.font = [Styling fontMedium:14];
     lbl.textColor = [UIColor ppTextPrimary];
     lbl.textAlignment = NSTextAlignmentCenter;
     lbl.numberOfLines = 1;

     // Stack (icon + label)
     UIStackView *sv = [[UIStackView alloc] initWithArrangedSubviews:@[iv, lbl]];
     sv.axis = UILayoutConstraintAxisVertical;
     sv.alignment = UIStackViewAlignmentCenter;
     sv.spacing = 6;
     sv.translatesAutoresizingMaskIntoConstraints = NO;
     [btn addSubview:sv];

     [NSLayoutConstraint activateConstraints:@[
         [sv.centerXAnchor constraintEqualToAnchor:btn.centerXAnchor],
         [sv.centerYAnchor constraintEqualToAnchor:btn.centerYAnchor],

         [btn.heightAnchor constraintEqualToConstant:self.buttonHeight],
         [btn.widthAnchor constraintEqualToConstant:width],

         [iv.heightAnchor constraintEqualToConstant:26],
         [iv.widthAnchor constraintEqualToConstant:26],
     ]];

     // Tap animation
     [PPButtonHelper attachTapAnimationToButton:btn style:PPButtonAnimationStyleDefault];

     // Button handler
     if (item.handler) {
         [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
             item.handler();
         }] forControlEvents:UIControlEventTouchUpInside];
     }

     // Extra: ImageView tap recognizer
     if (item.handler) {
         UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onIconTapped:)];
         iv.tag = [self.stack.arrangedSubviews count]; // assign index if needed
         [iv addGestureRecognizer:tap];

         // Store block in associated object (so both button & image call same handler)
         objc_setAssociatedObject(iv, @"pp_action_handler", item.handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
     }

     return btn;
 }

 // Icon tap callback
 - (void)onIconTapped:(UITapGestureRecognizer *)gr {
     void (^handler)(void) = objc_getAssociatedObject(gr.view, @"pp_action_handler");
     if (handler) handler();
 }
 
 
 */

@end

#pragma mark - PPQuickActionItem

@implementation PPQuickActionItem
+ (instancetype)itemWithTitleKey:(NSString *)titleKey iconName:(NSString *)iconName width:(CGFloat)width
                          handler:(void (^ _Nullable)(void))handler {
    PPQuickActionItem *i = [PPQuickActionItem new];
    i.titleKey = titleKey ?: @"";
    i.iconName = iconName ?: @"square";
    i.handler  = handler;
    i.buttonWidth  = width;
    return i;
}
@end
