//
//  PPServiceDetailViewController.m
//  PurePetsAdmin
//
//  UIKit owns navigation, authorization and service operations. SwiftUI renders
//  the service record without introducing another data or mutation owner.
//

#import "PPServiceDetailViewController.h"
#import "PPServiceModel.h"
#import "PPServiceManager.h"
#import "PPAddEditServiceViewController.h"
#import "PPServiceModerationViewController.h"
#import "PPStaffAuth.h"
#import "PurePetsAdmin-Swift.h"
@import FirebaseAuth;

@interface PPServiceDetailViewController ()
@property (nonatomic, strong) PPServiceModel *service;
@property (nonatomic, strong) PPServiceDetailHostingController *detailHost;
@property (nonatomic, strong, nullable) NSNumber *previousNavigationBarHidden;
@property (nonatomic, strong, nullable) NSNumber *pendingArchiveState;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, assign) BOOL refreshing;
@property (nonatomic, assign) BOOL mutating;
@property (nonatomic, assign) BOOL hasConfirmedService;
@property (nonatomic, assign) NSUInteger refreshGeneration;
@end

@implementation PPServiceDetailViewController

#pragma mark - Lifecycle

- (instancetype)initWithService:(PPServiceModel *)service {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _service = service;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor ppBackground];
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    __weak typeof(self) weakSelf = self;
    self.detailHost = [[PPServiceDetailHostingController alloc]
        initWithService:self.service actionHandler:^(PPServiceDetailAction action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            switch (action) {
                case PPServiceDetailActionClose: [self closeTapped]; break;
                case PPServiceDetailActionRefresh: [self reloadService]; break;
                case PPServiceDetailActionEdit: [self editTapped]; break;
                case PPServiceDetailActionModerate: [self moderationTapped]; break;
                case PPServiceDetailActionArchive: [self archiveTapped]; break;
                case PPServiceDetailActionDelete: [self deleteTapped]; break;
            }
        }];
    [self addChildViewController:self.detailHost];
    UIView *content = self.detailHost.view;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [self.detailHost didMoveToParentViewController:self];
    [self render];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.previousNavigationBarHidden && self.navigationController) {
        self.previousNavigationBarHidden = @(self.navigationController.navigationBarHidden);
    }
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self reloadService];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.previousNavigationBarHidden) {
        [self.navigationController setNavigationBarHidden:self.previousNavigationBarHidden.boolValue animated:animated];
        self.previousNavigationBarHidden = nil;
    }
}

#pragma mark - Permission and Presentation

- (BOOL)canReadService { return [PPServiceManager.sharedManager currentAdminCanReadServices]; }

- (BOOL)canManageService {
    PPStaffDoc *staff = PPStaffAuth.shared.cachedCurrentStaff;
    NSString *uid = FIRAuth.auth.currentUser.uid;
    return uid.length > 0 && [staff.uid isEqualToString:uid] && staff.isActive &&
        (staff.isAdmin || [staff hasPermission:kStaffPermServicesManage]) &&
        [PPServiceManager.sharedManager currentAdminCanManageServices];
}

- (void)render {
    [self.detailHost updateWithService:self.service
                           refreshing:self.refreshing
                             mutating:self.mutating
                            canManage:([self canManageService] && self.hasConfirmedService)
                         errorMessage:self.errorMessage];
}

- (BOOL)canPerformAction {
    if (self.refreshing || self.mutating) return NO;
    if (![self canManageService]) {
        self.errorMessage = kLang(@"Service_Error_NoPermission");
        [self render];
        return NO;
    }
    if (!self.hasConfirmedService || self.service.serviceID.length == 0) {
        [self reloadService];
        return NO;
    }
    return YES;
}

#pragma mark - Refresh

- (void)reloadService {
    if (self.refreshing || self.mutating) return;
    if (self.service.serviceID.length == 0) {
        self.hasConfirmedService = NO;
        self.errorMessage = kLang(@"Service_Error_MissingID");
        [self render];
        return;
    }

    self.refreshing = YES;
    self.hasConfirmedService = NO;
    self.errorMessage = nil;
    NSUInteger generation = ++self.refreshGeneration;
    NSString *serviceID = self.service.serviceID;
    __weak typeof(self) weakSelf = self;
    [self render];

    [PPStaffAuth.shared refreshCurrentStaff:^(PPStaffDoc * _Nullable staff, NSError * _Nullable authError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.refreshGeneration) return;
            if (authError || ![self canReadService]) {
                self.refreshing = NO;
                self.errorMessage = authError.localizedDescription ?: kLang(@"Service_Error_NoPermission");
                [self render];
                return;
            }
            [PPServiceManager.sharedManager fetchServiceByID:serviceID completion:^(PPServiceModel * _Nullable service, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) self = weakSelf;
                    if (!self || generation != self.refreshGeneration || ![self.service.serviceID isEqualToString:serviceID]) return;
                    self.refreshing = NO;
                    if (service && [service.serviceID isEqualToString:serviceID]) {
                        self.service = service;
                        self.hasConfirmedService = YES;
                        if (self.pendingArchiveState) {
                            BOOL expected = self.pendingArchiveState.boolValue;
                            self.pendingArchiveState = nil;
                            if (service.isDeleted == expected) {
                                [PPHUD showSuccess:kLang(@"Success_Title")
                                          subtitle:kLang(expected ? @"Service_Archived_Success" : @"Service_Restored_Success")];
                            } else {
                                self.errorMessage = kLang(@"Service_Detail_Changed");
                                self.hasConfirmedService = NO;
                            }
                        }
                    } else {
                        self.errorMessage = error.localizedDescription ?: kLang(@"Service_Error_NotFound");
                    }
                    [self render];
                });
            }];
        });
    }];
}

#pragma mark - Actions

- (void)closeTapped {
    UINavigationController *navigation = self.navigationController;
    if (navigation) {
        // A late delete completion must not pop or dismiss a different route.
        if (navigation.topViewController != self) return;
        if (navigation.viewControllers.count > 1) {
            [navigation popViewControllerAnimated:YES];
        } else if (navigation.presentingViewController) {
            [navigation dismissViewControllerAnimated:YES completion:nil];
        }
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)editTapped {
    if (![self canPerformAction]) return;
    [PPFunc pp_playTapEffect];
    PPAddEditServiceViewController *controller = [[PPAddEditServiceViewController alloc] initWithService:self.service];
    controller.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)moderationTapped {
    if (![self canPerformAction]) return;
    [PPFunc pp_playTapEffect];
    PPServiceModerationViewController *controller = [[PPServiceModerationViewController alloc] initWithService:self.service];
    controller.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)archiveTapped {
    if (![self canPerformAction] || self.presentedViewController) return;
    __weak typeof(self) weakSelf = self;
    BOOL shouldArchive = !self.service.isDeleted;
    NSString *serviceID = self.service.serviceID;
    [PPAlertHelper showConfirmationIn:self
                              title:kLang(shouldArchive ? @"Service_Confirm_Archive_Title" : @"Service_Confirm_Restore_Title")
                           subtitle:kLang(shouldArchive ? @"Service_Confirm_Archive_Subtitle" : @"Service_Confirm_Restore_Subtitle")
                        placeholder:nil
                      confirmButton:kLang(shouldArchive ? @"Service_Action_Archive" : @"Service_Action_Restore")
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self canPerformAction] || ![self.service.serviceID isEqualToString:serviceID]) return;
        self.mutating = YES;
        self.errorMessage = nil;
        [self render];
        PPServiceVoidBlock completion = ^(NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self.mutating = NO;
                self.hasConfirmedService = NO;
                if (error) {
                    self.errorMessage = error.localizedDescription;
                    [self render];
                } else {
                    self.pendingArchiveState = @(shouldArchive);
                    [self reloadService];
                }
            });
        };
        if (shouldArchive) {
            [PPServiceManager.sharedManager archiveServiceID:serviceID auditNote:nil completion:completion];
        } else {
            [PPServiceManager.sharedManager restoreServiceID:serviceID auditNote:nil completion:completion];
        }
    } cancelBlock:nil];
}

- (void)deleteTapped {
    if (![self canPerformAction] || self.presentedViewController) return;
    __weak typeof(self) weakSelf = self;
    NSString *serviceID = self.service.serviceID;
    [PPAlertHelper showConfirmationIn:self
                              title:kLang(@"Service_Confirm_Delete_Title")
                           subtitle:kLang(@"Service_Confirm_Delete_Subtitle")
                        placeholder:nil
                      confirmButton:kLang(@"Delete")
                       cancelButton:kLang(@"Cancel")
                       confirmBlock:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![self canPerformAction] || ![self.service.serviceID isEqualToString:serviceID]) return;
        self.mutating = YES;
        self.errorMessage = nil;
        [self render];
        [PPServiceManager.sharedManager deleteServicePermanently:serviceID auditNote:nil completion:^(NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self.mutating = NO;
                if (error) {
                    self.hasConfirmedService = NO;
                    self.errorMessage = error.localizedDescription;
                    [self render];
                } else {
                    [PPHUD showSuccess:kLang(@"Deleted") subtitle:kLang(@"Service_Deleted_Success")];
                    [self closeTapped];
                }
            });
        }];
    } cancelBlock:nil];
}

@end
