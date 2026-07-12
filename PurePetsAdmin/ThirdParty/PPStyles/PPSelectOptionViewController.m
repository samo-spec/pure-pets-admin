//
//  PPSelectOptionViewController.m
//  PurePetsAdmin
//

#import "PPSelectOptionViewController.h"
#import "Language.h"
#import "PPS.h"
#import "PPOptionCell.h"
#import "Styling.h"
#import "XLForm.h"
#import <math.h>

#ifndef DLog
#define DLog(fmt, ...) NSLog((@"[PPLOG] " fmt), ##__VA_ARGS__)
#endif

static inline NSString *PPSelectTrimmed(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [((NSString *)value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@interface PPSelectOptionViewController () <PPSDelegate>
@property (nonatomic, strong) PPS *searchView;
@end

@implementation PPSelectOptionViewController

#pragma mark - Init

- (instancetype)init {
    return [self initWithOptions:@[]
                           title:kLang(@"Select")
                             row:nil
               presentationStyle:PPSelectOptionPresentationSheet
                      completion:nil];
}

- (instancetype)initWithOptions:(NSArray *)options
                          title:(NSString *)title
                            row:(XLFormRowDescriptor *)row
               presentationStyle:(PPSelectOptionPresentationStyle)style
                     completion:(PPSelectOptionBlock)completion {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _allOptions = options ?: @[];
        _filteredOptions = _allOptions;
        _showSearchBar = YES;
        _presentationStyle = style;
        _onSelectOption = [completion copy];
        self.rowDescriptor = row;
        self.title = title.length ? title : kLang(@"Select");
    }
    return self;
}

- (instancetype)initWithCompletion:(PPSelectOptionBlock)completion {
    return [self initWithOptions:@[]
                           title:kLang(@"Select")
                             row:nil
               presentationStyle:PPSelectOptionPresentationSheet
                      completion:completion];
}

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = 72.0;
    self.tableView.estimatedRowHeight = 72.0;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.backgroundColor = AppBackgroundClr;
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (self.presentationStyle == PPSelectOptionPresentationSheet) {
        if (@available(iOS 15.0, *)) {
            UISheetPresentationController *sheet = self.sheetPresentationController;
            if (sheet) {
                sheet.detents = @[
                    [UISheetPresentationControllerDetent mediumDetent],
                    [UISheetPresentationControllerDetent largeDetent]
                ];
                sheet.prefersGrabberVisible = YES;
                sheet.preferredCornerRadius = 26.0;
                sheet.prefersScrollingExpandsWhenScrolledToEdge = NO;
            }
        }
    }

    if (self.showSearchBar) {
        [self setupSearchView];
    }

    if (!self.filteredOptions) {
        self.filteredOptions = self.allOptions ?: @[];
    }

    [self pp_refreshSearchIndex];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    if (!self.searchContainer) return;

    CGFloat width = self.tableView.bounds.size.width;
    CGRect frame = self.searchContainer.frame;
    if (fabs(frame.size.width - width) > 0.5) {
        frame.size.width = width;
        self.searchContainer.frame = frame;
        self.tableView.tableHeaderView = self.searchContainer;
    }
}

#pragma mark - Search

- (void)setupSearchView {
    CGFloat horizontal = 16.0;
    CGFloat vertical = 10.0;
    CGFloat searchHeight = 50.0;
    CGFloat containerHeight = vertical + searchHeight + vertical;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : self.view.bounds.size.width;

    self.searchContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, containerHeight)];
    self.searchContainer.backgroundColor = UIColor.clearColor;

    PPS *search = [[PPS alloc] initWithFrame:CGRectZero];
    search.translatesAutoresizingMaskIntoConstraints = NO;
    search.cornerRadius = searchHeight / 2.0;
    search.blurEnabled = NO;
    search.shadowEnabled = NO;
    search.debounceInterval = 0.18;
    search.fuzzyEnabled = YES;
    search.caseInsensitive = YES;
    search.diacriticsInsensitive = YES;
    search.minRelevanceScore = 0.40;
    search.maxResults = 500;
    search.delegate = self;
    search.showsPrimaryButton = NO;
    search.showsSecondaryButton = NO;
    search.textField.placeholder = kLang(@"SearchHere");
    search.textField.textAlignment = [Language alignmentForCurrentLanguage];
    search.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    search.backgroundColor = AppForgroundColr;
    self.searchView = search;

    [self.searchContainer addSubview:search];
    [NSLayoutConstraint activateConstraints:@[
        [search.topAnchor constraintEqualToAnchor:self.searchContainer.topAnchor constant:vertical],
        [search.leadingAnchor constraintEqualToAnchor:self.searchContainer.leadingAnchor constant:horizontal],
        [search.trailingAnchor constraintEqualToAnchor:self.searchContainer.trailingAnchor constant:-horizontal],
        [search.bottomAnchor constraintEqualToAnchor:self.searchContainer.bottomAnchor constant:-vertical],
        [search.heightAnchor constraintEqualToConstant:searchHeight]
    ]];

    self.tableView.tableHeaderView = self.searchContainer;
}

- (void)pp_refreshSearchIndex {
    if (!self.searchView) return;

    __weak typeof(self) weakSelf = self;
    [self.searchView setSearchItems:self.allOptions ?: @[]
                 multiStringProvider:^NSArray<NSString *> * _Nonnull(id item) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return @[];

        NSString *title = [self displayTextForOption:item];
        NSString *detail = [self detailTextForOption:item];

        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        if (title.length) [parts addObject:title];
        if (detail.length && ![detail isEqualToString:title]) [parts addObject:detail];
        return parts.count ? parts : @[[item description] ?: @""];
    }];
}

- (void)searchView:(PPS *)view didChangeText:(NSString *)text {
    NSString *query = PPSelectTrimmed(text);
    if (query.length == 0) {
        self.filteredOptions = self.allOptions ?: @[];
        [self reloadTableViewAnimated];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [view filterAsyncForText:query completion:^(NSString *q, NSArray *results) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSString *latestQuery = PPSelectTrimmed(self.searchView.textField.text);
        if (![latestQuery isEqualToString:PPSelectTrimmed(q)]) {
            return;
        }

        self.filteredOptions = results ?: @[];
        [self reloadTableViewAnimated];
    }];
}

- (void)searchViewDidSubmit:(PPS *)view {
    [view unfocus];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.filteredOptions.count;
}

- (PPOptionCell *)makeCellForTable:(UITableView *)tableView reuseId:(NSString *)reuse {
    PPOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) {
        cell = [[PPOptionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id option = self.filteredOptions[indexPath.row];
    PPOptionCell *cell = [self makeCellForTable:tableView reuseId:@"PPOptionCell"];

    NSString *title = [self displayTextForOption:option];
    NSString *detail = [self detailTextForOption:option];
    NSString *imageURL = [self imageURLForOption:option];

    if (imageURL.length > 0) {
        [cell configureWithTitle:title subtitle:detail imageUrl:imageURL];
    } else {
        UIImage *icon = nil;
        if ([option isKindOfClass:[XLFormOptionsObject class]]) {
            NSString *imgName = ((XLFormOptionsObject *)option).userInfo[@"image"];
            if (imgName.length > 0) {
                icon = [UIImage imageNamed:imgName];
            }
        }
        [cell configureWithTitle:title subtitle:detail image:icon];
    }

    BOOL selected = NO;
    id rowVal = self.rowDescriptor.value;
    if ([rowVal isKindOfClass:[NSString class]]) {
        selected = [PPSelectTrimmed(rowVal) isEqualToString:PPSelectTrimmed(title)];
    } else if (rowVal != nil) {
        selected = [rowVal isEqual:option];
    } else if (self.selectedOption != nil) {
        selected = [self.selectedOption isEqual:option];
    }

    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = AppPrimaryClr;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    id option = self.filteredOptions[indexPath.row];
    self.selectedOption = option;

    NSString *display = [self displayTextForOption:option] ?: @"";
    [self updateRowValue:display];

    if (self.onSelectOption) {
        self.onSelectOption(option);
    }

    if (self.presentationStyle == PPSelectOptionPresentationPush) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)reloadTableViewAnimated {
    [UIView transitionWithView:self.tableView
                      duration:0.20
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
        [self.tableView reloadData];
    } completion:nil];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = AppForgroundColr;
    cell.contentView.backgroundColor = AppForgroundColr;
    cell.layer.mask = nil;
    cell.layer.shadowOpacity = 0.0;
}

#pragma mark - Helpers

- (NSString *)displayTextForOption:(id)option {
    if (!option) return @"";

    if ([option isKindOfClass:[XLFormOptionsObject class]]) {
        return PPSelectTrimmed([(XLFormOptionsObject *)option displayText]);
    }

    NSString *name = [self valueForOption:option selector:@selector(PPBestDisplayName)];
    if (name.length) return name;

    name = [self valueForOption:option selector:@selector(UserName)];
    if (name.length) return name;

    name = [self valueForOption:option selector:@selector(displayName)];
    if (name.length) return name;

    name = [self valueForOption:option selector:@selector(UserEmail)];
    if (name.length) return name;

    name = [self valueForOption:option selector:@selector(MobileNo)];
    if (name.length) return name;

    if ([option isKindOfClass:[NSString class]]) {
        return PPSelectTrimmed(option);
    }

    return PPSelectTrimmed([option description]);
}

- (NSString *)detailTextForOption:(id)option {
    if (!option) return @"";

    if ([option isKindOfClass:[XLFormOptionsObject class]]) {
        NSDictionary *ui = ((XLFormOptionsObject *)option).userInfo ?: @{};
        return PPSelectTrimmed(ui[@"desc"]);
    }

    NSString *detail = [self valueForOption:option selector:@selector(UserEmail)];
    if (detail.length) return detail;

    detail = [self valueForOption:option selector:@selector(MobileNo)];
    if (detail.length) return detail;

    detail = [self valueForOption:option selector:@selector(uid)];
    if (detail.length) return detail;

    detail = [self valueForOption:option selector:@selector(ID)];
    return detail;
}

- (NSString *)imageURLForOption:(id)option {
    if (!option) return @"";

    if ([option respondsToSelector:@selector(UserImageUrl)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id urlValue = [option performSelector:@selector(UserImageUrl)];
#pragma clang diagnostic pop
        if ([urlValue isKindOfClass:[NSURL class]]) {
            return PPSelectTrimmed([(NSURL *)urlValue absoluteString]);
        }
        if ([urlValue isKindOfClass:[NSString class]]) {
            return PPSelectTrimmed(urlValue);
        }
    }
    return @"";
}

- (NSString *)valueForOption:(id)option selector:(SEL)selector {
    if (!option || !selector || ![option respondsToSelector:selector]) return @"";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id val = [option performSelector:selector];
#pragma clang diagnostic pop
    if (![val isKindOfClass:[NSString class]]) return @"";
    return PPSelectTrimmed((NSString *)val);
}

- (void)updateRowValue:(id)value {
    if (!self.rowDescriptor) return;
    self.rowDescriptor.value = value;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.parentForm && [self.parentForm respondsToSelector:@selector(updateFormRow:)]) {
            [self.parentForm updateFormRow:self.rowDescriptor];
        }
    });
}

- (void)setAllOptions:(NSArray *)allOptions {
    _allOptions = allOptions ?: @[];
    self.filteredOptions = _allOptions;
    [self pp_refreshSearchIndex];
}

@end
