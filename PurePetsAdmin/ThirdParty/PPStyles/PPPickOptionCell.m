//
//  PPPickOptionCell 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 26/08/2025.
//


// In PPPickOptionCell.m
// In PPPickOptionCell.m
#import "PPPickOptionCell.h"
#import "PPItem.h"
#import "Styling.h"
#import "Language.h"
#import "PPButtonHelper.h"
#ifndef DLog
#define DLog(fmt, ...) NSLog((@"[PPLOG][PPPickOptionCell] %s: " fmt), __FUNCTION__, ##__VA_ARGS__);
#endif

NSString * const XLFormRowDescriptorTypePickOption = @"XLFormRowDescriptorTypePickOption";


@interface PPPickOptionCell ()
@property (nonatomic, strong) UserModel *rowUserModel;
@end



@implementation PPPickOptionCell
@dynamic rowDescriptor;

+ (void)load {
    // Register custom type
    [XLFormViewController.cellClassesForRowDescriptorTypes setObject:self
                                                              forKey:XLFormRowDescriptorTypePickOption];
}

#pragma mark - Configure

- (void)configure {
    [super configure];
    [self updateCellLayout];
}

- (void)didTapMore {
    
}

// In PPPickOptionCell.m (recommended)
// Guard against reuse artifacts

- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedUID = nil;
    self.optionImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    self.optionImageView.alpha = 0.6f;
    // Remove handlers if you attach any directly to subviews here
}


- (void)updateCellLayout
{
    self.selectionStyle = UITableViewCellSelectionStyleNone;
     
    if(!_pickImage)
    {
        _pickImage = [UIImage pp_symbolNamed:Language.isRTL ? @"chevron.forward" : @"chevron.backward" pointSize:18 weight:UIImageSymbolWeightMedium scale:UIImageSymbolScaleDefault palette:@[UIColor.lightGrayColor,UIColor.lightGrayColor] makeTemplate:YES];
    }
    // in -updateCellLayout
   
    CGFloat imageSize = 50;

    _imageLoaded = NO;
    // option image
    if (!_optionImageView) {
        _optionImageView = [[UIImageView alloc] init];
        _optionImageView.contentMode = UIViewContentModeScaleAspectFill;
        _optionImageView.layer.cornerRadius = imageSize / 2;
        _optionImageView.clipsToBounds = YES;
        _optionImageView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.06];
        _optionImageView.image = [UIImage systemImageNamed:@"person.crop.circle.fill"];
        [self.contentView addSubview:_optionImageView];
    }
    
    [_optionImageView pp_applyDefualtGuardianWithRadius:25.0];

    self.textLabel.font = [Styling fontMedium:18];
    self.textLabel.textColor = PrimaryTextClr;
    self.textLabel.textAlignment = Language.alignmentForCurrentLanguage;
    [self.contentView addSubview:self.textLabel];
    
    // pick button
    if (!_pickButton) {
        _pickButton = [PPAdminButton buttonWithType:UIButtonTypeSystem];
        _pickButton.tintColor = AppPrimaryClr;
        _pickButton.layer.cornerRadius = 22;
        _pickButton.clipsToBounds = YES;
        [_pickButton setImage:_pickImage
                     forState:UIControlStateNormal];
        [_pickButton addTarget:self action:@selector(didTapPick) forControlEvents:UIControlEventTouchUpInside];
        [PPButtonHelper attachTapAnimationToButton:_pickButton style:PPButtonAnimationStyleDefault];
        [self.contentView addSubview:_pickButton];
    }  // person.fill.badge.plus // person.crop.circle.fill.badge.plus // person.crop.circle.fill.badge.plus

    
    // More Button
    if (!_moreButton) {
        _moreButton = [PPAdminButton buttonWithType:UIButtonTypeSystem];
        _moreButton.tintColor = AppPrimaryClr;
        _moreButton.layer.cornerRadius = 22;
        _moreButton.hidden = YES;
        _moreButton.clipsToBounds = YES;
        [_moreButton setImage:[UIImage pp_symbolNamed:@"ellipsis" pointSize:18 weight:UIImageSymbolWeightMedium scale:UIImageSymbolScaleDefault palette:@[AppPrimaryClr,AppPrimaryClrShiner] makeTemplate:YES] forState:UIControlStateNormal];
        [_moreButton addTarget:self action:@selector(didTapMore) forControlEvents:UIControlEventTouchUpInside];
        [PPButtonHelper attachTapAnimationToButton:_moreButton style:PPButtonAnimationStylePulse];
        [self.contentView addSubview:_moreButton];
    }  // person.fill.badge.plus // person.crop.circle.fill.badge.plus // person.crop.circle.fill.badge.plus

    if (!_adminBadgeContainer) {
            _adminBadgeContainer = [UIView new];
            _adminBadgeContainer.backgroundColor = UIColor.yellowColor;
            _adminBadgeContainer.layer.cornerRadius = 10;
            _adminBadgeContainer.layer.shadowColor = UIColor.blackColor.CGColor;
            _adminBadgeContainer.layer.shadowOpacity = 0.15;
            _adminBadgeContainer.layer.shadowOffset = CGSizeMake(0, 1);
            _adminBadgeContainer.layer.shadowRadius = 2;
            _adminBadgeContainer.hidden = YES;
            [self.contentView addSubview:_adminBadgeContainer];
            
            // Crown icon
            _adminBadgeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"crown.fill"]];
            _adminBadgeIcon.tintColor = UIColor.systemYellowColor;
            [_adminBadgeContainer addSubview:_adminBadgeIcon];
            
            // Text label
            _adminBadgeLabel = [UILabel new];
            _adminBadgeLabel.text = kLang(@"AdminBadge");
            _adminBadgeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
            _adminBadgeLabel.textColor = UIColor.blackColor;
            _adminBadgeLabel.textAlignment = Language.alignmentForCurrentLanguage;
            [_adminBadgeContainer addSubview:_adminBadgeLabel];
            
          
        }
    
    self.detailTextLabel.font = [Styling fontRegular:16];
    self.detailTextLabel.textColor = SeconderyTextClr;
    self.detailTextLabel.textAlignment = Language.alignmentForCurrentLanguage;
    
    [self updateCellLayoutFrames];

    self.showPickButton = YES;
    self.showOptionImage = YES;
}

-(void)updateCellLayoutFrames
{
    CGFloat imageSize = 50;
    CGFloat contentWidth = self.contentView.hxw;
    BOOL isRTL = (Language.languageVal == 1);
    CGFloat buttonWidth = 44;
    if (!isRTL) {
        // ===== LTR =====
        
        _optionImageView.hxFrame = CGRectMake(10,
                                              (self.contentView.hxh - imageSize) / 2.0,
                                              imageSize,
                                              imageSize);

        UIButton *TempButton = _pickButton;
        TempButton = self.reverseButtonAlign ? _moreButton : _pickButton;
        TempButton.hxFrame = CGRectMake(contentWidth - 10 - 40,
                                         (self.contentView.hxh - buttonWidth) / 2.0,
                                         buttonWidth,
                                         buttonWidth);
        
        TempButton = self.reverseButtonAlign ? _pickButton : _moreButton;
        _moreButton.hxFrame = CGRectMake(_pickButton.hxx - 40 - 10,
                                         (self.contentView.hxh - buttonWidth) / 2.0,
                                         buttonWidth,
                                         buttonWidth);

        CGFloat textStart = _optionImageView.hxmax + 8;

        self.textLabel.hxFrame = CGRectMake(textStart,
                                            12,
                                            _moreButton.hxx - textStart - 8,
                                            self.detailTextLabel.text.length > 0 ? 20.0 : self.contentView.hxh - 24);

        self.detailTextLabel.hxFrame = CGRectMake(textStart,
                                                  self.textLabel.hxmaxy + 0,
                                                  _moreButton.hxx - textStart - 12,
                                                  18);

        // Admin badge pinned bottom-right of optionImageView
        _adminBadgeContainer.hxFrame = CGRectMake(_optionImageView.hxmax - 6,
                                                  _optionImageView.hxmaxy - 6,
                                                  0,
                                                  18);
    } else {
        // ===== RTL =====
        _optionImageView.hxFrame = CGRectMake(contentWidth - 10 - imageSize,
                                              (self.contentView.hxh - imageSize) / 2.0,
                                              imageSize,
                                              imageSize);
        UIButton *TempButton = _pickButton;
        TempButton = self.reverseButtonAlign ? _moreButton : _pickButton;
       
        TempButton.hxFrame = CGRectMake(10,
                                         (self.contentView.hxh - buttonWidth) / 2.0,
                                         buttonWidth,
                                         buttonWidth);
        
        TempButton = self.reverseButtonAlign ? _pickButton : _moreButton;
        TempButton.hxFrame = CGRectMake(self.reverseButtonAlign ? (_moreButton.hxmax + 10) : (_pickButton.hxmax + 10)   ,
                                         (self.contentView.hxh - buttonWidth) / 2.0,
                                         buttonWidth,
                                         buttonWidth);


        CGFloat textEnd = _optionImageView.hxx - 10; // space before image

        self.textLabel.hxFrame = CGRectMake(_moreButton.hxmax + 8,
                                            12,
                                            textEnd - (_moreButton.hxmax + 8),
                                            self.detailTextLabel.text.length > 0 ? 20.0 : self.contentView.hxh - 24);

        self.detailTextLabel.hxFrame = CGRectMake(_moreButton.hxmax + 8,
                                                  self.textLabel.hxmaxy + 3,
                                                  textEnd - (_moreButton.hxmax + 8),
                                                  18);

        // Admin badge pinned bottom-left of optionImageView (mirror)
        _adminBadgeContainer.hxFrame = CGRectMake(_optionImageView.hxx - _adminBadgeContainer.hxw + 6,
                                                  _optionImageView.hxmaxy - 6,
                                                  0,
                                                  18);
        
    }

    // ===== Badge inner layout (same both directions) =====
    CGFloat badgeH = 18;
    CGFloat iconSize = 12;
    _adminBadgeIcon.hxFrame = CGRectMake(4,
                                         (badgeH - iconSize) / 2.0,
                                         iconSize,
                                         iconSize);

    CGFloat labelX = _adminBadgeIcon.hxmax + 2;
    CGSize labelSize = [_adminBadgeLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, badgeH)];
    _adminBadgeLabel.hxFrame = CGRectMake(labelX,
                                          (badgeH - labelSize.height) / 2.0,
                                          labelSize.width,
                                          labelSize.height);

    _adminBadgeContainer.hxw = _adminBadgeLabel.hxmax + 4;
    
    
    self.textLabel.font = [Styling fontRegular:16];
    self.detailTextLabel.font = [Styling fontRegular:14];
}

#pragma mark - Update

- (void)update {
    [super update];
    
    // Localized default title
    self.textLabel.text = self.rowDescriptor.title.length ? self.rowDescriptor.title : kLang(@"Select User");
    
    
    // KVC/XIB-provided system name takes priority
    NSString *symbol = self.pickButtonSystemName;
    if (!symbol.length) {
        symbol = [self safeConfigForKey:@"pickButtonSystemName"];
    }
    UIImage *icon = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
    [_pickButton setImage:(icon ?: _pickImage)
                 forState:UIControlStateNormal];
    
    
    
    NSString *moreSymbol = self.moreButtonSystemName;
    if (!moreSymbol.length) {
        moreSymbol = [self safeConfigForKey:@"moreButtonSystemName"];
    }
    UIImage *moreButtonIcon = moreSymbol.length ? [UIImage systemImageNamed:moreSymbol] : nil;
    [_moreButton setImage:(moreButtonIcon ?: nil)
                 forState:UIControlStateNormal];
    
    
    // Toggle visibility from config
    id rawShowBtn = [self safeConfigForKey:@"showPickButton"];
    if (rawShowBtn) self.showPickButton = [rawShowBtn boolValue];

    id rawShowImg = [self safeConfigForKey:@"showOptionImage"];
    if (rawShowImg) self.showOptionImage = [rawShowImg boolValue];
    
    
    // Toggle visibility from config
    id rawReverseButtonAlign = [self safeConfigForKey:@"reverseButtonAlign"];
    if (rawReverseButtonAlign) self.reverseButtonAlign = [rawReverseButtonAlign boolValue];

    // RTL/LTR
    self.contentView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.textLabel.textAlignment = Language.alignmentForCurrentLanguage;

    // Inline block from config (optional)
    id pickBlock = [self safeConfigForKey:@"onPickTap"];
    if (pickBlock && [pickBlock isKindOfClass:NSClassFromString(@"NSBlock")]) {
        self.onPickTap = pickBlock;
    }
    
    id value = self.rowDescriptor.value;
    [self applyValueToOptionImage:value];
    
    
    id titleStringValue = [self safeConfigForKey:@"titleString"];
    if(titleStringValue){
        NSString *titleString = (NSString *)titleStringValue;
        self.textLabel.text = titleString;
    }
    
    
    if(self.rowUserModel)
    {
        
        self.textLabel.text =
            PPStringOrNil(self.rowUserModel.UserName) ?:
            PPStringOrNil(self.rowUserModel.FirstName) ?:
            PPStringOrNil(self.rowUserModel.LastName) ?:
            kLang(@"user");
        
        
        self.detailTextLabel.text = self.rowUserModel.UserEmail ?: self.rowUserModel.MobileNo ?: self.rowUserModel.uid ?: self.rowUserModel.ID;

    }
    
}

-(void)setUserModelToCell:(UserModel *)userModel
{
    if(self.rowUserModel) { return; }
    //DLog(@"[setUserModelToCell] image result is : %@", userModel.UserName );
    self.rowDescriptor.value = userModel;
    self.rowUserModel = userModel;
    [self update];
    
}

#pragma mark - Apply value

- (void)applyValueToOptionImage:(id)value {
    if (self.showOptionImage == NO) { return; }
   // if (self.imageLoaded == YES) { return; }

    __weak typeof(self) weakSelf = self;
    // Fallback placeholder
    UIImage *placeholder = [UIImage systemImageNamed:@"person.crop.circle.fill"];
    BOOL isAdmin = NO;

    if ([value isKindOfClass:UserModel.class]) {
        //DLog(@"[PPUpdateRow][isKindOfClass][UserModel]");
        UserModel *user = (UserModel *)value;
        isAdmin = user.isAdmin;

        

        self.detailTextLabel.text = user.UserEmail ?: user.MobileNo ?: user.uid ?: user.ID ?: @"";
        self.textLabel.text = user.UserName ?: user.FirstName ?: user.LastName ?:@"";
        
        
        [_optionImageView setImageFromUrl:user.UserImageUrl.absoluteString placeholderImage:@"Profile5" completion:^(UIImage *image) {
            //DLog(@"[PPUpdateRow] image result is : %@", image? @"image done " : @"no Image");
           // weakify(self);
            weakSelf.optionImageView.image = image;
            weakSelf.adminBadgeContainer.hidden = !isAdmin;
        }];
        
        
        return;
    }
   
    if ([value isKindOfClass:PPItem.class]) {
        //DLog(@"[PPUpdateRow][isKindOfClass][PPItem]");
        PPItem *it = (PPItem *)value;
        if (it.title.length && (!self.rowDescriptor.title.length || [self.rowDescriptor.title isEqualToString:kLang(@"Select User")])) {
            // If title is default, show item's title
            self.textLabel.text = it.title;
        }
        if (it.image) {
           //DLog(@"[PPUpdateRow][PPItem][image]");
            _optionImageView.image = it.image;
            return;
        }
        if (it.imageName.length) {
           // DLog(@"[PPUpdateRow][PPItem][imageName]");
            UIImage *img = [UIImage imageNamed:it.imageName];
            _optionImageView.image = img ?: placeholder;
            return;
        }
        if (it.imageURLString.length) {
           // DLog(@"[PPUpdateRow][PPItem][imageURLString]");
                [_optionImageView setImageFromUrl:it.imageURLString placeholderImage:@"Profile" completion:^(UIImage *image) {
                 //   DLog(@"[PPUpdateRow] image result is : %@", image? @"image done " : @"no Image");
                    weakSelf.image = image;
                    weakSelf.imageLoaded = YES;
                }];
               
                return;
        }
        //_optionImageView.image = placeholder;
        return;
    }

   

    //_optionImageView.image = placeholder;
}

#pragma mark - Toggles

- (void)setShowPickButton:(BOOL)showPickButton {
    _showPickButton = showPickButton;
    _pickButton.hidden = !showPickButton;
}

- (void)setShowOptionImage:(BOOL)showOptionImage {
    _showOptionImage = showOptionImage;
    _optionImageView.hidden = !showOptionImage;
}

#pragma mark - Helpers

- (id)safeConfigForKey:(NSString *)key {
    return self.rowDescriptor.cellConfig[key] ?: self.rowDescriptor.cellConfigAtConfigure[key];
}

#pragma mark - Actions

- (void)didTapPick {
    DLog(@"didTapPick");
    if (self.onPickTap) { self.onPickTap(self.rowDescriptor); return; }
    if (self.delegate && [self.delegate respondsToSelector:@selector(pickOptionCellDidTapPick:)]) {
        [self.delegate pickOptionCellDidTapPick:self.rowDescriptor];
        return;
    }
    if (self.rowDescriptor.onChangeBlock) {
        self.rowDescriptor.onChangeBlock(self.rowDescriptor.value, self.rowDescriptor.value, self.rowDescriptor);
    }
}

#pragma mark - KVC safety

- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
    // Swallow unknown XIB runtime attributes to avoid NSUnknownKeyException
    DLog(@"Ignored undefined KVC key: %@ (value=%@)", key, value);
}

// In PPPickOptionCell.m
- (id)valueForUndefinedKey:(NSString *)key {
    DLog(@"Ignored valueForUndefinedKey: %@", key);
    return nil; // returning nil lets 'textField.placeholder' be ignored safely
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    [self updateCellLayoutFrames];
}

@end
