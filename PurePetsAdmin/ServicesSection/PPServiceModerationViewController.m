#import "PPServiceModerationViewController.h"
#import "PPServiceModel.h"
#import "PPServiceManager.h"
#import "PPStaffAuth.h"
#import "PurePetsAdmin-Swift.h"
@import FirebaseAuth;

@interface PPServiceModerationViewController () <UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) PPServiceModel *service;
@property (nonatomic, strong) PPServiceModerationHostingController *moderationHost;
@property (nonatomic, assign) PPServiceModerationPhase phase;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, strong, nullable) NSNumber *previousNavigationBarHidden;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong, nullable) NSNumber *previousInteractivePopEnabled;
@end

@implementation PPServiceModerationViewController

#pragma mark - Lifecycle

- (instancetype)initWithService:(PPServiceModel *)service {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _service = [service copy];
        _phase = PPServiceModerationPhaseLoading;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];
    __weak typeof(self) weakSelf = self;
    self.moderationHost = [[PPServiceModerationHostingController alloc]
        initWithService:self.service closeHandler:^{ [weakSelf requestClose]; }
        reloadHandler:^{ [weakSelf reloadService]; }
        saveHandler:^(PPServiceModel *candidate, PPServiceModel *expected, NSString *note) {
            [weakSelf saveCandidate:candidate expected:expected note:note];
        }];
    [self addChildViewController:self.moderationHost];
    UIView *content = self.moderationHost.view;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    [self.moderationHost didMoveToParentViewController:self];
    [self reloadService];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.previousNavigationBarHidden && self.navigationController) {
        self.previousNavigationBarHidden = @(self.navigationController.navigationBarHidden);
    }
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    if (!self.previousInteractivePopEnabled && self.navigationController.interactivePopGestureRecognizer) {
        self.previousInteractivePopEnabled = @(self.navigationController.interactivePopGestureRecognizer.enabled);
    }
    self.navigationController.interactivePopGestureRecognizer.enabled = NO;
    self.navigationController.presentationController.delegate = self;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.previousNavigationBarHidden) {
        [self.navigationController setNavigationBarHidden:self.previousNavigationBarHidden.boolValue animated:animated];
    }
    if (self.previousInteractivePopEnabled) {
        self.navigationController.interactivePopGestureRecognizer.enabled = self.previousInteractivePopEnabled.boolValue;
    }
}

#pragma mark - Authorization and observation

- (BOOL)canManage { return [PPServiceManager.sharedManager currentAdminCanManageServices]; }

- (BOOL)isBusy { return self.phase == PPServiceModerationPhaseSaving || self.phase == PPServiceModerationPhaseConfirming; }

- (void)renderReplacingDraft:(BOOL)replace {
    self.navigationController.modalInPresentation = [self isBusy] || self.moderationHost.hasUnsavedChanges;
    [self.moderationHost updateWithService:self.service phase:self.phase canManage:[self canManage]
                             errorMessage:self.errorMessage replaceDraft:replace];
}

- (void)reloadService {
    if ([self isBusy]) return;
    NSUInteger requestGeneration = ++self.generation;
    self.phase = PPServiceModerationPhaseLoading;
    self.errorMessage = nil;
    [self renderReplacingDraft:NO];
    __weak typeof(self) weakSelf = self;
    [PPStaffAuth.shared refreshCurrentStaff:^(PPStaffDoc * _Nullable staff, NSError * _Nullable authError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || requestGeneration != self.generation) return;
            if (authError || ![self canManage]) {
                self.phase = PPServiceModerationPhaseUnavailable;
                self.errorMessage = kLang(@"Service_Error_NoPermission");
                [self renderReplacingDraft:NO];
                return;
            }
            [PPServiceManager.sharedManager fetchServiceByID:self.service.serviceID completion:^(PPServiceModel * _Nullable service, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) self = weakSelf;
                    if (!self || requestGeneration != self.generation) return;
                    if (error || !service) {
                        self.phase = PPServiceModerationPhaseUnavailable;
                        self.errorMessage = error.localizedDescription ?: kLang(@"Service_Error_NotFound");
                        [self renderReplacingDraft:NO];
                    } else {
                        self.service = [service copy];
                        self.phase = PPServiceModerationPhaseReady;
                        [self renderReplacingDraft:YES];
                    }
                });
            }];
        });
    }];
}

#pragma mark - Decision

- (void)saveCandidate:(PPServiceModel *)candidate expected:(PPServiceModel *)expected note:(NSString *)note {
    if ([self isBusy] || self.phase == PPServiceModerationPhaseLoading || self.phase == PPServiceModerationPhaseSaved) return;
    if (![self canManage] || ![candidate.serviceID isEqualToString:self.service.serviceID]) {
        self.errorMessage = kLang(@"Service_Error_NoPermission");
        self.phase = PPServiceModerationPhaseUnavailable;
        [self renderReplacingDraft:NO];
        return;
    }
    self.phase = PPServiceModerationPhaseSaving;
    self.errorMessage = nil;
    [self renderReplacingDraft:NO];
    __weak typeof(self) weakSelf = self;
    [PPServiceManager.sharedManager updateAdministrativeStateForService:candidate expectedService:expected auditNote:note
        completion:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            if (error) {
                self.phase = error.code == 409 ? PPServiceModerationPhaseConflict : PPServiceModerationPhaseFailed;
                self.errorMessage = error.localizedDescription;
                [self renderReplacingDraft:NO];
                return;
            }
            self.phase = PPServiceModerationPhaseConfirming;
            [self renderReplacingDraft:NO];
            [PPServiceManager.sharedManager fetchServiceByID:candidate.serviceID completion:^(PPServiceModel * _Nullable observed, NSError * _Nullable readError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) self = weakSelf;
                    if (!self) return;
                    if (readError || !observed || ![PPServiceManager administrativeState:observed matchesService:candidate]) {
                        self.phase = PPServiceModerationPhaseConflict;
                        self.errorMessage = kLang(@"Service_Workspace_AwaitingConfirmation");
                        [self renderReplacingDraft:NO];
                        return;
                    }
                    self.service = observed;
                    self.phase = PPServiceModerationPhaseSaved;
                    [self renderReplacingDraft:YES];
                    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
                });
            }];
        });
    }];
}

#pragma mark - Close and draft protection

- (void)requestClose {
    if ([self isBusy] || self.presentedViewController) return;
    if (self.moderationHost.hasUnsavedChanges) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(@"Service_Review_DiscardTitle")
            message:kLang(@"Service_Review_DiscardDetail") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Service_Review_Discard") style:UIAlertActionStyleDestructive
            handler:^(UIAlertAction *action) { [weakSelf close]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else { [self close]; }
}

- (void)close {
    self.generation += 1;
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.navigationController.presentingViewController) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    } else { [self dismissViewControllerAnimated:YES completion:nil]; }
}

- (BOOL)presentationControllerShouldDismiss:(UIPresentationController *)presentationController {
    return ![self isBusy] && !self.moderationHost.hasUnsavedChanges;
}

- (void)presentationControllerDidAttemptToDismiss:(UIPresentationController *)presentationController { [self requestClose]; }

@end
