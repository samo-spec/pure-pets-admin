//
//  RoleOptionsViewController.m
//  PurePetsAdmin
//

#import "RoleOptionsViewController.h"
#import "RoleOptionCell.h"

@implementation RoleOptionsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = kLang(@"Role_Title");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.contentInset = UIEdgeInsetsMake(16, 0, 36, 0);
    
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
    [self.tableView registerClass:[RoleOptionCell class] forCellReuseIdentifier:@"RoleOptionCell"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    RoleOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RoleOptionCell" forIndexPath:indexPath];

    XLFormOptionsObject *option = self.rowDescriptor.selectorOptions[indexPath.row];
    cell.titleLabel.text = option.displayText;
    
    NSString *subtitle = @"";
    if ([option respondsToSelector:@selector(userInfo)]) {
        NSDictionary *info = [option performSelector:@selector(userInfo)];
        subtitle = info[@"desc"] ?: @"";
    }
    cell.subtitleLabel.text = subtitle;

    BOOL isSelected = [self.rowDescriptor.value isEqual:option] ||
                      ([self.rowDescriptor.value isKindOfClass:NSString.class] &&
                       [option.formValue isKindOfClass:NSString.class] &&
                       [self.rowDescriptor.value isEqualToString:option.formValue]);
    
    [cell pp_setSelectedState:isSelected];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 72.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormOptionsObject *option = self.rowDescriptor.selectorOptions[indexPath.row];
    self.rowDescriptor.value = option;
    
    if (self.rowDescriptor.onChangeBlock) {
        self.rowDescriptor.onChangeBlock(nil, option, self.rowDescriptor);
    }
    
    [self.tableView reloadData];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

@end
