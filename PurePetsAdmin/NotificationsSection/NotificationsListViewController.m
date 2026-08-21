// NotificationsListViewController.m
#import "NotificationsListViewController.h"
#import "PPToast.h"
#import "NotificationManager.h"   // replace with your manager
#import "NotificationModel.h"     // your notification model
#import "SceneDelegate.h"
#import "Styling.h"
#import "Language.h"
#import "PPS.h"

static NSString * const PPAdminNotificationPaymentsOrderRoute = @"payments_order";

static NSString *PPAdminNotificationsTrimmedString(id value)
{
    if (![value isKindOfClass:NSString.class]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *PPAdminAuthenticatedNotificationUID(void)
{
    return PPAdminNotificationsTrimmedString([FIRAuth auth].currentUser.uid);
}

static NSDictionary *PPAdminNotificationSafeMeta(NotificationModel *model)
{
    return [model.meta isKindOfClass:NSDictionary.class] ? model.meta : @{};
}

static NSString *PPAdminNotificationDisplayTitle(NotificationModel *model)
{
    NSDictionary *meta = PPAdminNotificationSafeMeta(model);
    NSString *titleKey = PPAdminNotificationsTrimmedString(meta[@"titleLocalizationKey"]);
    if (titleKey.length > 0) {
        return kLang(titleKey);
    }
    return PPAdminNotificationsTrimmedString(model.title);
}

static NSString *PPAdminNotificationDisplayBody(NotificationModel *model)
{
    NSDictionary *meta = PPAdminNotificationSafeMeta(model);
    NSString *bodyKey = PPAdminNotificationsTrimmedString(meta[@"bodyLocalizationKey"]);
    NSString *orderReference = PPAdminNotificationsTrimmedString(meta[@"orderReference"]);
    if (bodyKey.length > 0) {
        NSString *format = kLang(bodyKey);
        return orderReference.length > 0 ? [NSString stringWithFormat:format, orderReference] : format;
    }
    return PPAdminNotificationsTrimmedString(model.body);
}

static NSString *PPAdminNotificationOrderID(NotificationModel *model)
{
    NSDictionary *meta = PPAdminNotificationSafeMeta(model);
    NSString *orderID = PPAdminNotificationsTrimmedString(meta[@"orderId"]);
    if (orderID.length == 0) orderID = PPAdminNotificationsTrimmedString(meta[@"orderID"]);
    return orderID;
}

static BOOL PPAdminNotificationRoutesToPaymentOrder(NotificationModel *model)
{
    NSDictionary *meta = PPAdminNotificationSafeMeta(model);
    NSString *route = PPAdminNotificationsTrimmedString(meta[@"route"]);
    NSString *orderID = PPAdminNotificationOrderID(model);
    if (orderID.length == 0) return NO;
    return route.length == 0 || [route isEqualToString:PPAdminNotificationPaymentsOrderRoute] || model.type == PPNotificationTypeOrder;
}

static NSString *PPAdminNotificationInboxErrorSignature(NSError *error)
{
    if (![error isKindOfClass:NSError.class]) return @"";
    return [NSString stringWithFormat:@"%@:%ld", error.domain ?: @"", (long)error.code];
}



@interface NotificationsListViewController () <UITableViewDataSource, UITableViewDelegate, PPSDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NotificationModel *> *allNotifications;
@property (nonatomic, strong) NSArray<NotificationModel *> *filteredNotifications;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

@property (nonatomic, strong) PPS *searchView;              // the PPS instance
@property (nonatomic, strong) UIView *searchContainer;      // wrapper for header

@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, strong) NSString *uid;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> inboxListener;
@property (nonatomic, strong, nullable) NSError *inboxError;
@property (nonatomic, copy, nullable) NSString *lastInboxErrorSignature;
@end

@implementation NotificationsListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.uid = PPAdminAuthenticatedNotificationUID();

    self.view.backgroundColor = AppBackgroundClr;
    self.allNotifications = @[];
    self.filteredNotifications = @[];
    self.isLoading = NO;

    [self setupTableView];
    [self setupSearchView];
    [self fetchNotificationsShowToast:YES];
    
    

}


-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // globe  // plus
    [self pp_navBarWithOtherButton:nil title:kLang(@"NotificationsTitle")];

    NSString *currentUID = PPAdminAuthenticatedNotificationUID();
    if (![self.uid isEqualToString:currentUID] ||
        (currentUID.length > 0 && !self.inboxListener)) {
        [self.inboxListener remove];
        self.inboxListener = nil;
        self.uid = currentUID;
        self.allNotifications = @[];
        self.filteredNotifications = @[];
        self.isLoading = NO;
        [self reloadTableAnimated:NO];
        [self fetchNotificationsShowToast:NO];
    }

}

#pragma mark - Setup UI

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;

    // refresh
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:kLang(@"PullToRefresh")];
    [self.refreshControl addTarget:self action:@selector(onRefresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl.tintColor = AppPrimaryClrShiner;
    if (@available(iOS 10.0, *)) {
        self.tableView.refreshControl = self.refreshControl;
    } else {
        [self.tableView addSubview:self.refreshControl];
    }

    [self.view addSubview:self.tableView];

    // constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    // ensure table header will re-layout when we change container size
    self.tableView.tableHeaderView = nil;
}



- (void)setupSearchView {
    // container height: padding + search height + padding
    CGFloat padding = 12.0;
    CGFloat searchHeight = 50.0;
    CGFloat containerHeight = padding + searchHeight + padding;

    self.searchContainer = [[UIView alloc] initWithFrame:CGRectMake(10, 0, self.view.bounds.size.width-20, containerHeight)];
    self.searchContainer.backgroundColor = UIColor.clearColor;
    self.searchContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // PPS instance
    self.searchView = [[PPS alloc] initWithFrame:CGRectZero];
    self.searchView.translatesAutoresizingMaskIntoConstraints = NO;

    // Visual & behavior config (best practices)
    self.searchView.cornerRadius = searchHeight/2.0;
    self.searchView.blurEnabled = NO;
    self.searchView.shadowEnabled = YES;
    self.searchView.debounceInterval = 0.16;
    self.searchView.fuzzyEnabled = YES;
    self.searchView.caseInsensitive = YES;            // typical user expectation
    self.searchView.diacriticsInsensitive = YES;      // Arabic normalized already in PPS
    self.searchView.minRelevanceScore = 0.45;         // tune for recall/precision
    self.searchView.maxResults = 200;
    self.searchView.delegate = self;
    self.searchView.backgroundColor = AppForgroundColr;

    
    
    
    // Primary/secondary buttons (optional). Use localized labels only if you show them.
    UIImage *fil = [UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"];
    //UIImage *qr  = [UIImage systemImageNamed:@"qrcode.viewfinder"];
    [self.searchView configurePrimaryButtonWithImage:fil target:self action:@selector(onFilterTapped)];
    //[self.searchView configureSecondaryButtonWithImage:qr target:self action:@selector(onScanTapped)];
    self.searchView.showsPrimaryButton = YES;
    self.searchView.showsSecondaryButton = NO;

    // Localization & semantic
    self.searchView.textField.placeholder = kLang(@"SearchHere");
    self.searchView.textField.textAlignment = [Language alignmentForCurrentLanguage];
    self.searchView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    [self.searchContainer addSubview:self.searchView];

    // layout inside container
    [NSLayoutConstraint activateConstraints:@[
        [self.searchView.leadingAnchor constraintEqualToAnchor:self.searchContainer.leadingAnchor constant:26],
        [self.searchView.trailingAnchor constraintEqualToAnchor:self.searchContainer.trailingAnchor constant:-26],
        [self.searchView.centerYAnchor constraintEqualToAnchor:self.searchContainer.centerYAnchor],
        [self.searchView.heightAnchor constraintEqualToConstant:searchHeight]
    ]];

    // assign as tableHeaderView (works nicely with inset grouped)
    self.tableView.tableHeaderView = self.searchContainer;

    // IMPORTANT: set search items now (empty array until we fetch)
    [self.searchView setSearchItems:@[] stringProvider:^NSString * _Nonnull(id item) {
        // safe provider that returns a searchable string per notification (title + body)
        if (![item isKindOfClass:NotificationModel.class]) return @"";
        NotificationModel *m = (NotificationModel *)item;
        NSString *ttl = PPAdminNotificationDisplayTitle(m);
        NSString *bdy = PPAdminNotificationDisplayBody(m);
        // return combined string (use lowercased; PPS normalizes too)
        NSString *combined = [NSString stringWithFormat:@"%@ %@", ttl, bdy];
        return combined;
    }];
}

#pragma mark - Actions (filter/scan stubs)

- (void)onFilterTapped {
    DLog(@"Filter tapped");
    // show filter UI — left as an exercise (present modal, action sheet, etc.)
    [PPToast toast:kLang(@"PPS_Filter") style:PPToastStyleInfo haptic:NO duration:1.0 position:PPToastPositionBottom inView:self.view];
}

- (void)onScanTapped {
    DLog(@"Scan tapped");
    [PPToast toast:kLang(@"PPS_Scan") style:PPToastStyleInfo haptic:NO duration:1.0 position:PPToastPositionBottom inView:self.view];
}

#pragma mark - Fetch

- (void)onRefresh {
    [self fetchNotificationsShowToast:NO];
}

- (void)fetchNotificationsShowToast:(BOOL)showToast {
    if (self.isLoading) return;
    self.isLoading = YES;
    DLog(@"Fetching notifications...");

    if (showToast) {
        [PPToast toast:kLang(@"Loading") style:PPToastStyleInfo haptic:NO duration:1.2 position:PPToastPositionBottom inView:self.view];
    }

    NSString *currentUID = PPAdminAuthenticatedNotificationUID();
    if (currentUID.length == 0) {
        self.isLoading = NO;
        [self.refreshControl endRefreshing];
        self.allNotifications = @[];
        self.filteredNotifications = @[];
        [self reloadTableAnimated:NO];
        return;
    }
    self.uid = currentUID;

    __weak typeof(self) weakSelf = self;
    __block BOOL shouldToastLoaded = showToast;
    // Live listen

    [self.inboxListener remove];
    self.inboxListener = [[NotificationManager shared] observeInboxForUser:self.uid stateHandler:^(NSArray<NotificationModel *> *items, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.isLoading = NO;
        if (self.refreshControl.isRefreshing) [self.refreshControl endRefreshing];

        self.inboxError = error;
        if (error) {
            NSString *signature = PPAdminNotificationInboxErrorSignature(error);
            BOOL shouldSurfaceError = signature.length > 0 && ![signature isEqualToString:self.lastInboxErrorSignature];
            self.lastInboxErrorSignature = signature;
            if (shouldSurfaceError) {
                NSLog(@"[NotificationsV2] Admin inbox listener failed | domain=%@ code=%ld", error.domain ?: @"unknown", (long)error.code);
                [PPToast toast:kLang(@"FetchError") style:PPToastStyleError haptic:YES duration:2.0 position:PPToastPositionBottom inView:self.view];
            }
        } else {
            self.lastInboxErrorSignature = nil;
        }

        // A listener error must not erase already-rendered, confirmed inbox items.
        if (!error || items.count > 0 || self.allNotifications.count == 0) {
            self.allNotifications = items ?: @[];
            self.filteredNotifications = self.allNotifications;
        }
        // update PPS search index with items
        [self.searchView setSearchItems:self.allNotifications stringProvider:^NSString * _Nonnull(id item) {
            if (![item isKindOfClass:NotificationModel.class]) return @"";
            NotificationModel *m = (NotificationModel *)item;
            NSString *combined = [NSString stringWithFormat:@"%@ %@", PPAdminNotificationDisplayTitle(m), PPAdminNotificationDisplayBody(m)];
            return combined;
        }];

        [self reloadTableAnimated:YES];
        if (!error && shouldToastLoaded) {
            [PPToast toast:kLang(@"NotificationsLoaded") style:PPToastStyleSuccess haptic:NO duration:1.0 position:PPToastPositionBottom inView:self.view];
            shouldToastLoaded = NO;
        }
   
        
        
    }];
    /*
     
     [[NotificationManager shared] fetchAllNotificationsWithCompletion:^(NSArray<NotificationModel *> * _Nullable notifications, NSError * _Nullable error) {
         dispatch_async(dispatch_get_main_queue(), ^{
             __strong typeof(weakSelf) self = weakSelf;
             self.isLoading = NO;
             if (self.refreshControl.isRefreshing) [self.refreshControl endRefreshing];

             if (error) {
                 DLog(@"Failed fetching notifications: %@", error.localizedDescription);
                 [PPToast toast:kLang(@"FetchError") style:PPToastStyleError haptic:YES duration:2.0 position:PPToastPositionBottom inView:self.view];
                 return;
             }

             self.allNotifications = notifications ?: @[];
             self.filteredNotifications = self.allNotifications;

             // update PPS search index with items
             [self.searchView setSearchItems:self.allNotifications stringProvider:^NSString * _Nonnull(id item) {
                 if (![item isKindOfClass:NotificationModel.class]) return @"";
                 NotificationModel *m = (NotificationModel *)item;
                 NSString *combined = [NSString stringWithFormat:@"%@ %@", m.title ?: @"", m.body ?: @""];
                 return combined;
             }];

             [self reloadTableAnimated:YES];
             [PPToast toast:kLang(@"NotificationsLoaded") style:PPToastStyleSuccess haptic:NO duration:1.0 position:PPToastPositionBottom inView:self.view];
         });
     }];
     */
}

#pragma mark - PPSDelegate (fuzzy / debounce)

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    // PPS has filterAsyncForText:completion:
    if (text.length == 0) {
        // restore all
        self.filteredNotifications = self.allNotifications;
        [self reloadTableAnimated:YES];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [view filterAsyncForText:text completion:^(NSString * _Nonnull query, NSArray * _Nonnull results) {
        __strong typeof(weakSelf) self = weakSelf;
        // results are objects preserved from items array (NotificationModel)
        self.filteredNotifications = results ?: @[];
        [self reloadTableAnimated:YES];
    }];
}

- (void)searchViewDidSubmit:(PPS *)view {
    // optional: when user taps return
    [self.searchView unfocus];
}

#pragma mark - Table reload animation

- (void)reloadTableAnimated:(BOOL)animated {
    [self.tableView reloadData];

    if (!animated) return;

    NSArray *cells = [self.tableView visibleCells];
    CGFloat delay = 0.0;
    for (UITableViewCell *cell in cells) {
        cell.alpha = 0.0;
    }
    for (UITableViewCell *cell in cells) {
        [UIView animateWithDuration:0.28
                              delay:delay
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            cell.alpha = 1.0;
        } completion:nil];
        delay += 0.04;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(1, self.filteredNotifications.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    if (self.filteredNotifications.count == 0) {
        static NSString *emptyId = @"emptyCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:emptyId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:emptyId];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.numberOfLines = 0;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = SeconderyTextClr;
            cell.textLabel.font = [Styling fontMedium:15];
            cell.backgroundColor = UIColor.whiteColor;
        }
        cell.textLabel.text = self.inboxError
            ? [NSString stringWithFormat:@"%@\n%@", kLang(@"FetchError"), kLang(@"PullToRefresh")]
            : kLang(@"NoNotifications");
        return cell;
    }

    static NSString *cellId = @"notifCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NotificationModel *m = self.filteredNotifications[indexPath.row];
    cell.textLabel.text = PPAdminNotificationDisplayTitle(m);
    cell.textLabel.font = [Styling fontMedium:16];
    cell.detailTextLabel.text = PPAdminNotificationDisplayBody(m);
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [Styling fontMedium:14];
    cell.backgroundColor = UIColor.whiteColor;

    // mark unread with bold or a dot — keep minimal here
    if (!m.isRead) {
        cell.textLabel.font = [Styling fontBold:16];
    }

    return cell;
}

#pragma mark - UITableViewDelegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.filteredNotifications.count == 0 || indexPath.row >= self.filteredNotifications.count) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    NotificationModel *m = self.filteredNotifications[indexPath.row];
    if (!m.isRead) {
        m.isRead = YES;
        [[NotificationManager shared] markRead:m forUser:self.uid completion:nil];
    }
    if (PPAdminNotificationRoutesToPaymentOrder(m)) {
        NSString *orderID = PPAdminNotificationOrderID(m);
        if (orderID.length > 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:PPAdminRouteToPaymentOrderNotification
                                                                object:nil
                                                              userInfo:@{ PPAdminRouteToPaymentOrderIDUserInfoKey: orderID }];
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            return;
        }
    }
    NotificationDetailViewController *vc = [[NotificationDetailViewController alloc] initWithModel:m userID:self.uid];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Dealloc

- (void)dealloc {
    [self.inboxListener remove];
    DLog(@"NotificationsListViewController dealloc");
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO buttonRowIndex:0 buttonSection:1];
}


@end
