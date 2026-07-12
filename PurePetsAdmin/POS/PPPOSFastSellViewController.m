#import "PPPOSFastSellViewController.h"
#import "PPPOSService.h"
#import "Language.h"
#import "Styling.h"
#import "AlertHelper.h"
#import "PPFunc+Haptics.h"

@interface PPPOSFastSellViewController ()
@property (nonatomic, strong) NSMutableArray<PPPOSCartItem *> *cart;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UILabel *totalLabel;
@end

@implementation PPPOSFastSellViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = kLang(@"POS_Title");
    self.cart = [NSMutableArray array];
    self.tableView.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"ItemCell"];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"CartCell"];

    UIBarButtonItem *clearBtn = [[UIBarButtonItem alloc] initWithTitle:kLang(@"POS_Clear") style:UIBarButtonItemStylePlain target:self action:@selector(didTapClear)];
    self.navigationItem.leftBarButtonItem = clearBtn;

    UIBarButtonItem *checkoutBtn = [[UIBarButtonItem alloc] initWithTitle:kLang(@"POS_Checkout") style:UIBarButtonItemStyleDone target:self action:@selector(didTapCheckout)];
    self.navigationItem.rightBarButtonItem = checkoutBtn;
}

- (void)didTapClear {
    [self.cart removeAllObjects];
    [self.tableView reloadData];
}

- (void)didTapCheckout {
    if (self.cart.count == 0) {
        [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:kLang(@"POS_EmptyCart")];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"POS_Checkout") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"POS_Cash") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self submitOrder:@"cash"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"POS_Card") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self submitOrder:@"card"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)submitOrder:(NSString *)method {
    NSMutableArray *itemsPayload = [NSMutableArray array];
    double total = 0;
    for (PPPOSCartItem *item in self.cart) {
        [itemsPayload addObject:@{
            @"itemId": item.itemID,
            @"name": item.name,
            @"price": @(item.price),
            @"quantity": @(item.quantity)
        }];
        total += item.price * item.quantity;
    }

    [[PPPOSService shared] submitPOSOrderWithItems:itemsPayload total:total paymentMethod:method completion:^(NSString *orderID, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [AlertHelper showAlertIn:self title:kLang(@"Error_Title") subtitle:error.localizedDescription];
            } else {
                [PPFunc pp_playSuccessEffect];
                [self.cart removeAllObjects];
                [self.tableView reloadData];
                [AlertHelper showAlertIn:self title:kLang(@"Success_Title") subtitle:[NSString stringWithFormat:kLang(@"POS_OrderCreated"), orderID]];
            }
        });
    }];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    return MAX(self.cart.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? kLang(@"POS_AddItem") : kLang(@"POS_Cart");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ItemCell" forIndexPath:indexPath];
        cell.textLabel.text = kLang(@"POS_ScanOrSearch");
        cell.textLabel.textColor = UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CartCell" forIndexPath:indexPath];
    cell.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    if (self.cart.count == 0) {
        cell.textLabel.text = kLang(@"POS_CartEmpty");
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    PPPOSCartItem *item = self.cart[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ x%ld", item.name, (long)item.quantity];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.2f", item.price * item.quantity];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"POS_AddItem") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = kLang(@"POS_ItemName");
        }];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = kLang(@"POS_ItemPrice");
            tf.keyboardType = UIKeyboardTypeDecimalPad;
        }];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
            tf.placeholder = kLang(@"POS_ItemQty");
            tf.keyboardType = UIKeyboardTypeNumberPad;
            tf.text = @"1";
        }];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Add") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *name = alert.textFields[0].text ?: @"";
            double price = [alert.textFields[1].text doubleValue];
            NSInteger qty = MAX(1, [alert.textFields[2].text integerValue]);
            if (name.length == 0 || price <= 0) return;

            PPPOSCartItem *item = [PPPOSCartItem new];
            item.itemID = [NSUUID UUID].UUIDString;
            item.name = name;
            item.price = price;
            item.quantity = qty;
            [self.cart addObject:item];
            [self.tableView reloadData];
            [PPFunc pp_playTapEffect];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

@end
