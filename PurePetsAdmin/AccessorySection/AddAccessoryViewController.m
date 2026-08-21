
/*
 // Arabic
 "ItemType"       = "نوع العنصر";
 "Accessory"      = "إكسسوار";
 "Food"           = "طعام";
 "AddAccessory"   = "إضافة إكسسوار";
 "EditAccessory"  = "تعديل الإكسسوار";
 "AddFood"        = "إضافة طعام";
 "EditFood"       = "تعديل الطعام";
 */



//
//  AddAccessoryViewController.m
//  PurePetsAdmin
//

#import "AddAccessoryViewController.h"
#import "AlertHelper.h"
#import "PPImageCollectionRow.h"
#import "PPDesignTokens.h"
#import "UIViewController+PPNavBar.h"
#import <math.h>
@import Photos;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
static NSString * const PPMainStoreID = @"main_store";
static NSString * const PPMainStoreFallbackName = @"Main Store";
static NSString * const PPMyStoreFallbackName = @"My Store";
static CGFloat const PPAccessoryDefaultRowHeight = PPButtonHeightMD;

static UIFont *PPAccessoryScaledFont(UIFont *baseFont, UIFontTextStyle textStyle) {
    if (@available(iOS 11.0, *)) {
        return [[UIFontMetrics metricsForTextStyle:textStyle] scaledFontForFont:baseFont];
    }
    return baseFont;
}

@class AddAccessoryViewController;

@interface AddAccessoryViewController (PPAccessoryImageCollectionProxySupport)
- (void)pp_imageCollectionDidUpdate:(PPImageCollection *)collection;
- (void)pp_presentImageEditorForCollection:(PPImageCollection *)collection index:(NSInteger)index;
@end

/// Keeps the XLForm row as the mutation owner while giving the accessory flow
/// ownership of the editor presentation seam.
@interface PPAccessoryImageCollectionDelegateProxy : NSObject <PPImageCollectionDelegate>
@property (nonatomic, weak) PPImageCollectionRow *row;
@property (nonatomic, weak) AddAccessoryViewController *owner;
@end

@implementation PPAccessoryImageCollectionDelegateProxy

- (void)imageCollection:(PPImageCollection *)collection didUpdateImages:(NSArray<UIImage *> *)images {
    [self.row imageCollection:collection didUpdateImages:images];
    BOOL isExistingPreload = self.owner.editingAccessory.imageURLsArray.count > 0 && !self.row.imagesModified;
    if (!isExistingPreload) {
        [self.owner pp_imageCollectionDidUpdate:collection];
    }
}

- (void)imageCollection:(PPImageCollection *)collection didSelectImage:(UIImage *)image AtIndex:(NSInteger)index {
    [self.owner pp_presentImageEditorForCollection:collection index:index];
}

- (void)imageCollectionDidRequestAddImage:(PPImageCollection *)collection {
    (void)collection;
}

@end

@interface AddAccessoryViewController ()

@property (nonatomic, strong) NSArray<UIBarButtonItem *> *prevLeftItems;
@property (nonatomic, strong) NSArray<UIBarButtonItem *> *prevRightItems;
@property (nonatomic, assign) BOOL prevHidesBack;

@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *storeNamesByID;

@property (nonatomic, strong) UIButton *navigationSaveButton;
@property (nonatomic, strong) UIView *dossierHeader;
@property (nonatomic, strong) UILabel *dossierContextLabel;
@property (nonatomic, strong) UILabel *dossierTypeLabel;
@property (nonatomic, strong) UILabel *dossierTitleLabel;
@property (nonatomic, strong) UIView *dossierStateBanner;
@property (nonatomic, strong) UIImageView *dossierStateIcon;
@property (nonatomic, strong) UIActivityIndicatorView *dossierStateSpinner;
@property (nonatomic, strong) UILabel *dossierStateLabel;
@property (nonatomic, strong) UIButton *dossierRetryButton;

@property (nonatomic, strong) UIView *saveDock;
@property (nonatomic, strong) UIButton *saveDockButton;
@property (nonatomic, strong) UILabel *saveDockStatusLabel;
@property (nonatomic, strong) NSLayoutConstraint *saveDockBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *saveDockHeightConstraint;
@property (nonatomic, assign) UIEdgeInsets baseTableContentInset;
@property (nonatomic, assign) CGFloat keyboardOverlap;

@property (nonatomic, strong) PPAccessoryImageCollectionDelegateProxy *imageDelegateProxy;
@property (nonatomic, strong) NSMutableSet<NSString *> *invalidRowTags;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *validationMessagesByTag;
@property (nonatomic, assign) BOOL hasUnsavedChanges;
@property (nonatomic, assign) BOOL isSubmitting;
@property (nonatomic, assign) BOOL isLeavingAfterSave;
@property (nonatomic, assign) BOOL saveDockStatusIsError;
@property (nonatomic, assign) BOOL suppressChangeTracking;
@property (nonatomic, assign) BOOL mainKindsLoadInFlight;
@property (nonatomic, assign) BOOL capturedInteractivePopState;
@property (nonatomic, assign) BOOL previousInteractivePopEnabled;

@property (nonatomic, assign) CGFloat dossierHeaderMeasuredWidth;

@end

@implementation AddAccessoryViewController

// AddAccessoryViewController.m

- (instancetype)initWithAccessory:(PetAccessory * _Nullable)accessory {
    self = [super initWithForm:nil style:UITableViewStyleInsetGrouped];
    if (self) {
        _editingAccessory = accessory;
        _showTypeRow = YES;                    // default; caller can set to NO before presenting
        _defaultKind = AccessTypeAccessory;    // default; caller can set Food, etc.
        // ❌ DO NOT build the form here
        // ❌ DO NOT call pp_setupPhotoManager… here
    }
    return self;
}

- (instancetype)init {
    return [self initWithAccessory:nil];
}

- (NSString *)pp_typeDisplayNameForKind:(AccessKindType)kind {
    switch (kind) {
        case AccessTypeFood:
            return kLang(@"Food");
        case AccessTypeLivePets:
            return kLang(@"Live pets");
        case AccessTypeAccessory:
        default:
            return kLang(@"Accessory");
    }
}

- (NSString *)pp_screenTitle {
    AccessKindType kind = [self pp_resolvedKind];
    BOOL isFood = (kind == AccessTypeFood);
    BOOL isLivePets = (kind == AccessTypeLivePets);

    if (self.editingAccessory) {
        if (isFood) return kLang(@"EditFood");
        if (isLivePets) return kLang(@"EditLivePet");
        return kLang(@"EditAccessory");
    }

    if (isFood) return kLang(@"AddFood");
    if (isLivePets) return kLang(@"AddLivePet");
    return kLang(@"AddAccessory");
}

- (void)pp_setupDossierHeader {
    if (self.dossierHeader) return;

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = PPSpaceXS;
    stack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [header addSubview:stack];

    self.dossierContextLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dossierContextLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontCaption1], UIFontTextStyleCaption1);
    self.dossierContextLabel.textColor = [UIColor ppTextSecondary];
    self.dossierContextLabel.text = kLang(@"CommandCenter_Inventory_Workspace");
    self.dossierContextLabel.numberOfLines = 1;
    self.dossierContextLabel.adjustsFontForContentSizeCategory = YES;
    self.dossierContextLabel.textAlignment = NSTextAlignmentNatural;
    self.dossierContextLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.dossierTypeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dossierTypeLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontSubheadline], UIFontTextStyleSubheadline);
    self.dossierTypeLabel.textColor = [UIColor ppPrimary];
    self.dossierTypeLabel.numberOfLines = 1;
    self.dossierTypeLabel.adjustsFontForContentSizeCategory = YES;
    self.dossierTypeLabel.textAlignment = NSTextAlignmentNatural;
    self.dossierTypeLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.dossierTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dossierTitleLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontTitle2], UIFontTextStyleTitle2);
    self.dossierTitleLabel.textColor = [UIColor ppTextPrimary];
    self.dossierTitleLabel.numberOfLines = 0;
    self.dossierTitleLabel.adjustsFontForContentSizeCategory = YES;
    self.dossierTitleLabel.textAlignment = NSTextAlignmentNatural;
    self.dossierTitleLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    self.dossierStateBanner = [[UIView alloc] initWithFrame:CGRectZero];
    self.dossierStateBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.dossierStateBanner.hidden = YES;
    self.dossierStateBanner.layer.cornerRadius = PPCornerSmall;
    self.dossierStateBanner.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.dossierStateBanner.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stateStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stateStack.translatesAutoresizingMaskIntoConstraints = NO;
    stateStack.axis = UILayoutConstraintAxisHorizontal;
    stateStack.alignment = UIStackViewAlignmentCenter;
    stateStack.spacing = PPSpaceSM;
    stateStack.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.dossierStateBanner addSubview:stateStack];
    [NSLayoutConstraint activateConstraints:@[
        [stateStack.topAnchor constraintEqualToAnchor:self.dossierStateBanner.topAnchor constant:PPSpaceSM],
        [stateStack.leadingAnchor constraintEqualToAnchor:self.dossierStateBanner.leadingAnchor constant:PPSpaceSM],
        [stateStack.trailingAnchor constraintEqualToAnchor:self.dossierStateBanner.trailingAnchor constant:-PPSpaceSM],
        [stateStack.bottomAnchor constraintEqualToAnchor:self.dossierStateBanner.bottomAnchor constant:-PPSpaceSM]
    ]];

    self.dossierStateIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.dossierStateIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.dossierStateIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.dossierStateIcon.hidden = YES;
    [stateStack addArrangedSubview:self.dossierStateIcon];
    [self.dossierStateIcon.widthAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;
    [self.dossierStateIcon.heightAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;

    self.dossierStateSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.dossierStateSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.dossierStateSpinner.hidden = YES;
    [stateStack addArrangedSubview:self.dossierStateSpinner];
    [self.dossierStateSpinner.widthAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;
    [self.dossierStateSpinner.heightAnchor constraintEqualToConstant:PPButtonHeightXS].active = YES;

    self.dossierStateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.dossierStateLabel.font = PPAccessoryScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
    self.dossierStateLabel.numberOfLines = 0;
    self.dossierStateLabel.adjustsFontForContentSizeCategory = YES;
    self.dossierStateLabel.textAlignment = NSTextAlignmentNatural;
    self.dossierStateLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [stateStack addArrangedSubview:self.dossierStateLabel];
    [self.dossierStateLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.dossierRetryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.dossierRetryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dossierRetryButton setTitle:kLang(@"Retry") forState:UIControlStateNormal];
    self.dossierRetryButton.titleLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote);
    self.dossierRetryButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.dossierRetryButton.tintColor = [UIColor ppPrimary];
    self.dossierRetryButton.hidden = YES;
    self.dossierRetryButton.accessibilityLabel = kLang(@"Retry");
    [self.dossierRetryButton addTarget:self action:@selector(pp_retryMainKinds) forControlEvents:UIControlEventTouchUpInside];
    [stateStack addArrangedSubview:self.dossierRetryButton];
    [self.dossierRetryButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;

    [stack addArrangedSubview:self.dossierContextLabel];
    [stack addArrangedSubview:self.dossierTypeLabel];
    [stack addArrangedSubview:self.dossierTitleLabel];
    [stack addArrangedSubview:self.dossierStateBanner];

    UIView *rule = [[UIView alloc] initWithFrame:CGRectZero];
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    rule.backgroundColor = [UIColor ppSeparator];
    [stack addArrangedSubview:rule];
    [rule.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:PPSpaceSM],
        [stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [stack.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceSM]
    ]];

    self.dossierHeader = header;
    [self pp_updateDossierHeaderText];
    self.tableView.tableHeaderView = header;
}

- (void)pp_updateDossierHeaderText {
    if (!self.dossierHeader) return;

    AccessKindType kind = [self pp_resolvedKind];
    self.dossierTypeLabel.text = [self pp_typeDisplayNameForKind:kind];
    self.dossierTitleLabel.text = [self pp_screenTitle];
    self.dossierHeaderMeasuredWidth = 0.0;
    [self pp_updateDossierHeaderFrame];
}

- (void)pp_updateDossierHeaderFrame {
    if (!self.dossierHeader || !self.tableView) return;

    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;

    CGRect frame = self.dossierHeader.frame;
    if (fabs(self.dossierHeaderMeasuredWidth - width) < 0.5 && frame.size.height > 0.0) return;

    self.dossierHeader.frame = CGRectMake(0.0, 0.0, width, 1.0);
    [self.dossierHeader setNeedsLayout];
    [self.dossierHeader layoutIfNeeded];

    CGSize fittingSize = [self.dossierHeader systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                             withHorizontalFittingPriority:UILayoutPriorityRequired
                                                   verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    CGFloat height = MAX(PPButtonHeightLG, ceil(fittingSize.height));
    self.dossierHeader.frame = CGRectMake(0.0, 0.0, width, height);
    self.dossierHeaderMeasuredWidth = width;
    self.tableView.tableHeaderView = self.dossierHeader;
}

- (void)pp_setDossierStateMessage:(NSString *)message
                          isLoading:(BOOL)isLoading
                             isError:(BOOL)isError
                          showsRetry:(BOOL)showsRetry {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf pp_setDossierStateMessage:message
                                       isLoading:isLoading
                                          isError:isError
                                       showsRetry:showsRetry];
        });
        return;
    }

    BOOL visible = message.length > 0;
    self.dossierStateBanner.hidden = !visible;
    self.dossierStateLabel.text = message;
    self.dossierStateLabel.accessibilityLabel = message;
    self.dossierStateLabel.accessibilityTraits = UIAccessibilityTraitStaticText;
    self.dossierRetryButton.hidden = !showsRetry;
    self.dossierStateIcon.hidden = isLoading || !visible;
    self.dossierStateSpinner.hidden = !isLoading || !visible;

    if (isLoading) {
        self.dossierStateBanner.backgroundColor = [[UIColor ppInfo] colorWithAlphaComponent:0.08];
        self.dossierStateBanner.layer.borderColor = [[UIColor ppInfo] colorWithAlphaComponent:0.22].CGColor;
        self.dossierStateLabel.textColor = [UIColor ppInfo];
        self.dossierStateSpinner.color = [UIColor ppInfo];
        [self.dossierStateSpinner startAnimating];
    } else if (isError) {
        self.dossierStateBanner.backgroundColor = [[UIColor ppError] colorWithAlphaComponent:0.08];
        self.dossierStateBanner.layer.borderColor = [[UIColor ppError] colorWithAlphaComponent:0.22].CGColor;
        self.dossierStateIcon.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
        self.dossierStateIcon.tintColor = [UIColor ppError];
        self.dossierStateLabel.textColor = [UIColor ppError];
        [self.dossierStateSpinner stopAnimating];
    } else {
        self.dossierStateBanner.backgroundColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.08];
        self.dossierStateBanner.layer.borderColor = [[UIColor ppSuccess] colorWithAlphaComponent:0.22].CGColor;
        self.dossierStateIcon.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        self.dossierStateIcon.tintColor = [UIColor ppSuccess];
        self.dossierStateLabel.textColor = [UIColor ppSuccess];
        [self.dossierStateSpinner stopAnimating];
    }

    self.dossierStateBanner.accessibilityLabel = message;
    [self.dossierHeader setNeedsLayout];
    self.dossierHeaderMeasuredWidth = 0.0;
    [self pp_updateDossierHeaderFrame];
}

- (void)pp_clearDossierState {
    [self pp_setDossierStateMessage:nil isLoading:NO isError:NO showsRetry:NO];
}

- (void)pp_setupSaveDock {
    if (self.saveDock) return;

    UIView *dock = [[UIView alloc] initWithFrame:CGRectZero];
    dock.translatesAutoresizingMaskIntoConstraints = NO;
    dock.backgroundColor = [UIColor ppSurface];
    dock.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.view addSubview:dock];

    UIView *hairline = [[UIView alloc] initWithFrame:CGRectZero];
    hairline.translatesAutoresizingMaskIntoConstraints = NO;
    hairline.backgroundColor = [UIColor ppSeparator];
    [dock addSubview:hairline];

    self.saveDockStatusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.saveDockStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveDockStatusLabel.font = PPAccessoryScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
    self.saveDockStatusLabel.textColor = [UIColor ppTextSecondary];
    self.saveDockStatusLabel.numberOfLines = 2;
    self.saveDockStatusLabel.adjustsFontForContentSizeCategory = YES;
    self.saveDockStatusLabel.textAlignment = NSTextAlignmentNatural;
    self.saveDockStatusLabel.hidden = YES;
    self.saveDockStatusLabel.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [dock addSubview:self.saveDockStatusLabel];

    self.saveDockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.saveDockButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.saveDockButton.accessibilityLabel = kLang(@"Save");
    self.saveDockButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.saveDockButton addTarget:self action:@selector(onSave) forControlEvents:UIControlEventTouchUpInside];
    [dock addSubview:self.saveDockButton];

    self.saveDockHeightConstraint = [dock.heightAnchor constraintEqualToConstant:PPButtonHeightLG + PPSpaceBase];
    [NSLayoutConstraint activateConstraints:@[
        [dock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        self.saveDockHeightConstraint,
        [hairline.topAnchor constraintEqualToAnchor:dock.topAnchor],
        [hairline.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor],
        [hairline.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor],
        [hairline.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
        [self.saveDockButton.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-PPScreenMargin],
        [self.saveDockButton.centerYAnchor constraintEqualToAnchor:dock.centerYAnchor],
        [self.saveDockButton.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightLG],
        [self.saveDockStatusLabel.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:PPScreenMargin],
        [self.saveDockStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.saveDockButton.leadingAnchor constant:-PPSpaceMD],
        [self.saveDockStatusLabel.centerYAnchor constraintEqualToAnchor:self.saveDockButton.centerYAnchor]
    ]];

    self.saveDock = dock;
    self.saveDockBottomConstraint = [dock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor];
    self.saveDockBottomConstraint.active = YES;
    [self pp_updateSaveDockState];
}

- (void)pp_applySaveDockButtonConfiguration {
    NSString *title = self.isSubmitting ? kLang(@"Uploading") : kLang(@"Save");
    self.saveDockButton.accessibilityLabel = self.isSubmitting ? kLang(@"Uploading") : kLang(@"Save");

    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];
        configuration.baseBackgroundColor = [UIColor ppPrimary];
        configuration.baseForegroundColor = PPOnPrimaryColor();
        configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);
        configuration.title = title;
        configuration.showsActivityIndicator = self.isSubmitting;
        self.saveDockButton.configuration = configuration;
    } else {
        [self.saveDockButton setTitle:title forState:UIControlStateNormal];
        self.saveDockButton.backgroundColor = [UIColor ppPrimary];
        [self.saveDockButton setTitleColor:PPOnPrimaryColor() forState:UIControlStateNormal];
        PPApplyContinuousCorners(self.saveDockButton, PPCornerSmall);
        self.saveDockButton.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);
    }
}

- (void)pp_updateSaveDockState {
    if (!self.saveDockButton) return;

    BOOL disabled = self.isSubmitting || self.isLeavingAfterSave;
    self.saveDockButton.enabled = !disabled;
    self.navigationSaveButton.enabled = !disabled;
    self.navigationItem.rightBarButtonItem.enabled = !disabled;
    self.tableView.userInteractionEnabled = !disabled;
    [self pp_updateInteractivePopGestureState];
    self.saveDockStatusLabel.textColor = self.isLeavingAfterSave
        ? [UIColor ppSuccess]
        : (self.saveDockStatusIsError ? [UIColor ppError] : [UIColor ppTextSecondary]);

    if (self.isSubmitting) {
        self.saveDockStatusLabel.hidden = NO;
        self.saveDockStatusLabel.text = kLang(@"Uploading");
    } else if (self.isLeavingAfterSave) {
        self.saveDockStatusLabel.hidden = NO;
        self.saveDockStatusLabel.text = kLang(@"Saved");
    } else if (self.hasUnsavedChanges) {
        self.saveDockStatusLabel.hidden = NO;
        self.saveDockStatusLabel.text = kLang(@"CommandCenter_UnsavedChanges");
    } else if (self.saveDockStatusLabel.text.length == 0) {
        self.saveDockStatusLabel.hidden = NO;
        self.saveDockStatusLabel.text = kLang(@"CommandCenter_Draft");
    }

    [self pp_applySaveDockButtonConfiguration];
    [self pp_updateTableInsets];
    PPCommandCenterNavigationItemsDidChange(self);
}

- (void)pp_updateInteractivePopGestureState {
    if (!self.capturedInteractivePopState || !self.navigationController.interactivePopGestureRecognizer) return;
    BOOL canPopWithoutConfirmation = !self.hasUnsavedChanges && !self.isSubmitting && !self.isLeavingAfterSave;
    self.navigationController.interactivePopGestureRecognizer.enabled = canPopWithoutConfirmation && self.previousInteractivePopEnabled;
}

- (void)pp_registerKeyboardNotifications {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(pp_keyboardWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(pp_keyboardWillChange:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)pp_updateTableInsets {
    if (!self.tableView) return;

    UIEdgeInsets insets = self.baseTableContentInset;
    CGFloat dockHeight = CGRectGetHeight(self.saveDock.bounds);
    insets.bottom += dockHeight + PPSpaceSM + self.keyboardOverlap;
    self.tableView.contentInset = insets;
    self.tableView.scrollIndicatorInsets = insets;
}

- (void)pp_keyboardWillChange:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    CGRect endFrame = [userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardFrameInView = [self.view convertRect:endFrame fromView:nil];
    BOOL isHiding = [notification.name isEqualToString:UIKeyboardWillHideNotification];
    self.keyboardOverlap = (isHiding || CGRectIsEmpty(endFrame))
        ? 0.0
        : MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboardFrameInView));

    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    UIViewAnimationOptions options = (UIViewAnimationOptions)(curve << 16) | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:duration delay:0.0 options:options animations:^{
        self.saveDockBottomConstraint.constant = -self.keyboardOverlap;
        [self.view layoutIfNeeded];
        [self pp_updateTableInsets];
    } completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.saveDockHeightConstraint.constant = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        ? PPButtonHeightLG + PPSpaceXL
        : PPButtonHeightLG + PPSpaceBase;
    [self pp_updateDossierHeaderFrame];
    [self pp_updateTableInsets];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (![self.traitCollection.preferredContentSizeCategory isEqualToString:previousTraitCollection.preferredContentSizeCategory]) {
        self.dossierContextLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontCaption1], UIFontTextStyleCaption1);
        self.dossierTypeLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontSubheadline], UIFontTextStyleSubheadline);
        self.dossierTitleLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontTitle2], UIFontTextStyleTitle2);
        self.dossierStateLabel.font = PPAccessoryScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
        self.saveDockStatusLabel.font = PPAccessoryScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
        self.dossierRetryButton.titleLabel.font = PPAccessoryScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote);
        self.dossierHeaderMeasuredWidth = 0.0;
        [self.tableView reloadData];
        [self pp_updateSaveDockState];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Effective kind considering showTypeRow, the current form selection, the editing item, and defaultKind
- (AccessKindType)pp_resolvedKind {
    if (self.showTypeRow) {
        XLFormRowDescriptor *typeRow = [self.form formRowWithTag:@"itemType"];
        if ([typeRow.value isKindOfClass:XLFormOptionsObject.class]) {
            XLFormOptionsObject *opt = (XLFormOptionsObject *)typeRow.value;
            return [self pp_normalizedKindFromRaw:[opt.formValue integerValue]];
        }
    }
    if (self.editingAccessory) {
        return [self pp_normalizedKindFromRaw:self.editingAccessory.accessKindType];
    }
    return [self pp_normalizedKindFromRaw:self.defaultKind];
}

- (AccessKindType)pp_normalizedKindFromRaw:(NSInteger)rawKind {
    if (rawKind == AccessTypeFood) return AccessTypeFood;
    if (rawKind == AccessTypeLivePets) return AccessTypeLivePets;
    return AccessTypeAccessory;
}

- (NSInteger)pp_integerFromValue:(id)value defaultValue:(NSInteger)defaultValue {
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value integerValue];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value integerValue];
    return defaultValue;
}

- (NSNumber *)pp_numberFromValue:(id)value {
    if ([value isKindOfClass:NSNumber.class]) return (NSNumber *)value;
    if ([value isKindOfClass:NSString.class] && [(NSString *)value length] > 0) {
        NSNumberFormatter *formatter = [NSNumberFormatter new];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        return [formatter numberFromString:(NSString *)value];
    }
    return nil;
}

- (NSInteger)pp_optionValueFromFormValue:(id)value defaultValue:(NSInteger)defaultValue {
    if ([value isKindOfClass:XLFormOptionsObject.class]) {
        return [self pp_integerFromValue:((XLFormOptionsObject *)value).formValue defaultValue:defaultValue];
    }
    return [self pp_integerFromValue:value defaultValue:defaultValue];
}

- (NSString *)pp_localizedStringForKey:(NSString *)key fallback:(NSString *)fallback {
    NSString *value = kLang(key);
    if (value.length == 0 || [value isEqualToString:key]) {
        return fallback;
    }
    return value;
}

- (NSString *)pp_mainStoreDisplayName {
    return [self pp_localizedStringForKey:@"MainStore" fallback:PPMainStoreFallbackName];
}

- (NSString *)pp_myStoreDisplayName {
    return [self pp_localizedStringForKey:@"MyStore" fallback:PPMyStoreFallbackName];
}

- (void)pp_applyDefaultRowHeight:(XLFormRowDescriptor *)row {
    row.height = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        ? MAX(PPAccessoryDefaultRowHeight, PPButtonHeightLG + PPSpaceSM)
        : PPAccessoryDefaultRowHeight;
}

- (NSArray<XLFormOptionsObject *> *)pp_storeOptionsForAccessory:(PetAccessory *)accessory {
    NSMutableArray<XLFormOptionsObject *> *options = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];

    NSString *mainName = [self pp_mainStoreDisplayName];
    [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:PPMainStoreID displayText:mainName]];
    map[PPMainStoreID] = mainName;

    NSString *myStoreID = PPSafeString(UsrMgr.currentUser.uid);
    NSString *myStoreName = PPSafeString(UsrMgr.currentUser.displayName);
    if (myStoreID.length > 0 && ![myStoreID isEqualToString:PPMainStoreID]) {
        if (myStoreName.length == 0) myStoreName = [self pp_myStoreDisplayName];
        [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:myStoreID displayText:myStoreName]];
        map[myStoreID] = myStoreName;
    }

    NSString *existingStoreID = PPSafeString(accessory.storeID);
    NSString *existingStoreName = PPSafeString(accessory.storeName);
    if (existingStoreID.length > 0 && !map[existingStoreID]) {
        NSString *resolved = existingStoreName.length > 0 ? existingStoreName : existingStoreID;
        [options addObject:[XLFormOptionsObject formOptionsObjectWithValue:existingStoreID displayText:resolved]];
        map[existingStoreID] = resolved;
    }

    self.storeNamesByID = [map copy];
    return [options copy];
}

- (NSString *)pp_storeNameForID:(NSString *)storeID {
    NSString *sid = PPSafeString(storeID);
    if (sid.length == 0) sid = PPMainStoreID;
    NSString *name = self.storeNamesByID[sid];
    if (name.length > 0) return name;
    if ([sid isEqualToString:PPMainStoreID]) return [self pp_mainStoreDisplayName];
    return sid;
}

- (NSString *)pp_storeIDFromFormValue:(id)value {
    if ([value isKindOfClass:XLFormOptionsObject.class]) {
        id formValue = ((XLFormOptionsObject *)value).formValue;
        if ([formValue isKindOfClass:NSString.class]) return PPSafeString(formValue);
    } else if ([value isKindOfClass:NSString.class]) {
        return PPSafeString(value);
    }
    return @"";
}

- (NSNumber *)pp_calculateFinalPriceFromForm {
    XLFormRowDescriptor *priceRow = [self.form formRowWithTag:@"price"];
    XLFormRowDescriptor *percentRow = [self.form formRowWithTag:@"discountPercent"];
    XLFormRowDescriptor *amountRow = [self.form formRowWithTag:@"discountAmount"];

    NSNumber *price = [self pp_numberFromValue:priceRow.value];
    NSNumber *discountPercent = [self pp_numberFromValue:percentRow.value];
    NSNumber *discountAmount = [self pp_numberFromValue:amountRow.value];

    if (!price) return nil;
    CGFloat basePrice = MAX(0.0, price.floatValue);
    CGFloat final = basePrice;

    if (discountPercent && discountPercent.floatValue > 0) {
        CGFloat clampedPercent = MIN(100.0, MAX(0.0, discountPercent.floatValue));
        final = basePrice - (basePrice * clampedPercent / 100.0);
    }
    if (discountAmount && discountAmount.floatValue > 0) {
        final -= discountAmount.floatValue;
    }
    return @(MAX(0.0, final));
}

- (void)pp_refreshFinalPriceRow {
    XLFormRowDescriptor *finalPriceRow = [self.form formRowWithTag:@"finalPrice"];
    if (!finalPriceRow) return;
    finalPriceRow.value = [self pp_calculateFinalPriceFromForm] ?: @(0);
    [self updateFormRow:finalPriceRow];
}

- (NSDictionary *)pp_metaForURL:(NSString *)url width:(CGFloat)width height:(CGFloat)height {
    return @{
        @"url": PPSafeString(url),
        @"width": @(MAX(0.0, width)),
        @"height": @(MAX(0.0, height))
    };
}

- (NSDictionary<NSString *, NSDictionary *> *)pp_existingMetaByURLForAccessory:(PetAccessory *)accessory {
    NSMutableDictionary<NSString *, NSDictionary *> *map = [NSMutableDictionary dictionary];
    NSArray<NSString *> *urls = accessory.imageURLsArray ?: @[];
    NSArray<NSDictionary *> *meta = accessory.imageMeta ?: @[];

    for (NSInteger i = 0; i < urls.count; i++) {
        NSString *url = PPSafeString(urls[i]);
        if (url.length == 0) continue;

        NSDictionary *m = (i < meta.count && [meta[i] isKindOfClass:NSDictionary.class]) ? meta[i] : nil;
        CGFloat width = [m[@"width"] floatValue];
        CGFloat height = [m[@"height"] floatValue];
        map[url] = [self pp_metaForURL:url width:width height:height];
    }
    return [map copy];
}

- (NSArray<NSDictionary *> *)pp_imageMetaForURLs:(NSArray<NSString *> *)urls
                                  existingMetaByURL:(NSDictionary<NSString *, NSDictionary *> *)existingMetaByURL
                                  uploadedMetaByURL:(NSDictionary<NSString *, NSDictionary *> *)uploadedMetaByURL {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSString *url in urls) {
        NSString *clean = PPSafeString(url);
        if (clean.length == 0) continue;
        NSDictionary *meta = uploadedMetaByURL[clean] ?: existingMetaByURL[clean];
        if (!meta) {
            meta = [self pp_metaForURL:clean width:0 height:0];
        }
        [out addObject:meta];
    }
    return [out copy];
}

- (void)pp_backfillMissingEditFieldsIfNeeded {
    if (!self.editingAccessory) return;

    PetAccessory *candidate = [PetAccessory deepCopyFrom:self.editingAccessory];
    BOOL changed = NO;

    if (candidate.ownerID.length == 0) {
        candidate.ownerID = [FIRAuth auth].currentUser.uid ?: @"";
        changed = changed || (candidate.ownerID.length > 0);
    }
    if (candidate.storeID.length == 0) {
        candidate.storeID = PPMainStoreID;
        changed = YES;
    }
    if (candidate.storeName.length == 0) {
        candidate.storeName = [self pp_mainStoreDisplayName];
        changed = YES;
    }

    NSDictionary<NSString *, NSDictionary *> *existingMap = [self pp_existingMetaByURLForAccessory:candidate];
    NSArray<NSDictionary *> *normalizedMeta = [self pp_imageMetaForURLs:(candidate.imageURLsArray ?: @[])
                                                       existingMetaByURL:existingMap
                                                       uploadedMetaByURL:@{}];
    if (normalizedMeta.count != (candidate.imageMeta ?: @[]).count) {
        candidate.imageMeta = normalizedMeta;
        changed = YES;
    }

    NSInteger oldQty = candidate.quantity;
    BOOL oldNoStock = candidate.noStock;
    [candidate normalizeInventoryState];
    if (candidate.quantity != oldQty || candidate.noStock != oldNoStock) {
        changed = YES;
    }

    self.editingAccessory = candidate;
    if (!changed) return;

    [[AccessoryManager shared] createOrUpdateAccessory:candidate completion:^(NSError * _Nullable error) {
        if (error) {
            DLog(@"[AddAccessory] backfill save failed: %@", error.localizedDescription);
        } else {
            DLog(@"[AddAccessory] backfill save completed");
        }
    }];
}

/// Returns the UIImages currently in the PPImageCollection photos row.
- (NSArray<UIImage *> *)pp_selectedImages {
    XLFormRowDescriptor *photosRow = [self.form formRowWithTag:@"photos"];
    id val = photosRow.value;
    if ([val isKindOfClass:[NSArray class]]) {
        NSMutableArray<UIImage *> *result = [NSMutableArray array];
        for (id item in (NSArray *)val) {
            if ([item isKindOfClass:[UIImage class]]) {
                [result addObject:item];
            }
        }
        return result;
    }
    if ([val isKindOfClass:[UIImage class]]) {
        return @[(UIImage *)val];
    }
    return @[];
}

/// Returns YES if the user modified the images after preload (editing mode).
- (BOOL)pp_imagesModified {
    XLFormRowDescriptor *photosRow = [self.form formRowWithTag:@"photos"];
    NSIndexPath *ip = [self.form indexPathOfFormRow:photosRow];
    PPImageCollectionRow *cell = (PPImageCollectionRow *)[self.tableView cellForRowAtIndexPath:ip];
    if ([cell isKindOfClass:[PPImageCollectionRow class]]) {
        return cell.imagesModified;
    }
    // If cell not visible, check if value differs from editing state
    return YES;
}
- (XLFormDescriptor *)buildFormWithAccessory:(PetAccessory * _Nullable)accessory {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    // ===== Section 0: Type (Accessory/Food) when visible =====
    XLFormSectionDescriptor *section = nil;

    AccessKindType initialKind = AccessTypeAccessory;
    if (self.showTypeRow) {
        section = [XLFormSectionDescriptor formSection];
        section.title = kLang(@"Kind");
        [form addFormSection:section];

        XLFormRowDescriptor *typeRow =
        [XLFormRowDescriptor formRowDescriptorWithTag:@"itemType"
                                              rowType:XLFormRowDescriptorTypeSelectorSegmentedControl
                                                title:kLang(@"ItemType")];

        typeRow.selectorOptions = @[
            [XLFormOptionsObject formOptionsObjectWithValue:@(AccessTypeAccessory) displayText:kLang(@"Accessory")],
            [XLFormOptionsObject formOptionsObjectWithValue:@(AccessTypeFood)      displayText:kLang(@"Food")],
            [XLFormOptionsObject formOptionsObjectWithValue:@(AccessTypeLivePets)  displayText:kLang(@"Live pets")]
        ];

        // Preselect
        AccessKindType preselect = accessory ? accessory.accessKindType : self.defaultKind;
        if (preselect != AccessTypeAccessory && preselect != AccessTypeFood && preselect != AccessTypeLivePets) {
            preselect = AccessTypeAccessory;
        }
        for (XLFormOptionsObject *opt in typeRow.selectorOptions) {
            if ([opt.formValue integerValue] == preselect) { typeRow.value = opt; break; }
        }

        // If editing, lock the type (don't let the user change)
        if (self.editingAccessory) typeRow.disabled = @YES;

        __weak typeof(self) weakSelf = self;
        typeRow.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *r) {
            __strong typeof(weakSelf) self = weakSelf;
            // toggle Condition row + update title live for new flow
            [self pp_applyKindDrivenUIAndTitle];
        };

        [self pp_applyDefaultRowHeight:typeRow];
        [Styling applyGlobalStyleToRow:typeRow];
        [section addFormRow:typeRow];

        initialKind = [self pp_resolvedKind];
    } else {
        // Hidden mode: infer kind now (from editing item, or defaultKind, else Accessory)
        initialKind = [self pp_resolvedKind];
        // (No itemType row is added)
    }

    // ===== Section 1: Basic =====
    section = [XLFormSectionDescriptor formSection];
    section.title = kLang(@"Info");
    [form addFormSection:section];

    // Name
    XLFormRowDescriptor *row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"name"
                                           rowType:XLFormRowDescriptorTypeText
                                             title:kLang(@"Name")];
    row.required = YES;
    row.value = self.editingAccessory.name;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"Enter name");
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Description
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"desc"
                                           rowType:XLFormRowDescriptorTypeTextView
                                             title:kLang(@"Description")];
    row.value = self.editingAccessory.desc;
    row.cellConfigAtConfigure[@"textView.placeholder"] = kLang(@"Enter description");
    row.height = PPButtonHeightLG + PPSpaceSM;
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // ===== Section 2: Species / Breed =====
    section = [XLFormSectionDescriptor formSection];
    section.title = kLang(@"Species");
    [form addFormSection:section];

    // Species (required)
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"mainKind"
                                           rowType:XLFormRowDescriptorTypeSelectorPush
                                             title:kLang(@"Species")];
    row.required = YES;
    row.noValueDisplayText = kLang(@"SpeciesPlaceholder");
    row.selectorOptions = AppMgr.MainKindsArray ?: @[];
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    if (self.editingAccessory && self.editingAccessory.petMainCategoryID > 0) {
        MainKindsModel *mk = [self mainKindForID:self.editingAccessory.petMainCategoryID];
        if (mk) row.value = mk;
    }
    __weak typeof(self) weakSelf = self;
    row.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *r) {
        __strong typeof(weakSelf) self = weakSelf;
        XLFormRowDescriptor *subRow = [form formRowWithTag:@"subKind"];
        if ([newValue isKindOfClass:[MainKindsModel class]]) {
            MainKindsModel *selected = (MainKindsModel *)newValue;
            subRow.selectorOptions = selected.SubKindsArray ?: @[];
            subRow.hidden = @NO;
        } else {
            subRow.value = nil;
            subRow.selectorOptions = @[];
            subRow.hidden = @YES;
        }
        [self updateFormRow:subRow];
    };
    [section addFormRow:row];

    // Breed (optional)
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"subKind"
                                           rowType:XLFormRowDescriptorTypeSelectorPush
                                             title:kLang(@"Breed")];
    row.noValueDisplayText = kLang(@"BreedPlaceholder");
    row.selectorOptions = @[];
    row.hidden = [NSPredicate predicateWithFormat:@"$mainKind == nil"];
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    if (self.editingAccessory && self.editingAccessory.petSubCategoryID > 0) {
        SubKindModel *sk = [self subKindForID:self.editingAccessory.petSubCategoryID
                                       mainID:self.editingAccessory.petMainCategoryID];
        if (sk) row.value = sk;
    }
    [section addFormRow:row];

    // ===== Section 3: Pricing & Condition =====
    section = [XLFormSectionDescriptor formSection];
    section.title = kLang(@"Price");
    [form addFormSection:section];

    // Price
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"price"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"Price")];
    row.required = YES;
    row.value = self.editingAccessory.price;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"0.00");
    __weak typeof(self) weakPricingSelf = self;
    row.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *r) {
        __strong typeof(weakPricingSelf) self = weakPricingSelf;
        [self pp_refreshFinalPriceRow];
    };
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Discount %
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"discountPercent"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"DiscountPercent")];
    row.value = self.editingAccessory.discountPercent;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"DiscountPercentPlaceholder");
    row.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *r) {
        __strong typeof(weakPricingSelf) self = weakPricingSelf;
        [self pp_refreshFinalPriceRow];
    };
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Discount amount
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"discountAmount"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"DiscountAmount")];
    row.value = self.editingAccessory.discountAmount;
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"0.00");
    row.onChangeBlock = ^(__unused id oldValue, __unused id newValue, __unused XLFormRowDescriptor *r) {
        __strong typeof(weakPricingSelf) self = weakPricingSelf;
        [self pp_refreshFinalPriceRow];
    };
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Final price (auto)
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"finalPrice"
                                           rowType:XLFormRowDescriptorTypeDecimal
                                             title:kLang(@"FinalPrice")];
    row.disabled = @YES;
    row.value = self.editingAccessory.finalPrice ?: self.editingAccessory.price ?: @(0);
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    section = [XLFormSectionDescriptor formSection];
    section.title = kLang(@"StockSection");
    [form addFormSection:section];

    // Quantity
    row =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"quantity"
                                           rowType:XLFormRowDescriptorTypeInteger
                                             title:kLang(@"Quantity")];
    row.value = @(MAX(0, self.editingAccessory ? self.editingAccessory.quantity : 0));
    row.cellConfigAtConfigure[@"textField.placeholder"] = kLang(@"Enter quantity");
    [self pp_applyDefaultRowHeight:row];
    [Styling applyGlobalStyleToRow:row];
    [section addFormRow:row];

    // Condition (New/Used) — shown only for Accessory, hidden for Food
    XLFormRowDescriptor *conditionRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"condition"
                                           rowType:XLFormRowDescriptorTypeSelectorSegmentedControl
                                             title:kLang(@"Condition")];
    conditionRow.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(AccessConditionsNew)  displayText:kLang(@"New")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(AccessConditionsUsed) displayText:kLang(@"Used")]
    ];
    if (self.editingAccessory) {
        NSInteger cond = self.editingAccessory.condition;
        conditionRow.value = conditionRow.selectorOptions[(cond == AccessConditionsUsed ? 1 : 0)];
    } else {
        conditionRow.value = conditionRow.selectorOptions.firstObject;
    }
    [self pp_applyDefaultRowHeight:conditionRow];
    [Styling applyGlobalStyleToRow:conditionRow];
    [section addFormRow:conditionRow];

    // Initial visibility/lock for Condition based on resolved kind
    BOOL isFood = (initialKind == AccessTypeFood);
    if (isFood) {
        conditionRow.hidden = @YES;
        conditionRow.value  = conditionRow.selectorOptions.firstObject; // force "New"
        conditionRow.disabled = @YES;
    } else {
        conditionRow.hidden = @NO;
        conditionRow.disabled = @NO;
    }

    // ===== Section: Expiry Date =====
    section = [XLFormSectionDescriptor formSection];
    [form addFormSection:section];

    XLFormRowDescriptor *expiryRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"expiryDate"
                                           rowType:XLFormRowDescriptorTypeDate
                                             title:kLang(@"Expiry Date")];
    expiryRow.noValueDisplayText = kLang(@"No Expiry");
    expiryRow.required = NO;
    if (self.editingAccessory.expiryDate) {
        expiryRow.value = self.editingAccessory.expiryDate;
    }
    [self pp_applyDefaultRowHeight:expiryRow];
    [Styling applyGlobalStyleToRow:expiryRow];
    [section addFormRow:expiryRow];

    // ===== Section 4: Store =====
    section = [XLFormSectionDescriptor formSection];
    section.title = kLang(@"Store");
    [form addFormSection:section];

    XLFormRowDescriptor *storeRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"store"
                                           rowType:XLFormRowDescriptorTypeSelectorPush
                                             title:kLang(@"Store")];
    storeRow.noValueDisplayText = [self pp_mainStoreDisplayName];
    NSArray<XLFormOptionsObject *> *storeOptions = [self pp_storeOptionsForAccessory:accessory];
    storeRow.selectorOptions = storeOptions;
    NSString *selectedStoreID = PPSafeString(accessory.storeID);
    if (selectedStoreID.length == 0) selectedStoreID = PPMainStoreID;
    for (XLFormOptionsObject *opt in storeOptions) {
        if ([[self pp_storeIDFromFormValue:opt] isEqualToString:selectedStoreID]) {
            storeRow.value = opt;
            break;
        }
    }
    if (!storeRow.value && storeOptions.count > 0) {
        storeRow.value = storeOptions.firstObject;
    }
    [self pp_applyDefaultRowHeight:storeRow];
    [Styling applyGlobalStyleToRow:storeRow];
    [section addFormRow:storeRow];

    // ===== Section 5: Images =====
    section = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Images")];
    [form addFormSection:section];

    XLFormRowDescriptor *photosRow =
    [XLFormRowDescriptor formRowDescriptorWithTag:@"photos"
                                           rowType:XLFormRowDescriptorTypePPImageCollection
                                              title:kLang(@"Images")];
    photosRow.cellConfigAtConfigure[@"maxImages"] = @(9);
    // Preload existing images when editing
    if (accessory.imageURLsArray.count > 0) {
        photosRow.cellConfigAtConfigure[@"preloadImageURLs"] = accessory.imageURLsArray;
    }
    [section addFormRow:photosRow];

    return form;
}

/// Called after typeRow change to refresh title + condition visibility
- (void)pp_applyKindDrivenUIAndTitle {
    AccessKindType kind = [self pp_resolvedKind];
    BOOL isFood = (kind == AccessTypeFood);

    // Toggle condition row
    XLFormRowDescriptor *cond = [self.form formRowWithTag:@"condition"];
    if (!cond) return;
    cond.hidden   = @(isFood);
    cond.disabled = @(isFood);
    if (isFood && [cond.selectorOptions count] > 0) {
        cond.value = cond.selectorOptions.firstObject; // force "New"
    }
    [self updateFormRow:cond];

    [self pp_updateDossierHeaderText];
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.invalidRowTags = [NSMutableSet set];
    self.validationMessagesByTag = [NSMutableDictionary dictionary];

    [self pp_backfillMissingEditFieldsIfNeeded];

    [self setForm:[self buildFormWithAccessory:self.editingAccessory]];
    [self pp_refreshFinalPriceRow];
    [self pp_installFormStateTracking];
    [self pp_setupDossierHeader];
    [self pp_setupSaveDock];
    [self pp_registerKeyboardNotifications];
    [self pp_loadMainKindsIfNeeded];

    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = PPSpaceSM;
    }
    self.baseTableContentInset = UIEdgeInsetsMake(PPSpaceXS, 0, PPSpaceSM, 0);
    self.tableView.contentInset = self.baseTableContentInset;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.tableView.estimatedRowHeight = PPAccessoryDefaultRowHeight;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.title = [self pp_screenTitle];
    [self pp_updateDossierHeaderText];
    [self pp_updateSaveDockState];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    if (!self.capturedInteractivePopState) {
        self.previousInteractivePopEnabled = self.navigationController.interactivePopGestureRecognizer.enabled;
        self.capturedInteractivePopState = YES;
    }
    self.title = [self pp_screenTitle];
    self.dossierContextLabel.text = kLang(@"CommandCenter_Inventory_Workspace");
    // Long inventory forms use the persistent save dock as the single
    // primary commit action. Avoid duplicating Save in global navigation.
    [self pp_navBarWithOtherButton:nil title:self.title];
    PPCommandCenterNavigationItemsDidChange(self);
    [self pp_updateDossierHeaderText];
    [self pp_updateSaveDockState];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.capturedInteractivePopState) {
        self.navigationController.interactivePopGestureRecognizer.enabled = self.previousInteractivePopEnabled;
        self.capturedInteractivePopState = NO;
    }
}

- (void)onSave {
    if (self.isSubmitting || self.isLeavingAfterSave) return;
    [self saveAccessory];
}

- (void)onBack {
    if (self.isSubmitting || self.isLeavingAfterSave) return;
    if (![self pp_hasPendingChanges]) {
        [self pp_discardAndPop];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Warning")
                                                                     message:kLang(@"Are you sure you want to continue?")
                                                              preferredStyle:UIAlertControllerStyleAlert];
    alert.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel")
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Confirm")
                                               style:UIAlertActionStyleDestructive
                                             handler:^(__unused UIAlertAction *action) {
        [weakSelf pp_discardAndPop];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)pp_discardAndPop {
    self.hasUnsavedChanges = NO;
    [self.view endEditing:YES];
    [self.navigationController popViewControllerAnimated:YES];
}



- (UIButton *)circleButton:(NSString *)sfName action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setImage:[UIImage systemImageNamed:sfName] forState:UIControlStateNormal];
    b.tintColor = [UIColor ppPrimary];
    b.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceSM, PPSpaceSM, PPSpaceSM);
    PPApplyContinuousCorners(b, PPCornerMedium);
    b.backgroundColor = [UIColor ppSurfaceOverlay];
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:PPButtonHeightXS],
        [b.heightAnchor constraintEqualToConstant:PPButtonHeightXS]
    ]];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (BOOL)pp_hasPendingChanges {
    return self.hasUnsavedChanges;
}

- (void)pp_installFormStateTracking {
    for (XLFormSectionDescriptor *section in self.form.formSections) {
        for (XLFormRowDescriptor *row in section.formRows) {
            XLOnChangeBlock previousBlock = row.onChangeBlock;
            __weak typeof(self) weakSelf = self;
            row.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor *changedRow) {
                if (previousBlock) {
                    previousBlock(oldValue, newValue, changedRow);
                }
                [weakSelf pp_markFormDirtyForRow:changedRow];
            };
        }
    }
}

- (void)pp_markFormDirtyForRow:(XLFormRowDescriptor *)row {
    if (self.suppressChangeTracking || self.isLeavingAfterSave) return;

    self.hasUnsavedChanges = YES;
    self.saveDockStatusIsError = NO;
    if (row.tag.length > 0) {
        [self.invalidRowTags removeObject:row.tag];
        [self.validationMessagesByTag removeObjectForKey:row.tag];
        [self pp_applyValidationStyleToVisibleCellForTag:row.tag];
    }
    if (!self.mainKindsLoadInFlight) {
        [self pp_clearDossierState];
    }
    self.saveDockStatusLabel.hidden = NO;
    self.saveDockStatusLabel.text = kLang(@"CommandCenter_UnsavedChanges");
    self.saveDockStatusLabel.textColor = [UIColor ppTextSecondary];
    [self pp_updateSaveDockState];
}

- (void)pp_clearValidationErrors {
    [self.invalidRowTags removeAllObjects];
    [self.validationMessagesByTag removeAllObjects];
    for (NSIndexPath *indexPath in self.tableView.indexPathsForVisibleRows ?: @[]) {
        XLFormRowDescriptor *row = [self.form formRowAtIndex:indexPath];
        [self pp_applyValidationStyleToCell:[self.tableView cellForRowAtIndexPath:indexPath] row:row];
    }
    if (!self.mainKindsLoadInFlight) {
        [self pp_clearDossierState];
    }
}

- (void)pp_setValidationError:(NSString *)message forRowTag:(NSString *)tag {
    if (tag.length == 0) return;

    [self.invalidRowTags addObject:tag];
    if (message.length > 0) {
        self.validationMessagesByTag[tag] = message;
    }
    [self pp_applyValidationStyleToVisibleCellForTag:tag];
    [self pp_setDossierStateMessage:message isLoading:NO isError:YES showsRetry:NO];
    [self pp_focusRowTag:tag];
}

- (void)pp_applyValidationStyleToVisibleCellForTag:(NSString *)tag {
    XLFormRowDescriptor *row = [self.form formRowWithTag:tag];
    NSIndexPath *indexPath = row ? [self.form indexPathOfFormRow:row] : nil;
    if (!indexPath) return;
    [self pp_applyValidationStyleToCell:[self.tableView cellForRowAtIndexPath:indexPath] row:row];
}

- (void)pp_applyValidationStyleToCell:(UITableViewCell *)cell row:(XLFormRowDescriptor *)row {
    if (!cell || !row) return;

    BOOL invalid = [self.invalidRowTags containsObject:row.tag];
    cell.contentView.layer.borderWidth = invalid ? 1.0 / UIScreen.mainScreen.scale : 0.0;
    cell.contentView.layer.borderColor = invalid ? [[UIColor ppError] colorWithAlphaComponent:0.55].CGColor : UIColor.clearColor.CGColor;
    cell.contentView.layer.cornerRadius = PPCornerSmall;
    cell.textLabel.textColor = invalid ? [UIColor ppError] : [UIColor ppTextPrimary];
    cell.accessibilityHint = invalid ? self.validationMessagesByTag[row.tag] : nil;

    UITextField *textField = (UITextField *)[self findSubviewOfClass:[UITextField class] inView:cell];
    if (textField && invalid) {
        textField.accessibilityHint = self.validationMessagesByTag[row.tag];
    }
}

- (void)pp_focusRowTag:(NSString *)tag {
    XLFormRowDescriptor *row = [self.form formRowWithTag:tag];
    NSIndexPath *indexPath = row ? [self.form indexPathOfFormRow:row] : nil;
    if (!indexPath) return;

    [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    if (![tag isEqualToString:@"name"] && ![tag isEqualToString:@"price"]) return;

    NSTimeInterval delay = UIAccessibilityIsReduceMotionEnabled() ? 0.0 : PPAnimDurationNormal;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        UITextField *field = (UITextField *)[self findSubviewOfClass:[UITextField class] inView:cell];
        [field becomeFirstResponder];
    });
}

- (void)pp_loadMainKindsIfNeeded {
    XLFormRowDescriptor *mainKindRow = [self.form formRowWithTag:@"mainKind"];
    if (!mainKindRow) return;

    NSArray<MainKindsModel *> *cachedKinds = AppMgr.MainKindsArray ?: @[];
    if (cachedKinds.count > 0) {
        mainKindRow.selectorOptions = cachedKinds;
        mainKindRow.disabled = @NO;
        [self pp_restoreCategorySelectionIfNeeded];
        [self updateFormRow:mainKindRow];
        return;
    }

    self.mainKindsLoadInFlight = YES;
    mainKindRow.disabled = @YES;
    [self updateFormRow:mainKindRow];
    [self pp_setDossierStateMessage:kLang(@"Loading") isLoading:YES isError:NO showsRetry:NO];

    __weak typeof(self) weakSelf = self;
    [AppMgr fetchMainKindsWithCompletion:^(NSArray<MainKindsModel *> * _Nullable kinds, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            self.mainKindsLoadInFlight = NO;
            XLFormRowDescriptor *row = [self.form formRowWithTag:@"mainKind"];
            if (!row) return;

            if (error || kinds.count == 0) {
                row.selectorOptions = kinds ?: @[];
                row.disabled = @NO;
                [self updateFormRow:row];
                [self pp_setDossierStateMessage:kLang(@"Something went wrong.") isLoading:NO isError:YES showsRetry:YES];
                return;
            }

            row.selectorOptions = kinds;
            row.disabled = @NO;
            [self pp_restoreCategorySelectionIfNeeded];
            [self updateFormRow:row];
            [self pp_clearDossierState];
        });
    }];
}

- (void)pp_retryMainKinds {
    if (self.mainKindsLoadInFlight) return;
    [self pp_loadMainKindsIfNeeded];
}

- (void)pp_restoreCategorySelectionIfNeeded {
    if (!self.editingAccessory) return;

    MainKindsModel *mainKind = [self mainKindForID:self.editingAccessory.petMainCategoryID];
    XLFormRowDescriptor *mainKindRow = [self.form formRowWithTag:@"mainKind"];
    XLFormRowDescriptor *subKindRow = [self.form formRowWithTag:@"subKind"];
    if (!mainKind || !mainKindRow || !subKindRow) return;

    self.suppressChangeTracking = YES;
    mainKindRow.value = mainKind;
    subKindRow.selectorOptions = mainKind.SubKindsArray ?: @[];
    subKindRow.hidden = @NO;
    if (self.editingAccessory.petSubCategoryID > 0) {
        SubKindModel *subKind = [self subKindForID:self.editingAccessory.petSubCategoryID
                                             mainID:self.editingAccessory.petMainCategoryID];
        if (subKind) subKindRow.value = subKind;
    }
    [self updateFormRow:mainKindRow];
    [self updateFormRow:subKindRow];
    self.suppressChangeTracking = NO;
}

- (void)pp_imageCollectionDidUpdate:(PPImageCollection *)collection {
    if (!collection) return;
    [self pp_markFormDirtyForRow:[self.form formRowWithTag:@"photos"]];
}

- (void)pp_presentImageEditorForCollection:(PPImageCollection *)collection index:(NSInteger)index {
    if (!collection || self.isSubmitting || self.isLeavingAfterSave) return;
    [collection presentEditorForImageAtIndex:index fromViewController:self];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self.form formRowAtIndex:indexPath];
    if ([row.tag isEqualToString:@"photos"]) {
        return (PPButtonHeightLG * 2.0) + PPSpaceXL;
    }
    if ([row.tag isEqualToString:@"desc"]) {
        return UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
            ? PPButtonHeightLG + PPSpaceXL
            : PPButtonHeightLG + PPSpaceSM;
    }
    return UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        ? PPButtonHeightLG + PPSpaceSM
        : PPAccessoryDefaultRowHeight;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView heightForRowAtIndexPath:indexPath];
}



#pragma mark - Save

- (void)saveAccessory {
    if (self.isSubmitting || self.isLeavingAfterSave) return;

    NSDictionary *values = [self.form formValues];
    DLog(@"[AddAccessory] saveAccessory tapped. values=%@", values);

    NSString *name = [[NSString stringWithFormat:@"%@", values[@"name"] ?: @""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSNumber *price = [self pp_numberFromValue:values[@"price"]];
    NSNumber *discountPercentInput = [self pp_numberFromValue:values[@"discountPercent"]];
    NSNumber *discountAmountInput = [self pp_numberFromValue:values[@"discountAmount"]];
    NSInteger quantity = [self pp_integerFromValue:values[@"quantity"] defaultValue:0];
    MainKindsModel *mk = values[@"mainKind"];
    SubKindModel *sk = values[@"subKind"];
    NSString *storeID = [self pp_storeIDFromFormValue:values[@"store"]];
    if (storeID.length == 0) storeID = PPMainStoreID;
    NSString *storeName = [self pp_storeNameForID:storeID];

    [self pp_clearValidationErrors];
    if (name.length == 0 || !price) {
        if (name.length == 0) {
            [self.invalidRowTags addObject:@"name"];
            self.validationMessagesByTag[@"name"] = kLang(@"NamePriceRequired");
            [self pp_applyValidationStyleToVisibleCellForTag:@"name"];
        }
        if (!price) {
            [self.invalidRowTags addObject:@"price"];
            self.validationMessagesByTag[@"price"] = kLang(@"NamePriceRequired");
            [self pp_applyValidationStyleToVisibleCellForTag:@"price"];
        }
        [self pp_setDossierStateMessage:kLang(@"NamePriceRequired") isLoading:NO isError:YES showsRetry:NO];
        [self pp_focusRowTag:(name.length == 0 ? @"name" : @"price")];
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"NamePriceRequired")];
        return;
    }
    if (!mk) {
        if (self.mainKindsLoadInFlight) {
            [self pp_setDossierStateMessage:kLang(@"Loading") isLoading:YES isError:NO showsRetry:NO];
            return;
        }
        [self pp_setValidationError:kLang(@"SpeciesRequired") forRowTag:@"mainKind"];
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:kLang(@"SpeciesRequired")];
        return;
    }

    [self.view endEditing:YES];
    self.saveDockStatusIsError = NO;
    self.isSubmitting = YES;
    [self pp_updateSaveDockState];
    [PPHUD showRingIn:self.view title:kLang(@"Uploading") subtitle:kLang(@"PleaseWait")];

    PetAccessory *accessory = self.editingAccessory ?: [PetAccessory new];
    accessory.name = name;
    accessory.desc = [NSString stringWithFormat:@"%@", values[@"desc"] ?: @""];
    accessory.price = price;
    CGFloat clampedDiscountPercent = MIN(100.0, MAX(0.0, discountPercentInput.floatValue));
    accessory.discountPercent = (clampedDiscountPercent > 0.0) ? @(clampedDiscountPercent) : nil;
    accessory.discountAmount = (discountAmountInput.floatValue > 0.0) ? @(MAX(0.0, discountAmountInput.floatValue)) : nil;
    accessory.quantity = MAX(0, quantity);

    NSInteger defaultCondition = (accessory.condition == AccessConditionsUsed) ? AccessConditionsUsed : AccessConditionsNew;
    accessory.condition = [self pp_optionValueFromFormValue:values[@"condition"] defaultValue:defaultCondition];

    // Species / Breed IDs
    accessory.petMainCategoryID = mk ? mk.ID : 0;
    accessory.petSubCategoryID = sk ? sk.ID : 0;

    AccessKindType resolved = [self pp_resolvedKind];
    accessory.accessKindType = resolved;
    if (resolved == AccessTypeFood) {
        accessory.condition = AccessConditionsNew;
    }
    accessory.isNew = accessory.condition != AccessConditionsUsed;

    accessory.createdAt = accessory.createdAt ?: [NSDate date];
    if (accessory.ownerID.length == 0) {
        accessory.ownerID = [FIRAuth auth].currentUser.uid ?: @"";
    }
    accessory.storeID = storeID;
    accessory.storeName = storeName.length > 0 ? storeName : [self pp_mainStoreDisplayName];

    // Expiry date (optional)
    id expiryVal = values[@"expiryDate"];
    accessory.expiryDate = [expiryVal isKindOfClass:[NSDate class]] ? expiryVal : nil;

    accessory.active = YES;
    [accessory normalizeInventoryState];

    NSArray<UIImage *> *images = [self pp_selectedImages];
    BOOL modified = [self pp_imagesModified];
    DLog(@"[AddAccessory] selected images count = %lu, modified = %d", (unsigned long)images.count, modified);
    NSDictionary<NSString *, NSDictionary *> *existingMetaByURL = [self pp_existingMetaByURLForAccessory:self.editingAccessory ?: accessory];

    // Keep existing images when editing and user hasn't changed the selection.
    if (!modified && self.editingAccessory.imageURLsArray.count > 0) {
        DLog(@"[AddAccessory] images not modified; keeping existing URLs and saving meta.");
        accessory.imageURLsArray = self.editingAccessory.imageURLsArray ?: @[];
        accessory.imageMeta = [self pp_imageMetaForURLs:accessory.imageURLsArray
                                      existingMetaByURL:existingMetaByURL
                                      uploadedMetaByURL:@{}];
        [[AccessoryManager shared] createOrUpdateAccessory:accessory completion:^(NSError * _Nullable error) {
            [self handleSaveResult:error];
        }];
        return;
    }

    // Capture old image URLs before uploading replacements
    NSArray<NSString *> *oldImageURLs = self.editingAccessory.imageURLsArray ?: @[];

    // Upload all selected images
    NSMutableArray<NSString *> *uploadedURLs = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSDictionary *> *uploadedMetaByURL = [NSMutableDictionary dictionary];
    __block NSError *uploadError = nil;
    NSObject *uploadLock = [NSObject new];

    FIRStorageReference *storageRef = [[FIRStorage storage] reference];
    dispatch_group_t group = dispatch_group_create();

    for (UIImage *image in images) {
        NSData *data = UIImagePNGRepresentation(image);
        if (!data) continue;

        dispatch_group_enter(group);
        NSString *uuid = [[NSUUID UUID] UUIDString];
        FIRStorageReference *imgRef = [[storageRef child:@"petAccessories"] child:[NSString stringWithFormat:@"%@.png", uuid]];
        DLog(@"[AddAccessory] uploading image %@", uuid);

        FIRStorageMetadata *storageMetadata = [FIRStorageMetadata new];
        storageMetadata.contentType = @"image/png";
        storageMetadata.customMetadata = @{
            @"uploaded_by": [FIRAuth auth].currentUser.uid ?: @"",
            @"entity_type": @"accessory",
            @"media_type": @"image"
        };
        [imgRef putData:data metadata:storageMetadata completion:^(FIRStorageMetadata *metadata, NSError *error) {
            if (error) {
                DLog(@"[AddAccessory] upload error: %@", error.localizedDescription);
                @synchronized (uploadLock) {
                    if (!uploadError) uploadError = error;
                }
                dispatch_group_leave(group);
                return;
            }
            [imgRef downloadURLWithCompletion:^(NSURL *URL, NSError *error2) {
                @synchronized (uploadLock) {
                    if (URL.absoluteString.length > 0) {
                        [uploadedURLs addObject:URL.absoluteString];
                        uploadedMetaByURL[URL.absoluteString] = [self pp_metaForURL:URL.absoluteString
                                                                                width:image.size.width
                                                                               height:image.size.height];
                    }
                    if (error2 && !uploadError) uploadError = error2;
                }
                DLog(@"[AddAccessory] uploaded -> %@", URL.absoluteString);
                dispatch_group_leave(group);
            }];
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSArray<NSString *> *uploadedSnapshot = nil;
        NSDictionary<NSString *, NSDictionary *> *uploadedMetaSnapshot = nil;
        NSError *uploadErrorSnapshot = nil;
        @synchronized (uploadLock) {
            uploadedSnapshot = [uploadedURLs copy];
            uploadedMetaSnapshot = [uploadedMetaByURL copy];
            uploadErrorSnapshot = uploadError;
        }

        if (uploadErrorSnapshot) {
            // Do not persist a partially uploaded replacement set. Best-effort
            // cleanup prevents failed attempts from becoming permanent media.
            for (NSString *uploadedURL in uploadedSnapshot) {
                @try {
                    [[[FIRStorage storage] referenceForURL:uploadedURL] deleteWithCompletion:^(__unused NSError * _Nullable cleanupError) {}];
                } @catch (NSException *exception) {
                    DLog(@"[AddAccessory] invalid uploaded storage URL for cleanup: %@", uploadedURL);
                }
            }
            [self handleSaveResult:uploadErrorSnapshot];
            return;
        }

        if (uploadedSnapshot.count > 0) {
            accessory.imageURLsArray = uploadedSnapshot;
        } else if (images.count == 0) {
            accessory.imageURLsArray = @[];
        } else {
            accessory.imageURLsArray = @[];
        }
        accessory.imageMeta = [self pp_imageMetaForURLs:accessory.imageURLsArray
                                      existingMetaByURL:existingMetaByURL
                                      uploadedMetaByURL:uploadedMetaSnapshot ?: @{}];

        DLog(@"[AddAccessory] all uploads done. saving accessory…");
        [[AccessoryManager shared] createOrUpdateAccessory:accessory completion:^(NSError * _Nullable error) {
            if (!error && oldImageURLs.count > 0) {
                // Delete old images that were replaced
                NSSet *newURLSet = [NSSet setWithArray:accessory.imageURLsArray ?: @[]];
                for (NSString *oldURL in oldImageURLs) {
                    if (oldURL.length == 0 || [newURLSet containsObject:oldURL]) continue;
                    @try {
                        FIRStorageReference *oldRef = [[FIRStorage storage] referenceForURL:oldURL];
                        [oldRef deleteWithCompletion:^(NSError * _Nullable delErr) {
                            if (delErr) {
                                DLog(@"[AddAccessory] failed to delete old image: %@", delErr.localizedDescription);
                            } else {
                                DLog(@"[AddAccessory] deleted old image: %@", oldURL);
                            }
                        }];
                    } @catch (NSException *exception) {
                        DLog(@"[AddAccessory] invalid storage URL for cleanup: %@", oldURL);
                    }
                }
            }
            [self handleSaveResult:error];
        }];
    });
}

- (void)handleSaveResult:(NSError *)error {
    if (![NSThread isMainThread]) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleSaveResult:error];
        });
        return;
    }

    if (error) {
        self.isSubmitting = NO;
        self.isLeavingAfterSave = NO;
        self.saveDockStatusIsError = YES;
        self.saveDockStatusLabel.hidden = NO;
        self.saveDockStatusLabel.text = kLang(@"Error");
        self.saveDockStatusLabel.textColor = [UIColor ppError];
        [self pp_updateSaveDockState];
        [PPHUD dismiss];
        [self pp_setDossierStateMessage:kLang(@"Something went wrong.") isLoading:NO isError:YES showsRetry:NO];
        [AlertHelper showErrorIn:self title:kLang(@"Error") subtitle:error.localizedDescription ?: kLang(@"Something went wrong.")];
        DLog(@"[AddAccessory] save error: %@", error.localizedDescription);
        return;
    }

    self.isSubmitting = NO;
    self.isLeavingAfterSave = YES;
    self.saveDockStatusIsError = NO;
    self.hasUnsavedChanges = NO;
    [self pp_clearValidationErrors];
    self.saveDockStatusLabel.hidden = NO;
    self.saveDockStatusLabel.text = kLang(@"Saved");
    self.saveDockStatusLabel.textColor = [UIColor ppSuccess];
    [self pp_updateSaveDockState];
    NSString *successMessage = self.editingAccessory ? kLang(@"Your changes were saved successfully.") : kLang(@"AccessoryPosted");
    [self pp_setDossierStateMessage:successMessage isLoading:NO isError:NO showsRetry:NO];
    [PPHUD showSuccess:kLang(@"Saved") subtitle:successMessage];

    DLog(@"[AddAccessory] save success");
    // pop after a short delay so user sees the success
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

#pragma mark - Helpers (Species/Breed)

- (NSArray<MainKindsModel *> *)allMainKinds {
    return AppMgr.MainKindsArray ?: @[];
}

- (MainKindsModel *)mainKindForID:(NSInteger)kindID {
    for (MainKindsModel *m in [self allMainKinds]) {
        if (m.ID == kindID) return m;
    }
    return nil;
}

- (SubKindModel *)subKindForID:(NSInteger)subID mainID:(NSInteger)mainID {
    MainKindsModel *main = [self mainKindForID:mainID];
    if (!main) return nil;
    for (SubKindModel *s in main.SubKindsArray) {
        if (s.ID == subID) return s;
    }
    return nil;
}

#pragma mark - Subview Finder

- (UIView *)findSubviewOfClass:(Class)cls inView:(UIView *)view {
    if ([view isKindOfClass:cls]) return view;
    for (UIView *subview in view.subviews) {
        UIView *found = [self findSubviewOfClass:cls inView:subview];
        if (found) return found;
    }
    return nil;
}

#pragma mark - TableView Custom Headers & Footers

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)sectionIndex {
    if (sectionIndex < 0 || sectionIndex >= (NSInteger)self.form.formSections.count) return 0.0;
    XLFormSectionDescriptor *section = self.form.formSections[sectionIndex];
    if (section.title.length == 0) return PPSpaceMD;
    return UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)
        ? PPSpaceXXL + PPSpaceSM
        : PPSpaceXXL;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)sectionIndex {
    return sectionIndex == self.form.formSections.count - 1 ? PPSpaceLG : PPSpaceSM;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)sectionIndex {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectZero];
    footer.backgroundColor = UIColor.clearColor;
    return footer;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)sectionIndex {
    if (sectionIndex < 0 || sectionIndex >= (NSInteger)self.form.formSections.count) return nil;
    XLFormSectionDescriptor *section = self.form.formSections[sectionIndex];
    if (section.title.length == 0) return nil;

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = UIColor.clearColor;

    UIView *accent = [[UIView alloc] initWithFrame:CGRectZero];
    accent.translatesAutoresizingMaskIntoConstraints = NO;
    accent.backgroundColor = [UIColor ppPrimary];
    PPApplyContinuousCorners(accent, PPSpaceXXS);
    [header addSubview:accent];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = PPAccessoryScaledFont([Styling fontBold:PPFontSubheadline], UIFontTextStyleSubheadline);
    label.textColor = [UIColor ppTextSecondary];
    label.text = section.title;
    label.textAlignment = NSTextAlignmentNatural;
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    [header addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [accent.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:PPScreenMargin],
        [accent.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
        [accent.widthAnchor constraintEqualToConstant:PPSpaceXXS],
        [accent.heightAnchor constraintEqualToConstant:PPSpaceMD],
        [label.leadingAnchor constraintEqualToAnchor:accent.trailingAnchor constant:PPSpaceSM],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-PPScreenMargin],
        [label.topAnchor constraintGreaterThanOrEqualToAnchor:header.topAnchor constant:PPSpaceSM],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-PPSpaceXS]
    ]];

    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    return header;
}

#pragma mark - Table BG

static const void *kHasAnimatedFormCellKey = &kHasAnimatedFormCellKey;

- (void)tableView:(UITableView *)tableView
  willDisplayCell:(UITableViewCell *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath {

    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO];
    XLFormRowDescriptor *row = [self.form formRowAtIndex:indexPath];

    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    cell.textLabel.font = PPAccessoryScaledFont([Styling fontMedium:PPFontCallout], UIFontTextStyleCallout);
    cell.textLabel.textColor = [UIColor ppTextPrimary];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;

    cell.detailTextLabel.font = PPAccessoryScaledFont([Styling fontRegular:PPFontCallout], UIFontTextStyleCallout);
    cell.detailTextLabel.textColor = [UIColor ppTextSecondary];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;

    UITextField *textField = (UITextField *)[self findSubviewOfClass:[UITextField class] inView:cell];
    if (textField) {
        textField.font = PPAccessoryScaledFont([Styling fontRegular:PPFontCallout], UIFontTextStyleCallout);
        textField.textColor = [UIColor ppTextPrimary];
        textField.adjustsFontForContentSizeCategory = YES;
        textField.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        textField.textAlignment = [Language alignmentForCurrentLanguage];
        textField.accessibilityLabel = row.title;
    }

    UITextView *textView = (UITextView *)[self findSubviewOfClass:[UITextView class] inView:cell];
    if (textView) {
        textView.font = PPAccessoryScaledFont([Styling fontRegular:PPFontCallout], UIFontTextStyleCallout);
        textView.textColor = [UIColor ppTextPrimary];
        textView.adjustsFontForContentSizeCategory = YES;
        textView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        textView.textAlignment = [Language alignmentForCurrentLanguage];
        textView.accessibilityLabel = row.title;
    }

    UISegmentedControl *segmented = (UISegmentedControl *)[self findSubviewOfClass:[UISegmentedControl class] inView:cell];
    if (segmented) {
        segmented.selectedSegmentTintColor = [UIColor ppPrimary];
        segmented.backgroundColor = [UIColor ppSurfaceOverlay];
        segmented.accessibilityLabel = row.title;

        NSDictionary *normalAttributes = @{
            NSFontAttributeName: PPAccessoryScaledFont([Styling fontMedium:PPFontFootnote], UIFontTextStyleFootnote),
            NSForegroundColorAttributeName: [UIColor ppTextSecondary]
        };
        NSDictionary *selectedAttributes = @{
            NSFontAttributeName: PPAccessoryScaledFont([Styling fontBold:PPFontFootnote], UIFontTextStyleFootnote),
            NSForegroundColorAttributeName: PPOnPrimaryColor()
        };
        [segmented setTitleTextAttributes:normalAttributes forState:UIControlStateNormal];
        [segmented setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
        segmented.layer.cornerRadius = PPCornerSmall;
        segmented.clipsToBounds = YES;
    }

    if ([row.tag isEqualToString:@"finalPrice"]) {
        cell.contentView.backgroundColor = [UIColor ppPrimaryShiner];
        cell.textLabel.textColor = [UIColor ppAccentText];
        if (textField) textField.textColor = [UIColor ppAccentText];
    }

    if ([cell isKindOfClass:[PPImageCollectionRow class]]) {
        PPImageCollectionRow *imageRow = (PPImageCollectionRow *)cell;
        if (!self.imageDelegateProxy) {
            self.imageDelegateProxy = [PPAccessoryImageCollectionDelegateProxy new];
            self.imageDelegateProxy.owner = self;
        }
        self.imageDelegateProxy.row = imageRow;
        imageRow.imageCollection.delegate = self.imageDelegateProxy;
        imageRow.imageCollection.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        imageRow.imageCollection.accessibilityLabel = kLang(@"Images");
        cell.accessibilityLabel = kLang(@"Images");
    }

    if ([row.rowType isEqualToString:XLFormRowDescriptorTypeSelectorPush] ||
        [row.rowType isEqualToString:XLFormRowDescriptorTypeDate]) {
        cell.accessibilityLabel = row.title;
        cell.accessibilityValue = row.displayTextValue;
    }

    [self pp_applyValidationStyleToCell:cell row:row];

    // Spring Staggered Entrance Animation for Form Rows
    if (!UIAccessibilityIsReduceMotionEnabled() && !objc_getAssociatedObject(cell, kHasAnimatedFormCellKey)) {
        objc_setAssociatedObject(cell, kHasAnimatedFormCellKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        cell.alpha = 0.0;
        cell.transform = CGAffineTransformMakeTranslation(0, 16.0);
        
        [UIView animateWithDuration:PPAnimDurationSlow
                              delay:0.03 * indexPath.row
             usingSpringWithDamping:0.85
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            cell.alpha = 1.0;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

@end
