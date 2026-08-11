//
//  PPCellImageButton.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 07/09/2025.
//


#import "PPCellWithButtons.h"

@interface PPCellImageButton : UIButton
@end

@implementation PPCellImageButton

- (void)setImage:(UIImage *)image forState:(UIControlState)state {
    [super setImage:image forState:state];
    if (image) {
        // Show the button if an image is set for any state
        self.hidden = NO;
    } else {
        // If removing image, check if any state still has an image; hide if none
        BOOL hasAnyImage = NO;
        for (NSNumber *stateNumber in @[@(UIControlStateNormal), @(UIControlStateHighlighted),
                                        @(UIControlStateSelected), @(UIControlStateDisabled)]) {
            UIImage *img = [self imageForState:stateNumber.unsignedIntegerValue];
            if (img) { hasAnyImage = YES; break; }
        }
        self.hidden = !hasAnyImage;
    }
    // Request layout update on the cell's contentView when image visibility changes
    [self.superview setNeedsLayout];
}

@end

@interface PPCellWithButtons ()
// Private layout constraint references for dynamic updates
@property (nonatomic, strong) UIView *stockOverlayView;
#ifdef DEBUG
 #endif
@end

@implementation PPCellWithButtons {
    NSLayoutConstraint *_firstTrailingToContent;
    NSLayoutConstraint *_secondTrailingToContent;
    NSLayoutConstraint *_firstTrailingToSecondTrailing;
    NSLayoutConstraint *_secondTrailingToContentDouble;
 
    NSLayoutConstraint *_suplabelTrailingToFirst;
    NSLayoutConstraint *_suplabelTrailingToSecond;
    NSLayoutConstraint *_suplabelTrailingToContent;
}

+ (NSString *)reuseIdentifier {
    return @"PPCellWithButtons";
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier ?: PPCellWithButtons.reuseIdentifier]) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;
        self.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

        _stockOverlayView = [[UIView alloc] init];
        _stockOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
        _stockOverlayView.userInteractionEnabled = NO;
        _stockOverlayView.backgroundColor = UIColor.clearColor;
        _stockOverlayView.hidden = NO;
        _stockOverlayView.backgroundColor = [UIColor ppElevatedSurface];
        _stockOverlayView.layer.cornerRadius = 22.0;
        _stockOverlayView.layer.cornerCurve = kCACornerCurveContinuous;
        _stockOverlayView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        _stockOverlayView.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.72].CGColor;
        _stockOverlayView.layer.shadowColor = [UIColor ppShadow].CGColor;
        _stockOverlayView.layer.shadowOpacity = 0.045;
        _stockOverlayView.layer.shadowOffset = CGSizeMake(0, 7);
        _stockOverlayView.layer.shadowRadius = 16;
        _stockOverlayView.clipsToBounds = NO;
        [self.contentView addSubview:_stockOverlayView];
        [NSLayoutConstraint activateConstraints:@[
            [_stockOverlayView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
            [_stockOverlayView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],
            [_stockOverlayView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_stockOverlayView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16]
        ]];
        
        self.circleView = [self pp_circleShadowView];
        self.circleView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.circleView];

        
        
        // Initialize subviews (avatar, labels, and buttons)
        _avatarImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"placeholder"]];
        _avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
        
        _avatarImageView.clipsToBounds = YES;
        _avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarImageView.tintColor = AppPrimaryClr;  // use app's primary color for default avatar
        
        _titleLabel = [[PaddedLabel alloc] init];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:16]];
        _titleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        // Default appearance to ensure visibility
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.textColor = [UIColor ppTextPrimary];
        _titleLabel.adjustsFontForContentSizeCategory = YES;
        _titleLabel.backgroundColor = UIColor.clearColor;
#ifdef DEBUG
        // Temporary visual debug: translucent yellow background and thin red border
        //_titleLabel.backgroundColor = [[UIColor ppWarning] colorWithAlphaComponent:0.20];
        //_titleLabel.layer.borderColor = [UIColor ppError].CGColor;
        //_titleLabel.layer.borderWidth = 0.6;
#endif
        
        _subtitleLabel = [[PaddedLabel alloc] init];
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontMedium:14]];
        _subtitleLabel.textColor = SeconderyTextClr;
        _subtitleLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;
        
        _detailLabel = [[PaddedLabel alloc] init];
        _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _detailLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:[Styling fontMedium:12]];
        _detailLabel.textColor = [UIColor ppTextSecondary];
        _detailLabel.textAlignment = Language.alignmentForCurrentLanguage;
        _detailLabel.numberOfLines = 1;
        _detailLabel.adjustsFontForContentSizeCategory = YES;

        [self.contentView addSubview:_detailLabel];
        
        // Use custom button subclass that auto-shows/hides based on image
        _firstButton = [PPCellImageButton buttonWithType:UIButtonTypeSystem];
        _firstButton.translatesAutoresizingMaskIntoConstraints = NO;
        _firstButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _firstButton.hidden = YES;  // hidden until an image is set
        [_firstButton addTarget:self action:@selector(onTapFirstButton) forControlEvents:UIControlEventTouchUpInside];
        
        _secondButton = [PPCellImageButton buttonWithType:UIButtonTypeSystem];
        _secondButton.translatesAutoresizingMaskIntoConstraints = NO;
        _secondButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _secondButton.hidden = YES; // hidden until an image is set
        [_secondButton addTarget:self action:@selector(onTapSecondButton) forControlEvents:UIControlEventTouchUpInside];
        
        // (Optional) Attach a tap animation to the second button for visual feedback
        [PPButtonHelper attachTapAnimationToButton:_secondButton style:PPButtonAnimationStylePulse];
        // Add subviews to the content view
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_subtitleLabel];
        [self.contentView addSubview:_firstButton];
        [self.contentView addSubview:_secondButton];
       
        // Define layout constants
        CGFloat pad = 12.0;             // standard padding
        CGFloat avatarSize = 60.0;      // avatar image view size
        CGFloat buttonSize = 36.0;      // width/height for buttons
        CGFloat doubleButtonPad = 25.0; // trailing padding when two buttons are visible
        CGFloat labelToButtonSpacing = 50.0; // spacing between label and button
        _avatarImageView.layer.cornerRadius = avatarSize/2;
        // Activate static constraints for avatar and labels
        
        [NSLayoutConstraint activateConstraints:@[
            // Avatar position and size
            
            [_circleView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:28],
            [_circleView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_circleView.widthAnchor constraintEqualToConstant:avatarSize],
            [_circleView.heightAnchor constraintEqualToConstant:avatarSize],
            
        ]];
        
        [self.circleView addSubview:_avatarImageView];

        
        [NSLayoutConstraint activateConstraints:@[
            // Avatar position and size
            
                [_avatarImageView.centerYAnchor constraintEqualToAnchor:self.circleView.centerYAnchor],
                [_avatarImageView.centerXAnchor constraintEqualToAnchor:self.circleView.centerXAnchor],
                [_avatarImageView.widthAnchor constraintEqualToConstant:avatarSize],
                [_avatarImageView.heightAnchor constraintEqualToConstant:avatarSize],
                
                // Title label position
                [_titleLabel.leadingAnchor constraintEqualToAnchor:_circleView.trailingAnchor constant:12],
                [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:pad + 5],
                
                // Subtitle label position
                [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
                [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:10],
                
                // Detail label position (👈 NEW)
                [_detailLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
                [_detailLabel.topAnchor constraintEqualToAnchor:_subtitleLabel.bottomAnchor constant:2],
                
                // Pin detail to bottom instead of subtitle
                [_detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-24],
                [_detailLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-pad],
                
                [_subtitleLabel.heightAnchor constraintEqualToConstant:26.0],
                
        ]];
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:avatarSize+40].active = YES;
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-24].active = YES;
        [_titleLabel.heightAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;
      
        
        _suplabelTrailingToContent    = [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.trailingAnchor constant:-doubleButtonPad];
        _suplabelTrailingToFirst      = [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_firstButton.leadingAnchor constant:-labelToButtonSpacing];
        _suplabelTrailingToSecond   = [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_secondButton.leadingAnchor constant:-labelToButtonSpacing];
        // Match subtitle trailing to give space for accessory buttons
        _suplabelTrailingToContent.constant = -24.0;
        
        
        
        _firstTrailingToContent    = [_firstButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad];
        _secondTrailingToContent   = [_secondButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-pad];
        _firstTrailingToSecondTrailing = [_firstButton.trailingAnchor constraintEqualToAnchor:_secondButton.trailingAnchor constant:-(doubleButtonPad * 2)];
        _secondTrailingToContentDouble = [_secondButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-doubleButtonPad];
        
        NSLayoutConstraint *firstButtonWidth  = [_firstButton.widthAnchor constraintEqualToConstant:buttonSize];
        NSLayoutConstraint *firstButtonHeight = [_firstButton.heightAnchor constraintEqualToConstant:buttonSize];
        NSLayoutConstraint *secondButtonWidth  = [_secondButton.widthAnchor constraintEqualToConstant:buttonSize];
        NSLayoutConstraint *secondButtonHeight = [_secondButton.heightAnchor constraintEqualToConstant:buttonSize];
        // Activate size and initial position constraints for buttons, and a default trailing constraint for title
        [NSLayoutConstraint activateConstraints:@[
            firstButtonWidth, firstButtonHeight,
            secondButtonWidth, secondButtonHeight,
            // Vertically center buttons to align with avatar & text
            [_firstButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_secondButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            // Initially place both buttons at trailing with default padding (overlapping, since both are hidden)
            _firstTrailingToContent,
            _secondTrailingToContent,
            // Ensure title label does not extend beyond content padding
         ]];
        
        
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // Reset texts and stored data
    
   
    self.contentView.backgroundColor=UIColor.clearColor;
    self.stockOverlayView.hidden = NO;
    self.stockOverlayView.backgroundColor = [UIColor ppElevatedSurface];
    self.stockOverlayView.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.72].CGColor;
    _detailLabel.numberOfLines = 1;
    _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_detailLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                    forAxis:UILayoutConstraintAxisHorizontal];
    
    
    self.avatarImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.titleLabel.text = @"";
    self.subtitleLabel.text = @"";
    self.cellUser = nil;
    self.representedUID = nil;
    // Clear images on buttons (the PPCellImageButton subclass will auto-hide them)
    [self.firstButton setImage:nil forState:UIControlStateNormal];
    [self.secondButton setImage:nil forState:UIControlStateNormal];
    
}

- (void)configureWithUser:(UserModel *)user indexPath:(NSIndexPath *)indexPath {
    self.cellUser = user;
    self.indexPath = indexPath;
    self.representedUID = user.uid;
    
    // Set title and subtitle from the UserModel
    self.titleLabel.text = user.UserName.length ? user.UserName : (user.UserEmail ?: @"");
    NSString *email = ([user.UserEmail isKindOfClass:NSString.class] ? user.UserEmail : @"");
    NSString *mobile = ([user.MobileNo isKindOfClass:NSString.class] ? user.MobileNo : @"");
    if (email.length && mobile.length) {
        // Show both email and mobile, separated by a bullet
        self.subtitleLabel.text = [NSString stringWithFormat:@"%@  •  %@", email, mobile];
    } else {
        // Show whichever is available (email or mobile, or empty string if none)
        self.subtitleLabel.text = email.length ? email : mobile;
    }
    
    // Apply default styling to buttons (tint color, background, etc.)
    self.firstButton.tintColor = SeconderyTextClr;
    self.secondButton.tintColor = SeconderyTextClr;
    [Styling applyIconButtonStyle:self.firstButton tintColor:SeconderyTextClr backgroundColor:AppBackgroundClr];
    [Styling applyIconButtonStyle:self.secondButton tintColor:SeconderyTextClr backgroundColor:AppBackgroundClr];
    self.stockOverlayView.hidden = YES;
    self.stockOverlayView.backgroundColor = UIColor.clearColor;
    // (Images for the buttons are set from outside this class; by default buttons remain hidden until an image is assigned)
}

- (void)layoutSubviews {
    [super layoutSubviews];

    BOOL firstVisible  = !self.firstButton.hidden;
    BOOL secondVisible = !self.secondButton.hidden;

    // Reset dynamic constraints
    _firstTrailingToContent.active = NO;
    _secondTrailingToContent.active = NO;
    _firstTrailingToSecondTrailing.active = NO;
    _secondTrailingToContentDouble.active = NO;

 
    _suplabelTrailingToFirst.active = NO;
    _suplabelTrailingToSecond.active = NO;

    // Keep "content" trailing constraints always active (max width cap)
 
    if (firstVisible && secondVisible) {
        _firstTrailingToSecondTrailing.active = YES;
        _secondTrailingToContentDouble.active = YES;

         _suplabelTrailingToFirst.active = YES;
    } else if (firstVisible) {
        _firstTrailingToContent.active = YES;
        _secondTrailingToContent.active = YES;

         _suplabelTrailingToFirst.active = YES;
    } else if (secondVisible) {
        _firstTrailingToContent.active = YES;
        _secondTrailingToContent.active = YES;

         _suplabelTrailingToSecond.active = YES;
    } else {
        _firstTrailingToContent.active = YES;
        _secondTrailingToContent.active = YES;
    }

    // ✅ Z-order: overlay must always be behind
    [self.contentView sendSubviewToBack:self.stockOverlayView];

    // ✅ Bring the ACTUAL views to front (avatarImageView is inside circleView!)
    [self.contentView bringSubviewToFront:self.circleView];
    [self.contentView bringSubviewToFront:self.titleLabel];
    [self.contentView bringSubviewToFront:self.subtitleLabel];
    [self.contentView bringSubviewToFront:self.detailLabel];
    [self.contentView bringSubviewToFront:self.firstButton];
    [self.contentView bringSubviewToFront:self.secondButton];

 
}

#pragma mark - Button Tap Handlers

- (void)onTapFirstButton {
    if ([self.delegate respondsToSelector:@selector(cellWithButtons:didTapFirstButtonAtIndexPath:)]) {
        [self.delegate cellWithButtons:self didTapFirstButtonAtIndexPath:self.indexPath];
    }
}

- (void)onTapSecondButton {
    if ([self.delegate respondsToSelector:@selector(cellWithButtons:didTapSecondButtonAtIndexPath:)]) {
        [self.delegate cellWithButtons:self didTapSecondButtonAtIndexPath:self.indexPath];
    }
}


-(void)configureWithItem:(id)model
{
    
    if ([model isKindOfClass:[PetAccessory class]]) {
        PetAccessory *acees = (PetAccessory *)model;
        PPItem *item = [PPItem itemWithPetAccessory:acees firstBtnImageName:nil secBtnImageName:nil];
        
        [self.firstButton setImage:[UIImage systemImageNamed:item.firstButtonImageName] forState:UIControlStateNormal];
        [self.secondButton setImage:[UIImage systemImageNamed:item.secondButtonImageName] forState:UIControlStateNormal];
        
        [Styling applyIconButtonStyle:self.firstButton tintColor:SeconderyTextClr backgroundColor:AppBackgroundClr];
        self.firstButton.layer.shadowRadius = 1;
        self.firstButton.backgroundColor = AppClearClr;
        _avatarImageView.backgroundColor = AppBackgroundClr;
        self.firstButton.tintColor = SeconderyTextClr;
        self.secondButton.tintColor = SeconderyTextClr;
        
        _titleLabel.text = acees.name.length ? acees.name : @"-";
        UIColor *titleColor = [UIColor ppTextPrimary];
#ifdef DEBUG
        // In debug, force a vivid color to help visual debugging
        titleColor = [UIColor ppError];
#endif
        _titleLabel.textColor = titleColor;
        _titleLabel.hidden = NO;
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.alpha = 1.0;
        // Accessibility id for debugging
        _titleLabel.accessibilityIdentifier = @"PPCellWithButtons_title";
        // Ensure title appears above overlays/buttons and force layout
        [self.contentView bringSubviewToFront:_titleLabel];
        [self setNeedsLayout];
        [self layoutIfNeeded];
        //_subtitleLabel.text = item.subtitle.length > 0 ? item.subtitle : @"-";
        
        NSInteger qty = MAX(0, acees.quantity);
        UIColor *overlayColor = nil;
        if (qty <= 0) {
            overlayColor = [[UIColor ppError] colorWithAlphaComponent:0.12];
        } else if (qty <= 5) {
            // Use a subtle foreground overlay for low stock
            overlayColor = [AppForgroundColr colorWithAlphaComponent:1];
        } else {
            overlayColor = [AppForgroundColr colorWithAlphaComponent:1];
        }
         self.stockOverlayView.hidden = NO;
         self.stockOverlayView.backgroundColor = overlayColor;
        
        //_subtitleLabel.textInsets = UIEdgeInsetsMake(8, 18, 8, 18);
        _subtitleLabel.text = [NSString stringWithFormat:@"%@: %ld", kLang(@"Qty"), (long)qty];
       
       
        _subtitleLabel.textColor = qty == 0 ? [UIColor ppTextSecondary] : [UIColor ppTextSecondary];
        _subtitleLabel.backgroundColor = AppClearClr;
        _subtitleLabel.layer.cornerRadius =  13;
        _subtitleLabel.clipsToBounds = YES;

        _detailLabel.text = [NSString stringWithFormat:@"%@ • %@", [PetAccessory typeTextForAccessory:acees], [acees stockStatusText]];
        
        // Debug: log title assignment to help trace missing-title issues
        NSLog(@"[PPCellWithButtons] configureWithItem: set title -> '%@' (accessoryID=%@)", _titleLabel.text ?: @"(nil)", acees.accessoryID ?: @"(no-id)");
 
        
        if (item.imageURLString) {
            [_avatarImageView setImageFromUrl:[NSURL URLWithString:item.imageURLString].absoluteString placeholderImage:@"placeholder" Blr:YES Shimmering:YES completion:^(UIImage *image) {
                
            }];
        } else {
            _avatarImageView.image = [UIImage systemImageNamed:@"placeholder"];
        }
    }
}


// In some helper or directly in your VC
- (UIView *)pp_circleShadowView {
    CGFloat size = 60.0;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
    
    // Rounded full
    v.layer.cornerRadius = size / 2.0;
    v.clipsToBounds = NO; // keep shadow visible
    v.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];
    v.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    v.layer.borderColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.18].CGColor;
    
    // Shadow
    v.layer.shadowColor = [UIColor ppShadow].CGColor;
    v.layer.shadowOpacity = 0.06;
    v.layer.shadowOffset = CGSizeMake(0, 4);
    v.layer.shadowRadius = 12.0;
    
    // Optional: improve shadow performance
    v.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:v.bounds].CGPath;
    v.layer.shouldRasterize = YES;
    v.layer.rasterizationScale = UIScreen.mainScreen.scale;
    
    return v;
}



@end
