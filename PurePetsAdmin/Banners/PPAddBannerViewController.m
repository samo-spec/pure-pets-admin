//
//  PPAddBannerViewController 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 09/09/2025.
//


//  PPAddBannerViewController.m
//  PurePetsAdmin

#import "PPAddBannerViewController.h"
#import "PPBannersManager.h"
#import "MainBannerModel.h"
#import "PPBannerViewModel.h"
#import "AlertHelper.h"

@import Photos;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
// MARK: - Row tags
static NSString * const kRowGroupID       = @"groupID";
static NSString * const kRowVisible       = @"visible";
static NSString * const kRowHolder        = @"holder";
static NSString * const kRowPosition      = @"position";
static NSString * const kRowTransaction   = @"transaction";

static NSString * const kRowTitleEn       = @"titleEn";
static NSString * const kRowTitleAr       = @"titleAr";
static NSString * const kRowDescEn        = @"descEn";
static NSString * const kRowDescAr        = @"descAr";
static NSString * const kRowPostDate      = @"postDate";
static NSString * const kRowTextStyle     = @"textStyle";

static NSString * const kRowTapAction     = @"tapAction";
static NSString * const kRowTapValue      = @"tapValue";

static NSString * const kRowValidDays     = @"validDays";
static NSString * const kRowValidHours    = @"validHours";
static NSString * const kRowValidMins     = @"validMins";
static NSString * const kRowExpireDT      = @"expireDateTime";

static NSString * const kRowBGPhoto       = @"bgPhoto";
static NSString * const kRowSamplePhoto   = @"samplePhoto";
static NSString * const kRowBadgePhoto    = @"badgePhoto";
static NSString * const kPPAdminHomeTopCarouselGroupID = @"HOME_MAIN_TOP_CAROUSEL";

@interface PPAddBannerViewController ()
@end

@implementation PPAddBannerViewController

#pragma mark - Init

// Modify your initialization
- (instancetype)initWithEditMode:(PPEditMode)editMode
                            group:(MainBannerModel *)group
                           banner:(PPBannerViewModel *)banner {
    self = [super initWithForm:[XLFormDescriptor formDescriptor] style:UITableViewStyleInsetGrouped];
    if (self) {
        _editMode = editMode;
        _editingBannerGroup = group;
        _editingBanner = banner;
        self.form = [self buildFormWithModel:group andBanner:banner];
    }
    return self;
}

- (instancetype)initWithMainBanner:(MainBannerModel * _Nullable)banner  {
    return [self initWithEditMode:(banner ? PPEditModeGroupOnly : PPEditModeNewGroup)
                            group:banner
                           banner:nil];
}

- (instancetype)initWithBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group  {
    return [self initWithEditMode:PPEditModeBannerOnly
                            group:group
                           banner:banner];
}

- (instancetype)init {
    return [self initWithEditMode:PPEditModeNewGroup group:nil banner:nil];
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;
    
    
    XLFormSectionDescriptor *section = [self.form formSectionAtIndex:0];
    if(_editMode == PPEditModeAddBannerToGroup)
    {
        [self setSection:section enabled:NO];
    }
    else
    {
        [self setSection:section enabled:YES];
    }
}

#pragma mark - Form

- (void)addGroupSettingsSectionInForm:(XLFormDescriptor *)form MainBannerModel:(MainBannerModel * _Nullable)mainBannerModel {
    // ===== Section A: Group settings =====
    CGFloat rowHeight = 54.0;
    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Group Settings")];
    [form addFormSection:sec];
    
    // Group ID (editable so admin can choose a stable key; optional)
    XLFormRowDescriptor *row =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowGroupID
                                          rowType:XLFormRowDescriptorTypeText
                                            title:kLang(@"Banner Group ID")];
    row.value = PPSafeString(mainBannerModel.bannerViewID);
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"Auto if empty");
    row.height = rowHeight;
    [Styling applyGlobalStyleToRow:row];
    [sec addFormRow:row];
    
    // Visible
    row = [XLFormRowDescriptor formRowDescriptorWithTag:kRowVisible
                                                rowType:XLFormRowDescriptorTypeBooleanSwitch
                                                  title:kLang(@"Visible")];
    row.value = @(mainBannerModel ? mainBannerModel.bannerViewVisible : YES);
    [Styling applyGlobalStyleToRow:row];
    [sec addFormRow:row];
    
    
    
    // Holder
    row = [XLFormRowDescriptor formRowDescriptorWithTag:kRowHolder
                                                rowType:XLFormRowDescriptorTypeSelectorPush
                                                  title:kLang(@"Holder")];
    row.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerHolderMainView)        displayText:kLang(@"Main")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerHolderAccessoriesView) displayText:kLang(@"Accessories")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerHolderAdsView)         displayText:kLang(@"Ads")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerHolderFoodView)        displayText:kLang(@"Food")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerHolderVetsView)        displayText:kLang(@"Vets")]
    ];
    // preselect
    {
        PPBannerHolder hv = mainBannerModel ? mainBannerModel.bannerViewHolder : PPBannerHolderMainView;
        for (XLFormOptionsObject *opt in row.selectorOptions) if ([opt.formValue integerValue]==hv){ row.value = opt; break; }
    }
    row.height = rowHeight;
    row.action.viewControllerClass = [PPOptionsViewController class];
    [Styling applyGlobalStyleToRow:row];
    
    [sec addFormRow:row];
    
    // Position
    row = [XLFormRowDescriptor formRowDescriptorWithTag:kRowPosition
                                                rowType:XLFormRowDescriptorTypeSelectorPush
                                                  title:kLang(@"Position")];
    row.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerPositionTop)    displayText:kLang(@"Top")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerPositionCenter) displayText:kLang(@"Center")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerPositionBottom) displayText:kLang(@"Bottom")]
    ];
    {
        PPBannerPosition pos = mainBannerModel ? mainBannerModel.bannerViewPosition : PPBannerPositionTop;
        for (XLFormOptionsObject *opt in row.selectorOptions) if ([opt.formValue integerValue]==pos){ row.value = opt; break; }
    }
    row.height = rowHeight;
    row.action.viewControllerClass = [PPOptionsViewController class];
    [Styling applyGlobalStyleToRow:row];
    [sec addFormRow:row];
    
    // Transaction (animation)
    row = [XLFormRowDescriptor formRowDescriptorWithTag:kRowTransaction
                                                rowType:XLFormRowDescriptorTypeSelectorPush
                                                  title:kLang(@"Transition")];
    row.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerTransactionScroll)  displayText:kLang(@"Scroll")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerTransactionFade)    displayText:kLang(@"Fade")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerTransactionReplace) displayText:kLang(@"Replace")]
    ];
    {
        PPBannerTransaction tr = mainBannerModel ? mainBannerModel.bannerViewTransaction : PPBannerTransactionScroll;
        for (XLFormOptionsObject *opt in row.selectorOptions) if ([opt.formValue integerValue]==tr){ row.value = opt; break; }
    }
    row.height = rowHeight;
    row.action.viewControllerClass = [PPOptionsViewController class];
    [Styling applyGlobalStyleToRow:row];
    [sec addFormRow:row];
}

- (void)addBannerDataAnImagesSectionInForm:(XLFormDescriptor *)form MainBannerModel:(MainBannerModel * _Nullable)group PPbannerViewModel:(PPBannerViewModel * _Nullable)PPbannerViewModel{
    
    
    NSLog(@"cellConfigAtConfigure PPbannerViewModel %@",[PPbannerViewModel modelToJSONString]);
    XLFormSectionDescriptor * sec = [XLFormSectionDescriptor formSection];
    [form addFormSection:sec];
    
    
    // Sample image picker row (PPImageCollection via XLForm)
    XLFormRowDescriptor *sampleRow = [XLFormRowDescriptor formRowDescriptorWithTag:kRowSamplePhoto rowType:XLFormRowDescriptorTypePPImageCollection];
    sampleRow.title = kLang(@"Banners_Tap_Select_Sample");
    sampleRow.cellConfigAtConfigure[@"maxImages"] = @(1);
    if (PPbannerViewModel.sampleImageURL) {
        sampleRow.cellConfigAtConfigure[@"preloadImageURL"] = PPbannerViewModel.sampleImageURL.absoluteString;
    }
    [sec addFormRow:sampleRow];

    // Background image picker row (PPImageCollection via XLForm)
    XLFormRowDescriptor *bgRow = [XLFormRowDescriptor formRowDescriptorWithTag:kRowBGPhoto rowType:XLFormRowDescriptorTypePPImageCollection];
    bgRow.title = kLang(@"Background");
    bgRow.cellConfigAtConfigure[@"maxImages"] = @(1);
    if (PPbannerViewModel.backgroundImageURL) {
        bgRow.cellConfigAtConfigure[@"preloadImageURL"] = PPbannerViewModel.backgroundImageURL.absoluteString;
    }
    [sec addFormRow:bgRow];
    
    
    // ===== Section B: Child banner content (single-item editor) =====
    sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Banner Content")];
    [form addFormSection:sec];
    CGFloat rowHeight = 54.0;

    
    XLFormRowDescriptor *r =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowTitleEn
                                          rowType:XLFormRowDescriptorTypeText
                                            title:kLang(@"Title (EN)")];
    r.required = YES;
    r.value = PPSafeString(PPbannerViewModel.titleTextEn);
    r.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"Enter English title");
    r.height = rowHeight;
    [Styling applyGlobalStyleToRow:r];
    [sec addFormRow:r];
    
    r = [XLFormRowDescriptor formRowDescriptorWithTag:kRowTitleAr
                                              rowType:XLFormRowDescriptorTypeText
                                                title:kLang(@"Title (AR)")];
    r.value = PPSafeString(PPbannerViewModel.titleTextAr);
    r.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"Enter Arabic title");
    [Styling applyGlobalStyleToRow:r];
    [sec addFormRow:r];
    
    r = [XLFormRowDescriptor formRowDescriptorWithTag:kRowDescEn
                                              rowType:XLFormRowDescriptorTypeTextView
                                                title:kLang(@"Description (EN)")];
    r.value = PPSafeString(PPbannerViewModel.descTextEn);
    r.cellConfigAtConfigure[@"textView.placeholder"] = kLang(@"Enter English description");
    [Styling applyGlobalStyleToRow:r];
    r.height = rowHeight * 2;
    [sec addFormRow:r];
    
    r = [XLFormRowDescriptor formRowDescriptorWithTag:kRowDescAr
                                              rowType:XLFormRowDescriptorTypeTextView
                                                title:kLang(@"Description (AR)")];
    r.value = PPSafeString(PPbannerViewModel.descTextAr);
    r.cellConfigAtConfigure[@"textView.placeholder"] = kLang(@"Enter Arabic description");
    r.height = rowHeight * 2;
    [Styling applyGlobalStyleToRow:r];
    [sec addFormRow:r];
    
    // Post date
    r = [XLFormRowDescriptor formRowDescriptorWithTag:kRowPostDate
                                              rowType:XLFormRowDescriptorTypeDateInline
                                                title:kLang(@"Post Date")];
    r.value = (PPbannerViewModel.postDate ?: [NSDate date]);
    [Styling applyGlobalStyleToRow:r];
    [sec addFormRow:r];
    
    // Text style (white/black)
    r = [XLFormRowDescriptor formRowDescriptorWithTag:kRowTextStyle
                                              rowType:XLFormRowDescriptorTypeSelectorPush
                                                title:kLang(@"Text Color")];
    r.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerTextStyleWhite) displayText:kLang(@"White")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerTextStyleBlack) displayText:kLang(@"Black")]
    ];
    {
        PPBannerTextStyle ts = PPbannerViewModel ? PPbannerViewModel.pannerTextStyle : PPBannerTextStyleWhite;
        for (XLFormOptionsObject *opt in r.selectorOptions) if ([opt.formValue integerValue]==ts){ r.value = opt; break; }
    }
    r.height = rowHeight;
    r.action.viewControllerClass = [PPOptionsViewController class];
    [Styling applyGlobalStyleToRow:r];
    [sec addFormRow:r];
    
    // Tap action + value
    r = [XLFormRowDescriptor formRowDescriptorWithTag:kRowTapAction
                                              rowType:XLFormRowDescriptorTypeSelectorPush
                                                title:kLang(@"On Tap Action")];
    r.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerOnTapViewAccessory)     displayText:kLang(@"View Accessory")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerOnTapViewAd)            displayText:kLang(@"View Ad")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerOnTapOpenUrl)           displayText:kLang(@"Open URL")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerOnTapCallPhoneNumber)   displayText:kLang(@"Call")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPBannerOnTapWhatsApp)          displayText:kLang(@"WhatsApp")]
    ];
    {
        PPBannerOnTapAction ac = PPbannerViewModel ? PPbannerViewModel.onTapAction : PPBannerOnTapViewAccessory;
        for (XLFormOptionsObject *opt in r.selectorOptions) if ([opt.formValue integerValue]==ac){ r.value = opt; break; }
    }
    r.height = rowHeight;
    r.action.viewControllerClass = [PPOptionsViewController class];
    [Styling applyGlobalStyleToRow:r];
    [sec addFormRow:r];
    
    r = [XLFormRowDescriptor formRowDescriptorWithTag:kRowTapValue
                                              rowType:XLFormRowDescriptorTypeText
                                                title:kLang(@"On Tap Value")];
    r.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"ID / URL / Phone");
    r.value = PPSafeString(PPbannerViewModel.onTapValue);
    r.height = rowHeight;
    [Styling applyGlobalStyleToRow:r];
    [sec addFormRow:r];
    
    // Validity / countdown rows
    sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Validity (optional)")];
    [form addFormSection:sec];
    
    NSInteger initD = 0, initH = 0, initM = 0;
    if (PPbannerViewModel.validityDuration) {
        initD = PPbannerViewModel.validityDuration.day;
        initH = PPbannerViewModel.validityDuration.hour;
        initM = PPbannerViewModel.validityDuration.minute;
    }
    XLFormRowDescriptor *rd =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowValidDays
                                          rowType:XLFormRowDescriptorTypeInteger
                                            title:kLang(@"Days")];
    rd.value = @(initD);
    [Styling applyGlobalStyleToRow:rd];
    r.height = rowHeight;
    [sec addFormRow:rd];
    
    rd = [XLFormRowDescriptor formRowDescriptorWithTag:kRowValidHours
                                               rowType:XLFormRowDescriptorTypeInteger
                                                 title:kLang(@"Hours")];
    rd.value = @(initH);
    [Styling applyGlobalStyleToRow:rd];
    r.height = rowHeight;
    [sec addFormRow:rd];
    
    rd = [XLFormRowDescriptor formRowDescriptorWithTag:kRowValidMins
                                               rowType:XLFormRowDescriptorTypeInteger
                                                 title:kLang(@"Minutes")];
    rd.value = @(initM);
    r.height = rowHeight;
    [Styling applyGlobalStyleToRow:rd];
    [sec addFormRow:rd];
    
    rd = [XLFormRowDescriptor formRowDescriptorWithTag:kRowExpireDT
                                               rowType:XLFormRowDescriptorTypeDateTimeInline
                                                 title:kLang(@"Expire At")];
    rd.value = PPbannerViewModel.expirationDate;
    r.height = rowHeight;
    [Styling applyGlobalStyleToRow:rd];
    rd.action.formBlock = ^(XLFormRowDescriptor *rowDescriptor) {
        DLog(@"[XLFormRowDescriptor] action: action action action action action action action action action");
        
    };
    rd.onChangeBlock = ^(id  _Nullable oldValue, id  _Nullable newValue, XLFormRowDescriptor * _Nonnull rowDescriptor) {
        DLog(@"[XLFormRowDescriptor] onChangeBlock: onChangeBlock onChangeBlock onChangeBlock onChangeBlock onChangeBlock ");
    };
    [sec addFormRow:rd];
    
    
    
    
    
}

#pragma mark - Build Banner From Form


- (XLFormDescriptor *)buildFormWithModel:(MainBannerModel * _Nullable)group
                               andBanner:(PPBannerViewModel * _Nullable)banner {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];
    
    if (self.editMode == PPEditModeGroupOnly) {
        // Show only group settings
        [self addGroupSettingsSectionInForm:form MainBannerModel:group];
    }
    else if (self.editMode == PPEditModeBannerOnly) {
        // Show only banner data
        [self addBannerDataAnImagesSectionInForm:form MainBannerModel:group PPbannerViewModel:banner];
    }
    else if (self.editMode == PPEditModeAddBannerToGroup) {
        // Show only banner data
        [self addGroupSettingsSectionInForm:form MainBannerModel:group];
        [self addBannerDataAnImagesSectionInForm:form MainBannerModel:group PPbannerViewModel:banner];
        
       

    }
    else {
        // Fallback: show both (maybe for Add New)
        [self addGroupSettingsSectionInForm:form MainBannerModel:group];
        [self addBannerDataAnImagesSectionInForm:form MainBannerModel:group PPbannerViewModel:banner];
    }
    
    return form;
}

- (UIImage *)getImageFromRowWithTag:(NSString *)rowTag {
    XLFormRowDescriptor *row = [self.form formRowWithTag:rowTag];
    if (row && [row.value isKindOfClass:[UIImage class]]) {
        return (UIImage *)row.value;
    }
    return nil;
}



#pragma mark - Save

- (void)onSave { [self saveBanner]; }

- (void)saveBanner {
    NSDictionary *values = [self.form formValues] ?: @{};

    BOOL editsBannerContent = (_editMode != PPEditModeGroupOnly);
    if (editsBannerContent) {
        NSString *titleEn = PPSafeString(values[kRowTitleEn]);
        if (titleEn.length == 0) {
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"Title required")];
            return;
        }
    }

    [PPHUD showRingIn:self.view title:kLang(@"Uploading") subtitle:kLang(@"PleaseWait")];

    if (_editMode == PPEditModeGroupOnly) {
        MainBannerModel *group = [self pp_groupModelForSaveUsingFormValues:values
                                                     preserveGroupMetadata:NO];
        if (!group) {
            [PPHUD dismiss];
            [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"Banner group is invalid")];
            return;
        }

        [[PPBannersManager sharedManager] updateBannerGroup:group completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            if (error) {
                [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription];
                return;
            }
            [PPHUD showSuccess:kLang(@"Saved") subtitle:kLang(@"Banner saved")];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.navigationController popViewControllerAnimated:YES];
            });
        }];
        return;
    }

    BOOL preserveGroupMetadata =
        (_editMode == PPEditModeBannerOnly || _editMode == PPEditModeAddBannerToGroup);
    MainBannerModel *group = [self pp_groupModelForSaveUsingFormValues:values
                                                 preserveGroupMetadata:preserveGroupMetadata];
    if (!group) {
        [PPHUD dismiss];
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"Banner group is invalid")];
        return;
    }

    PPBannerViewModel *child = [self buildBannerFromForm];
    if (_editMode == PPEditModeAddBannerToGroup && child.bannerID.length == 0) {
        child.bannerID = [[NSUUID UUID] UUIDString];
    }

    [self uploadImagesAndUpdateBanner:child inGroup:group];
}


// Create helper methods for common operations
- (void)updateBannerGroup:(MainBannerModel *)group withCompletion:(void (^)(NSError *error))completion {
    [[PPBannersManager sharedManager] updateBannerGroup:group completion:completion];
}

- (void)uploadImagesAndUpdateBanner:(PPBannerViewModel *)banner inGroup:(MainBannerModel *)group {
    // Capture old image URLs before they get overwritten
    PPBannerViewModel *existingBanner = self.editingBanner;
    NSURL *oldBgURL     = existingBanner.backgroundImageURL;
    NSURL *oldSampleURL = existingBanner.sampleImageURL;
    NSURL *oldBadgeURL  = existingBanner.badgeImageURL;

    [self pp_uploadSelectedImagesWithCompletion:^(NSURL * _Nullable bgURL, NSURL * _Nullable sampleURL, NSURL * _Nullable badgeURL, NSError * _Nullable error) {
        if (error) {
            [PPFunc handleCompletionWithError:error successMessage:nil onController:self];
            return;
        }

        banner.backgroundImageURL = bgURL ?: banner.backgroundImageURL ?: existingBanner.backgroundImageURL;
        banner.sampleImageURL     = sampleURL ?: banner.sampleImageURL ?: existingBanner.sampleImageURL;
        banner.badgeImageURL      = badgeURL ?: banner.badgeImageURL ?: existingBanner.badgeImageURL;
        

        // Replace (single child) array
        NSMutableArray *updatedBanners = [group.childBanners mutableCopy] ?: [NSMutableArray array];
        if (self.editingBanner) {
            NSUInteger idx = [updatedBanners indexOfObjectPassingTest:^BOOL(PPBannerViewModel *obj, NSUInteger idx, BOOL *stop) {
                return [obj.bannerID isEqualToString:self.editingBanner.bannerID];
            }];
            if (idx != NSNotFound) {
                [updatedBanners replaceObjectAtIndex:idx withObject:banner];
            }
        } else { [updatedBanners addObject:banner]; }
        group.childBanners = updatedBanners;

        
        
        // Update the group with the modified banner
        [self updateBannerGroup:group withCompletion:^(NSError * _Nullable error) {
            if (!error) {
                // Delete old images from Storage after successful save
                [self pp_deleteOldStorageImageIfReplaced:oldBgURL newURL:bgURL];
                [self pp_deleteOldStorageImageIfReplaced:oldSampleURL newURL:sampleURL];
                [self pp_deleteOldStorageImageIfReplaced:oldBadgeURL newURL:badgeURL];
            }
            [PPFunc handleCompletionWithError:error successMessage:kLang(@"Banner saved") onController:self];
        }];
    }];
}

-(void)sendBannerToGroupToFireStore:(PPBannerViewModel *) newBanner
{
    // Replace all block references to self with weak references
    __weak typeof(self) weakSelf = self;

    // Example in saveBanner method:
    [[PPBannersManager sharedManager] addBanner:newBanner
                                        toGroup:self.editingBannerGroup
                                     completion:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            [PPHUD dismiss];
            [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
        } else {
            [PPHUD dismiss];
            [PPHUD showSuccess:kLang(@"Saved") subtitle:kLang(@"Banner added to group")];
            [strongSelf.navigationController popViewControllerAnimated:YES];
        }
    }];
}


- (void)setSection:(XLFormSectionDescriptor *)section enabled:(BOOL)enabled {
    for (XLFormRowDescriptor *row in section.formRows) {
        row.disabled = @(!enabled);   // NSNumber wrapping BOOL
    }
    [self.tableView reloadData];
}

- (NSInteger)pp_integerValueFromFormValue:(id)value defaultValue:(NSInteger)defaultValue {
    if ([value isKindOfClass:[XLFormOptionsObject class]]) {
        return [((XLFormOptionsObject *)value).formValue integerValue];
    }
    if ([value respondsToSelector:@selector(integerValue)]) {
        return [value integerValue];
    }
    return defaultValue;
}

- (NSString *)pp_resolvedBannerGroupIDFromRawValue:(NSString *)rawGroupID
                                            holder:(PPBannerHolder)holder
                                          position:(PPBannerPosition)position
                                        fallbackID:(NSString *)fallbackID {
    NSString *trimmed = [PPSafeString(rawGroupID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) return trimmed;
    if (PPSafeString(fallbackID).length > 0) return fallbackID;

    // Canonical ID for the iOS home top carousel. This lets the admin shortcut reliably control the home carousel.
    if (holder == PPBannerHolderMainView && position == PPBannerPositionTop) {
        return kPPAdminHomeTopCarouselGroupID;
    }

    return UUIDJoin(@"GROUP");
}

- (MainBannerModel *)pp_groupModelForSaveUsingFormValues:(NSDictionary *)values
                                   preserveGroupMetadata:(BOOL)preserveGroupMetadata {
    MainBannerModel *sourceGroup = self.editingBannerGroup;
    MainBannerModel *group = nil;
    if (sourceGroup) {
        group = [[MainBannerModel alloc] initWithID:PPSafeString(sourceGroup.bannerViewID)
                                            visible:sourceGroup.bannerViewVisible
                                             holder:sourceGroup.bannerViewHolder
                                           position:sourceGroup.bannerViewPosition
                                        transaction:sourceGroup.bannerViewTransaction
                                            banners:sourceGroup.childBanners ?: @[]];
        group.docID = sourceGroup.docID;
    } else {
        group = [[MainBannerModel alloc] init];
    }
    if (!group) return nil;

    BOOL hasVisibleRow = ([self.form formRowWithTag:kRowVisible] != nil);
    BOOL hasHolderRow = ([self.form formRowWithTag:kRowHolder] != nil);
    BOOL hasPositionRow = ([self.form formRowWithTag:kRowPosition] != nil);
    BOOL hasTransactionRow = ([self.form formRowWithTag:kRowTransaction] != nil);
    BOOL hasGroupIDRow = ([self.form formRowWithTag:kRowGroupID] != nil);

    BOOL visibleDefault = sourceGroup ? sourceGroup.bannerViewVisible : YES;
    PPBannerHolder holderDefault = sourceGroup ? sourceGroup.bannerViewHolder : PPBannerHolderMainView;
    PPBannerPosition positionDefault = sourceGroup ? sourceGroup.bannerViewPosition : PPBannerPositionTop;
    PPBannerTransaction transactionDefault = sourceGroup ? sourceGroup.bannerViewTransaction : PPBannerTransactionScroll;

    BOOL visible = visibleDefault;
    PPBannerHolder holder = holderDefault;
    PPBannerPosition position = positionDefault;
    PPBannerTransaction transaction = transactionDefault;

    if (!preserveGroupMetadata) {
        if (hasVisibleRow) {
            visible = [values[kRowVisible] boolValue];
        }
        if (hasHolderRow) {
            holder = (PPBannerHolder)[self pp_integerValueFromFormValue:values[kRowHolder]
                                                           defaultValue:holderDefault];
        }
        if (hasPositionRow) {
            position = (PPBannerPosition)[self pp_integerValueFromFormValue:values[kRowPosition]
                                                               defaultValue:positionDefault];
        }
        if (hasTransactionRow) {
            transaction = (PPBannerTransaction)[self pp_integerValueFromFormValue:values[kRowTransaction]
                                                                     defaultValue:transactionDefault];
        }
    }

    NSString *rawGroupID = hasGroupIDRow ? PPSafeString(values[kRowGroupID]) : @"";
    NSString *fallbackID = PPSafeString(sourceGroup.bannerViewID);
    if (fallbackID.length == 0) {
        fallbackID = PPSafeString(sourceGroup.docID);
    }
    NSString *resolvedGroupID = [self pp_resolvedBannerGroupIDFromRawValue:rawGroupID
                                                                     holder:holder
                                                                   position:position
                                                                 fallbackID:fallbackID];

    group.bannerViewID = resolvedGroupID;
    group.docID = sourceGroup.docID.length ? sourceGroup.docID : resolvedGroupID;
    group.bannerViewVisible = visible;
    group.bannerViewHolder = holder;
    group.bannerViewPosition = position;
    group.bannerViewTransaction = transaction;
    group.childBanners = group.childBanners ?: @[];

    return group.bannerViewID.length > 0 ? group : nil;
}

- (void)pp_applyTimingFieldsFromFormValues:(NSDictionary *)values toBanner:(PPBannerViewModel *)banner {
    if (!banner) return;

    NSInteger days = PPSafeInteger(values[kRowValidDays]);
    NSInteger hours = PPSafeInteger(values[kRowValidHours]);
    NSInteger mins = PPSafeInteger(values[kRowValidMins]);
    if (days > 0 || hours > 0 || mins > 0) {
        NSDateComponents *dc = [NSDateComponents new];
        dc.day = days;
        dc.hour = hours;
        dc.minute = mins;
        banner.validityDuration = dc;
    } else {
        banner.validityDuration = nil;
    }

    banner.expirationDate = PPSafeDate(values[kRowExpireDT]);
}



#pragma mark - Build Banner From Form

- (PPBannerViewModel *)buildBannerFromForm {
    XLFormDescriptor *form = self.form;
    NSDictionary *values = [form formValues];

    // Safe accessors
    NSString *titleEn   = PPSafeString(values[kRowTitleEn]);
    NSString *titleAr   = PPSafeString(values[kRowTitleAr]);
    NSString *descEn    = PPSafeString(values[kRowDescEn]);
    NSString *descAr    = PPSafeString(values[kRowDescAr]);
    NSDate   *postDate  = values[kRowPostDate] ?: [NSDate date];

    // Handle dropdowns (XLFormOptionsObject or NSNumber fallback)
    NSInteger tapAction = [self pp_integerValueFromFormValue:values[kRowTapAction]
                                                defaultValue:PPBannerOnTapViewAccessory];

    NSInteger textStyle = [self pp_integerValueFromFormValue:values[kRowTextStyle]
                                                defaultValue:PPBannerTextStyleWhite];

    NSString *tapValue  = PPSafeString(values[kRowTapValue]);

    // UUID (new if not editing)
    NSString *bannerID = self.editingBanner.bannerID ?: UUIDJoin(@"BANNER");
    
    // Build model
    PPBannerViewModel *model = [[PPBannerViewModel alloc] initWithTitleEn:titleEn
                                                                 titleAr:titleAr
                                                              descTextEn:descEn
                                                              descTextAr:descAr
                                                                postDate:postDate
                                                      backgroundImageURL:nil // fill after upload
                                                          sampleImageURL:nil
                                                           badgeImageURL:nil
                                                             onTapAction:(PPBannerOnTapAction)tapAction
                                                               textStyle:(PPBannerTextStyle)textStyle
                                                              onTapValue:tapValue
                                                                bannerID:bannerID];

    [self pp_applyTimingFieldsFromFormValues:values toBanner:model];
    if (self.editingBanner) {
        model.tapCount = self.editingBanner.tapCount;
    }

    return model;
}


#pragma mark - Upload helpers

- (void)pp_uploadSelectedImagesWithCompletion:(void(^)(NSURL * _Nullable bgURL,
                                                       NSURL * _Nullable sampleURL,
                                                       NSURL * _Nullable badgeURL,
                                                       NSError * _Nullable error))completion
{
    // Extract images from XLForm rows
    UIImage *bgImage = [self getImageFromRowWithTag:kRowBGPhoto];
    UIImage *sampleImage = [self getImageFromRowWithTag:kRowSamplePhoto];
    UIImage *badgeImage = [self getImageFromRowWithTag:kRowBadgePhoto]; // Add this if you have a badge row
    
    // Nothing to upload? return nils (keep existing)
    if (!bgImage && !sampleImage && !badgeImage) {
        if (completion) completion(nil, nil, nil, nil);
        return;
    }
    
    FIRStorageReference *root = [[FIRStorage storage] reference];
    
    dispatch_group_t g = dispatch_group_create();
    __block NSURL *bgURL = nil, *smURL = nil, *bdURL = nil;
    __block NSError *firstErr = nil;
    
    void (^uploadImage)(UIImage *, NSString *, void(^)(NSURL *)) =
    ^(UIImage *image, NSString *folder, void(^setter)(NSURL *u)){
        if (!image) { return; }
        
        // Convert UIImage to JPEG data
        dispatch_group_enter(g);
        
        NSData *data = UIImagePNGRepresentation(image);
        if (!data) {
            if (!firstErr) {
                firstErr = [NSError errorWithDomain:@"ImageConversionError"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert image to PNG"}];
            }
            dispatch_group_leave(g);
            return;
        }
        
        NSString *name = [NSString stringWithFormat:@"%@/%@.png", folder, [[NSUUID UUID] UUIDString]];
        FIRStorageReference *ref = [root child:name];
        
        [ref putData:data metadata:nil completion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
            if (error) {
                if (!firstErr) firstErr = error;
                dispatch_group_leave(g);
                return;
            }
            [ref downloadURLWithCompletion:^(NSURL * _Nullable URL, NSError * _Nullable error2) {
                if (URL) setter(URL);
                if (error2 && !firstErr) firstErr = error2;
                dispatch_group_leave(g);
            }];
        }];
    };
    
    // Upload each image if it exists
    uploadImage(bgImage,     @"banners/bg",     ^(NSURL *u){ bgURL = u; });
    uploadImage(sampleImage, @"banners/sample", ^(NSURL *u){ smURL = u; });
    uploadImage(badgeImage,  @"banners/badge",  ^(NSURL *u){ bdURL = u; });
    
    dispatch_group_notify(g, dispatch_get_main_queue(), ^{
        if (completion) completion(bgURL, smURL, bdURL, firstErr);
    });
}

- (void)pp_deleteOldStorageImageIfReplaced:(NSURL *)oldURL newURL:(NSURL *)newURL {
    if (!oldURL || !newURL) return;
    if ([oldURL.absoluteString isEqualToString:newURL.absoluteString]) return;
    @try {
        FIRStorageReference *ref = [[FIRStorage storage] referenceForURL:oldURL.absoluteString];
        [ref deleteWithCompletion:^(NSError * _Nullable error) {
            if (error) {
                DLog(@"[Banner] failed to delete old image: %@", error.localizedDescription);
            } else {
                DLog(@"[Banner] deleted old image: %@", oldURL.absoluteString);
            }
        }];
    } @catch (NSException *exception) {
        DLog(@"[Banner] invalid storage URL for cleanup: %@", oldURL);
    }
}





#pragma mark - Table BG & Photo cell hookup

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if(indexPath.section != 2)
        [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO];
    
  
    
}


/*
 #pragma mark - Small UI helper


 */


-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // Title & NAV
    
    NSString *title;
      switch (self.editMode) {
          case PPEditModeGroupOnly:
              title = kLang(@"Edit Banner Group");
              break;
          case PPEditModeBannerOnly:
              title = kLang(@"Edit Banner");
              break;
          case PPEditModeAddBannerToGroup:
              title = kLang(@"Add Banner Group");
              break;
              
          case PPEditModeGroupAndBanner:
          case PPEditModeNewGroup:
          default:
              title = kLang(@"Add Banner Group");
              break;
      }
    
    if(_editMode == PPEditModeGroupOnly)
    {
        // Get the row descriptor if using XLForm
        XLFormRowDescriptor *rowDescriptor = [self.form formRowAtIndex:[NSIndexPath indexPathForRow:0 inSection:0]];
        rowDescriptor.disabled = @YES;
        
        [self updateFormRow:rowDescriptor];
    }
    
    
    UIButton *save = [self pp_ButtonWithSystemName:@"checkmark" action:@selector(onSave)];
    save.tintColor = AppPrimaryClr;
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:save title:title showBack:YES];
}



@end
