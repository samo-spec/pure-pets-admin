//
//  QBAlbumCell.m
//  QBImagePicker
//
//  Created by Katsuma Tanaka on 2015/04/03.
//  Copyright (c) 2015 Katsuma Tanaka. All rights reserved.
#import "QB.h"
 
@interface AddButtonCell ()
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@end

@implementation AddButtonCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.contentView.clipsToBounds = YES;
    self.contentView.layer.cornerRadius = 12;

    [self setupBackground];
    [self setupButton];

    return self;
}

-(void)prepareForReuse
{
    [super prepareForReuse];
    self.onTap = nil;
    if (@available(iOS 14.0, *)) {
        self.addButton.menu = nil;
        self.addButton.showsMenuAsPrimaryAction = NO;
    }
}

#pragma mark - Background (Glass / Blur)

- (void)setupBackground {
    if (@available(iOS 26.0, *)) {
        // iOS 16+ → Use glass material
         
//
    } else {
        // Earlier iOS → Use blur
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight];
        self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        self.blurView.layer.cornerRadius = 12;
        self.blurView.clipsToBounds = YES;

        self.blurView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.blurView];

        [NSLayoutConstraint activateConstraints:@[
            [self.blurView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.blurView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [self.blurView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.blurView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]
        ]];
    }
}

#pragma mark - Button

- (void)setupButton {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) {
        config = [UIButtonConfiguration tintedButtonConfiguration];
        config.cornerStyle = UIButtonConfigurationCornerStyleFixed;
     } else {
        config = [UIButtonConfiguration plainButtonConfiguration];
    }
    config.background.cornerRadius = 12;
    config.background.backgroundColor = [PPColorUtils pp_selectedCellColorFromPrimary];
    config.baseBackgroundColor = [PPColorUtils pp_selectedCellColorFromPrimary];
    config.image = [UIImage systemImageNamed:@"photo.badge.plus"];
    config.imagePadding = 6;
    config.contentInsets = NSDirectionalEdgeInsetsMake(0, 0,0, 0);
    UIImageSymbolConfiguration *palette =
        [UIImageSymbolConfiguration configurationWithPaletteColors:@[
            AppPrimaryTextClr,
            [AppPrimaryClr colorWithAlphaComponent:1.1]
        ]];

    UIImageSymbolConfiguration *size =
        [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];

    // Combine configurations
    UIImageSymbolConfiguration *finalConfig =
        [palette configurationByApplyingConfiguration:size];

    config.preferredSymbolConfigurationForImage = finalConfig;
    if(!self.addButton)
    {
        self.addButton = [UIButton buttonWithConfiguration:config primaryAction:nil];
        self.addButton.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.addButton];
    }
    else
    {
        self.addButton.configuration = config;
    }
   
    [self.addButton removeTarget:self
                          action:@selector(tapAction)
                forControlEvents:UIControlEventTouchUpInside];
    [self.addButton addTarget:self
                       action:@selector(tapAction)
             forControlEvents:UIControlEventTouchUpInside];
    self.addButton.layer.cornerRadius = 12;
    

    [NSLayoutConstraint activateConstraints:@[
        [self.addButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.addButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [self.addButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.addButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor]
     ]];
}

#pragma mark - Configuration

- (void)setButtonTitle:(NSString *)title {
    if (!title) return;
    UIButtonConfiguration *cfg = self.addButton.configuration;
    cfg.title = title;
    self.addButton.configuration = cfg;
}

- (void)setButtonSymbol:(NSString *)symbol {
    if (!symbol) return;
    UIButtonConfiguration *cfg = self.addButton.configuration;
    cfg.image = [UIImage systemImageNamed:symbol];
    self.addButton.configuration = cfg;
}

#pragma mark - Tap

- (void)tapAction {
    if (@available(iOS 14.0, *)) {
        if (self.addButton.showsMenuAsPrimaryAction && self.addButton.menu != nil) {
            return;
        }
    }
    if (self.onTap) self.onTap();
}

- (void)setPrimaryMenu:(UIMenu *)menu
{
    if (@available(iOS 14.0, *)) {
        self.addButton.menu = menu;
        self.addButton.showsMenuAsPrimaryAction = (menu != nil);
    }
}

@end














 
@interface PP_ImageCell ()
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *bgButton;
@end

@implementation PP_ImageCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.contentView.clipsToBounds = NO;
    
    _bgButton = [PPNavigationController setButtonAsBackroundButtonWithStyle:UIButtonConfigurationCornerStyleFixed configType:PPButtonConfigrationGlass];
    _bgButton.configuration.background.cornerRadius = 12;
    _bgButton.layer.cornerRadius = 12;
    [self.contentView addSubview:_bgButton];
    _bgButton.layer.cornerRadius = 16;
    _bgButton.layer.masksToBounds = YES;
    
    [NSLayoutConstraint activateConstraints:@[
        [_bgButton.widthAnchor constraintEqualToAnchor:self.contentView.heightAnchor],
        [_bgButton.heightAnchor constraintEqualToAnchor:self.contentView.heightAnchor],
        [_bgButton.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0],
        [_bgButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-0]
    ]];
    
    [_bgButton addTarget:self action:@selector(trigerTap) forControlEvents:UIControlEventTouchUpInside];
    
    [self setupImageView];
    [self setupDeleteButton];

    return self;
}

- (void)trigerTap
{
    if (self.onTap) self.onTap();
}
#pragma mark - Setup UI

- (void)setupImageView {
    _imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.clipsToBounds = YES;
    _imageView.layer.cornerRadius = 12;
    [_bgButton addSubview:_imageView];

    [NSLayoutConstraint activateConstraints:@[
        [_imageView.topAnchor constraintEqualToAnchor:self.bgButton.topAnchor],
        [_imageView.bottomAnchor constraintEqualToAnchor:self.bgButton.bottomAnchor],
        [_imageView.leadingAnchor constraintEqualToAnchor:self.bgButton.leadingAnchor],
        [_imageView.trailingAnchor constraintEqualToAnchor:self.bgButton.trailingAnchor]
    ]];
}

- (void)setupDeleteButton {
    UIButtonConfiguration *cfg;

  
   
    _deleteButton.hidden = NO;
    
    _deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _deleteButton.translatesAutoresizingMaskIntoConstraints = NO;

    _deleteButton.backgroundColor = [AppForgroundColr colorWithAlphaComponent:1];
    _deleteButton.tintColor = AppPrimaryClr;
    [_bgButton addSubview:_deleteButton];
    
    
    [NSLayoutConstraint activateConstraints:@[
        [_deleteButton.widthAnchor constraintEqualToConstant:22],
        [_deleteButton.heightAnchor constraintEqualToConstant:22],
        [_deleteButton.topAnchor constraintEqualToAnchor:self.bgButton.topAnchor constant:6],
        [_deleteButton.trailingAnchor constraintEqualToAnchor:self.bgButton.trailingAnchor constant:-6]
    ]];
    [_deleteButton setImage:PPSYSImage(@"multiply") forState:UIControlStateNormal];

    [_deleteButton addTarget:self action:@selector(deletePressed)
            forControlEvents:UIControlEventTouchUpInside];

    _deleteButton.layer.cornerRadius = 11;
    _deleteButton.clipsToBounds = YES;
  
}

#pragma mark - Public API

- (void)configureWithImage:(UIImage *)image {
    self.imageView.image = image;
}

- (void)setDeleteVisible:(BOOL)visible {
    self.deleteButton.hidden = !visible;
}

#pragma mark - Delete

- (void)deletePressed {
    if (self.onDelete) self.onDelete();
}

#pragma mark - Reuse safety

- (void)prepareForReuse {
    [super prepareForReuse];
    self.imageView.image = nil;
    self.onDelete = nil;
    self.onTap = nil;
    self.deleteButton.hidden = NO;
}

@end




