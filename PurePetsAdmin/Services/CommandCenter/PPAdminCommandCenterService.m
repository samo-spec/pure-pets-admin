#import "PPAdminCommandCenterService.h"

#import "Services/Session/PPAdminSessionBridge.h"
#import "Payments/PPPaymentManagementService.h"
#import "Fulfillment/PPFulfillmentService.h"
#import "Delivery/PPDeliveryService.h"
#import "Providers/PPProviderService.h"

@import FirebaseFirestore;

@implementation PPAdminCommandSnapshot
@end

@implementation PPAdminCommandCenterService

+ (instancetype)shared {
    static PPAdminCommandCenterService *service;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [PPAdminCommandCenterService new];
    });
    return service;
}

- (void)loadSnapshotForSession:(PPAdminSessionSnapshot *)session
                    completion:(PPAdminCommandSnapshotCompletion)completion {
    PPAdminCommandSnapshot *snapshot = [PPAdminCommandSnapshot new];
    snapshot.generatedAt = [NSDate date];
    snapshot.activeOrdersCount = NSNotFound;
    snapshot.awaitingFulfillmentCount = NSNotFound;
    snapshot.activeDeliveryCount = NSNotFound;
    snapshot.pendingProviderApplicationCount = NSNotFound;
    snapshot.adsCount = NSNotFound;
    snapshot.usersCount = NSNotFound;
    snapshot.accessoriesCount = NSNotFound;

    NSMutableOrderedSet<NSString *> *failedAreas = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *partialAreas = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *requestedAreas = [NSMutableOrderedSet orderedSet];
    dispatch_group_t group = dispatch_group_create();
    FIRFirestore *db = [FIRFirestore firestore];

    BOOL canViewPayments = [session hasAnyPermission:@[@"payments.view", @"payments.manage"]];
    BOOL canViewFulfillment = [session hasAnyPermission:@[@"payments.view", @"payments.manage", @"providers.view"]];
    BOOL canViewDelivery = [session hasPermission:@"payments.manage"];
    BOOL canViewProviders = [session hasAnyPermission:@[@"providers.view", @"providers.manage"]];
    BOOL canViewListings = [session hasAnyPermission:@[@"listings.view", @"listings.manage", @"listings.moderate"]] &&
                           [session hasPermission:@"stock.manage"];
    BOOL canViewUsers = [session hasAnyPermission:@[@"users.view", @"users.manage"]];
    BOOL canViewStock = [session hasAnyPermission:@[@"stock.view", @"stock.manage"]];

    if (canViewPayments) {
        [requestedAreas addObject:@"payments"];
        dispatch_group_enter(group);
        [[PPPaymentManagementService shared] fetchOrdersWithFilters:[PPPaymentManagementFilters defaultFilters]
                                                            pageSize:100
                                                          startAfter:nil
                                                          completion:^(NSArray<PPPaymentAdminRecord *> *records,
                                                                       FIRDocumentSnapshot * _Nullable nextCursor,
                                                                       NSError * _Nullable error) {
            (void)nextCursor;
            BOOL isPartialRead = [PPPaymentManagementService isPartialReadError:error];
            if (error && !isPartialRead) {
                @synchronized (failedAreas) { [failedAreas addObject:@"payments"]; }
            } else {
                if (isPartialRead) {
                    @synchronized (partialAreas) { [partialAreas addObject:@"payments"]; }
                }
                NSInteger active = 0;
                for (PPPaymentAdminRecord *record in records ?: @[]) {
                    NSString *status = [record workflowStatusKey];
                    BOOL isResolvedRefund = [status isEqualToString:@"refunded"] || [status isEqualToString:@"partially_refunded"];
                    BOOL isTerminal = [PPPaymentAdminRecord isDeliveredLikeStatus:status] ||
                                      [PPPaymentAdminRecord isCancelledLikeStatus:status] ||
                                      [PPPaymentAdminRecord isFailureLikeStatus:status] ||
                                      isResolvedRefund;
                    if (!isTerminal) {
                        active += 1;
                    }
                }
                snapshot.activeOrdersCount = active;
            }
            dispatch_group_leave(group);
        }];
    }

    if (canViewFulfillment) {
        [requestedAreas addObject:@"fulfillment"];
        dispatch_group_enter(group);
        [[PPFulfillmentService shared] fetchFulfillmentsWithCompletion:^(NSArray<PPFulfillmentRecord *> *records,
                                                                         NSError * _Nullable error) {
            BOOL isPartialRead = [PPFulfillmentService isPartialReadError:error];
            if (error && !isPartialRead) {
                @synchronized (failedAreas) { [failedAreas addObject:@"fulfillment"]; }
            } else {
                if (isPartialRead) {
                    @synchronized (partialAreas) { [partialAreas addObject:@"fulfillment"]; }
                }
                NSSet<NSString *> *awaiting = [NSSet setWithArray:@[
                    @"new_request", @"accepted", @"preparing", @"ready_for_pickup", @"delivery_assigned"
                ]];
                NSInteger count = 0;
                for (PPFulfillmentRecord *record in records ?: @[]) {
                    NSString *status = record.status.lowercaseString ?: @"";
                    if ([awaiting containsObject:status]) count += 1;
                }
                snapshot.awaitingFulfillmentCount = count;
            }
            dispatch_group_leave(group);
        }];
    }

    if (canViewDelivery) {
        [requestedAreas addObject:@"delivery"];
        dispatch_group_enter(group);
        [[PPDeliveryService shared] fetchAllDeliveryRequestsWithCompletion:^(NSArray<PPDeliveryRequestRecord *> *records,
                                                                              NSError *error) {
            if (error) {
                @synchronized (failedAreas) { [failedAreas addObject:@"delivery"]; }
            } else {
                NSSet<NSString *> *activeStatuses = [NSSet setWithArray:@[
                    @"offered", @"accepted_by_company", @"assigned_to_driver", @"picked_up", @"in_transit", @"delivered"
                ]];
                NSInteger count = 0;
                for (PPDeliveryRequestRecord *record in records ?: @[]) {
                    if ([activeStatuses containsObject:record.status.lowercaseString ?: @""]) count += 1;
                }
                snapshot.activeDeliveryCount = count;
            }
            dispatch_group_leave(group);
        }];
    }

    if (canViewProviders) {
        [requestedAreas addObject:@"providers"];
        dispatch_group_enter(group);
        [[PPProviderService shared] fetchApplicationsWithCompletion:^(NSArray<PPProviderApplication *> *apps,
                                                                       NSError *error) {
            if (error) {
                @synchronized (failedAreas) { [failedAreas addObject:@"providers"]; }
            } else {
                NSInteger count = 0;
                for (PPProviderApplication *application in apps ?: @[]) {
                    NSString *status = application.status.lowercaseString ?: @"";
                    if (status.length == 0 || [status isEqualToString:@"pending"] || [status isEqualToString:@"under_review"]) {
                        count += 1;
                    }
                }
                snapshot.pendingProviderApplicationCount = count;
            }
            dispatch_group_leave(group);
        }];
    }

    [self pp_fetchCountForCollection:@"pet_ads"
                             allowed:canViewListings
                                  key:@"listings"
                                   db:db
                                group:group
                           failedAreas:failedAreas
                           assignment:^(NSInteger count) { snapshot.adsCount = count; }];
    if (canViewListings) [requestedAreas addObject:@"listings"];
    [self pp_fetchCountForCollection:@"UsersCol"
                             allowed:canViewUsers
                                  key:@"users"
                                   db:db
                                group:group
                           failedAreas:failedAreas
                           assignment:^(NSInteger count) { snapshot.usersCount = count; }];
    if (canViewUsers) [requestedAreas addObject:@"users"];
    [self pp_fetchCountForCollection:@"petAccessories"
                             allowed:canViewStock
                                  key:@"stock"
                                   db:db
                                group:group
                           failedAreas:failedAreas
                           assignment:^(NSInteger count) { snapshot.accessoriesCount = count; }];
    if (canViewStock) [requestedAreas addObject:@"stock"];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        snapshot.requestedAreas = requestedAreas.array ?: @[];
        snapshot.failedAreas = failedAreas.array ?: @[];
        snapshot.partialAreas = partialAreas.array ?: @[];
        snapshot.generatedAt = [NSDate date];
        if (completion) completion(snapshot);
    });
}

- (void)pp_fetchCountForCollection:(NSString *)collection
                           allowed:(BOOL)allowed
                                key:(NSString *)key
                                 db:(FIRFirestore *)db
                              group:(dispatch_group_t)group
                        failedAreas:(NSMutableOrderedSet<NSString *> *)failedAreas
                         assignment:(void (^)(NSInteger count))assignment {
    if (!allowed) return;
    dispatch_group_enter(group);
    [[db collectionWithPath:collection] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable result,
                                                                      NSError * _Nullable error) {
        if (error) {
            @synchronized (failedAreas) { [failedAreas addObject:key]; }
        } else if (assignment) {
            assignment(result.documents.count);
        }
        dispatch_group_leave(group);
    }];
}

@end
