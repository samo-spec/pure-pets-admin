//
//  NotificationSettingsViewController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationSettingsViewController.m
#import "NotificationSettingsViewController.h"

@implementation NotificationSettingsViewController

- (instancetype)init { if (self = [super init]) { [self buildForm]; } return self; }

- (void)buildForm {
    self.title = kLang(@"Notification Settings");
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    XLFormSectionDescriptor *sec = [XLFormSectionDescriptor formSectionWithTitle:kLang(@"Categories")];
    [form addFormSection:sec];

    [sec addFormRow:[self switchRow:@"cat_general" title:kLang(@"General") defaultValue:@(YES)]];
    [sec addFormRow:[self switchRow:@"cat_order"   title:kLang(@"Orders")  defaultValue:@(YES)]];
    [sec addFormRow:[self switchRow:@"cat_review"  title:kLang(@"Ad Review") defaultValue:@(YES)]];
    [sec addFormRow:[self switchRow:@"cat_warning" title:kLang(@"Warnings") defaultValue:@(YES)]];

    self.form = form;
}

- (XLFormRowDescriptor *)switchRow:(NSString *)tag title:(NSString *)title defaultValue:(NSNumber *)def {
    XLFormRowDescriptor *r = [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:XLFormRowDescriptorTypeBooleanSwitch title:title];
    r.value = def;
    return r;
}
@synthesize rowDescriptor;

@end
