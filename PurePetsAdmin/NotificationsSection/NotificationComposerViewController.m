//
//  NotificationComposerViewController.m
//  PurePetsAdmin
//

#import "NotificationComposerViewController.h"
#import "AlertHelper.h"
#import "Language.h"
#import "PPPickOptionCell.h"
#import "PPNotificationsManager.h"
#import "PPSelectUsersViewController.h"
#import "Styling.h"
#import "UserManager.h"

typedef NS_ENUM(NSInteger, PPNotificationTargetKind) {
    PPNotificationTargetKindNone = 0,
    PPNotificationTargetKindSpecificUsers,
    PPNotificationTargetKindAllUsers,
    PPNotificationTargetKindAdmins,
    PPNotificationTargetKindEveryone
};

static inline NSString *PPNotifL(NSString *ar, NSString *en) {
    return [Language languageVal] == 1 ? (ar ?: en ?: @"") : (en ?: ar ?: @"");
}

static inline NSString *PPNotifTrimmedString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [((NSString *)value) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static inline NSString *PPNotifFirstNonEmpty(NSArray<NSString *> *candidates) {
    for (NSString *candidate in candidates) {
        NSString *safe = PPNotifTrimmedString(candidate);
        if (safe.length > 0) return safe;
    }
    return @"";
}


static inline NSString *PPNotifServerMessage(NSDictionary *response) {
    if (![response isKindOfClass:[NSDictionary class]]) return @"";
    NSString *error = PPNotifTrimmedString(response[@"error"]);
    if (error.length) return error;
    NSString *message = PPNotifTrimmedString(response[@"message"]);
    if (message.length) return message;
    NSString *msg = PPNotifTrimmedString(response[@"msg"]);
    return msg;
}

static inline BOOL PPNotifResponseHasFailure(NSDictionary *response) {
    if (![response isKindOfClass:[NSDictionary class]]) return NO;
    id errorObj = response[@"error"];
    if ([errorObj isKindOfClass:[NSString class]] && PPNotifTrimmedString(errorObj).length > 0) return YES;
    if ([errorObj isKindOfClass:[NSDictionary class]]) return YES;
    id success = response[@"success"];
    if ([success respondsToSelector:@selector(boolValue)] && ![success boolValue]) return YES;
    id ok = response[@"ok"];
    if ([ok respondsToSelector:@selector(boolValue)] && ![ok boolValue]) return YES;
    NSString *status = PPNotifTrimmedString(response[@"status"]).lowercaseString;
    if ([status isEqualToString:@"error"] || [status isEqualToString:@"failed"] || [status isEqualToString:@"fail"]) return YES;
    return NO;
}

static NSString * const kRowTitleTag = @"title";
static NSString * const kRowBodyTag = @"body";
static NSString * const kRowTypeTag = @"type";

static NSString * const kTargetNoneTag = @"t_none";
static NSString * const kTargetSpecificTag = @"t_specific";
static NSString * const kTargetAllUsersTag = @"t_allusers";
static NSString * const kTargetAdminsTag = @"t_admins";
static NSString * const kTargetEveryoneTag = @"t_everyone";

static NSString * const kSpecificPickRowTag = @"specific_users_picker";
static NSString * const kSpecificSummaryRowTag = @"specific_users_summary";
static NSString * const kSpecificUserRowPrefix = @"specific_user_row_";

@interface NotificationComposerViewController ()
@property (nonatomic, strong) XLFormSectionDescriptor *specificUsersSection;
@property (nonatomic, assign) BOOL isSending;
@end

@implementation NotificationComposerViewController

- (instancetype)init {
    XLFormDescriptor *form = [self buildForm];
    return [super initWithForm:form style:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.selectedUIDs = [NSMutableArray array];
    self.cachedUsers = @[];

    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.tableFooterView = [UIView new];
    [self updateSpecificUsersSummary];
    [self prefetchUsers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UIButton *send = [self pp_ButtonWithSystemName:@"paperplane.fill" action:@selector(onSend)];
    [self pp_navBarWithOtherButton:send title:PPNotifL(@"إنشاء إشعار", @"Compose Notification")];
}

#pragma mark - Form

- (XLFormDescriptor *)buildForm {
    XLFormDescriptor *form = [XLFormDescriptor formDescriptor];

    XLFormSectionDescriptor *content = [XLFormSectionDescriptor formSection];
    [form addFormSection:content];

    XLFormRowDescriptor *title =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowTitleTag rowType:XLFormRowDescriptorTypeText title:kLang(@"Title")];
    title.required = YES;
    [Styling applyGlobalStyleToRow:title];
    [content addFormRow:title];

    XLFormRowDescriptor *body =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowBodyTag rowType:XLFormRowDescriptorTypeTextView title:kLang(@"Body")];
    body.required = YES;
    [Styling applyGlobalStyleToRow:body];
    [content addFormRow:body];

    XLFormRowDescriptor *type =
    [XLFormRowDescriptor formRowDescriptorWithTag:kRowTypeTag rowType:XLFormRowDescriptorTypeSelectorActionSheet title:kLang(@"Type")];
    type.selectorOptions = @[
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeGeneral) displayText:kLang(@"General")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeOrder) displayText:kLang(@"Order")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeAdReview) displayText:kLang(@"Ad Review")],
        [XLFormOptionsObject formOptionsObjectWithValue:@(PPNotificationTypeWarning) displayText:kLang(@"Warning")]
    ];
    type.value = type.selectorOptions.firstObject;
    type.height = 52.0;
    [Styling applyGlobalStyleToRow:type];
    [content addFormRow:type];

    XLFormSectionDescriptor *target = [XLFormSectionDescriptor formSectionWithTitle:PPNotifL(@"هدف الإشعار", @"Notification Target")];
    [form addFormSection:target];

    [target addFormRow:[self targetRowWithTag:kTargetNoneTag title:PPNotifL(@"لا أحد", @"Nobody") subtitle:PPNotifL(@"لن يتم إرسال أي إشعار.", @"No notification will be sent.") selected:YES]];
    [target addFormRow:[self targetRowWithTag:kTargetSpecificTag title:PPNotifL(@"مستخدمون محددون", @"Specific Users") subtitle:PPNotifL(@"اختر مستخدماً واحداً أو أكثر.", @"Select one or more users.") selected:NO]];
    [target addFormRow:[self targetRowWithTag:kTargetAllUsersTag title:PPNotifL(@"جميع المستخدمين", @"All Users") subtitle:PPNotifL(@"إرسال إلى كل مستخدمي التطبيق.", @"Send to all app users.") selected:NO]];
    [target addFormRow:[self targetRowWithTag:kTargetAdminsTag title:PPNotifL(@"المشرفون", @"Admins") subtitle:PPNotifL(@"إرسال إلى جميع المشرفين فقط.", @"Send to all admins only.") selected:NO]];
    [target addFormRow:[self targetRowWithTag:kTargetEveryoneTag title:PPNotifL(@"الكل", @"Everyone") subtitle:PPNotifL(@"إرسال إلى المستخدمين والمشرفين.", @"Send to users and admins.") selected:NO]];

    self.specificUsersSection = [XLFormSectionDescriptor formSectionWithTitle:PPNotifL(@"مستخدمون محددون", @"Specific Users")];

    XLFormRowDescriptor *pickUsers =
    [XLFormRowDescriptor formRowDescriptorWithTag:kSpecificPickRowTag rowType:XLFormRowDescriptorTypePickOption title:PPNotifL(@"اختر مستخدم", @"Select User")];
    pickUsers.height = 60.0;
    __weak typeof(self) weakSelf = self;
    pickUsers.cellConfig[@"onPickTap"] = ^(XLFormRowDescriptor *sender) {
        __strong typeof(weakSelf) self = weakSelf;
        [self presentSpecificUserPickerForRow:sender];
    };
    [self.specificUsersSection addFormRow:pickUsers];

    return form;
}

- (XLFormRowDescriptor *)targetRowWithTag:(NSString *)tag
                                    title:(NSString *)title
                                 subtitle:(NSString *)subtitle
                                 selected:(BOOL)selected {
    XLFormRowDescriptor *row =
    [XLFormRowDescriptor formRowDescriptorWithTag:tag rowType:XLFormRowDescriptorTypeBooleanCheck title:title];
    row.value = @(selected);
    row.cellStyle = UITableViewCellStyleSubtitle;
    row.cellConfigAtConfigure[@"detailTextLabel.text"] = subtitle ?: @"";
    row.cellConfigAtConfigure[@"detailTextLabel.numberOfLines"] = @2;
    __weak typeof(self) weakSelf = self;
    row.onChangeBlock = ^(id oldValue, id newValue, XLFormRowDescriptor * _Nonnull rowDescriptor) {
        __strong typeof(weakSelf) self = weakSelf;
        [self onTargetToggleChanged:rowDescriptor];
    };
    [Styling applyGlobalStyleToRow:row];
    return row;
}

#pragma mark - Target state

- (void)onTargetToggleChanged:(XLFormRowDescriptor *)rowDescriptor {
    if (self.isUpdatingTargets) return;

    self.isUpdatingTargets = YES;
    NSArray<NSString *> *allTargetTags = @[kTargetNoneTag, kTargetSpecificTag, kTargetAllUsersTag, kTargetAdminsTag, kTargetEveryoneTag];
    BOOL changedOn = [rowDescriptor.value boolValue];

    if (changedOn) {
        for (NSString *tag in allTargetTags) {
            if ([tag isEqualToString:rowDescriptor.tag]) continue;
            XLFormRowDescriptor *row = [self.form formRowWithTag:tag];
            row.value = @NO;
            [self updateFormRow:row];
        }
    } else {
        BOOL anyOn = NO;
        for (NSString *tag in allTargetTags) {
            XLFormRowDescriptor *row = [self.form formRowWithTag:tag];
            if ([row.value boolValue]) {
                anyOn = YES;
                break;
            }
        }
        if (!anyOn) {
            XLFormRowDescriptor *noneRow = [self.form formRowWithTag:kTargetNoneTag];
            noneRow.value = @YES;
            [self updateFormRow:noneRow];
        }
    }

    BOOL showSpecific = [[[self.form formRowWithTag:kTargetSpecificTag] value] boolValue];
    [self toggleSpecificUsersSection:showSpecific];
    [self updateSpecificUsersSummary];

    self.isUpdatingTargets = NO;
}

- (void)toggleSpecificUsersSection:(BOOL)show {
    BOOL isShown = [self.form.formSections containsObject:self.specificUsersSection];
    if (show == isShown) return;

    if (show) {
        [self.form addFormSection:self.specificUsersSection atIndex:self.form.formSections.count];
    } else {
        [self.form removeFormSection:self.specificUsersSection];
    }
    [self.tableView reloadData];
}

- (PPNotificationTargetKind)currentTargetKind {
    if ([[[self.form formRowWithTag:kTargetSpecificTag] value] boolValue]) return PPNotificationTargetKindSpecificUsers;
    if ([[[self.form formRowWithTag:kTargetAllUsersTag] value] boolValue]) return PPNotificationTargetKindAllUsers;
    if ([[[self.form formRowWithTag:kTargetAdminsTag] value] boolValue]) return PPNotificationTargetKindAdmins;
    if ([[[self.form formRowWithTag:kTargetEveryoneTag] value] boolValue]) return PPNotificationTargetKindEveryone;
    return PPNotificationTargetKindNone;
}

#pragma mark - Users

- (void)prefetchUsers {
    __weak typeof(self) weakSelf = self;
    [[UserManager shared] fetchAllUsersWithCompletion:^(NSArray<UserModel *> * _Nullable users, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (error) return;
        self.cachedUsers = users ?: @[];
        [self updateSpecificUsersSummary];
    }];
}

- (void)presentSpecificUserPickerForRow:(XLFormRowDescriptor *)row {
    if (self.cachedUsers.count == 0) {
        __weak typeof(self) weakSelf = self;
        [[UserManager shared] fetchAllUsersWithCompletion:^(NSArray<UserModel *> * _Nullable users, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error) {
                [AlertHelper showErrorIn:self title:PPNotifL(@"خطأ", @"Error") subtitle:error.localizedDescription];
                return;
            }
            self.cachedUsers = users ?: @[];
            [self showSpecificUserPickerForRow:row ?: [self.form formRowWithTag:kSpecificPickRowTag]];
        }];
        return;
    }

    [self showSpecificUserPickerForRow:row ?: [self.form formRowWithTag:kSpecificPickRowTag]];
}

- (void)showSpecificUserPickerForRow:(XLFormRowDescriptor *)row {
    (void)row;
    NSArray *options = self.cachedUsers ?: @[];
    if (options.count == 0) {
        [AlertHelper showInfoIn:self
                          title:PPNotifL(@"معلومة", @"Info")
                       subtitle:PPNotifL(@"لا يوجد مستخدمون.", @"No users found.")];
        return;
    }

    __weak typeof(self) weakSelf = self;
    PPSelectUsersViewController *vc =
    [[PPSelectUsersViewController alloc] initWithCompletion:^(id selected) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        NSArray *selectedUsers = @[];
        if ([selected isKindOfClass:[NSArray class]]) {
            selectedUsers = (NSArray *)selected;
        } else if ([selected isKindOfClass:[UserModel class]]) {
            selectedUsers = @[selected];
        }

        NSMutableOrderedSet<NSString *> *uids = [NSMutableOrderedSet orderedSet];
        for (id item in selectedUsers) {
            if (![item isKindOfClass:[UserModel class]]) continue;
            UserModel *user = (UserModel *)item;
            NSString *uid = PPNotifFirstNonEmpty(@[user.uid, user.ID]);
            if (uid.length > 0) [uids addObject:uid];
        }

        self.selectedUIDs = [uids.array mutableCopy];
        [self updateSpecificUsersSummary];
    }];

    vc.allOptions = options;
    vc.filteredOptions = options;
    vc.preselectedOptionIDs = self.selectedUIDs.copy;
    vc.rowDescriptor = [self.form formRowWithTag:kSpecificPickRowTag];
    vc.parentForm = self;
    vc.imageLoaded = NO;
    vc.presentationStyle = PPSelectOptionPresentationSheet;
    vc.title = PPNotifL(@"اختر مستخدم", @"Select User");

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    nav.modalPresentationCapturesStatusBarAppearance = YES;
    nav.view.backgroundColor = [UIColor ppSurface];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = nav.sheetPresentationController;
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
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)updateSpecificUsersSummary {
    XLFormRowDescriptor *pickerRow = [self.form formRowWithTag:kSpecificPickRowTag];
    if (!pickerRow || !self.specificUsersSection) return;

    NSMutableArray<XLFormRowDescriptor *> *rowsToRemove = [NSMutableArray array];
    for (XLFormRowDescriptor *row in self.specificUsersSection.formRows ?: @[]) {
        if ([row.tag isEqualToString:kSpecificSummaryRowTag] || [self isSpecificUserRowTag:row.tag]) {
            [rowsToRemove addObject:row];
        }
    }
    for (XLFormRowDescriptor *row in rowsToRemove) {
        [self.specificUsersSection removeFormRow:row];
    }

    self.selectedUIDs = [[self normalizedSelectedUIDs] mutableCopy];
    NSUInteger selectedCount = self.selectedUIDs.count;

    pickerRow.height = 60.0;
    pickerRow.cellConfig[@"showPickButton"] = @YES;
    pickerRow.cellConfig[@"showOptionImage"] = @YES;
    pickerRow.title = PPNotifL(@"اختر مستخدم", @"Select User");

    if (selectedCount == 0) {
        pickerRow.value = nil;
    } else if (selectedCount == 1) {
        UserModel *singleUser = [self userForUID:self.selectedUIDs.firstObject];
        pickerRow.value = singleUser;
        if (!singleUser) {
            pickerRow.title = [NSString stringWithFormat:@"%@ (1)", PPNotifL(@"اختر مستخدم", @"Select User")];
        }
    } else {
        pickerRow.value = nil;
        pickerRow.title = [NSString stringWithFormat:@"%@ (%lu)",
                           PPNotifL(@"اختر مستخدم", @"Select User"),
                           (unsigned long)selectedCount];

        for (NSString *uid in self.selectedUIDs) {
            UserModel *user = [self userForUID:uid];
            XLFormRowDescriptor *userRow =
            [XLFormRowDescriptor formRowDescriptorWithTag:[self specificUserRowTagForUID:uid]
                                                  rowType:XLFormRowDescriptorTypePickOption
                                                    title:[self displayNameForUser:user fallbackUID:uid]];
            userRow.value = user;
            userRow.height = 54.0;
            userRow.cellConfig[@"showPickButton"] = @NO;
            userRow.cellConfig[@"showOptionImage"] = @YES;
            [self.specificUsersSection addFormRow:userRow beforeRow:pickerRow];
        }
    }

    [self updateFormRow:pickerRow];
    [self.tableView reloadData];
}

- (NSArray<NSString *> *)normalizedSelectedUIDs {
    NSMutableOrderedSet<NSString *> *uids = [NSMutableOrderedSet orderedSet];
    for (id raw in self.selectedUIDs ?: @[]) {
        NSString *uid = PPNotifTrimmedString(raw);
        if (uid.length > 0) [uids addObject:uid];
    }
    return uids.array;
}

- (NSString *)displayNameForUser:(UserModel *)user fallbackUID:(NSString *)uid {
    return PPNotifFirstNonEmpty(@[
        [user PPBestDisplayName],
        user.UserName,
        user.displayName,
        user.UserEmail,
        user.MobileNo,
        uid ?: @""
    ]);
}

- (NSString *)specificUserRowTagForUID:(NSString *)uid {
    NSString *safeUID = PPNotifTrimmedString(uid);
    return [kSpecificUserRowPrefix stringByAppendingString:safeUID];
}

- (BOOL)isSpecificUserRowTag:(NSString *)tag {
    return [tag isKindOfClass:[NSString class]] && [tag hasPrefix:kSpecificUserRowPrefix];
}

- (NSString *)uidFromSpecificUserRowTag:(NSString *)tag {
    if (![self isSpecificUserRowTag:tag]) return @"";
    return [tag substringFromIndex:kSpecificUserRowPrefix.length];
}

- (XLFormRowDescriptor *)rowDescriptorForIndexPath:(NSIndexPath *)indexPath {
    if (!indexPath) return nil;
    if (indexPath.section >= self.form.formSections.count) return nil;
    XLFormSectionDescriptor *section = self.form.formSections[indexPath.section];
    if (indexPath.row >= section.formRows.count) return nil;
    return section.formRows[indexPath.row];
}

- (UserModel *)userForUID:(NSString *)uid {
    for (UserModel *user in self.cachedUsers) {
        if ([user.uid isEqualToString:uid] || [user.ID isEqualToString:uid]) return user;
    }
    return nil;
}

#pragma mark - Send

- (void)onSend {
    NSArray *errors = [self formValidationErrors];
    if (errors.count) {
        NSString *message = ((NSError *)errors.firstObject).localizedDescription ?: PPNotifL(@"النموذج غير صالح.", @"Invalid form.");
        [AlertHelper showErrorIn:self title:PPNotifL(@"خطأ", @"Error") subtitle:message];
        return;
    }

    PPNotificationTargetKind target = [self currentTargetKind];
    if (target == PPNotificationTargetKindNone) {
        [AlertHelper showInfoIn:self
                          title:PPNotifL(@"معلومة", @"Info")
                       subtitle:PPNotifL(@"لم يتم اختيار مستلمين.", @"No recipients selected.")];
        return;
    }

    if (self.isSending) return;

    NSString *title = [self.form formRowWithTag:kRowTitleTag].value ?: @"";
    NSString *body = [self.form formRowWithTag:kRowBodyTag].value ?: @"";
    NSInteger typeValue = [self integerFromRowValue:[self.form formRowWithTag:kRowTypeTag].value];

    NSMutableDictionary *data = [@{
        @"senderUID": PPSafeString(UsrMgr.currentUser.uid),
        @"type": [NSString stringWithFormat:@"%ld", (long)typeValue]
    } mutableCopy];

    PPNotificationAudience audience = PPNotificationAudienceAllUsers;
    NSArray<NSString *> *userIDs = nil;
    NSString *successMessage = PPNotifL(@"تمت جدولة الإشعار.", @"Notification queued.");

    switch (target) {
        case PPNotificationTargetKindSpecificUsers:
            if (self.selectedUIDs.count == 0) {
                [AlertHelper showInfoIn:self
                                  title:PPNotifL(@"معلومة", @"Info")
                               subtitle:PPNotifL(@"يرجى اختيار مستخدم واحد على الأقل.", @"Please select at least one user.")];
                return;
            }
            audience = PPNotificationAudienceSpecificUsers;
            userIDs = self.selectedUIDs.copy;
            successMessage = (self.selectedUIDs.count == 1)
            ? PPNotifL(@"تم إرسال الإشعار إلى مستخدم واحد.", @"Notification sent to 1 user.")
            : [NSString stringWithFormat:PPNotifL(@"تم إرسال الإشعار إلى %lu مستخدمين.", @"Notification sent to %lu users."), (unsigned long)self.selectedUIDs.count];
            break;
        case PPNotificationTargetKindAllUsers:
            [self setSending:YES];
            [self sendFallbackUsingUsersCollectionWithTitle:title
                                                       body:body
                                                       data:data
                                          includeNonAdmins:YES
                                         includeAdminTokens:NO
                                               limitToUIDs:nil];
            return;
        case PPNotificationTargetKindAdmins:
            [self setSending:YES];
            [self sendFallbackUsingUsersCollectionWithTitle:title
                                                       body:body
                                                       data:data
                                          includeNonAdmins:NO
                                         includeAdminTokens:YES
                                               limitToUIDs:nil];
            return;
        case PPNotificationTargetKindEveryone:
            [self setSending:YES];
            [self sendFallbackUsingUsersCollectionWithTitle:title
                                                       body:body
                                                       data:data
                                          includeNonAdmins:YES
                                         includeAdminTokens:YES
                                               limitToUIDs:nil];
            return;
        case PPNotificationTargetKindNone:
        default:
            return;
    }

    [self setSending:YES];
    [PPNotificationsManager sendNotificationWithTitle:title
                                                 body:body
                                                 data:data
                                             audience:audience
                                              userIDs:userIDs
                                           completion:^(NSDictionary * _Nullable response, NSError * _Nullable error) {
        NSString *errMsg = PPNotifTrimmedString(error.localizedDescription);
        NSString *serverMsg = PPNotifServerMessage(response);
        NSString *combinedMsg = [NSString stringWithFormat:@"%@ %@", errMsg, serverMsg];
        NSString *combinedLower = combinedMsg.lowercaseString;

        BOOL status404 = (error && [error.domain isEqualToString:@"PPNotificationsManager"] && error.code == 404);
        BOOL noAdminTokens = [combinedLower containsString:@"no admin tokens found"];
        BOOL noUserToken = [combinedLower containsString:@"no user token found"];
        BOOL noUserTokens = [combinedLower containsString:@"no user tokens found"];
        BOOL noTokens = [combinedLower containsString:@"no tokens found"] || [combinedLower containsString:@"no token found"];
        BOOL userMissing = [combinedLower containsString:@"user not found"];
        BOOL invalidDataShape = [combinedLower containsString:@"data must only contain string values"];

        BOOL needsSpecificFallback =
        (target == PPNotificationTargetKindSpecificUsers) &&
        (noUserToken || noUserTokens || noTokens || userMissing || invalidDataShape || status404);

        BOOL needsAdminFallback =
        (target == PPNotificationTargetKindAdmins || target == PPNotificationTargetKindEveryone) &&
        (noAdminTokens || invalidDataShape || status404);

        BOOL needsUsersFallback =
        (target == PPNotificationTargetKindAllUsers || target == PPNotificationTargetKindEveryone) &&
        (noUserToken || noUserTokens || noTokens || invalidDataShape || status404);

        if (needsSpecificFallback || needsAdminFallback || needsUsersFallback) {
            BOOL includeAdminsTokens = (target == PPNotificationTargetKindAdmins || target == PPNotificationTargetKindEveryone || target == PPNotificationTargetKindSpecificUsers);
            [self sendFallbackUsingUsersCollectionWithTitle:title
                                                       body:body
                                                       data:data
                                          includeNonAdmins:(target != PPNotificationTargetKindAdmins)
                                         includeAdminTokens:includeAdminsTokens
                                               limitToUIDs:(target == PPNotificationTargetKindSpecificUsers ? userIDs : nil)];
            return;
        }

        [self setSending:NO];
        BOOL responseFailure = PPNotifResponseHasFailure(response);
        if (error || responseFailure) {
            NSString *subtitle = errMsg.length ? errMsg : (serverMsg.length ? serverMsg : PPNotifL(@"فشل إرسال الإشعار.", @"Failed to send notification."));
            [AlertHelper showErrorIn:self title:PPNotifL(@"فشل", @"Failed") subtitle:subtitle];
            return;
        }
        [AlertHelper showSuccessIn:self title:PPNotifL(@"تم الإرسال", @"Sent") subtitle:successMessage];
    }];
}

- (void)sendFallbackUsingUsersCollectionWithTitle:(NSString *)title
                                              body:(NSString *)body
                                              data:(NSDictionary *)data
                                 includeNonAdmins:(BOOL)includeNonAdmins
                                  includeAdminTokens:(BOOL)includeAdminTokens
                                      limitToUIDs:(NSArray<NSString *> * _Nullable)limitToUIDs {
    __weak typeof(self) weakSelf = self;
    [[UserManager shared] fetchAllUsersWithCompletion:^(NSArray<UserModel *> * _Nullable users, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (error) {
            [self setSending:NO];
            [AlertHelper showErrorIn:self title:PPNotifL(@"فشل", @"Failed") subtitle:error.localizedDescription];
            return;
        }

        NSMutableOrderedSet<NSString *> *allowedSet = nil;
        if ([limitToUIDs isKindOfClass:[NSArray class]] && limitToUIDs.count > 0) {
            allowedSet = [NSMutableOrderedSet orderedSet];
            for (id raw in limitToUIDs) {
                NSString *uid = PPNotifTrimmedString(raw);
                if (uid.length) [allowedSet addObject:uid];
            }
        }

        NSMutableOrderedSet<NSString *> *tokens = [NSMutableOrderedSet orderedSet];
        for (UserModel *u in users ?: @[]) {
            NSString *uid = PPNotifFirstNonEmpty(@[u.uid, u.ID]);
            if (allowedSet.count > 0 && ![allowedSet containsObject:uid]) continue;

            BOOL isAdminRole = (u.role == UserRoleAdmin || u.role == UserRoleSuperAdmin);
            BOOL isAdminUser = (u.isAdmin || u.isSuperAdmin || isAdminRole);
            if (!includeNonAdmins && !isAdminUser) continue;

            NSString *adminToken = PPNotifTrimmedString(u.PPAdminTokenID);
            NSString *userToken = PPNotifTrimmedString(u.PPUserTokenID);
            NSString *proToken = PPNotifTrimmedString(u.PPProTokenID);

            if (includeAdminTokens && isAdminUser && adminToken.length) [tokens addObject:adminToken];
            if (userToken.length) [tokens addObject:userToken];
            if (proToken.length) [tokens addObject:proToken];
        }

        if (tokens.count == 0) {
            [self setSending:NO];
            [AlertHelper showErrorIn:self
                               title:PPNotifL(@"فشل", @"Failed")
                            subtitle:PPNotifL(@"لا توجد رموز أجهزة صالحة للإرسال.", @"No valid recipient tokens found.")];
            return;
        }

        dispatch_group_t group = dispatch_group_create();
        __block NSInteger successCount = 0;
        __block NSInteger failCount = 0;
        __block NSString *lastError = @"";

        for (NSString *token in tokens.array) {
            dispatch_group_enter(group);
            [PPNotificationsManager sendToToken:token title:title body:body data:data completion:^(NSDictionary * _Nullable response, NSError * _Nullable err) {
                if (err) {
                    failCount += 1;
                    lastError = err.localizedDescription ?: @"";
                } else {
                    successCount += 1;
                }
                dispatch_group_leave(group);
            }];
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [self setSending:NO];
            if (successCount > 0) {
                NSString *message = (successCount == 1)
                ? PPNotifL(@"تم إرسال إشعار واحد.", @"1 notification sent.")
                : [NSString stringWithFormat:PPNotifL(@"تم إرسال %ld إشعار.", @"%ld notifications sent."), (long)successCount];
                [AlertHelper showSuccessIn:self title:PPNotifL(@"تم الإرسال", @"Sent") subtitle:message];
            } else {
                NSString *msg = lastError.length ? lastError : PPNotifL(@"فشل إرسال الإشعارات.", @"Failed to send notifications.");
                [AlertHelper showErrorIn:self title:PPNotifL(@"فشل", @"Failed") subtitle:msg];
            }
        });
    }];
}

- (void)setSending:(BOOL)isSending {
    _isSending = isSending;
    self.navigationItem.rightBarButtonItem.enabled = !isSending;
}

#pragma mark - UI styling

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    header.textLabel.font = [Styling fontMedium:14];
    header.textLabel.textColor = SeconderyTextClr;
    header.textLabel.textAlignment = [Language alignmentForCurrentLanguage];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [Styling applyBackgroundStyleForTableView:tableView cell:cell indexPath:indexPath useRowCardMode:NO];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self rowDescriptorForIndexPath:indexPath];
    if ([self isSpecificUserRowTag:row.tag]) {
        return YES;
    }
    return [super tableView:tableView canEditRowAtIndexPath:indexPath];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    XLFormRowDescriptor *row = [self rowDescriptorForIndexPath:indexPath];
    if ([self isSpecificUserRowTag:row.tag]) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    XLFormRowDescriptor *row = [self rowDescriptorForIndexPath:indexPath];
    if (![self isSpecificUserRowTag:row.tag]) return;

    NSString *uid = [self uidFromSpecificUserRowTag:row.tag];
    if (uid.length > 0) {
        [self.selectedUIDs removeObject:uid];
    }
    [self updateSpecificUsersSummary];
}

- (NSInteger)integerFromRowValue:(id)raw {
    if (raw == nil || raw == (id)kCFNull) return PPNotificationTypeGeneral;
    if ([raw isKindOfClass:[XLFormOptionsObject class]]) {
        XLFormOptionsObject *opt = raw;
        id fv = [opt respondsToSelector:@selector(formValue)] ? [opt formValue] : nil;
        if ([fv isKindOfClass:[NSNumber class]]) return [fv integerValue];
        if ([fv isKindOfClass:[NSString class]]) return [fv integerValue];
        return [[opt displayText] integerValue];
    }
    if ([raw isKindOfClass:[NSNumber class]]) return [raw integerValue];
    if ([raw isKindOfClass:[NSString class]]) return [raw integerValue];
    return PPNotificationTypeGeneral;
}

@end
