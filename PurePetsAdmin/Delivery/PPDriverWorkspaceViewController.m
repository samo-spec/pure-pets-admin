#import "PPDriverWorkspaceViewController.h"
#import "PPDriverWorkspaceService.h"
#import "PPDesignTokens.h"
#import "Language.h"
#import "Styling.h"
#import "PPFirebaseCompat.h"

#import <UserNotifications/UserNotifications.h>
#import <MapKit/MapKit.h>

NSString * const PPAdminRouteToDriverTaskNotification = @"PPAdminRouteToDriverTaskNotification";
NSString * const PPDriverTasksDidChangeNotification = @"PPDriverTasksDidChangeNotification";
static NSDictionary *DDict(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }
static NSString *DText(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSArray *DArray(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static BOOL DFlag(id value) { return [value isKindOfClass:NSNumber.class] && [value boolValue]; }
static NSString *DL(NSString *key) { return kLang(key); }
NSDictionary<NSString *,NSString *> *PPDriverTaskRoute(NSDictionary *payload) {
    NSDictionary *root = DDict(payload), *meta = DDict(root[@"meta"]);
    NSString *route = DText(root[@"route"] ?: meta[@"route"]);
    NSString *target = DText(root[@"targetAppId"] ?: root[@"appId"] ?: root[@"targetApp"] ?: meta[@"targetAppId"]);
    NSString *task = DText(root[@"taskId"] ?: meta[@"taskId"] ?: root[@"requestId"] ?: meta[@"requestId"]);
    NSString *authority = DText(root[@"authority"] ?: meta[@"authority"]);
    if (![route isEqualToString:@"driver_task"] || (target.length && ![target isEqualToString:@"admin_ios"]) ||
        !task.length || task.length > 128 || [task containsString:@"/"] ||
        ![@[@"FULFILLMENT_V1",@"COMPANY_DELIVERY_REQUEST"] containsObject:authority]) return @{};
    return @{ @"taskId":task, @"authority":authority };
}
static UIFont *DFont(CGFloat size, BOOL bold, UIFontTextStyle style) {
    UIFont *font = bold ? [Styling fontBold:size] : [Styling fontRegular:size];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:font ?: [UIFont systemFontOfSize:size]];
}
static UILabel *DLabel(NSString *text, CGFloat size, BOOL bold, UIColor *color) {
    UILabel *label = [UILabel new]; label.text = text; label.numberOfLines = 0;
    label.font = DFont(size,bold,size >= 25 ? UIFontTextStyleTitle1 : UIFontTextStyleBody);
    label.adjustsFontForContentSizeCategory = YES; label.textColor = color;
    label.textAlignment = [Language alignmentForCurrentLanguage];
    return label;
}
static UIStackView *DStack(NSArray<UIView *> *views, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = spacing; return stack;
}
static UIButton *DButton(NSString *title, NSString *symbol, BOOL primary) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = primary ? UIButtonConfiguration.filledButtonConfiguration : UIButtonConfiguration.tintedButtonConfiguration;
    config.title = title; config.image = [UIImage systemImageNamed:symbol]; config.imagePadding = 10;
    config.baseBackgroundColor = UIColor.ppPrimary; config.baseForegroundColor = primary ? UIColor.whiteColor : UIColor.ppPrimary;
    config.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    config.contentInsets = NSDirectionalEdgeInsetsMake(13,16,13,16);
    config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attrs) {
        NSMutableDictionary *result = attrs.mutableCopy; result[NSFontAttributeName] = DFont(17,YES,UIFontTextStyleHeadline); return result;
    };
    button.configuration = config; button.titleLabel.numberOfLines = 0;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    return button;
}
static NSString *DAddress(NSDictionary *address) {
    for (NSString *key in @[@"formattedAddress",@"fullAddress",@"address",@"addressLine1",@"label"]) {
        if (DText(address[key]).length) return DText(address[key]);
    }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"buildingNumber",@"streetName",@"street",@"zoneNumber",@"area",@"city"]) {
        id value = address[key]; NSString *part = DText(value);
        if ([value isKindOfClass:NSNumber.class]) part = [value stringValue];
        if (part.length && ![parts containsObject:part]) [parts addObject:part];
    }
    return parts.count ? [parts componentsJoinedByString:@" · "] : DL(@"Driver_Address_Pending");
}
static NSString *DStatus(NSString *status) {
    NSDictionary *keys = @{ @"delivery_requested":@"Driver_Status_New", @"accepted_by_company":@"Driver_Status_New",
      @"delivery_assigned":@"Driver_Status_Handover", @"awaiting_handover":@"Driver_Status_Pickup",
      @"assigned_to_driver":@"Driver_Status_Pickup", @"handed_over":@"Driver_Status_Collected", @"picked_up":@"Driver_Status_Collected",
      @"in_transit":@"Driver_Status_Transit", @"delivered":@"Driver_Status_Delivered", @"payment_pending":@"Driver_Status_Payment",
      @"payment_confirmed":@"Driver_Status_Paid", @"completed":@"Driver_Status_Complete", @"cancelled":@"Driver_Status_Cancelled",
      @"failed":@"Driver_Status_Attention", @"returned":@"Driver_Status_Returned", @"rejected":@"Driver_Status_Cancelled" };
    return DL(keys[status] ?: @"Driver_Status_Updated");
}
static NSString *DAction(NSString *action) {
    return DL(@{ @"CLAIM":@"Driver_Action_Claim", @"PICK_UP":@"Driver_Action_Pickup", @"START_TRANSIT":@"Driver_Action_Transit",
      @"DELIVER":@"Driver_Action_Deliver", @"CONFIRM_PAYMENT":@"Driver_Action_Cash", @"COMPLETE":@"Driver_Action_Complete" }[action] ?: @"Driver_Open");
}

@interface PPDriverTaskCell : UITableViewCell
- (void)render:(NSDictionary *)task focused:(BOOL)focused detail:(BOOL)detail;
@end
@implementation PPDriverTaskCell
- (void)render:(NSDictionary *)task focused:(BOOL)focused detail:(BOOL)detail {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.backgroundColor = UIColor.clearColor; self.selectionStyle = UITableViewCellSelectionStyleDefault;
    UIView *paper = [UIView new]; paper.translatesAutoresizingMaskIntoConstraints = NO;
    paper.backgroundColor = UIColor.ppSurface; paper.layer.cornerRadius = focused ? 28 : 22;
    paper.layer.cornerCurve = kCACornerCurveContinuous;
    paper.layer.borderWidth = 1; paper.layer.borderColor = (focused ? [UIColor.ppPrimary colorWithAlphaComponent:0.22] : UIColor.ppSeparator).CGColor;
    [self.contentView addSubview:paper];
    UILabel *eyebrow = DLabel(focused ? DL(@"Driver_Next") : DStatus(DText(task[@"status"])),13,YES,UIColor.ppPrimary);
    NSString *number = DText(task[@"orderNumber"]);
    NSString *isolatedNumber = [NSString stringWithFormat:@"\u2068%@\u2069",number];
    UILabel *title = DLabel(number.length ? [NSString stringWithFormat:DL(@"Driver_Order_Format"),isolatedNumber] : DL(@"Driver_Delivery"),focused ? 27 : 21,YES,UIColor.ppTextPrimary);
    title.accessibilityTraits |= UIAccessibilityTraitHeader;
    UILabel *state = DLabel(DStatus(DText(task[@"status"])),17,YES,UIColor.ppTextSecondary);
    UIView *hairline = [UIView new]; hairline.backgroundColor = UIColor.ppSeparator;
    [hairline.heightAnchor constraintEqualToConstant:1 / UIScreen.mainScreen.scale].active = YES;
    NSMutableArray *content = [NSMutableArray arrayWithObjects:eyebrow,title,nil];
    if (focused || detail) [content addObject:state];
    [content addObject:hairline];
    for (NSString *stop in @[@"pickup",@"dropoff"]) {
        BOOL pickup = [stop isEqualToString:@"pickup"];
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:pickup ? @"shippingbox" : @"mappin.and.ellipse"]];
        icon.tintColor = pickup ? UIColor.ppPrimary : UIColor.ppSuccess; icon.contentMode = UIViewContentModeScaleAspectFit;
        [icon.widthAnchor constraintEqualToConstant:28].active = YES; [icon.heightAnchor constraintEqualToConstant:28].active = YES;
        UIStackView *copy = DStack(@[DLabel(DL(pickup ? @"Driver_Pickup" : @"Driver_Dropoff"),12,YES,UIColor.ppTextSecondary),
            DLabel(DAddress(DDict(task[stop])),17,YES,UIColor.ppTextPrimary)],3);
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[icon,copy]]; row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentTop; row.spacing = 12; [content addObject:row];
    }
    if (!DFlag(task[@"mine"])) [content addObject:DLabel(DL(@"Driver_Private_Until_Claim"),14,NO,UIColor.ppTextSecondary)];
    if (detail && DText(task[@"customerName"]).length) [content addObject:DLabel(DText(task[@"customerName"]),18,YES,UIColor.ppTextPrimary)];
    if (!detail) [content addObject:DLabel(DL(@"Driver_Open"),16,YES,UIColor.ppPrimary)];
    UIStackView *stack = DStack(content,focused ? 16 : 12); stack.translatesAutoresizingMaskIntoConstraints = NO; [paper addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
      [paper.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
      [paper.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
      [paper.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],
      [paper.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8],
      [stack.leadingAnchor constraintEqualToAnchor:paper.leadingAnchor constant:20], [stack.trailingAnchor constraintEqualToAnchor:paper.trailingAnchor constant:-20],
      [stack.topAnchor constraintEqualToAnchor:paper.topAnchor constant:20], [stack.bottomAnchor constraintEqualToAnchor:paper.bottomAnchor constant:-20]
    ]];
    self.isAccessibilityElement = !detail;
    self.accessibilityLabel = [@[title.text ?: @"",state.text ?: @"",DL(@"Driver_Pickup"),DAddress(DDict(task[@"pickup"])),DL(@"Driver_Dropoff"),DAddress(DDict(task[@"dropoff"]))] componentsJoinedByString:@", "];
    self.accessibilityTraits = detail ? UIAccessibilityTraitNone : UIAccessibilityTraitButton;
    self.accessibilityHint = detail ? nil : DL(@"Driver_Open");
}
@end

@interface PPDriverWorkspaceViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic,copy) NSString *taskID;
@property(nonatomic,copy) NSString *authority;
@property(nonatomic,copy) NSString *uid;
@property(nonatomic,copy) NSString *lane;
@property(nonatomic,strong) PPDriverWorkspaceService *service;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) UIStackView *lanes;
@property(nonatomic,strong) UIStackView *header;
@property(nonatomic,strong) UIStackView *detailActions;
@property(nonatomic,strong) UIStackView *feedback;
@property(nonatomic,strong) UIButton *availabilityButton;
@property(nonatomic,strong) UIButton *utilityButton;
@property(nonatomic,strong) NSDictionary *availability;
@property(nonatomic,assign) BOOL pendingAvailability;
@property(nonatomic,strong) UIStackView *dock;
@property(nonatomic,strong) NSArray<NSDictionary *> *tasks;
@property(nonatomic,strong) NSDictionary *cursor;
@property(nonatomic,strong) NSDictionary *pendingCommand;
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic,assign) BOOL loading;
@property(nonatomic,assign) BOOL submitting;
@property(nonatomic,assign) BOOL hasMore;
@property(nonatomic,assign) BOOL showingAdditionalPages;
@property(nonatomic,assign) BOOL visible;
@property(nonatomic,assign) NSUInteger generation;
@end

@implementation PPDriverWorkspaceViewController
- (instancetype)initWithTaskID:(NSString *)taskID authority:(NSString *)authority {
    if ((self = [super initWithNibName:nil bundle:nil])) { _taskID = taskID.copy ?: @""; _authority = authority.copy ?: @"";
        _lane = @"active"; _tasks = @[]; _service = [PPDriverWorkspaceService new]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.uid = FIRAuth.auth.currentUser.uid ?: @"";
    self.view.backgroundColor = UIColor.ppBackground; self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    UIStackView *header = DStack(@[],8); self.header = header;
    header.layoutMargins = UIEdgeInsetsMake(12,20,8,20); header.layoutMarginsRelativeArrangement = YES;
    UILabel *caption = DLabel(DL(self.taskID.length ? @"Driver_Task_Subtitle" : @"Driver_Workspace_Subtitle"),13,YES,UIColor.ppPrimary);
    UILabel *heading = DLabel(DL(self.taskID.length ? @"Driver_Task_Title" : @"Driver_Title"),32,YES,UIColor.ppTextPrimary);
    heading.accessibilityTraits |= UIAccessibilityTraitHeader;
    UIButton *utility = DButton(DL(self.taskID.length ? @"Driver_Back" : @"Driver_Notifications"),self.taskID.length ? @"chevron.backward" : @"bell",NO);
    self.utilityButton = utility;
    utility.hidden = !self.taskID.length && !self.onNotifications;
    [utility addTarget:self action:@selector(utilityTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addArrangedSubview:utility]; [header addArrangedSubview:caption]; [header addArrangedSubview:heading];
    self.lanes = [[UIStackView alloc] init]; self.lanes.spacing = 8; self.lanes.distribution = UIStackViewDistributionFillEqually;
    if (!self.taskID.length) {
        NSArray *names = @[@"Driver_Lane_Active",@"Driver_Lane_New",@"Driver_Lane_History"];
        for (NSInteger i=0;i<3;i++) { UIButton *b=DButton(DL(names[i]),@[@"location.north.line",@"plus.circle",@"checkmark.circle"][i],i==0);
            b.tag=i; [b addTarget:self action:@selector(laneTapped:) forControlEvents:UIControlEventTouchUpInside]; [self.lanes addArrangedSubview:b]; }
        [header addArrangedSubview:self.lanes];
        self.availabilityButton = DButton(DL(@"Driver_Availability_Loading"),@"circle.dotted",NO);
        self.availabilityButton.enabled = NO;
        [self.availabilityButton addTarget:self action:@selector(toggleAvailability) forControlEvents:UIControlEventTouchUpInside];
        [header addArrangedSubview:self.availabilityButton];
    }
    self.feedback = DStack(@[],8); [header addArrangedSubview:self.feedback];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.translatesAutoresizingMaskIntoConstraints=NO; self.table.backgroundColor=UIColor.clearColor;
    self.table.separatorStyle=UITableViewCellSeparatorStyleNone; self.table.rowHeight=UITableViewAutomaticDimension;
    self.table.estimatedRowHeight=280; self.table.dataSource=self; self.table.delegate=self;
    [self.table registerClass:PPDriverTaskCell.class forCellReuseIdentifier:@"task"];
    self.table.refreshControl=[UIRefreshControl new]; [self.table.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.table.contentInset=UIEdgeInsetsMake(8,0,self.taskID.length ? 12 : 110,0);
    self.table.accessibilityIdentifier=@"driver.workspace.tasks";
    self.dock=DStack(@[],8); self.dock.translatesAutoresizingMaskIntoConstraints=NO;
    self.dock.layoutMargins=UIEdgeInsetsMake(12,20,4,20); self.dock.layoutMarginsRelativeArrangement=YES;
    self.dock.backgroundColor=UIColor.ppBackground;
    self.table.tableHeaderView = header;
    [self.view addSubview:self.table]; [self.view addSubview:self.dock];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    UILayoutGuide *readable=self.view.readableContentGuide;
    [NSLayoutConstraint activateConstraints:@[[self.table.topAnchor constraintEqualToAnchor:safe.topAnchor], [self.table.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor], [self.table.bottomAnchor constraintEqualToAnchor:self.dock.topAnchor],
        [self.dock.leadingAnchor constraintEqualToAnchor:readable.leadingAnchor], [self.dock.trailingAnchor constraintEqualToAnchor:readable.trailingAnchor],
        [self.dock.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-4]]];
    [self adaptType];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(passiveRefresh) name:PPDriverTasksDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(passiveRefresh) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(adaptType) name:UIContentSizeCategoryDidChangeNotification object:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    for (UIStackView *stack in @[self.header, self.detailActions ?: self.header]) {
        CGFloat width = self.table.bounds.size.width;
        CGSize size = [stack systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
        if (fabs(stack.frame.size.height - size.height) > 0.5 || fabs(stack.frame.size.width - width) > 0.5) {
            stack.frame = CGRectMake(0,0,width,size.height);
            if (stack == self.header) self.table.tableHeaderView = stack; else self.table.tableFooterView = stack;
        }
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection])[self.table reloadData];
}
- (void)adaptType { self.lanes.axis = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory) ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal; [self.table reloadData]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.visible=YES; [self.refreshTimer invalidate]; [self refresh];
    __weak typeof(self) weakSelf=self; self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *timer){ [weakSelf passiveRefresh]; }]; }
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; self.visible=NO; [self.refreshTimer invalidate]; self.refreshTimer=nil; self.generation++; self.loading=NO; }
- (void)dealloc { [self.refreshTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)setOnNotifications:(void (^)(void))onNotifications {
    _onNotifications = [onNotifications copy];
    self.utilityButton.hidden = !self.taskID.length && !onNotifications;
}
- (BOOL)sessionMatches { return self.uid.length && [self.uid isEqualToString:FIRAuth.auth.currentUser.uid]; }
- (void)utilityTapped { if (self.taskID.length) { if(self.onClose)self.onClose(); } else if(self.onNotifications)self.onNotifications(); }
- (void)laneTapped:(UIButton *)button {
    if(self.submitting)return; self.generation++; self.loading=NO; self.lane=@[@"active",@"available",@"history"][button.tag];
    self.tasks=@[]; self.cursor=nil; self.hasMore=NO; self.showingAdditionalPages=NO;
    for(UIButton *b in self.lanes.arrangedSubviews){ UIButtonConfiguration *c=b.configuration; c.baseBackgroundColor=b==button ? UIColor.ppPrimary : [UIColor.ppPrimary colorWithAlphaComponent:0.08]; c.baseForegroundColor=b==button ? UIColor.whiteColor : UIColor.ppPrimary; b.configuration=c; b.accessibilityTraits=b==button ? UIAccessibilityTraitButton|UIAccessibilityTraitSelected : UIAccessibilityTraitButton; }
    [self.table reloadData]; [self refresh];
}
- (void)refresh { if(!self.visible || UIApplication.sharedApplication.applicationState != UIApplicationStateActive || self.loading || self.submitting || self.pendingCommand || self.presentedViewController)return; [self loadMore:NO]; }
- (void)passiveRefresh {
    // Keep an expanded run sheet and the driver's reading position intact.
    // Pull-to-refresh remains an explicit request to reload from the first page.
    if(self.table.dragging || self.table.decelerating || (!self.taskID.length && self.showingAdditionalPages))return;
    [self refresh];
}
- (void)loadNext { if(self.hasMore && !self.loading && !self.submitting && !self.pendingCommand) [self loadMore:YES]; }
- (void)clear:(UIStackView *)stack { for(UIView *view in stack.arrangedSubviews.copy){[stack removeArrangedSubview:view];[view removeFromSuperview];} }
- (void)message:(NSString *)key retry:(BOOL)retry {
    [self clear:self.feedback]; [self.feedback addArrangedSubview:DLabel(DL(key),15,NO,UIColor.ppTextSecondary)];
    [self.view setNeedsLayout];
    if(retry){UIButton *button=DButton(DL(@"Driver_Retry"),@"arrow.clockwise",NO);[button addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];[self.feedback addArrangedSubview:button];}
}
- (void)retryTapped { if(self.pendingCommand) [self submitPending]; else [self refresh]; }
- (void)loadMore:(BOOL)more {
    if(![self sessionMatches]){self.tasks=@[];[self.table reloadData];[self renderDock];[self message:@"Driver_Access_Denied" retry:NO];return;}
    self.loading=YES; NSUInteger epoch=++self.generation;
    [self renderDock];[self renderAvailability];
    NSMutableDictionary *parameters=[NSMutableDictionary dictionary];
    if(self.taskID.length){parameters[@"taskId"]=self.taskID;parameters[@"authority"]=self.authority;}
    else{parameters[@"lane"]=self.lane;if(more && self.cursor)parameters[@"cursor"]=self.cursor;}
    if(!self.tasks.count) [self message:@"Driver_Loading" retry:NO];
    __weak typeof(self) weakSelf=self;
    [self.service load:parameters completion:^(NSDictionary *data,NSError *error){
        __strong typeof(weakSelf) self=weakSelf;if(!self || epoch!=self.generation || ![self sessionMatches])return;
        self.loading=NO;[self.table.refreshControl endRefreshing];
        if(error){
            BOOL denied=[error.domain isEqualToString:FIRFunctionsErrorDomain] && (error.code==FIRFunctionsErrorCodePermissionDenied || error.code==FIRFunctionsErrorCodeUnauthenticated || error.code==FIRFunctionsErrorCodeNotFound);
            if(denied){self.tasks=@[];self.cursor=nil;self.hasMore=NO;self.availability=@{};[self renderDock];[self renderAvailability];[self.table reloadData];if(!self.taskID.length)[self updateFooter];}
            [self message:denied ? @"Driver_Access_Denied" : @"Driver_Error_Load" retry:!denied];return;
        }
        NSMutableArray *items=more ? self.tasks.mutableCopy : [NSMutableArray array];
        NSArray *rows=self.taskID.length ? (DDict(data[@"task"]).count ? @[data[@"task"]] : @[]) : DArray(data[@"tasks"]);
        for(id raw in rows){NSDictionary *task=DDict(raw); if(!DText(task[@"taskId"]).length || ![@[@"FULFILLMENT_V1",@"COMPANY_DELIVERY_REQUEST"] containsObject:DText(task[@"authority"])])continue;
            NSIndexSet *duplicate=[items indexesOfObjectsPassingTest:^BOOL(NSDictionary *other,NSUInteger idx,BOOL *stop){return [other[@"taskId"] isEqual:task[@"taskId"]] && [other[@"authority"] isEqual:task[@"authority"]];}];
            [items removeObjectsAtIndexes:duplicate];[items addObject:task];}
        self.tasks=items;self.cursor=DDict(data[@"nextCursor"]);self.hasMore=DFlag(data[@"hasMore"]);self.showingAdditionalPages=more;
        if(!self.taskID.length){self.availability = DDict(DArray(data[@"availability"]).firstObject);[self renderAvailability];}
        [self clear:self.feedback];[self.table reloadData];[self renderDock];if(!self.taskID.length)[self updateFooter];[self.view setNeedsLayout];
        if(!self.tasks.count)[self message:self.hasMore ? @"Driver_More_Available" : [self.lane isEqualToString:@"available"] ? @"Driver_Empty_New" : [self.lane isEqualToString:@"history"] ? @"Driver_Empty_History" : @"Driver_Empty_Active" retry:NO];
        if(!self.taskID.length) [self notificationStatus];
    }];
}
- (void)renderAvailability {
    NSString *key = !self.availability.count ? @"Driver_Fleet_Pending" : DFlag(self.availability[@"assignmentsPaused"]) ? @"Driver_Dispatch_Paused" : DFlag(self.availability[@"online"]) ? @"Driver_Online" : @"Driver_Offline";
    UIButtonConfiguration *configuration = self.availabilityButton.configuration;
    configuration.title = DL(key); configuration.image = [UIImage systemImageNamed:DFlag(self.availability[@"online"]) ? @"checkmark.circle.fill" : @"pause.circle"];
    self.availabilityButton.configuration = configuration;
    self.availabilityButton.enabled = self.availability.count > 0 && !self.pendingCommand && !self.submitting && !self.loading;
    self.availabilityButton.accessibilityHint = DL(DFlag(self.availability[@"online"]) ? @"Driver_Go_Offline" : @"Driver_Go_Online");
    [self.view setNeedsLayout];
}
- (void)toggleAvailability {
    if(!self.availability.count || self.submitting || self.pendingCommand)return;
    BOOL online = !DFlag(self.availability[@"online"]);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DL(online ? @"Driver_Go_Online" : @"Driver_Go_Offline") message:DL(@"Driver_Availability_Body") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:DL(online ? @"Driver_Go_Online" : @"Driver_Go_Offline") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        __strong typeof(weakSelf) self = weakSelf; if(!self || ![self sessionMatches])return;
        self.pendingAvailability=YES;
        self.pendingCommand=@{@"companyId":self.availability[@"companyId"],@"online":@(online),@"expectedRevision":self.availability[@"revision"] ?: @0,@"commandId":NSUUID.UUID.UUIDString};
        [self submitPending];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)updateFooter {
    if(!self.hasMore){self.detailActions=nil;self.table.tableFooterView=[UIView new];return;}
    UIButton *more=DButton(DL(@"Driver_Load_More"),@"arrow.down",NO);[more addTarget:self action:@selector(loadNext) forControlEvents:UIControlEventTouchUpInside];
    self.detailActions=DStack(@[more],0);self.detailActions.layoutMargins=UIEdgeInsetsMake(8,20,20,20);self.detailActions.layoutMarginsRelativeArrangement=YES;self.table.tableFooterView=self.detailActions;[self.view setNeedsLayout];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.tasks.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PPDriverTaskCell *cell=[tableView dequeueReusableCellWithIdentifier:@"task" forIndexPath:indexPath];
    NSDictionary *task=self.tasks[indexPath.row];
    BOOL finished=[@[@"completed",@"cancelled",@"rejected",@"failed",@"returned"] containsObject:DText(task[@"status"])];
    BOOL focused=indexPath.row==0 && [self.lane isEqualToString:@"active"] && DFlag(task[@"mine"]) && !finished;
    [cell render:task focused:focused detail:self.taskID.length>0];return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];if(self.taskID.length)return;
    NSDictionary *task=self.tasks[indexPath.row];if(self.onOpenTask)self.onOpenTask(DText(task[@"taskId"]),DText(task[@"authority"]));
}
- (NSString *)cashText:(NSDictionary *)task {
    NSDictionary *cash=DDict(task[@"cash"]);NSNumber *amount=[cash[@"amount"] isKindOfClass:NSNumber.class]?cash[@"amount"]:nil;
    NSString *currency=DText(cash[@"currency"]);if(!amount || !currency.length)return DL(@"Driver_Cash_Unavailable");
    NSNumberFormatter *f=[NSNumberFormatter new];f.locale=[NSLocale localeWithLocaleIdentifier:[Language isRTL]?@"ar_QA":@"en_QA"];f.numberStyle=NSNumberFormatterCurrencyStyle;f.currencyCode=currency;
    return [NSString stringWithFormat:DL(@"Driver_Cash_Format"),[f stringFromNumber:amount] ?: @""];
}
- (void)renderDock {
    [self clear:self.dock];
    if(self.taskID.length && !self.tasks.count){self.detailActions=nil;self.table.tableFooterView=[UIView new];}
    if(!self.taskID.length || !self.tasks.count)return;
    NSDictionary *task=self.tasks.firstObject;
    self.detailActions = DStack(@[],10); self.detailActions.layoutMargins = UIEdgeInsetsMake(8,20,20,20); self.detailActions.layoutMarginsRelativeArrangement = YES;
    self.table.tableFooterView = self.detailActions;
    if(DFlag(task[@"mine"])){
        UIButton *navigate=DButton(DL(@"Driver_Navigate"),@"arrow.triangle.turn.up.right.diamond",NO);
        [navigate addTarget:self action:@selector(navigate) forControlEvents:UIControlEventTouchUpInside];[self.detailActions addArrangedSubview:navigate];
        if(DText(task[@"phone"]).length){UIButton *call=DButton(DL(@"Driver_Call"),@"phone",NO);[call addTarget:self action:@selector(callRecipient) forControlEvents:UIControlEventTouchUpInside];[self.detailActions addArrangedSubview:call];}
    }
    if(DFlag(DDict(task[@"cash"])[@"required"]) && !DFlag(DDict(task[@"cash"])[@"collected"])) [self.detailActions addArrangedSubview:DLabel([self cashText:task],16,YES,UIColor.ppTextPrimary)];
    NSArray *actions=DArray(task[@"actions"]);
    if(actions.count){UIButton *action=DButton(DAction(DText(actions.firstObject)),@"checkmark",YES);action.accessibilityIdentifier=@"driver.task.primaryAction";
        [action addTarget:self action:@selector(confirmAction) forControlEvents:UIControlEventTouchUpInside];action.enabled=!self.loading && !self.submitting && !self.pendingCommand;[self.dock addArrangedSubview:action];}
    else [self.detailActions addArrangedSubview:DLabel(DL([DText(task[@"status"]) isEqualToString:@"delivery_assigned"] ? @"Driver_Wait_Handover" : @"Driver_No_Action"),15,NO,UIColor.ppTextSecondary)];
}
- (void)confirmAction {
    if(self.loading || self.submitting || self.pendingCommand || !self.tasks.count)return;
    NSDictionary *task=self.tasks.firstObject;NSString *action=DText(DArray(task[@"actions"]).firstObject);if(!action.length)return;
    NSDictionary *proof=DDict(task[@"proofRequirements"]);
    if([action isEqualToString:@"DELIVER"] && [self.authority isEqualToString:@"COMPANY_DELIVERY_REQUEST"] &&
        (DFlag(proof[@"photoRequired"]) || DFlag(proof[@"signatureRequired"]) || DFlag(proof[@"otpRequired"]))){
        [self message:@"Driver_Proof_Assistance" retry:NO];return;
    }
    BOOL legacyCash=[action isEqualToString:@"DELIVER"] && [self.authority isEqualToString:@"COMPANY_DELIVERY_REQUEST"] && DFlag(DDict(task[@"cash"])[@"required"]);
    BOOL cash=legacyCash || [action isEqualToString:@"CONFIRM_PAYMENT"];
    NSDictionary *cashSnapshot = DDict(task[@"cash"]);
    if (cash && (![cashSnapshot[@"amount"] isKindOfClass:NSNumber.class] || [cashSnapshot[@"amount"] doubleValue] <= 0 || !DText(cashSnapshot[@"currency"]).length)) {
        [self message:@"Driver_Cash_Unavailable" retry:YES]; return;
    }
    NSString *message=cash ? [self cashText:task] : DL(@"Driver_Confirm_Body");
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:DAction(action) message:message preferredStyle:UIAlertControllerStyleAlert];
    BOOL receiver=[action isEqualToString:@"DELIVER"] && [self.authority isEqualToString:@"COMPANY_DELIVERY_REQUEST"];
    if(receiver)[alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=DL(@"Driver_Receiver");field.textAlignment=[Language alignmentForCurrentLanguage];field.textContentType=UITextContentTypeName;}];
    [alert addAction:[UIAlertAction actionWithTitle:DL(@"Driver_Cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:DAction(action) style:UIAlertActionStyleDefault handler:^(UIAlertAction *ignored){
        __strong typeof(weakSelf) self=weakSelf;if(!self || ![self sessionMatches])return;
        NSString *name=[weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if(receiver && DFlag(proof[@"receiverNameRequired"]) && !name.length){[self message:@"Driver_Receiver_Required" retry:NO];return;}
        NSMutableDictionary *command=[@{@"taskId":self.taskID,@"authority":self.authority,@"action":action,@"expectedState":task[@"status"],@"expectedRevision":task[@"revision"],@"commandId":NSUUID.UUID.UUIDString} mutableCopy];
        if(receiver)command[@"receiverName"]=name;
        if([action isEqualToString:@"CONFIRM_PAYMENT"]){command[@"confirmedCashAmount"]=cashSnapshot[@"amount"];command[@"confirmedCashCurrency"]=cashSnapshot[@"currency"];}
        if(legacyCash){id amount=DDict(task[@"cash"])[@"amount"];if(![amount isKindOfClass:NSNumber.class]){[self message:@"Driver_Cash_Unavailable" retry:NO];return;}command[@"cashCollected"]=@YES;command[@"cashAmountCollected"]=amount;}
        self.pendingAvailability=NO; self.pendingCommand=command;[self submitPending];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)submitPending {
    if(self.submitting || !self.pendingCommand || ![self sessionMatches])return;
    self.submitting=YES;[self renderDock];[self renderAvailability];[self message:@"Driver_Saving" retry:NO];
    __weak typeof(self) weakSelf=self;
    void (^completion)(NSDictionary *,NSError *) = ^(NSDictionary *data,NSError *error){
        __strong typeof(weakSelf) self=weakSelf;if(!self || ![self sessionMatches])return;self.submitting=NO;
        if(error){BOOL definite=[error.domain isEqualToString:FIRFunctionsErrorDomain] && [@[@(FIRFunctionsErrorCodePermissionDenied),@(FIRFunctionsErrorCodeUnauthenticated),@(FIRFunctionsErrorCodeFailedPrecondition),@(FIRFunctionsErrorCodeInvalidArgument),@(FIRFunctionsErrorCodeNotFound),@(FIRFunctionsErrorCodeAborted),@(FIRFunctionsErrorCodeAlreadyExists)] containsObject:@(error.code)];
            if(definite){self.pendingCommand=nil;
                if(error.code==FIRFunctionsErrorCodePermissionDenied || error.code==FIRFunctionsErrorCodeUnauthenticated || error.code==FIRFunctionsErrorCodeNotFound){self.tasks=@[];[self.table reloadData];}
                [self message:@"Driver_Error_Changed" retry:YES];}else [self message:@"Driver_Error_Uncertain" retry:YES];[self renderDock];[self renderAvailability];return;}
        self.pendingCommand=nil;[self renderAvailability];if(!UIAccessibilityIsReduceMotionEnabled())[[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,DL(@"Driver_Saved"));
        // A fast callable can finish before the confirmation alert has dismissed.
        // Refresh directly so an obsolete primary action never stays enabled.
        if(self.visible)[self loadMore:NO];
        [NSNotificationCenter.defaultCenter postNotificationName:PPDriverTasksDidChangeNotification object:self];
    };
    if(self.pendingAvailability)[self.service setAvailability:self.pendingCommand completion:completion];
    else [self.service execute:self.pendingCommand completion:completion];
}
- (void)callRecipient {
    NSString *phone=DText(self.tasks.firstObject[@"phone"]);
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"+0123456789"];
    NSString *safe=[[phone componentsSeparatedByCharactersInSet:allowed.invertedSet] componentsJoinedByString:@""];
    if(safe.length) [UIApplication.sharedApplication openURL:[NSURL URLWithString:[@"tel:" stringByAppendingString:safe]] options:@{} completionHandler:nil];
}
- (void)navigate {
    if(!self.tasks.count)return;NSDictionary *task=self.tasks.firstObject;NSString *status=DText(task[@"status"]);
    BOOL pickup=[@[@"delivery_assigned",@"awaiting_handover",@"assigned_to_driver"] containsObject:status];
    NSDictionary *address=DDict(task[pickup?@"pickup":@"dropoff"]);
    NSString *query=DAddress(address);if([query isEqualToString:DL(@"Driver_Address_Pending")]){[self message:@"Driver_Address_Pending" retry:NO];return;}
    NSURLComponents *url=[NSURLComponents componentsWithString:@"https://maps.apple.com/"];
    url.queryItems=@[[NSURLQueryItem queryItemWithName:@"daddr" value:query],[NSURLQueryItem queryItemWithName:@"dirflg" value:@"d"]];
    [UIApplication.sharedApplication openURL:url.URL options:@{} completionHandler:nil];
}
- (void)notificationStatus {
    if(!self.onNotifications)return;
    NSUInteger epoch=self.generation;
    __weak typeof(self) weakSelf=self;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){dispatch_async(dispatch_get_main_queue(),^{
        __strong typeof(weakSelf) self=weakSelf;if(!self || epoch!=self.generation || !self.visible || !self.onNotifications || ![self sessionMatches])return;
        if(settings.authorizationStatus==UNAuthorizationStatusDenied || settings.authorizationStatus==UNAuthorizationStatusNotDetermined){
            UIButton *button=DButton(DL(@"Driver_Enable_Notifications"),@"bell.badge",NO);[button addTarget:self action:@selector(enableNotifications) forControlEvents:UIControlEventTouchUpInside];[self.feedback addArrangedSubview:button];
            [self.view setNeedsLayout];
        }
    });}];
}
- (void)enableNotifications {
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings){
        if(settings.authorizationStatus==UNAuthorizationStatusDenied){dispatch_async(dispatch_get_main_queue(),^{[UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];});}
        else [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionBadge|UNAuthorizationOptionSound completionHandler:^(BOOL granted,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(granted)[UIApplication.sharedApplication registerForRemoteNotifications];[self refresh];});}];
    }];
}
@end
