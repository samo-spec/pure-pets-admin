//
//  PPChatsViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 2026-07-13.
//

#import "PPChatsViewController.h"
#import "PPHero.h"
#import "Styling.h"
#import "Language.h"

@interface PPChatsViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) PPHero *heroGlassBG;
@property (nonatomic, strong) UILabel *heroCountLabel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *allChats;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *filteredChats;

@end

@implementation PPChatsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = AppBackgroundClr ?: UIColor.systemGroupedBackgroundColor;
    self.title = kLang(@"Chats") ?: @"Chats";
    
    [self setupMockData];
    [self setupTableView];
    [self setupHeaderUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:kLang(@"Chats") ?: @"Chats" showBack:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.heroGlassBG startAnimations];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.heroGlassBG stopAnimations];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self.heroGlassBG reapplyPalette];
    }
}

#pragma mark - Mock Data

- (void)setupMockData {
    self.allChats = [@[
        @{
            @"name": @"Ahmed Al-Mansoori",
            @"role": @"Pet Owner",
            @"lastMessage": @"Can I update my booking reservation for tomorrow?",
            @"time": @"10:24 AM",
            @"unread": @YES,
            @"avatar": @"person.crop.circle.fill"
        },
        @{
            @"name": @"Sara Smith (Dr.)",
            @"role": @"Veterinarian Partner",
            @"lastMessage": @"The prescription details have been successfully uploaded.",
            @"time": @"Yesterday",
            @"unread": @NO,
            @"avatar": @"person.crop.circle.fill"
        },
        @{
            @"name": @"PurePets Support (Admin)",
            @"role": @"System Admin",
            @"lastMessage": @"Weekly server optimization has been scheduled for 2:00 AM.",
            @"time": @"2 days ago",
            @"unread": @NO,
            @"avatar": @"shield.fill"
        }
    ] mutableCopy];
    self.filteredChats = [self.allChats mutableCopy];
}

#pragma mark - UI Setup

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = UIColor.clearColor;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 90.0;
    
    [self.view addSubview:self.tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupHeaderUI {
    CGFloat width = CGRectGetWidth(self.view.bounds);
    if (width <= 0.0) width = UIScreen.mainScreen.bounds.size.width;
    
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 200.0)];
    header.backgroundColor = UIColor.clearColor;
    
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16.0, 8.0, width - 32.0, 184.0)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = UIColor.clearColor;
    [header addSubview:card];
    
    PPHero *glassBG = [PPHero new];
    glassBG.frame = card.bounds;
    glassBG.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:glassBG];
    self.heroGlassBG = glassBG;
    
    UIView *content = [UIView new];
    content.frame = card.bounds;
    content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card addSubview:content];
    
    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bubble.left.and.bubble.right.fill"]];
    iconView.frame = CGRectMake(20.0, 20.0, 36.0, 36.0);
    iconView.tintColor = AppPrimaryClr ?: UIColor.systemBlueColor;
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [content addSubview:iconView];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame: CGRectMake(70.0, 20.0, CGRectGetWidth(card.bounds) - 150.0, 36.0)];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.font = [Styling fontBold:22];
    titleLabel.textColor = PrimaryTextClr ?: UIColor.labelColor;
    titleLabel.text = kLang(@"Chats") ?: @"Chats";
    [content addSubview:titleLabel];
    
    UIView *countShell = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetWidth(card.bounds) - 76.0, 20.0, 56.0, 36.0)];
    countShell.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    countShell.backgroundColor = [(AppPrimaryClr ?: UIColor.systemBlueColor) colorWithAlphaComponent:0.12];
    countShell.layer.cornerRadius = 12.0;
    [content addSubview:countShell];
    
    self.heroCountLabel = [[UILabel alloc] initWithFrame:countShell.bounds];
    self.heroCountLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightBold];
    self.heroCountLabel.textColor = AppPrimaryClr ?: UIColor.systemBlueColor;
    self.heroCountLabel.textAlignment = NSTextAlignmentCenter;
    self.heroCountLabel.text = @"1";
    [countShell addSubview:self.heroCountLabel];
    
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(12.0, 116.0, CGRectGetWidth(card.bounds) - 24.0, 48.0)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.placeholder = kLang(@"Search") ?: @"Search Chats";
    [content addSubview:self.searchBar];
    
    self.tableView.tableHeaderView = header;
}

#pragma mark - Search Bar Delegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredChats = [self.allChats mutableCopy];
    } else {
        self.filteredChats = [NSMutableArray array];
        for (NSDictionary *chat in self.allChats) {
            NSString *name = chat[@"name"];
            if ([name.lowercaseString containsString:searchText.lowercaseString]) {
                [self.filteredChats addObject:chat];
            }
        }
    }
    [self.tableView reloadData];
}

#pragma mark - UITableView Delegate & DataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredChats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ChatCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ChatCell"];
        cell.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UIView *surface = [UIView new];
        surface.tag = 99;
        surface.translatesAutoresizingMaskIntoConstraints = NO;
        surface.backgroundColor = AppForgroundColr ?: UIColor.secondarySystemBackgroundColor;
        surface.layer.cornerRadius = 20.0;
        surface.layer.borderWidth = 1.0;
        surface.layer.borderColor = [(AppPrimaryClr ?: UIColor.systemBlueColor) colorWithAlphaComponent:0.06].CGColor;
        surface.layer.shadowColor = UIColor.blackColor.CGColor;
        surface.layer.shadowOpacity = 0.04;
        surface.layer.shadowRadius = 8.0;
        surface.layer.shadowOffset = CGSizeMake(0.0, 4.0);
        [cell.contentView addSubview:surface];
        
        UIImageView *avatar = [UIImageView new];
        avatar.tag = 100;
        avatar.translatesAutoresizingMaskIntoConstraints = NO;
        avatar.tintColor = AppPrimaryClr ?: UIColor.systemBlueColor;
        avatar.contentMode = UIViewContentModeScaleAspectFit;
        [surface addSubview:avatar];
        
        UILabel *nameLabel = [UILabel new];
        nameLabel.tag = 101;
        nameLabel.font = [Styling fontBold:16];
        nameLabel.textColor = PrimaryTextClr ?: UIColor.labelColor;
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:nameLabel];
        
        UILabel *msgLabel = [UILabel new];
        msgLabel.tag = 102;
        msgLabel.font = [Styling fontRegular:13];
        msgLabel.textColor = SeconderyTextClr ?: UIColor.secondaryLabelColor;
        msgLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:msgLabel];
        
        UILabel *timeLabel = [UILabel new];
        timeLabel.tag = 103;
        timeLabel.font = [Styling fontRegular:11];
        timeLabel.textColor = SeconderyTextClr ?: UIColor.secondaryLabelColor;
        timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:timeLabel];
        
        UIView *badge = [UIView new];
        badge.tag = 104;
        badge.backgroundColor = AppPrimaryClr ?: UIColor.systemBlueColor;
        badge.layer.cornerRadius = 5.0;
        badge.translatesAutoresizingMaskIntoConstraints = NO;
        [surface addSubview:badge];
        
        [NSLayoutConstraint activateConstraints:@[
            [surface.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6.0],
            [surface.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
            [surface.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
            [surface.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6.0],
            
            [avatar.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:14.0],
            [avatar.centerYAnchor constraintEqualToAnchor:surface.centerYAnchor],
            [avatar.widthAnchor constraintEqualToConstant:40.0],
            [avatar.heightAnchor constraintEqualToConstant:40.0],
            
            [nameLabel.topAnchor constraintEqualToAnchor:surface.topAnchor constant:14.0],
            [nameLabel.leadingAnchor constraintEqualToAnchor:avatar.trailingAnchor constant:12.0],
            [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:timeLabel.leadingAnchor constant:-8.0],
            
            [msgLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:4.0],
            [msgLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
            [msgLabel.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-30.0],
            [msgLabel.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-14.0],
            
            [timeLabel.topAnchor constraintEqualToAnchor:surface.topAnchor constant:14.0],
            [timeLabel.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-14.0],
            
            [badge.centerYAnchor constraintEqualToAnchor:msgLabel.centerYAnchor],
            [badge.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-14.0],
            [badge.widthAnchor constraintEqualToConstant:10.0],
            [badge.heightAnchor constraintEqualToConstant:10.0]
        ]];
    }
    
    NSDictionary *chat = self.filteredChats[indexPath.row];
    
    UIImageView *avatar = [cell.contentView viewWithTag:100];
    UILabel *nameLabel = [cell.contentView viewWithTag:101];
    UILabel *msgLabel = [cell.contentView viewWithTag:102];
    UILabel *timeLabel = [cell.contentView viewWithTag:103];
    UIView *badge = [cell.contentView viewWithTag:104];
    
    avatar.image = [UIImage systemImageNamed:chat[@"avatar"]];
    nameLabel.text = chat[@"name"];
    msgLabel.text = chat[@"lastMessage"];
    timeLabel.text = chat[@"time"];
    
    BOOL unread = [chat[@"unread"] boolValue];
    badge.hidden = !unread;
    
    return cell;
}

@end
