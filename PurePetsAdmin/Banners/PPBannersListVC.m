//
//  PPBannersListVC.m
//  PurePetsAdmin
//
//  Created by Admin on 09/09/2025.
//
//  PPBannersListVC.m
//  PurePetsAdmin
//  PPBannersListVC.m
//  PurePetsAdmin

#import "PPBannersListVC.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "PPBannersManager.h"
#import "PPDesignTokens.h"
@import Firebase;
@import FirebaseAuth;
// Your app headers (adjust if needed)


// If you use Firebase listener types without importing the whole SDK here:

@interface PPBannersListVC () <PPSDelegate, PPCellWithButtonsDelegate>
{
    UIView *containerView;
}
@property (nonatomic, strong) id<FIRListenerRegistration> bannersListener;

@property (nonatomic, strong) PPS *searchView;
@property (nonatomic, strong) NSMutableArray<MainBannerModel *> *banners;
@property (nonatomic, strong) NSMutableArray<MainBannerModel *> *filteredBanners;
@property (nonatomic, copy)   NSString *currentQuery;
@property (nonatomic, strong) UIView *summaryHeader;
@property (nonatomic, strong) UILabel *totalMetricLabel;
@property (nonatomic, strong) UILabel *visibleMetricLabel;
@property (nonatomic, strong) UILabel *hiddenMetricLabel;
@property (nonatomic, strong) UILabel *groupMetricLabel;
@property (nonatomic, assign) BOOL isSizingSummaryHeader;
@end

@implementation PPBannersListVC

static void PPBannerApplyCardChrome(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    view.layer.borderColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.72].CGColor;
    view.layer.shadowColor = [UIColor ppShadow].CGColor;
    view.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    view.layer.shadowRadius = 18.0;
    view.layer.shadowOpacity = 0.045;
}

static UIView *PPBannerMetric(NSString *caption, UILabel * __strong *valueLabel) {
    UIView *metric = [UIView new];
    metric.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *value = [UILabel new];
    value.translatesAutoresizingMaskIntoConstraints = NO;
    value.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle3] scaledFontForFont:[Styling fontBold:20]];
    value.textColor = [UIColor ppPrimary];
    value.textAlignment = NSTextAlignmentCenter;
    value.adjustsFontForContentSizeCategory = YES;
    value.text = @"0";
    [metric addSubview:value];

    UILabel *captionLabel = [UILabel new];
    captionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    captionLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1] scaledFontForFont:[Styling fontMedium:11]];
    captionLabel.textColor = [UIColor ppTextSecondary];
    captionLabel.textAlignment = NSTextAlignmentCenter;
    captionLabel.adjustsFontForContentSizeCategory = YES;
    captionLabel.text = caption;
    [metric addSubview:captionLabel];

    [NSLayoutConstraint activateConstraints:@[
        [value.topAnchor constraintEqualToAnchor:metric.topAnchor constant:8.0],
        [value.leadingAnchor constraintEqualToAnchor:metric.leadingAnchor constant:4.0],
        [value.trailingAnchor constraintEqualToAnchor:metric.trailingAnchor constant:-4.0],
        [captionLabel.topAnchor constraintEqualToAnchor:value.bottomAnchor constant:2.0],
        [captionLabel.leadingAnchor constraintEqualToAnchor:metric.leadingAnchor constant:4.0],
        [captionLabel.trailingAnchor constraintEqualToAnchor:metric.trailingAnchor constant:-4.0],
        [captionLabel.bottomAnchor constraintEqualToAnchor:metric.bottomAnchor constant:-8.0]
    ]];
    if (valueLabel) *valueLabel = value;
    return metric;
}

-(void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
}
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)view;
    (void)section;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.filteredBanners.count; // each group = section
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    MainBannerModel *group = self.filteredBanners[section];
    return group.childBanners.count; // rows = banners in that group
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    MainBannerModel *group = self.filteredBanners[indexPath.section];
    PPBannerViewModel *child = group.childBanners[indexPath.row];
    PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeBannerOnly group:group banner:child];
    [self.navigationController pushViewController:vc animated:YES];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPCellWithButtons *cell = [tableView dequeueReusableCellWithIdentifier:@"PPCellWithButtons"
                                                              forIndexPath:indexPath];
    
    MainBannerModel *group = self.filteredBanners[indexPath.section];
    PPBannerViewModel *banner = group.childBanners[indexPath.row];
    cell.PPbannerModel = banner;
    cell.PPGroubModel = group;
    
    cell.titleLabel.text = PPSafeString([banner localizedTitleText]);
    cell.subtitleLabel.text = PPSafeString([banner localizedDescText]);
    cell.detailLabel.text = PPSafeString(banner.postDateText);
    cell.delegate = self;

    if (banner.sampleImageURL) {
        // With custom fade
        [[PPImageManager sharedManager] setImageFromUrl:banner.sampleImageURL.absoluteString
                                            toImageView:cell.avatarImageView
                                               fadeType:PPImageFadeTypeCrossDissolve
                                               duration:0.35
                                             completion:nil];
        
        
        
      
    } else {
        cell.avatarImageView.image = nil;
    }
    return cell;
}

/*
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    MainBannerModel *group = self.filteredBanners[section];
    
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = AppClearClr;
    
    
    UIView *container = [[UIView alloc] init];
    //[Styling applyCardStyleToView:container];
    container.backgroundColor = AppClearClr;
    
    UILabel *title = [[UILabel alloc] init];
    title.text = [NSString stringWithFormat:@"%@: %@ • %@",kLang(@"screen"), [self _holderName:group.bannerViewHolder], [self _bannerPositionName:group.bannerViewPosition]];
    title.font = [Styling fontBold:18];
    title.numberOfLines = 1;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.7;
    [container addSubview:title];
    
    // Add button
    UIButton *addBtn = [self pp_circleButtonWithSystemName:@"plus" action:@selector(onAddBannerToGroup:)];
    addBtn.tag = section;
    //addBtn.backgroundColor = [UIColor ppWarning];
    [container addSubview:addBtn];
    
    // Update button
    UIButton *editBtn = [self pp_circleButtonWithSystemName:@"pencil" action:@selector(editGroup:)];
    editBtn.tag = section;
    //editBtn.backgroundColor = [UIColor ppError];
    [container addSubview:editBtn];
    
    // Delete button
    UIButton *delBtn = [self pp_circleButtonWithSystemName:@"trash" action:@selector(deleteGroup:)];
    delBtn.tag = section;
   // delBtn.backgroundColor = [UIColor ppSuccess];
    [container addSubview:delBtn];
    [header addSubview:container];
    // Disable autoresizing mask translation
    container.translatesAutoresizingMaskIntoConstraints = NO;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    addBtn.translatesAutoresizingMaskIntoConstraints = NO;
    editBtn.translatesAutoresizingMaskIntoConstraints = NO;
    delBtn.translatesAutoresizingMaskIntoConstraints = NO;
    
    
    addBtn.backgroundColor = AppBackgroundClr;
    editBtn.backgroundColor = AppBackgroundClr;
    delBtn.backgroundColor = AppBackgroundClr;
    
    CGFloat buttonSize = 36;
    // Set up constraints
    [NSLayoutConstraint activateConstraints:@[
        // Title constraints
        [title.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [title.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:addBtn.leadingAnchor constant:-16],
        
        // Add button constraints
        [addBtn.trailingAnchor constraintEqualToAnchor:editBtn.leadingAnchor constant:-8],
        [addBtn.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [addBtn.widthAnchor constraintEqualToConstant:buttonSize],
        [addBtn.heightAnchor constraintEqualToConstant:buttonSize],
        
        // Edit button constraints
        [editBtn.trailingAnchor constraintEqualToAnchor:delBtn.leadingAnchor constant:-8],
        [editBtn.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [editBtn.widthAnchor constraintEqualToConstant:buttonSize],
        [editBtn.heightAnchor constraintEqualToConstant:buttonSize],
        
        // Delete button constraints
        [delBtn.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-5],
        [delBtn.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [delBtn.widthAnchor constraintEqualToConstant:buttonSize],
        [delBtn.heightAnchor constraintEqualToConstant:buttonSize],
        
        // Header height constraint
        [header.heightAnchor constraintEqualToConstant:60],
        
        [container.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:0],
        [container.topAnchor constraintEqualToAnchor:header.topAnchor],
        [container.trailingAnchor constraintLessThanOrEqualToAnchor:addBtn.leadingAnchor constant:-0],
        [container.heightAnchor constraintEqualToConstant:50],
        [container.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
    ]];
    
    addBtn.layer.cornerRadius =
    editBtn.layer.cornerRadius = 
    delBtn.layer.cornerRadius = 18;
    container.layer.cornerRadius = 25;
    
    
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.bounds = container.bounds;
    gradient.colors = @[ (__bridge id)[AppPrimaryClr colorWithAlphaComponent:0.9].CGColor,
                         (__bridge id)[AppPrimaryClrShiner colorWithAlphaComponent:0.9].CGColor ];
    gradient.startPoint = CGPointMake(0.5, 0.0);
    gradient.endPoint   = CGPointMake(0.5, 1.0);
    [container.layer addSublayer:gradient];
    
    
    return header;
}
*/

// Create a helper method for HUD handling
- (void)handleCompletionWithError:(NSError *)error successMessage:(NSString *)successMessage {
    [PPHUD dismiss];
    
    if (error) {
        [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
    } else {
        [PPHUD showSuccess:kLang(@"Saved") subtitle:successMessage];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.navigationController popViewControllerAnimated:YES];
        });
    }
}



- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    MainBannerModel *group = self.filteredBanners[section];
    
    
    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;
    header.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.backgroundColor = [UIColor ppElevatedSurface];
    PPBannerApplyCardChrome(containerView, 18.0);
    [header addSubview:containerView];

    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [containerView.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
        [containerView.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
        [containerView.topAnchor constraintEqualToAnchor:header.topAnchor constant:5.0],
        [containerView.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-5.0],
    ]];
    
    UILabel *title = [[UILabel alloc] init];
    title.text = [NSString stringWithFormat:@"%@: %@",kLang(@"screen"), [self _holderName:group.bannerViewHolder]];
   // title.text = [NSString stringWithFormat:@"%@: %@ • %@",kLang(@"screen"), [self _holderName:group.bannerViewHolder], [self _bannerPositionName:group.bannerViewPosition]];
  //    title.text = [NSString stringWithFormat:@"%@: %@",kLang(@"screen"), [self _holderName:group.bannerViewHolder]];

    title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:16]];
    title.numberOfLines = 1;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.9;
    title.adjustsFontForContentSizeCategory = YES;
    title.textAlignment = [Language alignmentForCurrentLanguage];
    title.textColor = [UIColor ppTextPrimary];
    [containerView addSubview:title];
    
    // Create button container
    UIStackView *buttonStack = [[UIStackView alloc] init];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 0;
    buttonStack.distribution = UIStackViewDistributionEqualSpacing;
    buttonStack.alignment = UIStackViewAlignmentCenter;
    [containerView addSubview:buttonStack];

    
    // Customize font via attributedTitle
    UIFont *customFont = [Styling fontMedium:16];
    NSDictionary *attributes = @{
        NSFontAttributeName: customFont,
        NSForegroundColorAttributeName: AppPrimaryClr
    };

    
    
    UIButton *optionsButton = [self currentCircleButtonWithSystemName:@"ellipsis" action:nil];  // hand.point.up.braille.badge.ellipsis
    optionsButton.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];
    optionsButton.tintColor = [UIColor ppPrimary];
    
    [optionsButton.imageView addSymbolEffect: [[NSSymbolWiggleEffect wiggleBackwardEffect] effectWithByLayer] options: [NSSymbolEffectOptions optionsWithRepeatBehavior:[NSSymbolEffectOptionsRepeatBehavior behaviorPeriodicWithDelay:3.0]]];
    optionsButton.layer.cornerRadius = 18;
    optionsButton.clipsToBounds = YES;
    __weak typeof(self) weakSelf = self;
    NSInteger currentSection = section; // capture section
   
    
    // Create menu actions
    UIAction *add = [UIAction actionWithTitle:kLang(@"Add banner to group")
                                         image:[UIImage systemImageNamed:@"plus"]
                                    identifier:[NSString stringWithFormat:@"%ld",section]
                                       handler:^(__kindof UIAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
           if (!self) return;
        MainBannerModel *group = self.filteredBanners[currentSection];
        PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeGroupOnly group:group  banner:nil];
        [self.navigationController pushViewController:vc animated:YES];
    }];
    NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:add.title attributes:attributes];
    [add setValue:attrTitle forKey:@"attributedTitle"];
    
    
    
    // Create menu actions
    UIAction *edit = [UIAction actionWithTitle:kLang(@"Edit Banner Group")
                                         image:[UIImage systemImageNamed:@"pencil"]
                                    identifier:[NSString stringWithFormat:@"%ld",section]
                                       handler:^(__kindof UIAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
           if (!self) return;
        MainBannerModel *group = self.filteredBanners[currentSection];
        PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeGroupOnly group:group  banner:nil];
        [self.navigationController pushViewController:vc animated:YES];
    }];
    attrTitle = [[NSAttributedString alloc] initWithString:edit.title attributes:attributes];
    [edit setValue:attrTitle forKey:@"attributedTitle"];
    
    

    UIAction *delete = [UIAction actionWithTitle:kLang(@"Delete")
                                           image:[UIImage systemImageNamed:@"trash"]
                                      identifier:nil
                                         handler:^(__kindof UIAction * _Nonnull action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        MainBannerModel *group = self.filteredBanners[currentSection];
        
        [AlertHelper showConfirmationIn:self
                                  title:kLang(@"Confirm Delete")
                               subtitle:kLang(@"Delete this entire banner group?")
                            placeholder:nil
                          confirmButton:kLang(@"Delete")
                           cancelButton:kLang(@"Cancel")
                            confirmBlock:^{
            [PPHUD showIndeterminateIn:self.view title:kLang(@"Deleting") subtitle:nil];
            
            [[PPBannersManager sharedManager] deleteBannerGroup:group completion:^(NSError * _Nullable error) {
                [PPHUD dismiss];
                if (error) {
                    [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
                } else {
                    [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Group removed")];
                }
            }];
        } cancelBlock:^{}];
    }];
    
    attrTitle = [[NSAttributedString alloc] initWithString:delete.title attributes:attributes];

    // Sneakily set it via KVC
    [delete setValue:attrTitle forKey:@"attributedTitle"];

    UIAction *newAction= [UIAction actionWithTitle:kLang(@"Add banner to group")
                                                     image:[UIImage systemImageNamed:@"plus"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction * _Nonnull action) {
        
        __strong typeof(weakSelf) self = weakSelf;
           if (!self) return;
        MainBannerModel *group = self.filteredBanners[currentSection];
        PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeAddBannerToGroup group:group  banner:nil];
        [self.navigationController pushViewController:vc animated:YES];
   
        
        
    }];
    attrTitle = [[NSAttributedString alloc] initWithString:newAction.title attributes:attributes];
    [newAction setValue:attrTitle forKey:@"attributedTitle"];
    
    
    
    UIAction *toggleVisibility = [UIAction actionWithTitle:group.bannerViewVisible ? kLang(@"GrouphiddenActionHide") : kLang(@"GrouphiddenActionShow")
                                                     image:[UIImage systemImageNamed:group.bannerViewVisible ? @"eye.slash" : @"eye"]
                                                identifier:nil
                                                   handler:^(__kindof UIAction * _Nonnull action) {
        [PPHUD showIndeterminateIn:self.view title:kLang(@"Updating") subtitle:nil];
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        MainBannerModel *group = self.filteredBanners[currentSection];
        group.bannerViewVisible = !group.bannerViewVisible; // you need a property like "hidden"
        [PPBannersManager.sharedManager updateBannerGroup:group completion:^(NSError * _Nullable error) {
            if(!error)
            {
                [PPHUD dismiss];
                [PPHUD showSuccess:kLang(@"Updated") subtitle:group.bannerViewVisible ? kLang(@"Group hidden") : kLang(@"Group visible")];
                [self.tableView reloadData];
            }else { [PPHUD dismiss]; }
        }];
        
        
    }];
    attrTitle = [[NSAttributedString alloc] initWithString:toggleVisibility.title
                                                                    attributes:attributes];

    // Sneakily set it via KVC
    [toggleVisibility setValue:attrTitle forKey:@"attributedTitle"];
    // Create menu
    UIMenu *menu = [UIMenu menuWithTitle:kLang(@"Group Settings") children:@[newAction , edit, delete, toggleVisibility]];

    // Attach menu to button
    optionsButton.menu = menu;
    optionsButton.showsMenuAsPrimaryAction = YES;
    [buttonStack addArrangedSubview:optionsButton];
    // Set fixed button sizes
    for (UIButton *button in buttonStack.arrangedSubviews) {
        [button.widthAnchor constraintEqualToConstant:40].active = YES;
        [button.heightAnchor constraintEqualToConstant:40].active = YES;

    }
    
    // Disable autoresizing mask translation
    title.translatesAutoresizingMaskIntoConstraints = NO;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
   
    // Disable autoresizing mask translation
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
       title.translatesAutoresizingMaskIntoConstraints = NO;
       buttonStack.translatesAutoresizingMaskIntoConstraints = NO;
       
       // Set up constraints
       [NSLayoutConstraint activateConstraints:@[
         
           
           // Title constraints
           [title.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:22],
           [title.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
           [title.trailingAnchor constraintLessThanOrEqualToAnchor:buttonStack.leadingAnchor constant:-22],
           
           // Button stack constraints
           [buttonStack.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16],
           [buttonStack.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor],
           [buttonStack.heightAnchor constraintEqualToConstant:40]
       ]];
    
       // Store gradient layer reference for layout updates
       
       return header;
}


- (UIButton *)currentCircleButtonWithSystemName:(NSString *)sfName action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b pp_setSymbolNamed:sfName pointSize:22 weight:UIImageSymbolWeightRegular scale:UIImageSymbolScaleMedium tint:AppForgroundColr palette:@[AppForgroundColr,AppBackgroundClrShiner]];

    //b.contentEdgeInsets = UIEdgeInsetsMake(4,4,4,4);

    b.backgroundColor = [UIColor clearColor];
    [NSLayoutConstraint activateConstraints:@[
        [b.widthAnchor constraintEqualToConstant:40.0],
        [b.heightAnchor constraintEqualToConstant:40.0]
    ]];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    b.layer.cornerRadius = 20;
    return b;
}


- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 74;
}


- (void)onAddBannerToGroup:(UIButton *)sender {
    MainBannerModel *group = self.filteredBanners[sender.tag];
    PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeAddBannerToGroup group:group banner:nil];
    [self.navigationController pushViewController:vc animated:YES];
}





- (void)deleteGroup:(UIButton *)sender {
    MainBannerModel *group = self.filteredBanners[sender.tag];
    
    [AlertHelper showConfirmationIn:self
                              title:kLang(@"Confirm Delete")
                           subtitle:kLang(@"Delete this entire banner group?")
                        placeholder:nil
                      confirmButton:kLang(@"Delete")
                       cancelButton:kLang(@"Cancel")
                        confirmBlock:^{
        
        [PPHUD showIndeterminateIn:self.view title:kLang(@"Deleting") subtitle:nil];
        
        [[PPBannersManager sharedManager] deleteBannerGroup:group completion:^(NSError * _Nullable error) {
            [PPHUD dismiss];
            
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Group removed")];
            }
        }];
    } cancelBlock:^{}];
}




#pragma mark - Lifecycle

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        // custom if needed
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = AppBackgroundClr;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 100;
    [self.tableView registerClass:[PPCellWithButtons class] forCellReuseIdentifier:@"PPCellWithButtons"];

    self.banners = [NSMutableArray array];
    self.filteredBanners = [NSMutableArray array];

    [self setupSearchHeader];

    // Nav
    UIButton *plus = [self pp_ButtonWithSystemName:@"plus" action:@selector(addBanner)];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto
                      button:plus
                       title:kLang(@"Banners_Manage_Title")
                    showBack:YES];

    __weak typeof(self) weakSelf = self;
    // Real-time Firestore listener via manager
    self.bannersListener = [[PPBannersManager sharedManager] observeAllBanner:^(NSArray<MainBannerModel *> * _Nullable items, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[PPBannersListVC] observe error: %@", error);
            return;
        }
        weakSelf.banners = items.mutableCopy;
        [weakSelf _applyFilterAndReload];
    }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Re-apply nav each appear (like your accessories VC)
    UIButton *plus = [self pp_ButtonWithSystemName:@"plus" action:@selector(addBanner)];
    
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto
                      button:plus
                       title:kLang(@"Manage Banners")
                    showBack:YES];
}

- (void)dealloc {
    if (self.bannersListener) {
        [self.bannersListener remove];
    }
}

#pragma mark - UI header (search)

- (void)setupSearchHeader {
    CGFloat barH = 50.0, pad = 16.0;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 1.0)];
    container.backgroundColor = UIColor.clearColor;
    container.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12.0;
    [container addSubview:stack];

    UIView *summary = [UIView new];
    summary.translatesAutoresizingMaskIntoConstraints = NO;
    summary.backgroundColor = [UIColor ppElevatedSurface];
    PPBannerApplyCardChrome(summary, 22.0);
    [stack addArrangedSubview:summary];
    [summary.heightAnchor constraintGreaterThanOrEqualToConstant:96.0].active = YES;

    UIStackView *metrics = [[UIStackView alloc] initWithArrangedSubviews:@[
        PPBannerMetric(kLang(@"Banners_Stat_Total"), &_totalMetricLabel),
        PPBannerMetric(kLang(@"Banners_Stat_Visible"), &_visibleMetricLabel),
        PPBannerMetric(kLang(@"Banners_Stat_Hidden"), &_hiddenMetricLabel),
        PPBannerMetric(kLang(@"Banners_Stat_Groups"), &_groupMetricLabel)
    ]];
    metrics.translatesAutoresizingMaskIntoConstraints = NO;
    metrics.axis = UILayoutConstraintAxisHorizontal;
    metrics.alignment = UIStackViewAlignmentFill;
    metrics.distribution = UIStackViewDistributionFillEqually;
    metrics.spacing = 1.0;
    [summary addSubview:metrics];

    PPS *sv = [[PPS alloc] initWithFrame:CGRectZero];
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    sv.delegate = self;
    sv.cornerRadius = barH/2.0;
    sv.blurEnabled = NO;
    sv.shadowEnabled = NO;
    sv.strokeColor = [[UIColor ppSurfaceBorder] colorWithAlphaComponent:0.85];
    sv.textField.placeholder = kLang(@"Banners_Search_Placeholder");
    sv.textField.textColor = [UIColor ppTextPrimary];
   // sv.textField.adjustsFontForContentSizeCategory = YES;
  //  sv.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
   // sv.backgroundColor = [UIColor ppElevatedSurface];

    UIImage *filterImg = [UIImage pp_symbolNamed:@"calendar.day.timeline.leading.circle" pointSize:22 weight:UIImageSymbolWeightRegular scale:UIImageSymbolScaleLarge palette:@[AppPrimaryClr,AppBackgroundClr] makeTemplate:YES];
    [sv configurePrimaryButtonWithImage:filterImg target:self action:@selector(onFilterTapped)];
    sv.showsPrimaryButton = YES;

    [stack addArrangedSubview:sv];
    [sv.heightAnchor constraintEqualToConstant:barH].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:pad],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:pad],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-pad],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-pad],
        [metrics.topAnchor constraintEqualToAnchor:summary.topAnchor constant:10.0],
        [metrics.leadingAnchor constraintEqualToAnchor:summary.leadingAnchor constant:10.0],
        [metrics.trailingAnchor constraintEqualToAnchor:summary.trailingAnchor constant:-10.0],
        [metrics.bottomAnchor constraintEqualToAnchor:summary.bottomAnchor constant:-10.0]
    ]];

    self.tableView.tableHeaderView = container;
    self.searchView = sv;
    self.summaryHeader = container;
    [self pp_updateSummaryHeader];
    [self pp_sizeSummaryHeader];
}

- (void)pp_sizeSummaryHeader {
    if (!self.summaryHeader || self.isSizingSummaryHeader) return;
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) return;
    self.isSizingSummaryHeader = YES;
    CGRect frame = self.summaryHeader.frame;
    BOOL widthChanged = fabs(frame.size.width - width) > 0.5;
    frame.size.width = width;
    self.summaryHeader.frame = frame;
    [self.summaryHeader setNeedsLayout];
    [self.summaryHeader layoutIfNeeded];
    CGFloat height = [self.summaryHeader systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                                         withHorizontalFittingPriority:UILayoutPriorityRequired
                                               verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat targetHeight = ceil(MAX(1.0, height));
    BOOL heightChanged = fabs(frame.size.height - targetHeight) > 0.5;
    if (widthChanged || heightChanged) {
        frame.size.height = targetHeight;
        self.summaryHeader.frame = frame;
        self.tableView.tableHeaderView = self.summaryHeader;
    }
    self.isSizingSummaryHeader = NO;
}

- (void)pp_updateSummaryHeader {
    NSInteger total = 0;
    NSInteger visible = 0;
    NSInteger hidden = 0;
    for (MainBannerModel *group in self.banners ?: @[]) {
        NSInteger groupCount = group.childBanners.count;
        total += groupCount;
        if (group.bannerViewVisible) visible += groupCount;
        else hidden += groupCount;
    }
    self.totalMetricLabel.text = [NSString stringWithFormat:@"%ld", (long)total];
    self.visibleMetricLabel.text = [NSString stringWithFormat:@"%ld", (long)visible];
    self.hiddenMetricLabel.text = [NSString stringWithFormat:@"%ld", (long)hidden];
    self.groupMetricLabel.text = [NSString stringWithFormat:@"%ld", (long)self.banners.count];
}

- (void)onFilterTapped {
    [PPToast toast:kLang(@"Filter coming soon")];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pp_sizeSummaryHeader];
}

#pragma mark - Search delegate

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    self.currentQuery = text ?: @"";
    [self _applyFilterAndReload];
}

- (void)_applyFilterAndReload {
    NSString *q = (self.currentQuery ?: @"").lowercaseString;
    if (q.length == 0) {
        self.filteredBanners = self.banners.mutableCopy;
    } else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(MainBannerModel *m, NSDictionary *_) {
            // Match on documentID or any child localized title/desc
            BOOL hit = [PPSafeString(m.bannerViewID).lowercaseString containsString:q];
            if (hit) return YES;
            for (PPBannerViewModel *child in m.childBanners) {
                NSString *t = PPSafeString([child localizedTitleText]).lowercaseString;
                NSString *d = PPSafeString([child localizedDescText]).lowercaseString;
                if ([t containsString:q] || [d containsString:q]) return YES;
            }
            return NO;
        }];
        self.filteredBanners = [[self.banners filteredArrayUsingPredicate:p] mutableCopy];
    }
    [self pp_updateSummaryHeader];
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)addBanner {
    // Push your Add/Edit Banner VC
    // Replace with your own controller if name differs
    PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeNewGroup
                                                                                  group:nil
                                                                                 banner:nil];
    [self.navigationController pushViewController:vc animated:YES];

}

#pragma mark - TableView delegate
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 112.0;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(PPCellWithButtons *)cell
forRowAtIndexPath:(NSIndexPath *)indexPath
{
    (void)tableView;
    (void)indexPath;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.tintColor = [UIColor ppPrimary];
    cell.layer.mask = nil;
    cell.layer.shadowOpacity = 0.0;
    
    if (@available(iOS 17.0, *)) {
       //NSSymbolWiggleEffect *wiggle = [NSSymbolWiggleEffect effect];
        //[cell.firstButton.imageView addSymbolEffect:wiggle options:[NSSymbolEffectOptions optionsWithRepeatBehavior: [NSSymbolEffectOptionsRepeatBehavior behaviorPeriodicWithDelay:2.0]]];
    }
}

- (void)applyBackgroundStyleForTableView:(UITableView *)tableView
                                   cell:(UITableViewCell *)cell
                              indexPath:(NSIndexPath *)indexPath
                          useRowCardMode:(BOOL)useRowCardMode
                        buttonRowIndex:(NSInteger)buttonRowIndex
                          buttonSection:(NSInteger)buttonSection
{
    (void)tableView;
    (void)indexPath;
    (void)useRowCardMode;
    (void)buttonRowIndex;
    (void)buttonSection;
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.layer.mask = nil;
    cell.layer.shadowOpacity = 0.0;
}

#pragma mark - Swipe actions (Update / Offer / Delete)

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    //__weak typeof(self) weakSelf = self;

    UIContextualAction *updateAction =
    [self styledActionWithTitle:kLang(@"Update")
                          color:AppPrimaryClr
                          image:@"pencil.and.outline"
                        handler:^(NSIndexPath *idx) {
        
        
        PPCellWithButtons *cell = [tableView cellForRowAtIndexPath:indexPath];
        MainBannerModel *m = cell.PPGroubModel;;
        PPBannerViewModel *currnertBanner = cell.PPbannerModel;;
        PPAddBannerViewController *vc = [[PPAddBannerViewController alloc] initWithEditMode:PPEditModeBannerOnly
                                                                                      group:m
                                                                                     banner:currnertBanner];
        [self.navigationController pushViewController:vc animated:YES];
      
        
    }];
    
    
    UIContextualAction *deleteAction =
    [self styledActionWithTitle:kLang(@"Delete")
                          color:[UIColor ppError]
                          image:@"trash.circle"
                        handler:^(NSIndexPath *idx) {
       // __weak typeof(self) w = weakSelf;
        
        PPCellWithButtons *cell = [tableView cellForRowAtIndexPath:indexPath];
        MainBannerModel *m = cell.PPGroubModel;;
        PPBannerViewModel *currnertBanner = cell.PPbannerModel;
        
        
        [[PPBannersManager sharedManager] deleteChildBanner:currnertBanner inGroup:m completion:^(NSError * _Nullable error) {
            
            [PPHUD dismiss];
            
            if (error) {
                [PPHUD showError:kLang(@"Error") subtitle:error.localizedDescription];
            } else {
                [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Group removed")];
            }
        }];
    
    
    }];

    UISwipeActionsConfiguration *config =
    [UISwipeActionsConfiguration configurationWithActions:@[deleteAction, updateAction]];
    config.performsFirstActionWithFullSwipe = NO;
    return config;
}

#pragma mark - PPCellWithButtonsDelegate

- (void)cellWithButtons:(PPCellWithButtons *)cell didTapFirstButtonAtIndexPath:(NSIndexPath *)indexPath {
    [self triggerLeadingSwipeActionAtIndexPath:indexPath];
}

// Programmatically trigger first leading action (like your sample)
- (void)triggerLeadingSwipeActionAtIndexPath:(NSIndexPath *)indexPath {
    id<UITableViewDelegate> delegate = self.tableView.delegate;
    if (![delegate respondsToSelector:@selector(tableView:leadingSwipeActionsConfigurationForRowAtIndexPath:)]) return;

    UISwipeActionsConfiguration *config =
    [delegate tableView:self.tableView leadingSwipeActionsConfigurationForRowAtIndexPath:indexPath];
    if (!config || config.actions.count == 0) return;

    UIContextualAction *first = config.actions.firstObject;
    UIContextualActionHandler handler = first.handler;
    if (handler) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        handler(first, cell, ^(BOOL completed){});
    }
}

#pragma mark - Helpers

- (NSString *)_holderName:(PPBannerHolder)holder {
    switch (holder) {
        case PPBannerHolderMainView:         return kLang(@"Main");
        case PPBannerHolderAccessoriesView:  return kLang(@"Accessories");
        case PPBannerHolderAdsView:          return kLang(@"Ads");
        case PPBannerHolderFoodView:         return kLang(@"Food");
        case PPBannerHolderVetsView:         return kLang(@"Vets");
    }
    return @"";
}

- (NSString *)_bannerPositionName:(PPBannerPosition)position {
    switch (position) {
        case PPBannerPositionTop:         return kLang(@"Top");
        case PPBannerPositionCenter:        return kLang(@"Center");
        case PPBannerPositionBottom:          return kLang(@"Bottom");
    }
    return @"";
}

// Same builder as your sample to render image button
- (UIContextualAction *)styledActionWithTitle:(NSString *)title
                                        color:(UIColor *)color
                                        image:(NSString *)icon
                                      handler:(void(^)(NSIndexPath *indexPath))handler
{
    UIContextualAction *action =
    [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                            title:@""
                                          handler:^(__unused UIContextualAction *a,
                                                    __unused UIView *source,
                                                    void (^completion)(BOOL)) {
        handler(nil);
        completion(YES);
    }];

    UIView *v = [self buildViewWithTitle:title iconName:icon width:70];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:v.bounds.size];
    UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull ctx) {
        [v.layer renderInContext:ctx.CGContext];
    }];
    action.image = img;
    action.backgroundColor = AppForgroundColr;
    return action;
}

- (UIView *)buildViewWithTitle:(NSString *)title iconName:(NSString *)iconName width:(CGFloat)width {
    CGFloat containerW = 74, containerH = 74, iconSize = 28, spacing = 0;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, containerW, containerH)];
    container.backgroundColor = AppForgroundColr;
    [Styling applyCardStyleToView:container];
    container.layer.cornerRadius = 26;
    container.layer.masksToBounds = YES;
    container.backgroundColor = AppPrimaryClr;
    UIImageView *iv = [[UIImageView alloc] initWithImage:
       [UIImage pp_symbolNamed:iconName pointSize:18 weight:UIImageSymbolWeightRegular
                         scale:UIImageSymbolScaleDefault palette:@[AppForgroundColr, AppBackgroundClr] makeTemplate:YES]];
    if (@available(iOS 17.0, *)) {
        [iv addSymbolEffect:[NSSymbolWiggleEffect effect]
                    options:[NSSymbolEffectOptions optionsWithRepeatBehavior:
                             [NSSymbolEffectOptionsRepeatBehavior behaviorPeriodicWithDelay:2.0]]];
    }
    iv.tintColor = AppPrimaryClr;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.backgroundColor=AppClearClr;
    iv.frame = CGRectMake((containerW - iconSize)/2, 12, iconSize, iconSize);
    [container addSubview:iv];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(4, CGRectGetMaxY(iv.frame)+spacing,
                                                             containerW-8, 18)];
    lbl.text = kLang(title);
    lbl.font = [Styling fontBold:14];
    lbl.textColor = UIColor.whiteColor;
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.adjustsFontSizeToFitWidth = YES;
    [container addSubview:lbl];
    return container;
}

@end
