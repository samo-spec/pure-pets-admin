//
//  PPAlertHelper.m
//  PurePetsAdmin
//
//  Objective-C compatibility facade over the SwiftUI alert presentation owner.
//

#import "PPAlertHelper.h"
#import "Language.h"
#import "PurePetsAdmin-Swift.h"

static NSString *PPAlertTrimmedText(NSString *value) {
    return [value isKindOfClass:NSString.class]
        ? [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
}

typedef NS_ENUM(NSInteger, PPAlertActionStyle) {
    PPAlertActionStylePrimary = 0,
    PPAlertActionStyleSecondary,
    PPAlertActionStyleDestructive,
    PPAlertActionStyleCancel
};

// MARK: - Action Item Model

@interface PPAlertActionItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) PPAlertActionStyle style;
@property (nonatomic, copy, nullable) AlertCompletionBlock completion;
@property (nonatomic, copy, nullable) PPAlertSimpleActionBlock simpleCompletion;

+ (instancetype)itemWithTitle:(NSString *)title
                        style:(PPAlertActionStyle)style
                   completion:(AlertCompletionBlock _Nullable)completion
             simpleCompletion:(PPAlertSimpleActionBlock _Nullable)simpleCompletion;
@end

@implementation PPAlertActionItem

+ (instancetype)itemWithTitle:(NSString *)title
                        style:(PPAlertActionStyle)style
                   completion:(AlertCompletionBlock _Nullable)completion
             simpleCompletion:(PPAlertSimpleActionBlock _Nullable)simpleCompletion {
    PPAlertActionItem *item = [[self alloc] init];
    item.title = title ?: @"";
    item.style = style;
    item.completion = completion;
    item.simpleCompletion = simpleCompletion;
    return item;
}

@end

#pragma mark - PPAlert Compatibility Adapter

@interface PPAlert ()
@property (nonatomic, assign) PPAlertType type;
@property (nonatomic, copy) NSString *alertTitle;
@property (nonatomic, copy) NSString *alertSubtitle;
@property (nonatomic, strong, nullable) UIImage *iconImage;
@property (nonatomic, copy) NSArray<PPAlertActionItem *> *actionItems;
@property (nonatomic, assign) NSInteger defaultActionIndex;
@property (nonatomic, copy, nullable) NSString *textPlaceholder;
@property (nonatomic, copy, nullable) NSString *initialText;
@property (nonatomic, assign) BOOL secureEntry;
@property (nonatomic, assign) UIKeyboardType keyboardType;
@property (nonatomic, assign) BOOL shouldDismissOnBackgroundTap;

- (instancetype)initWithType:(PPAlertType)type
                       title:(NSString *)title
                    subtitle:(NSString *)subtitle
                        icon:(UIImage * _Nullable)icon
                     actions:(NSArray<PPAlertActionItem *> *)actions
                 placeholder:(NSString * _Nullable)placeholder
                 initialText:(NSString * _Nullable)initialText
                 secureEntry:(BOOL)secureEntry
                keyboardType:(UIKeyboardType)keyboardType
 shouldDismissOnBackgroundTap:(BOOL)shouldDismissOnBackgroundTap;
@end

@implementation PPAlert

- (instancetype)initWithType:(PPAlertType)type
                       title:(NSString *)title
                    subtitle:(NSString *)subtitle
                        icon:(UIImage *)icon
                confirmTitle:(NSString * _Nullable)confirmTitle
                 cancelTitle:(NSString * _Nullable)cancelTitle
               confirmAction:(AlertCompletionBlock _Nullable)confirmAction
                cancelAction:(void(^ _Nullable)(void))cancelAction {
    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];
    NSString *safeConfirmTitle = confirmTitle.length ? confirmTitle : kLang(@"OK");
    if (cancelTitle.length > 0) {
        [actions addObject:[PPAlertActionItem itemWithTitle:cancelTitle
                                                      style:PPAlertActionStyleCancel
                                                 completion:nil
                                           simpleCompletion:cancelAction]];
    }
    [actions addObject:[PPAlertActionItem itemWithTitle:safeConfirmTitle
                                                  style:(type == PPAlertTypeError ? PPAlertActionStyleDestructive : PPAlertActionStylePrimary)
                                             completion:confirmAction
                                       simpleCompletion:nil]];
    PPAlert *alert = [self initWithType:type
                                 title:title
                              subtitle:subtitle
                                  icon:icon
                               actions:actions
                           placeholder:nil
                           initialText:nil
                           secureEntry:NO
                          keyboardType:UIKeyboardTypeDefault
          shouldDismissOnBackgroundTap:(cancelTitle.length > 0)];
    alert.defaultActionIndex = (NSInteger)actions.count - 1;
    return alert;
}

- (instancetype)initWithType:(PPAlertType)type
                       title:(NSString *)title
                    subtitle:(NSString *)subtitle
                        icon:(UIImage * _Nullable)icon
                     actions:(NSArray<PPAlertActionItem *> *)actions
                 placeholder:(NSString * _Nullable)placeholder
                 initialText:(NSString * _Nullable)initialText
                 secureEntry:(BOOL)secureEntry
                keyboardType:(UIKeyboardType)keyboardType
 shouldDismissOnBackgroundTap:(BOOL)shouldDismissOnBackgroundTap {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _type = type;
    _alertTitle = title ?: @"";
    _alertSubtitle = subtitle ?: @"";
    _iconImage = icon;
    _actionItems = [actions copy] ?: @[];
    _defaultActionIndex = NSNotFound;
    for (NSInteger index = 0; index < (NSInteger)_actionItems.count; index += 1) {
        if (_actionItems[index].style == PPAlertActionStylePrimary) {
            _defaultActionIndex = index;
            break;
        }
    }
    _textPlaceholder = [placeholder copy];
    _initialText = [initialText copy];
    _secureEntry = secureEntry;
    _keyboardType = keyboardType;
    _shouldDismissOnBackgroundTap = shouldDismissOnBackgroundTap;
    return self;
}

- (void)showInViewController:(UIViewController *)vc {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showInViewController:vc];
        });
        return;
    }
    NSArray<PPAlertActionItem *> *actions = self.actionItems;
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithCapacity:actions.count];
    NSMutableArray<NSNumber *> *styles = [NSMutableArray arrayWithCapacity:actions.count];
    for (PPAlertActionItem *item in actions) {
        [titles addObject:item.title];
        [styles addObject:@(item.style)];
    }

    [PPAlertSwiftUIPresenter showIn:vc
                              type:self.type
                             title:self.alertTitle
                          subtitle:self.alertSubtitle
                              icon:self.iconImage
                      actionTitles:titles
                      actionStyles:styles
                defaultActionIndex:self.defaultActionIndex
                       placeholder:self.textPlaceholder
                       initialText:self.initialText
                       secureEntry:self.secureEntry
                      keyboardType:self.keyboardType
                allowsCancellation:self.shouldDismissOnBackgroundTap
                         selection:^(NSInteger index, NSString * _Nullable text) {
        if (index < 0 || index >= (NSInteger)actions.count) return;
        PPAlertActionItem *item = actions[index];
        if (item.completion) {
            item.completion(PPAlertTrimmedText(text), item.style != PPAlertActionStyleCancel);
        } else if (item.simpleCompletion) {
            item.simpleCompletion();
        }
    }];
}

@end

#pragma mark - PPAlertHelper Facade

@implementation PPAlertHelper

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle {
    [self showSuccessIn:vc title:title subtitle:subtitle OKAction:nil];
}

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
             OKAction:(AlertCompletionBlock _Nullable)okAction {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showSuccessIn:vc title:title subtitle:subtitle OKAction:okAction];
        });
        return;
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeSuccess
                                             title:title
                                          subtitle:subtitle
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:okAction
                                      cancelAction:nil];
    [alert showInViewController:vc];
}

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
        confirmAction:(AlertCompletionBlock _Nullable)confirmAction
         cancelAction:(void (^)(void))cancelAction {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showSuccessIn:vc title:title subtitle:subtitle confirmAction:confirmAction cancelAction:cancelAction];
        });
        return;
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeSuccess
                                             title:title
                                          subtitle:subtitle
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:kLang(@"Cancel") ?: @"Cancel"
                                     confirmAction:confirmAction
                                      cancelAction:cancelAction];
    [alert showInViewController:vc];
}

+ (void)showFailIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showFailIn:vc title:title subtitle:subtitle completion:completion];
        });
        return;
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeError
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion();
    } cancelAction:completion];
    [alert showInViewController:vc];
}

+ (void)showErrorIn:(UIViewController *)vc
              title:(NSString *)title
           subtitle:(NSString * _Nullable)subtitle {
    [self showErrorIn:vc title:title subtitle:subtitle completion:nil];
}

+ (void)showErrorIn:(UIViewController * _Nullable)vc
              title:(NSString *)title
           subtitle:(NSString * _Nullable)subtitle
         completion:(void (^ _Nullable)(void))completion {
    [self showFailIn:vc title:title subtitle:subtitle completion:completion];
}

+ (void)showWarningIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString * _Nullable)subtitle {
    [self showWarningIn:vc title:title subtitle:subtitle completion:nil];
}

+ (void)showWarningIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString * _Nullable)subtitle
           completion:(void (^ _Nullable)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showWarningIn:vc title:title subtitle:subtitle completion:completion];
        });
        return;
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeWarning
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion();
    } cancelAction:completion];
    [alert showInViewController:vc];
}

+ (void)showInfoIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle {
    [self showInfoIn:vc title:title subtitle:subtitle completion:nil];
}

+ (void)showInfoIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showInfoIn:vc title:title subtitle:subtitle completion:completion];
        });
        return;
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeInfo
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                      confirmTitle:kLang(@"OK") ?: @"OK"
                                       cancelTitle:nil
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion();
    } cancelAction:completion];
    [alert showInViewController:vc];
}

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString *)cancelTitle
                      icon:(UIImage * _Nullable)icon
               confirmBlock:(AlertCompletionBlock _Nullable)confirmBlock
                cancelBlock:(void(^ _Nullable)(void))cancelBlock {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showConfirmationIn:vc title:title subtitle:subtitle confirmButton:confirmTitle cancelButton:cancelTitle icon:icon confirmBlock:confirmBlock cancelBlock:cancelBlock];
        });
        return;
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle
                                              icon:icon
                                      confirmTitle:confirmTitle
                                       cancelTitle:cancelTitle
                                     confirmAction:confirmBlock
                                      cancelAction:cancelBlock];
    [alert showInViewController:vc];
}

+ (void)showDestructiveConfirmationIn:(UIViewController *)vc
                                title:(NSString *)title
                             subtitle:(NSString *)subtitle
                        confirmButton:(NSString *)confirmTitle
                         cancelButton:(NSString *)cancelTitle
                                 icon:(UIImage * _Nullable)icon
                         confirmBlock:(AlertCompletionBlock _Nullable)confirmBlock
                          cancelBlock:(void(^ _Nullable)(void))cancelBlock {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showDestructiveConfirmationIn:vc title:title subtitle:subtitle confirmButton:confirmTitle cancelButton:cancelTitle icon:icon confirmBlock:confirmBlock cancelBlock:cancelBlock];
        });
        return;
    }

    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];
    NSString *safeCancelTitle = cancelTitle.length ? cancelTitle : ([Language get:@"Cancel" alter:@"إلغاء"] ?: @"إلغاء");
    NSString *safeConfirmTitle = confirmTitle.length ? confirmTitle : ([Language get:@"Delete" alter:@"حذف"] ?: @"حذف");

    [actions addObject:[PPAlertActionItem itemWithTitle:safeCancelTitle
                                                  style:PPAlertActionStyleCancel
                                             completion:nil
                                       simpleCompletion:cancelBlock]];
    [actions addObject:[PPAlertActionItem itemWithTitle:safeConfirmTitle
                                                  style:PPAlertActionStyleDestructive
                                             completion:confirmBlock
                                       simpleCompletion:nil]];

    UIImage *alertIcon = icon ?: [UIImage systemImageNamed:@"trash.fill"];
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeError
                                             title:title
                                          subtitle:subtitle
                                              icon:alertIcon
                                           actions:actions
                                       placeholder:nil
                                       initialText:nil
                                       secureEntry:NO
                                      keyboardType:UIKeyboardTypeDefault
                      shouldDismissOnBackgroundTap:YES];
    alert.defaultActionIndex = (NSInteger)actions.count - 1;
    [alert showInViewController:vc];
}

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
               placeholder:(NSString * _Nullable)placeholder
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString * _Nullable)cancelTitle
              confirmBlock:(void(^_Nullable)(void))confirmBlock
               cancelBlock:(void(^_Nullable)(void))cancelBlock {
    [self showConfirmationIn:vc
                       title:title
                    subtitle:subtitle
                 placeholder:placeholder
               confirmButton:confirmTitle
                cancelButton:cancelTitle
                        icon:nil
                confirmBlock:confirmBlock
                 cancelBlock:cancelBlock];
}

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
               placeholder:(NSString * _Nullable)placeholder
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString * _Nullable)cancelTitle
                      icon:(UIImage * _Nullable)icon
              confirmBlock:(void(^_Nullable)(void))confirmBlock
               cancelBlock:(void(^_Nullable)(void))cancelBlock {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showConfirmationIn:vc title:title subtitle:subtitle placeholder:placeholder confirmButton:confirmTitle cancelButton:cancelTitle icon:icon confirmBlock:confirmBlock cancelBlock:cancelBlock];
        });
        return;
    }

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle
                                              icon:icon
                                      confirmTitle:confirmTitle
                                       cancelTitle:cancelTitle
                                     confirmAction:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
        if (confirmBlock) confirmBlock();
    } cancelAction:cancelBlock];
    [alert showInViewController:vc];
}

+ (void)showThreeActionConfirmationIn:(UIViewController *)vc
                                title:(NSString *)title
                             subtitle:(NSString * _Nullable)subtitle
                        primaryButton:(NSString *)primaryTitle
                         primaryStyle:(UIAlertActionStyle)primaryStyle
                      secondaryButton:(NSString *)secondaryTitle
                       secondaryStyle:(UIAlertActionStyle)secondaryStyle
                       tertiaryButton:(NSString *)tertiaryTitle
                        tertiaryStyle:(UIAlertActionStyle)tertiaryStyle
                         primaryBlock:(PPAlertSimpleActionBlock _Nullable)primaryBlock
                       secondaryBlock:(PPAlertSimpleActionBlock _Nullable)secondaryBlock
                        tertiaryBlock:(PPAlertSimpleActionBlock _Nullable)tertiaryBlock {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showThreeActionConfirmationIn:vc title:title subtitle:subtitle primaryButton:primaryTitle primaryStyle:primaryStyle secondaryButton:secondaryTitle secondaryStyle:secondaryStyle tertiaryButton:tertiaryTitle tertiaryStyle:tertiaryStyle primaryBlock:primaryBlock secondaryBlock:secondaryBlock tertiaryBlock:tertiaryBlock];
        });
        return;
    }

    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];

    PPAlertActionStyle pStyle = primaryStyle == UIAlertActionStyleCancel ? PPAlertActionStyleCancel :
        (primaryStyle == UIAlertActionStyleDestructive ? PPAlertActionStyleDestructive : PPAlertActionStylePrimary);
    PPAlertActionStyle sStyle = secondaryStyle == UIAlertActionStyleCancel ? PPAlertActionStyleCancel :
        (secondaryStyle == UIAlertActionStyleDestructive ? PPAlertActionStyleDestructive : PPAlertActionStyleSecondary);
    PPAlertActionStyle tStyle = tertiaryStyle == UIAlertActionStyleCancel ? PPAlertActionStyleCancel :
        (tertiaryStyle == UIAlertActionStyleDestructive ? PPAlertActionStyleDestructive : PPAlertActionStyleSecondary);

    if (primaryTitle.length) {
        [actions addObject:[PPAlertActionItem itemWithTitle:primaryTitle style:pStyle completion:nil simpleCompletion:primaryBlock]];
    }
    if (secondaryTitle.length) {
        [actions addObject:[PPAlertActionItem itemWithTitle:secondaryTitle style:sStyle completion:nil simpleCompletion:secondaryBlock]];
    }
    if (tertiaryTitle.length) {
        [actions addObject:[PPAlertActionItem itemWithTitle:tertiaryTitle style:tStyle completion:nil simpleCompletion:tertiaryBlock]];
    }

    if (actions.count == 0) {
        [actions addObject:[PPAlertActionItem itemWithTitle:kLang(@"OK")
                                                      style:PPAlertActionStylePrimary
                                                 completion:nil
                                           simpleCompletion:nil]];
    }
    BOOL hasCancelAction = NO;
    for (PPAlertActionItem *item in actions) {
        if (item.style == PPAlertActionStyleCancel) { hasCancelAction = YES; break; }
    }
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeConfirmation
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                           actions:actions
                                       placeholder:nil
                                       initialText:nil
                                       secureEntry:NO
                                      keyboardType:UIKeyboardTypeDefault
                      shouldDismissOnBackgroundTap:hasCancelAction];
    alert.defaultActionIndex = primaryTitle.length > 0 && primaryStyle != UIAlertActionStyleCancel ? 0 : NSNotFound;
    [alert showInViewController:vc];
}

+ (void)showTextFieldAlertIn:(UIViewController *)vc
                   title:(NSString *)title
                subtitle:(NSString * _Nullable)subtitle
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
             confirmText:(NSString * _Nullable)confirmText
              cancelText:(NSString * _Nullable)cancelText
             completion:(AlertCompletionBlock)completion {
    [self showTextPromptIn:vc
                     title:title
                  subtitle:subtitle
               placeholder:placeholder
               initialText:initialText
               confirmText:confirmText
                cancelText:cancelText
               secureEntry:NO
              keyboardType:UIKeyboardTypeDefault
                completion:^(NSString * _Nullable text) {
        if (completion) completion(text, (text != nil));
    }];
}

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
                subtitle:(NSString * _Nullable)subtitle
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
             confirmText:(NSString * _Nullable)confirmText
              cancelText:(NSString * _Nullable)cancelText
              completion:(void(^)(NSString * _Nullable text))completion {
    [self showTextPromptIn:vc
                     title:title
                  subtitle:subtitle
               placeholder:placeholder
               initialText:initialText
               confirmText:confirmText
                cancelText:cancelText
               secureEntry:NO
              keyboardType:UIKeyboardTypeDefault
                completion:completion];
}

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
                subtitle:(NSString * _Nullable)subtitle
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
             confirmText:(NSString * _Nullable)confirmText
              cancelText:(NSString * _Nullable)cancelText
             secureEntry:(BOOL)secureEntry
            keyboardType:(UIKeyboardType)keyboardType
              completion:(void(^)(NSString * _Nullable text))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showTextPromptIn:vc title:title subtitle:subtitle placeholder:placeholder initialText:initialText confirmText:confirmText cancelText:cancelText secureEntry:secureEntry keyboardType:keyboardType completion:completion];
        });
        return;
    }

    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];

    if (cancelText.length > 0) {
        [actions addObject:[PPAlertActionItem itemWithTitle:cancelText
                                                      style:PPAlertActionStyleCancel
                                                 completion:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
            if (completion) completion(nil);
        } simpleCompletion:nil]];
    }

    NSString *safeConfirmText = confirmText.length ? confirmText : (kLang(@"OK") ?: @"OK");
    [actions addObject:[PPAlertActionItem itemWithTitle:safeConfirmText
                                                  style:PPAlertActionStylePrimary
                                             completion:^(NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion(text);
    } simpleCompletion:nil]];

    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeTextInput
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:nil
                                           actions:actions
                                       placeholder:placeholder
                                       initialText:initialText
                                       secureEntry:secureEntry
                                      keyboardType:keyboardType
                      shouldDismissOnBackgroundTap:(cancelText.length > 0)];
    [alert showInViewController:vc];
}

#pragma mark - Declared Compatibility Conveniences

+ (void)showDestructiveTextFieldAlertIn:(UIViewController *)vc
                                  title:(NSString *)title
                               subtitle:(NSString * _Nullable)subtitle
                            placeholder:(NSString * _Nullable)placeholder
                            initialText:(NSString * _Nullable)initialText
                            confirmText:(NSString * _Nullable)confirmText
                             cancelText:(NSString * _Nullable)cancelText
                                   icon:(UIImage * _Nullable)icon
                             completion:(AlertCompletionBlock)completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showDestructiveTextFieldAlertIn:vc title:title subtitle:subtitle placeholder:placeholder initialText:initialText confirmText:confirmText cancelText:cancelText icon:icon completion:completion];
        });
        return;
    }

    NSMutableArray<PPAlertActionItem *> *actions = [NSMutableArray array];
    if (cancelText.length > 0) {
        [actions addObject:[PPAlertActionItem itemWithTitle:cancelText
                                                      style:PPAlertActionStyleCancel
                                                 completion:^(__unused NSString * _Nullable text, __unused BOOL didConfirm) {
            if (completion) completion(nil, NO);
        } simpleCompletion:nil]];
    }
    NSString *safeConfirmText = confirmText.length ? confirmText : kLang(@"Delete");
    [actions addObject:[PPAlertActionItem itemWithTitle:safeConfirmText
                                                  style:PPAlertActionStyleDestructive
                                             completion:^(NSString * _Nullable text, __unused BOOL didConfirm) {
        if (completion) completion(text, YES);
    } simpleCompletion:nil]];
    PPAlert *alert = [[PPAlert alloc] initWithType:PPAlertTypeTextInput
                                             title:title
                                          subtitle:subtitle ?: @""
                                              icon:icon ?: [UIImage systemImageNamed:@"trash.fill"]
                                           actions:actions
                                       placeholder:placeholder
                                       initialText:initialText
                                       secureEntry:NO
                                      keyboardType:UIKeyboardTypeDefault
                      shouldDismissOnBackgroundTap:(cancelText.length > 0)];
    alert.defaultActionIndex = (NSInteger)actions.count - 1;
    [alert showInViewController:vc];
}

+ (void)showAlertIn:(UIViewController *)vc
              title:(NSString *)title
           subtitle:(NSString * _Nullable)subtitle {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlertIn:vc title:title subtitle:subtitle];
        });
        return;
    }
    NSString *normalizedTitle = PPAlertTrimmedText(title);
    NSArray<NSString *> *typeKeys = @[@"Success", @"Warning", @"Info", @"Error"];
    for (NSString *key in typeKeys) {
        NSString *localizedTitle = kLang(key);
        BOOL matchesKey = [normalizedTitle caseInsensitiveCompare:key] == NSOrderedSame;
        BOOL matchesLocalizedTitle = localizedTitle.length > 0 &&
            [normalizedTitle caseInsensitiveCompare:localizedTitle] == NSOrderedSame;
        if (!matchesKey && !matchesLocalizedTitle) continue;
        if ([key isEqualToString:@"Success"]) {
            [self showSuccessIn:vc title:title subtitle:subtitle];
        } else if ([key isEqualToString:@"Warning"]) {
            [self showWarningIn:vc title:title subtitle:subtitle];
        } else if ([key isEqualToString:@"Info"]) {
            [self showInfoIn:vc title:title subtitle:subtitle];
        } else {
            [self showErrorIn:vc title:title subtitle:subtitle];
        }
        return;
    }
    [self showErrorIn:vc title:title subtitle:subtitle];
}

@end
