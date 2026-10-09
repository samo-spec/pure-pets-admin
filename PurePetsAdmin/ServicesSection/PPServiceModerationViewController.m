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
@property (nonatomic, strong, nullable) PPServiceModel *pendingCandidate;
@property (nonatomic, copy, nullable) NSString *pendingCommandID;
@property (nonatomic, strong, nullable) NSNumber *pendingRevision;
@property (nonatomic, copy, nullable) NSString *pendingActorUID;
@property (nonatomic, assign) BOOL pendingAccepted;
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
    if (self.phase == PPServiceModerationPhaseAwaitingConfirmation && self.pendingCandidate) {
        [self confirmPendingCandidate];
        return;
    }
    self.pendingCandidate = nil;
    self.pendingCommandID = nil;
    self.pendingRevision = nil;
    self.pendingActorUID = nil;
    self.pendingAccepted = NO;
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

- (void)confirmPendingCandidate {
    if ([self isBusy] || !self.pendingCandidate) return;
    if (![self.pendingActorUID isEqualToString:FIRAuth.auth.currentUser.uid] || ![self canManage]) {
        self.phase = PPServiceModerationPhaseUnavailable;
        self.errorMessage = kLang(@"Service_Error_NoPermission");
        [self renderReplacingDraft:NO];
        return;
    }
    NSUInteger requestGeneration = ++self.generation;
    self.phase = PPServiceModerationPhaseConfirming;
    self.errorMessage = nil;
    [self renderReplacingDraft:NO];
    __weak typeof(self) weakSelf = self;
    [PPServiceManager.sharedManager fetchServiceByID:self.pendingCandidate.serviceID completion:^(PPServiceModel *observed, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || requestGeneration != self.generation) return;
            NSNumber *observedRevision = [observed.extraFields[@"adminRevision"] isKindOfClass:NSNumber.class]
                ? observed.extraFields[@"adminRevision"] : nil;
            if (![self.pendingActorUID isEqualToString:FIRAuth.auth.currentUser.uid] || ![self canManage]) {
                self.phase = PPServiceModerationPhaseUnavailable;
                self.errorMessage = kLang(@"Service_Error_NoPermission");
            } else if (observed && [observed.extraFields[@"adminLastCommandID"] isEqual:self.pendingCommandID] &&
                       [observed.extraFields[@"adminRevision"] isEqual:self.pendingRevision] &&
                       [PPServiceManager administrativeState:observed matchesService:self.pendingCandidate]) {
                self.service = observed;
                self.pendingCandidate = nil;
                self.phase = PPServiceModerationPhaseSaved;
                [self renderReplacingDraft:YES];
                [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
                return;
            } else if ((!error && !observed) ||
                       ([error.domain isEqualToString:PPServiceManagerErrorDomain] && error.code == 404) ||
                       (observedRevision && observedRevision.longLongValue >= self.pendingRevision.longLongValue)) {
                self.phase = PPServiceModerationPhaseConflict;
                self.errorMessage = kLang(self.pendingAccepted ? @"Service_Review_ChangedAfterDecision" : @"Service_Review_Conflict");
            } else {
                self.phase = PPServiceModerationPhaseAwaitingConfirmation;
                self.errorMessage = kLang(self.pendingAccepted ? @"Service_Review_AcceptedPending" : @"Service_Workspace_AwaitingConfirmation");
            }
            [self renderReplacingDraft:NO];
        });
    }];
}

- (void)saveCandidate:(PPServiceModel *)candidate expected:(PPServiceModel *)expected note:(NSString *)note {
    if (self.phase != PPServiceModerationPhaseReady && self.phase != PPServiceModerationPhaseFailed) return;
    if (![self canManage] || ![candidate.serviceID isEqualToString:self.service.serviceID]) {
        self.errorMessage = kLang(@"Service_Error_NoPermission");
        self.phase = PPServiceModerationPhaseUnavailable;
        [self renderReplacingDraft:NO];
        return;
    }
    self.phase = PPServiceModerationPhaseSaving;
    self.errorMessage = nil;
    NSUInteger requestGeneration = ++self.generation;
    NSString *actorUID = [FIRAuth.auth.currentUser.uid copy];
    [self renderReplacingDraft:NO];
    __weak typeof(self) weakSelf = self;
    [PPServiceManager.sharedManager saveAdministrativeStateForService:candidate expectedService:expected auditNote:note
        completion:^(PPServiceModel * _Nullable observed, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || requestGeneration != self.generation) return;
            if (![actorUID isEqualToString:FIRAuth.auth.currentUser.uid]) {
                self.phase = PPServiceModerationPhaseUnavailable;
                self.errorMessage = kLang(@"Service_Error_NoPermission");
                [self renderReplacingDraft:NO];
                return;
            }
            if (error) {
                if (error.code == PPServiceCommandAwaitingConfirmationCode) {
                    self.pendingCandidate = [candidate copy];
                    self.pendingCommandID = error.userInfo[PPServiceCommandIDKey];
                    self.pendingRevision = error.userInfo[PPServiceCommandRevisionKey];
                    self.pendingActorUID = actorUID;
                    self.pendingAccepted = [error.userInfo[PPServiceCommandAcceptedKey] boolValue];
                    self.phase = PPServiceModerationPhaseAwaitingConfirmation;
                } else {
                    self.phase = error.code == 409 ? PPServiceModerationPhaseConflict :
                        (error.code == 403 ? PPServiceModerationPhaseUnavailable : PPServiceModerationPhaseFailed);
                }
                self.errorMessage = error.localizedDescription;
                [self renderReplacingDraft:NO];
                return;
            }
            if (!observed || ![PPServiceManager administrativeState:observed matchesService:candidate]) {
                self.phase = PPServiceModerationPhaseConflict;
                self.errorMessage = kLang(@"Service_Review_ChangedAfterDecision");
                [self renderReplacingDraft:NO];
                return;
            }
            self.service = observed;
            self.phase = PPServiceModerationPhaseSaved;
            [self renderReplacingDraft:YES];
            [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
        });
    }];
}

#pragma mark - Close and draft protection

- (void)requestClose {
    if ([self isBusy] || self.presentedViewController) return;
    if (self.moderationHost.hasUnsavedChanges) {
        BOOL pending = self.pendingCandidate != nil;
        NSString *detail = pending ? (self.pendingAccepted ? @"Service_Review_LeavePendingDetail" : @"Service_Review_LeaveUnconfirmedDetail") : @"Service_Review_DiscardDetail";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:kLang(pending ? @"Service_Review_LeavePendingTitle" : @"Service_Review_DiscardTitle")
            message:kLang(detail) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:kLang(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:kLang(pending ? @"Service_Review_LeavePending" : @"Service_Review_Discard")
            style:pending ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive
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
