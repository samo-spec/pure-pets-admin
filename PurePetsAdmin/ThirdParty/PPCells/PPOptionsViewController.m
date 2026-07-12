//
//  PPOptionsViewController.m
//
#import "PPOptionsViewController.h"

@interface PPOptionsViewController ()
@property (nonatomic, strong) NSArray *allOptions;
@property (nonatomic, strong) NSArray *filteredOptions;
@end

@implementation PPOptionsViewController


#pragma mark - Force grouped style
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        // if XLForm uses NSCoder init, reattach coder
    }
    return self;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = AppBackgroundClr;
    self.view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    self.tableView.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage;
    // 🔹 Row height
    self.tableView.rowHeight = 50.0;

    // 🔹 Save options (so we can filter later)
    self.allOptions = self.rowDescriptor.selectorOptions;
    self.filteredOptions = self.allOptions;

    // 🔹 Optional search bar
    if (self.showSearchBar) {
        UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 56)];
        searchBar.delegate = self;
        searchBar.placeholder = kLang(@"Search");
       // self.tableView.tableHeaderView = searchBar;
    }
    
    NSLog(@"PPOptionsViewController title = %@", self.title);

    NSString *formRowTitle = self.rowDescriptor.title;
    NSLog(@"PPOptionsViewController row title = %@", formRowTitle);
    
    //self.tableView.hxy = 150;
   
    //magnifyingglass checkmark.rectangle.stack.fill
   // UIButton *close = [self pp_circleButtonWithSystemName:@"magnifyingglass" action:@selector(onClose)];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:formRowTitle showBack:YES];

  
}

- (void)onClose {
    [self.navigationController popViewControllerAnimated:YES];
}



-(void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self pp_navBarSetVisible:NO animated:YES];
}



#pragma mark - UITableView Data Source override

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredOptions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];

    id option = self.filteredOptions[indexPath.row];
    if ([option isKindOfClass:[XLFormOptionsObject class]]) {
        cell.textLabel.text = [(XLFormOptionsObject *)option displayText];
    } else {
        cell.textLabel.text = [option description];
    }
    cell.textLabel.font = [Styling fontMedium:16];
    //cell.textLabel.font = [Styling fontMedium:16];
    // Show checkmark
    if ([option isEqual:self.rowDescriptor.value]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    cell.tintColor = AppPrimaryClr;
    return cell;
}




#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.filteredOptions = self.allOptions;
    } else {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(id option, NSDictionary *bindings) {
            NSString *txt = [option isKindOfClass:[XLFormOptionsObject class]] ?
                [(XLFormOptionsObject *)option displayText] : [option description];
            return [txt localizedCaseInsensitiveContainsString:searchText];
        }];
        self.filteredOptions = [self.allOptions filteredArrayUsingPredicate:p];
    }
    [self.tableView reloadData];
}

@end
