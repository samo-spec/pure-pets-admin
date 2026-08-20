#import "PPCategoriesViewController.h"
#import "PPCategoryEditorViewController.h"
#import "MainKindsArrayManager.h"
#import "PPStaffAuth.h"
#import "PPHUD.h"
#import "Language.h"
#import "Styling.h"
@import Firebase;
@import FirebaseAuth;
static NSString *const kCategoryCellID = @"CategoryCell";

@interface PPCategoriesViewController ()
@property (nonatomic, strong) NSArray<MainKindsModel *> *categories;
@property (nonatomic, assign) BOOL hasAppeared;
@property (nonatomic, assign) BOOL didPrepareEntrance;
@property (nonatomic, strong) UIView *heroHeaderView;
@property (nonatomic, strong) UILabel *heroTitleLabel;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, assign) BOOL canManage;
@end

@implementation PPCategoriesViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigation];
    [self setupTableView];
    [self loadData];
    [self evaluatePermissions];
}

- (void)setupNavigation {
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.title = kLang(@"Categories_Title");
    
    if (self.canManage) {
        UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(didTapAdd)];
        self.navigationItem.rightBarButtonItem = addButton;
        PPCommandCenterNavigationItemsDidChange(self);
    }
}

- (void)setupTableView {
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCategoryCellID];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = PPSpace4XL;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(refreshData) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)evaluatePermissions {
    BOOL hasView = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermCategoriesView];
    BOOL hasManage = [[PPStaffAuth shared].cachedCurrentStaff hasPermission:kStaffPermCategoriesManage];
    self.canManage = hasManage;
    if (!hasView && !hasManage) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
}

- (void)loadData {
    self.categories = [PPMainKindsArray copy];
    [self.tableView reloadData];
    [self updateHero];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mainKindsDidUpdate:)
                                                 name:@"MainKindsUpdatedNotification"
                                               object:nil];
}

- (void)refreshData {
    [PPMainKindsManager loadMainDataCompletionHandler:^(int result) {
        [self.refreshControl endRefreshing];
        self.categories = [PPMainKindsArray copy];
        [self.tableView reloadData];
        [self updateHero];
    }];
}

- (void)mainKindsDidUpdate:(NSNotification *)note {
    self.categories = [PPMainKindsArray copy];
    [self.tableView reloadData];
    [self updateHero];
}

- (void)updateHero {
    NSInteger total = self.categories.count;
    NSInteger visible = 0;
    for (MainKindsModel *cat in self.categories) {
        if (cat.is_visible_in_user_app) visible++;
    }
    self.heroCountLabel.text = [NSString stringWithFormat:kLang(@"Categories_Count_Format"), (long)total, (long)visible];
}

#pragma mark - Hero Header

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != 0) return nil;
    if (!self.heroHeaderView) {
        self.heroHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 120)];
        self.heroHeaderView.clipsToBounds = NO;
        
        UIView *card = [[UIView alloc] init];
        card.backgroundColor = [UIColor ppBackground];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        PPApplyContinuousCorners(card, PPCornerMedium);
        PPApplyCardShadow(card);
        [self.heroHeaderView addSubview:card];
        
        self.heroTitleLabel = [[UILabel alloc] init];
        self.heroTitleLabel.font = PPFontMedium(PPFontTitle2);
        self.heroTitleLabel.textColor = [UIColor ppTextPrimary];
        self.heroTitleLabel.text = kLang(@"Categories_Title");
        self.heroTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:self.heroTitleLabel];
        
        UILabel *subtitle = [[UILabel alloc] init];
        subtitle.font = PPFontRegular(PPFontSubheadline);
        subtitle.textColor = [UIColor ppTextSecondary];
        subtitle.text = kLang(@"Categories_Subtitle");
        subtitle.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:subtitle];
        
        self.heroCountLabel = [[UILabel alloc] init];
        self.heroCountLabel.font = PPFontMedium(PPFontCallout);
        self.heroCountLabel.textColor = AppPrimaryClr;
        self.heroCountLabel.textAlignment = NSTextAlignmentNatural;
        self.heroCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:self.heroCountLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [card.leadingAnchor constraintEqualToAnchor:self.heroHeaderView.leadingAnchor constant:PPSpaceBase],
            [card.trailingAnchor constraintEqualToAnchor:self.heroHeaderView.trailingAnchor constant:-PPSpaceBase],
            [card.topAnchor constraintEqualToAnchor:self.heroHeaderView.topAnchor constant:PPSpaceMD],
            [card.bottomAnchor constraintEqualToAnchor:self.heroHeaderView.bottomAnchor constant:-PPSpaceSM],
            
            [self.heroTitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:PPSpaceLG],
            [self.heroTitleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:PPSpaceLG],
            [self.heroTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-PPSpaceLG],
            
            [subtitle.leadingAnchor constraintEqualToAnchor:self.heroTitleLabel.leadingAnchor],
            [subtitle.topAnchor constraintEqualToAnchor:self.heroTitleLabel.bottomAnchor constant:PPSpaceXS],
            [subtitle.trailingAnchor constraintEqualToAnchor:self.heroTitleLabel.trailingAnchor],
            
            [self.heroCountLabel.leadingAnchor constraintEqualToAnchor:self.heroTitleLabel.leadingAnchor],
            [self.heroCountLabel.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:PPSpaceSM],
            [self.heroCountLabel.trailingAnchor constraintEqualToAnchor:self.heroTitleLabel.trailingAnchor],
        ]];
    }
    return self.heroHeaderView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 130 : UITableViewAutomaticDimension;
}

#pragma mark - TableView DataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.categories.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCategoryCellID forIndexPath:indexPath];
    
    MainKindsModel *cat = self.categories[indexPath.row];
    
    UIColor *tint = [cat kindColor];
    
    UIImageView *dotView = [cell.contentView viewWithTag:100];
    if (!dotView) {
        dotView = [[UIImageView alloc] init];
        dotView.tag = 100;
        dotView.translatesAutoresizingMaskIntoConstraints = NO;
        dotView.layer.cornerRadius = PPSpaceXL;
        dotView.clipsToBounds = YES;
        dotView.contentMode = UIViewContentModeCenter;
        [cell.contentView addSubview:dotView];
        
        [NSLayoutConstraint activateConstraints:@[
            [dotView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:PPSpaceMD],
            [dotView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [dotView.widthAnchor constraintEqualToConstant:PPSpace4XL],
            [dotView.heightAnchor constraintEqualToConstant:PPSpace4XL],
        ]];
    }
    dotView.backgroundColor = tint;
    
    UIImage *iconImage = nil;
    if (cat.KindIconName.length > 0) {
        iconImage = [UIImage systemImageNamed:cat.KindIconName];
    }
    if (!iconImage && cat.KindImageNamed.length > 0) {
        iconImage = [UIImage imageNamed:cat.KindImageNamed];
    }
    if (iconImage) {
        dotView.image = [iconImage imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:PPSpaceLG weight:UIImageSymbolWeightMedium]];
        dotView.tintColor = [UIColor whiteColor];
    } else {
        dotView.image = nil;
    }
    
    UILabel *nameLabel = [cell.contentView viewWithTag:101];
    if (!nameLabel) {
        nameLabel = [[UILabel alloc] init];
        nameLabel.tag = 101;
        nameLabel.font = PPFontMedium(PPFontHeadline);
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:nameLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [nameLabel.leadingAnchor constraintEqualToAnchor:dotView.trailingAnchor constant:PPSpaceMD],
            [nameLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:PPSpaceMD + 2],
            [nameLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-PPSpaceBase],
        ]];
    }
    nameLabel.text = cat.KindNameEn.length > 0 ? cat.KindNameEn : cat.KindName;
    
    UILabel *arLabel = [cell.contentView viewWithTag:102];
    if (!arLabel) {
        arLabel = [[UILabel alloc] init];
        arLabel.tag = 102;
        arLabel.font = PPFontRegular(PPFontSubheadline);
        arLabel.textColor = [UIColor ppTextSecondary];
        arLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:arLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [arLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
            [arLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:PPSpaceXXS],
            [arLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        ]];
    }
    arLabel.text = cat.KindNameAr.length > 0 ? cat.KindNameAr : nil;
    
    UILabel *metaLabel = [cell.contentView viewWithTag:103];
    if (!metaLabel) {
        metaLabel = [[UILabel alloc] init];
        metaLabel.tag = 103;
        metaLabel.font = PPFontRegular(PPFontCaption1);
        metaLabel.textColor = [UIColor ppTextTertiary];
        metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:metaLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [metaLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
            [metaLabel.topAnchor constraintEqualToAnchor:(arLabel ? arLabel.bottomAnchor : nameLabel.bottomAnchor) constant:PPSpaceXXS + 2],
            [metaLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
            [metaLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-PPSpaceMD - 2],
        ]];
    }
    metaLabel.text = [NSString stringWithFormat:@"ID: %ld · %@: %lu · %@: %@",
                      (long)cat.ID,
                      kLang(@"Categories_SubKinds"),
                      (unsigned long)cat.SubKindsArray.count,
                      kLang(@"Categories_Visibility"),
                      cat.is_visible_in_user_app ? kLang(@"Visible") : kLang(@"Hidden")];
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    
    UIView *selBg = [UIView new];
    selBg.backgroundColor = [[tint colorWithAlphaComponent:0.08] colorWithAlphaComponent:1.0];
    cell.selectedBackgroundView = selBg;
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.canManage;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        MainKindsModel *cat = self.categories[indexPath.row];
        [self confirmDeleteCategory:cat];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.canManage) return;
    MainKindsModel *cat = self.categories[indexPath.row];
    PPCategoryEditorViewController *editor = [[PPCategoryEditorViewController alloc] initWithCategory:cat];
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - Actions

- (void)didTapAdd {
    PPCategoryEditorViewController *editor = [[PPCategoryEditorViewController alloc] initWithCategory:nil];
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)confirmDeleteCategory:(MainKindsModel *)cat {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Delete_Confirm_Title")
                                                                   message:[NSString stringWithFormat:kLang(@"Delete_Confirm_Message"), cat.KindName]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *del = [UIAlertAction actionWithTitle:kLang(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self deleteCategory:cat];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:del];
    [alert addAction:cancel];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.tableView;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteCategory:(MainKindsModel *)cat {
    NSString *docID = cat.documentID.length > 0 ? cat.documentID : [NSString stringWithFormat:@"%ld", (long)cat.ID];
    [[[[FIRFirestore firestore] collectionWithPath:@"MainKindsCollection"] documentWithPath:docID]
     deleteDocumentWithCompletion:^(NSError *error) {
        if (error) {
            [PPHUD showError:kLang(@"Error_Generic")];
        } else {
            [PPHUD showSuccess:kLang(@"Category_Deleted")];
            [self writeAuditLog:@"delete_category" category:cat];
        }
    }];
}

- (void)writeAuditLog:(NSString *)action category:(MainKindsModel *)cat {
    NSString *uid = [FIRAuth auth].currentUser.uid ?: @"";
    [[[[FIRFirestore firestore] collectionWithPath:@"AdminAuditLogs"] documentWithAutoID]
      setData:@{
        @"action": action ?: @"",
        @"targetCollection": @"MainKindsCollection",
        @"targetId": cat.documentID ?: [NSString stringWithFormat:@"%ld", (long)cat.ID],
        @"adminUid": uid,
        @"timestamp": [FIRFieldValue fieldValueForServerTimestamp],
    }];
}

#pragma mark - Entrance Animation

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self runEntranceIfNeeded];
}

- (void)runEntranceIfNeeded {
    if (self.didPrepareEntrance) return;
    self.didPrepareEntrance = YES;
    
    self.heroHeaderView.alpha = 0;
    self.heroHeaderView.transform = CGAffineTransformMakeTranslation(0, 14);
    
    [UIView animateWithDuration:0.42 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.heroHeaderView.alpha = 1;
        self.heroHeaderView.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    [self.tableView.visibleCells enumerateObjectsUsingBlock:^(UITableViewCell *cell, NSUInteger idx, BOOL *stop) {
        cell.alpha = 0;
        cell.transform = CGAffineTransformMakeTranslation(0, 10);
        [UIView animateWithDuration:0.32 delay:0.08 + idx * 0.04 options:UIViewAnimationOptionCurveEaseOut animations:^{
            cell.alpha = 1;
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
