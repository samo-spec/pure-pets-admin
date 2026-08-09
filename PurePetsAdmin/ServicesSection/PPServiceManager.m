//
//  PPServiceManager.m
//  PurePetsAdmin
//

#import "PPServiceManager.h"
#import "PPServiceModel.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "UserManager.h"
#import "UserModel.h"
#import "PPRolePermission.h"
@import Firebase;
@import FirebaseAuth;
static NSString * const kPPServicesCollection = @"serviceOffers";
static NSString * const kPPAdminAuditCollection = @"AdminAuditLogs";
static NSString * const kPPServiceManagerErrorDomain = @"pp.service.manager";

typedef void (^PPServiceExistingDocumentBlock)(FIRDocumentReference * _Nullable docRef,
                                               NSDictionary * _Nullable data,
                                               NSError * _Nullable error);

@interface PPServiceManager ()
@property (nonatomic, strong) FIRFirestore *db;
@end

@implementation PPServiceManager

+ (instancetype)sharedManager {
    static PPServiceManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PPServiceManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _db = [FIRFirestore firestore];
    }
    return self;
}

#pragma mark - Public

- (BOOL)currentAdminCanManageServices {
    UserModel *currentUser = [UserManager shared].currentUser;
    if (!currentUser) {
        return NO;
    }
    return ([currentUser hasPermissionNamed:kPermManageServices] ||
            [currentUser hasPermissionNamed:kPermAdminAll]);
}

- (id<FIRListenerRegistration>)observeAllServices:(PPServiceArrayBlock)onChange {
    if (![self currentAdminCanManageServices]) {
        [self pp_completeArray:nil
                         error:[self pp_errorWithCode:403 message:kLang(@"Service_Error_NoPermission")]
                    completion:onChange];
        return nil;
    }

    return [[self pp_collection] addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!onChange) {
            return;
        }
        NSArray<PPServiceModel *> *mapped = error ? nil : [self pp_mapDocuments:snap.documents];
        [self pp_completeArray:mapped error:error completion:onChange];
    }];
}

- (void)fetchAllServicesWithCompletion:(PPServiceArrayBlock)completion {
    if (![self currentAdminCanManageServices]) {
        [self pp_completeArray:nil
                         error:[self pp_errorWithCode:403 message:kLang(@"Service_Error_NoPermission")]
                    completion:completion];
        return;
    }

    [[self pp_collection] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        [self pp_completeArray:(error ? nil : [self pp_mapDocuments:snap.documents])
                         error:error
                    completion:completion];
    }];
}

- (void)fetchServiceByID:(NSString *)serviceID completion:(PPServiceModelBlock)completion {
    NSString *cleanServiceID = [[PPSafeString(serviceID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (cleanServiceID.length == 0) {
        [self pp_completeModel:nil
                         error:[self pp_errorWithCode:400 message:kLang(@"Service_Error_MissingID")]
                    completion:completion];
        return;
    }

    [[[self pp_collection] documentWithPath:cleanServiceID] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable error) {
        if (error) {
            [self pp_completeModel:nil error:error completion:completion];
            return;
        }
        if (!snap.exists) {
            [self pp_completeModel:nil
                             error:[self pp_errorWithCode:404 message:kLang(@"Service_Error_NotFound")]
                        completion:completion];
            return;
        }
        PPServiceModel *model = [PPServiceModel fromDictionary:snap.data ?: @{} withID:snap.documentID ?: cleanServiceID];
        [self pp_completeModel:model error:nil completion:completion];
    }];
}

- (void)addService:(PPServiceModel *)service
             image:(UIImage *)image
         auditNote:(NSString *)auditNote
        completion:(PPServiceVoidBlock)completion {
    if (![self currentAdminCanManageServices]) {
        [self pp_completeVoid:[self pp_errorWithCode:403 message:kLang(@"Service_Error_NoPermission")] completion:completion];
        return;
    }

    PPServiceModel *candidate = [service copy] ?: [PPServiceModel new];
    candidate.serviceID = [[NSUUID UUID] UUIDString];
    if (candidate.serviceOwnerID.length == 0) {
        candidate.serviceOwnerID = [self pp_currentAdminUID];
    }
    if (!candidate.createdAt) {
        candidate.createdAt = [NSDate date];
    }
    candidate.updatedAt = [NSDate date];
    if (!candidate.timestamp) {
        candidate.timestamp = candidate.createdAt ?: [NSDate date];
    }

    NSError *validationError = nil;
    [self pp_servicePayloadForModel:candidate creating:YES error:&validationError];
    if (validationError) {
        [self pp_completeVoid:validationError completion:completion];
        return;
    }

    void (^commitBlock)(NSString *) = ^(NSString *resolvedImageURL) {
        if (resolvedImageURL.length > 0) {
            candidate.imageURL = resolvedImageURL;
        }
        NSDictionary *docPayload = [self pp_servicePayloadForModel:candidate creating:YES error:nil];
        NSDictionary *auditAfter = [[PPServiceModel fromDictionary:docPayload withID:candidate.serviceID] toDictionary];
        FIRDocumentReference *docRef = [[self pp_collection] documentWithPath:candidate.serviceID];
        FIRWriteBatch *batch = [self.db batch];
        [batch setData:docPayload forDocument:docRef];
        [self pp_appendAuditWithBatch:batch
                               action:@"service_create"
                            serviceID:candidate.serviceID
                               before:nil
                                after:auditAfter
                                 note:auditNote];
        [batch commitWithCompletion:^(NSError * _Nullable error) {
            [self pp_completeVoid:error completion:completion];
        }];
    };

    if (image) {
        [self pp_uploadImage:image serviceID:candidate.serviceID completion:^(NSString *imageURL, NSError *error) {
            if (error) {
                [self pp_completeVoid:error completion:completion];
                return;
            }
            commitBlock(imageURL);
        }];
    } else {
        commitBlock(candidate.imageURL);
    }
}

- (void)updateService:(PPServiceModel *)service
                image:(UIImage *)image
            auditNote:(NSString *)auditNote
           completion:(PPServiceVoidBlock)completion {
    if (![self currentAdminCanManageServices]) {
        [self pp_completeVoid:[self pp_errorWithCode:403 message:kLang(@"Service_Error_NoPermission")] completion:completion];
        return;
    }

    NSString *serviceID = [[PPSafeString(service.serviceID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (serviceID.length == 0) {
        [self pp_completeVoid:[self pp_errorWithCode:400 message:kLang(@"Service_Error_MissingID")] completion:completion];
        return;
    }

    [self pp_fetchExistingDocumentForServiceID:serviceID completion:^(FIRDocumentReference * _Nullable docRef, NSDictionary * _Nullable beforeData, NSError * _Nullable error) {
        if (error || !docRef) {
            [self pp_completeVoid:error completion:completion];
            return;
        }

        PPServiceModel *candidate = [service copy];
        candidate.serviceID = serviceID;
        candidate.createdAt = candidate.createdAt ?: [PPServiceModel fromDictionary:beforeData ?: @{} withID:serviceID].createdAt;
        candidate.updatedAt = [NSDate date];
        if (!candidate.timestamp) {
            candidate.timestamp = [PPServiceModel fromDictionary:beforeData ?: @{} withID:serviceID].timestamp ?: [NSDate date];
        }

        NSError *validationError = nil;
        NSDictionary *initialPayload = [self pp_servicePayloadForModel:candidate creating:NO error:&validationError];
        if (validationError) {
            [self pp_completeVoid:validationError completion:completion];
            return;
        }

        void (^commitBlock)(NSString *) = ^(NSString *resolvedImageURL) {
            if (resolvedImageURL.length > 0) {
                candidate.imageURL = resolvedImageURL;
            }
            NSDictionary *docPayload = [self pp_servicePayloadForModel:candidate creating:NO error:nil];
            NSDictionary *auditAfter = [[PPServiceModel fromDictionary:docPayload withID:serviceID] toDictionary];
            FIRWriteBatch *batch = [self.db batch];
            [batch setData:docPayload forDocument:docRef merge:YES];
            [self pp_appendAuditWithBatch:batch
                                   action:@"service_update"
                                serviceID:serviceID
                                   before:beforeData
                                    after:auditAfter
                                     note:auditNote];
            [batch commitWithCompletion:^(NSError * _Nullable commitError) {
                [self pp_completeVoid:commitError completion:completion];
            }];
        };

        if (image) {
            [self pp_uploadImage:image serviceID:serviceID completion:^(NSString *imageURL, NSError *uploadError) {
                if (uploadError) {
                    [self pp_completeVoid:uploadError completion:completion];
                    return;
                }
                commitBlock(imageURL);
            }];
        } else {
            commitBlock(candidate.imageURL.length > 0 ? candidate.imageURL : PPSafeString(initialPayload[@"imageURL"]));
        }
    }];
}

- (void)updateAdministrativeStateForService:(PPServiceModel *)service
                                  auditNote:(NSString *)auditNote
                                 completion:(PPServiceVoidBlock)completion {
    if (![self currentAdminCanManageServices]) {
        [self pp_completeVoid:[self pp_errorWithCode:403 message:kLang(@"Service_Error_NoPermission")] completion:completion];
        return;
    }

    NSString *serviceID = [[PPSafeString(service.serviceID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (serviceID.length == 0) {
        [self pp_completeVoid:[self pp_errorWithCode:400 message:kLang(@"Service_Error_MissingID")] completion:completion];
        return;
    }

    [self pp_fetchExistingDocumentForServiceID:serviceID completion:^(FIRDocumentReference * _Nullable docRef, NSDictionary * _Nullable beforeData, NSError * _Nullable error) {
        if (error || !docRef) {
            [self pp_completeVoid:error completion:completion];
            return;
        }

        PPServiceModel *existing = [PPServiceModel fromDictionary:beforeData ?: @{} withID:serviceID];
        PPServiceModel *candidate = [existing copy];
        candidate.isDisabled = service.isDisabled;
        candidate.isBlocked = service.isBlocked;
        candidate.verificationStatus = service.verificationStatus;
        candidate.subscriptionType = service.subscriptionType;
        candidate.subscriptionPlan = service.subscriptionPlan;
        candidate.subscriptionStatus = service.subscriptionStatus;
        candidate.subscriptionActive = service.subscriptionActive;
        candidate.subscriptionStartDate = service.subscriptionStartDate;
        candidate.subscriptionEndDate = service.subscriptionEndDate;
        candidate.serviceFlags = service.serviceFlags ?: @{};
        candidate.updatedAt = [NSDate date];
        candidate.blockedBy = candidate.isBlocked ? [self pp_currentAdminUID] : @"";
        candidate.disabledBy = candidate.isDisabled ? [self pp_currentAdminUID] : @"";

        NSDictionary *docPayload = [self pp_servicePayloadForModel:candidate creating:NO error:nil];
        NSMutableDictionary *mergedPayload = [docPayload mutableCopy];
        if (!candidate.isBlocked) {
            mergedPayload[@"blockedBy"] = [FIRFieldValue fieldValueForDelete];
        }
        if (!candidate.isDisabled) {
            mergedPayload[@"disabledBy"] = [FIRFieldValue fieldValueForDelete];
        }

        FIRWriteBatch *batch = [self.db batch];
        [batch setData:mergedPayload forDocument:docRef merge:YES];
        [self pp_appendAuditWithBatch:batch
                               action:@"service_admin_update"
                            serviceID:serviceID
                               before:beforeData
                                after:[[PPServiceModel fromDictionary:docPayload withID:serviceID] toDictionary]
                                 note:auditNote];
        [batch commitWithCompletion:^(NSError * _Nullable commitError) {
            [self pp_completeVoid:commitError completion:completion];
        }];
    }];
}

- (void)setDisabled:(BOOL)disabled
       forServiceID:(NSString *)serviceID
          auditNote:(NSString *)auditNote
         completion:(PPServiceVoidBlock)completion {
    NSString *action = disabled ? @"service_disable" : @"service_enable";
    [self pp_updateStateForServiceID:serviceID
                              action:action
                                note:auditNote
                          patchBlock:^NSDictionary *(NSMutableDictionary *after) {
        after[@"isDisabled"] = @(disabled);
        after[@"updatedAt"] = [NSDate date];
        if (disabled) {
            after[@"disabledBy"] = [self pp_currentAdminUID];
            return @{
                @"isDisabled": @YES,
                @"disabledBy": [self pp_currentAdminUID],
                @"updatedAt": [NSDate date]
            };
        }
        after[@"disabledBy"] = @"";
        return @{
            @"isDisabled": @NO,
            @"disabledBy": [FIRFieldValue fieldValueForDelete],
            @"updatedAt": [NSDate date]
        };
    } completion:completion];
}

- (void)setBlocked:(BOOL)blocked
      forServiceID:(NSString *)serviceID
         auditNote:(NSString *)auditNote
        completion:(PPServiceVoidBlock)completion {
    NSString *action = blocked ? @"service_block" : @"service_unblock";
    [self pp_updateStateForServiceID:serviceID
                              action:action
                                note:auditNote
                          patchBlock:^NSDictionary *(NSMutableDictionary *after) {
        after[@"isBlocked"] = @(blocked);
        after[@"updatedAt"] = [NSDate date];
        if (blocked) {
            after[@"blockedBy"] = [self pp_currentAdminUID];
            return @{
                @"isBlocked": @YES,
                @"blockedBy": [self pp_currentAdminUID],
                @"updatedAt": [NSDate date]
            };
        }
        after[@"blockedBy"] = @"";
        return @{
            @"isBlocked": @NO,
            @"blockedBy": [FIRFieldValue fieldValueForDelete],
            @"updatedAt": [NSDate date]
        };
    } completion:completion];
}

- (void)archiveServiceID:(NSString *)serviceID
               auditNote:(NSString *)auditNote
              completion:(PPServiceVoidBlock)completion {
    [self pp_updateStateForServiceID:serviceID
                              action:@"service_archive"
                                note:auditNote
                          patchBlock:^NSDictionary *(NSMutableDictionary *after) {
        NSDate *now = [NSDate date];
        after[@"isDeleted"] = @YES;
        after[@"archivedAt"] = now;
        after[@"archivedBy"] = [self pp_currentAdminUID];
        after[@"updatedAt"] = now;
        return @{
            @"isDeleted": @YES,
            @"archivedAt": now,
            @"archivedBy": [self pp_currentAdminUID],
            @"updatedAt": now
        };
    } completion:completion];
}

- (void)restoreServiceID:(NSString *)serviceID
               auditNote:(NSString *)auditNote
              completion:(PPServiceVoidBlock)completion {
    [self pp_updateStateForServiceID:serviceID
                              action:@"service_restore"
                                note:auditNote
                          patchBlock:^NSDictionary *(NSMutableDictionary *after) {
        after[@"isDeleted"] = @NO;
        after[@"archivedAt"] = [NSNull null];
        after[@"archivedBy"] = @"";
        after[@"updatedAt"] = [NSDate date];
        return @{
            @"isDeleted": @NO,
            @"archivedAt": [FIRFieldValue fieldValueForDelete],
            @"archivedBy": [FIRFieldValue fieldValueForDelete],
            @"updatedAt": [NSDate date]
        };
    } completion:completion];
}

- (void)deleteServicePermanently:(NSString *)serviceID
                       auditNote:(NSString *)auditNote
                      completion:(PPServiceVoidBlock)completion {
    if (![self currentAdminCanManageServices]) {
        [self pp_completeVoid:[self pp_errorWithCode:403 message:kLang(@"Service_Error_NoPermission")] completion:completion];
        return;
    }

    NSString *cleanServiceID = [[PPSafeString(serviceID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (cleanServiceID.length == 0) {
        [self pp_completeVoid:[self pp_errorWithCode:400 message:kLang(@"Service_Error_MissingID")] completion:completion];
        return;
    }

    [self pp_fetchExistingDocumentForServiceID:cleanServiceID completion:^(FIRDocumentReference * _Nullable docRef, NSDictionary * _Nullable beforeData, NSError * _Nullable error) {
        if (error || !docRef) {
            [self pp_completeVoid:error completion:completion];
            return;
        }

        FIRWriteBatch *batch = [self.db batch];
        [batch deleteDocument:docRef];
        [self pp_appendAuditWithBatch:batch
                               action:@"service_delete_permanent"
                            serviceID:cleanServiceID
                               before:beforeData
                                after:@{}
                                 note:auditNote];
        [batch commitWithCompletion:^(NSError * _Nullable commitError) {
            [self pp_completeVoid:commitError completion:completion];
        }];
    }];
}

#pragma mark - Private

- (FIRCollectionReference *)pp_collection {
    return [self.db collectionWithPath:kPPServicesCollection];
}

- (NSArray<PPServiceModel *> *)pp_mapDocuments:(NSArray<FIRDocumentSnapshot *> *)documents {
    NSMutableArray<PPServiceModel *> *items = [NSMutableArray arrayWithCapacity:documents.count];
    for (FIRDocumentSnapshot *doc in documents) {
        [items addObject:[PPServiceModel fromDictionary:doc.data ?: @{} withID:doc.documentID ?: @""]];
    }
    return items.copy;
}

- (void)pp_fetchExistingDocumentForServiceID:(NSString *)serviceID completion:(PPServiceExistingDocumentBlock)completion {
    NSString *cleanServiceID = [[PPSafeString(serviceID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (cleanServiceID.length == 0) {
        if (completion) {
            completion(nil, nil, [self pp_errorWithCode:400 message:kLang(@"Service_Error_MissingID")]);
        }
        return;
    }

    FIRDocumentReference *docRef = [[self pp_collection] documentWithPath:cleanServiceID];
    [docRef getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) {
            return;
        }
        if (error) {
            completion(nil, nil, error);
            return;
        }
        if (!snap.exists) {
            completion(nil, nil, [self pp_errorWithCode:404 message:kLang(@"Service_Error_NotFound")]);
            return;
        }
        completion(docRef, snap.data ?: @{}, nil);
    }];
}

- (NSDictionary *)pp_servicePayloadForModel:(PPServiceModel *)service creating:(BOOL)creating error:(NSError * _Nullable __autoreleasing *)errorPointer {
    PPServiceModel *candidate = [service copy] ?: [PPServiceModel new];
    candidate.title = [[PPSafeString(candidate.title) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.serviceDescriptionText = [[PPSafeString(candidate.serviceDescriptionText) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.category = [[PPSafeString(candidate.category) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.categoryID = [[PPSafeString(candidate.categoryID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.imageURL = [[PPSafeString(candidate.imageURL) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.blurHash = PPSafeString(candidate.blurHash);
    candidate.serviceOwnerID = [[PPSafeString(candidate.serviceOwnerID) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.verificationStatus = [[PPSafeString(candidate.verificationStatus) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.subscriptionType = [[PPSafeString(candidate.subscriptionType) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.subscriptionPlan = [[PPSafeString(candidate.subscriptionPlan) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.subscriptionStatus = [[PPSafeString(candidate.subscriptionStatus) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    candidate.extraFields = PPSafeDict(candidate.extraFields);
    candidate.serviceFlags = PPSafeDict(candidate.serviceFlags);
    candidate.updatedAt = candidate.updatedAt ?: [NSDate date];
    if (creating && !candidate.createdAt) {
        candidate.createdAt = [NSDate date];
    }
    if (!candidate.timestamp) {
        candidate.timestamp = candidate.createdAt ?: [NSDate date];
    }

    NSString *validationMessage = [self pp_validationMessageForService:candidate creating:creating];
    if (validationMessage.length > 0) {
        if (errorPointer) {
            *errorPointer = [self pp_errorWithCode:422 message:validationMessage];
        }
        return nil;
    }

    return [candidate toDictionary];
}

- (NSString *)pp_validationMessageForService:(PPServiceModel *)service creating:(BOOL)creating {
    if (service.title.length == 0) {
        return kLang(@"Service_Error_TitleRequired");
    }
    if (service.serviceDescriptionText.length == 0) {
        return kLang(@"Service_Error_DescriptionRequired");
    }
    if (service.serviceOwnerID.length == 0) {
        return kLang(@"Service_Error_OwnerRequired");
    }
    if (service.price < 0) {
        return kLang(@"Service_Error_InvalidPrice");
    }
    if (service.category.length == 0 && service.categoryID.length == 0) {
        return kLang(@"Service_Error_CategoryRequired");
    }
    if (service.subscriptionStartDate && service.subscriptionEndDate &&
        [service.subscriptionStartDate compare:service.subscriptionEndDate] == NSOrderedDescending) {
        return kLang(@"Service_Error_SubscriptionDateOrder");
    }
    if (creating && service.serviceID.length == 0) {
        return kLang(@"Service_Error_MissingID");
    }
    return @"";
}

- (void)pp_updateStateForServiceID:(NSString *)serviceID
                            action:(NSString *)action
                              note:(NSString *)note
                        patchBlock:(NSDictionary * (^)(NSMutableDictionary *after))patchBlock
                        completion:(PPServiceVoidBlock)completion {
    if (![self currentAdminCanManageServices]) {
        [self pp_completeVoid:[self pp_errorWithCode:403 message:kLang(@"Service_Error_NoPermission")] completion:completion];
        return;
    }

    [self pp_fetchExistingDocumentForServiceID:serviceID completion:^(FIRDocumentReference * _Nullable docRef, NSDictionary * _Nullable beforeData, NSError * _Nullable error) {
        if (error || !docRef) {
            [self pp_completeVoid:error completion:completion];
            return;
        }

        NSMutableDictionary *after = [PPSafeDict(beforeData) mutableCopy];
        NSDictionary *patch = patchBlock ? patchBlock(after) : @{};
        FIRWriteBatch *batch = [self.db batch];
        [batch setData:patch forDocument:docRef merge:YES];
        [self pp_appendAuditWithBatch:batch
                               action:action
                            serviceID:PPSafeString(serviceID)
                               before:beforeData
                                after:after
                                 note:note];
        [batch commitWithCompletion:^(NSError * _Nullable commitError) {
            [self pp_completeVoid:commitError completion:completion];
        }];
    }];
}

- (void)pp_appendAuditWithBatch:(FIRWriteBatch *)batch
                         action:(NSString *)action
                      serviceID:(NSString *)serviceID
                         before:(NSDictionary *)before
                          after:(NSDictionary *)after
                           note:(NSString *)note {
    FIRDocumentReference *auditRef = [[self.db collectionWithPath:kPPAdminAuditCollection] documentWithAutoID];
    NSDictionary *payload = @{
        @"auditId": PPSafeString(auditRef.documentID),
        @"area": @"services",
        @"action": PPSafeString(action),
        @"entityType": @"service",
        @"entityId": PPSafeString(serviceID),
        @"serviceId": PPSafeString(serviceID),
        @"adminUid": [self pp_currentAdminUID],
        @"adminName": [self pp_currentAdminName],
        @"note": PPSafeString(note),
        @"before": PPSafeDict(before),
        @"after": PPSafeDict(after),
        @"createdAt": [NSDate date]
    };
    [batch setData:payload forDocument:auditRef];
}

- (void)pp_uploadImage:(UIImage *)image
              serviceID:(NSString *)serviceID
             completion:(void (^)(NSString *imageURL, NSError * _Nullable error))completion {
    NSData *imageData = UIImageJPEGRepresentation(image, 0.85);
    if (!imageData) {
        if (completion) {
            completion(@"", [self pp_errorWithCode:400 message:kLang(@"Service_Error_ImageUpload")]);
        }
        return;
    }

    NSString *path = [NSString stringWithFormat:@"services/%@.jpg", serviceID];
    FIRStorageReference *reference = [[[FIRStorage storage] reference] child:path];

    FIRStorageMetadata *meta = [[FIRStorageMetadata alloc] init];
    meta.contentType = @"image/jpeg";
    meta.customMetadata = @{
        @"uploaded_by": [self pp_currentAdminUID],
        @"entity_type": @"service",
        @"entity_id": serviceID ?: @""
    };

    [reference putData:imageData metadata:meta completion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
        if (error) {
            if (completion) {
                completion(@"", error);
            }
            return;
        }
        [reference downloadURLWithCompletion:^(NSURL * _Nullable URL, NSError * _Nullable downloadError) {
            if (completion) {
                completion(PPSafeString(URL.absoluteString), downloadError);
            }
        }];
    }];
}

- (NSError *)pp_errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:kPPServiceManagerErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: PPSafeString(message).length > 0 ? message : kLang(@"Service_Error_Generic")}];
}

- (NSString *)pp_currentAdminUID {
    return PPSafeString([FIRAuth auth].currentUser.uid);
}

- (NSString *)pp_currentAdminName {
    UserModel *currentUser = [UserManager shared].currentUser;
    NSString *name = [currentUser respondsToSelector:@selector(PPBestDisplayName)] ? [currentUser PPBestDisplayName] : currentUser.displayName;
    if (PPSafeString(name).length > 0) {
        return name;
    }
    return [self pp_currentAdminUID];
}

- (void)pp_completeVoid:(NSError *)error completion:(PPServiceVoidBlock)completion {
    if (!completion) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(error);
    });
}

- (void)pp_completeArray:(NSArray<PPServiceModel *> *)services error:(NSError *)error completion:(PPServiceArrayBlock)completion {
    if (!completion) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(services, error);
    });
}

- (void)pp_completeModel:(PPServiceModel *)service error:(NSError *)error completion:(PPServiceModelBlock)completion {
    if (!completion) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(service, error);
    });
}

@end
