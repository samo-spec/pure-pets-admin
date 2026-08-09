//
//  PPVetManager.m
//  PurePetsAdmin
//

#import "PPVetManager.h"
#import "PPVetModel.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
@import Firebase;
@import FirebaseAuth;
static NSString * const kColVets = @"veterinarians";

static NSError *PPVetError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"pp.vet.manager"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Vet operation failed"}];
}

@interface PPVetManager ()
@property (nonatomic, strong) FIRFirestore *db;
@end

@implementation PPVetManager

+ (instancetype)sharedManager {
    static PPVetManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PPVetManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _db = [FIRFirestore firestore];
    }
    return self;
}

- (FIRCollectionReference *)col {
    return [self.db collectionWithPath:kColVets];
}

#pragma mark - Mapping

- (PPVetModel *)_mapDoc:(FIRDocumentSnapshot *)doc {
    return [PPVetModel fromDictionary:doc.data ?: @{} withID:doc.documentID];
}

- (NSArray<PPVetModel *> *)_mapDocs:(NSArray<FIRDocumentSnapshot *> *)docs {
    NSMutableArray<PPVetModel *> *arr = [NSMutableArray arrayWithCapacity:docs.count];
    for (FIRDocumentSnapshot *doc in docs) {
        [arr addObject:[self _mapDoc:doc]];
    }
    return arr;
}

#pragma mark - READ

- (void)fetchAllVetsWithCompletion:(PPVetArrayBlock)completion {
    [[self col] getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        completion(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (id<FIRListenerRegistration>)observeAllVets:(PPVetArrayBlock)onChange {
    return [[self col] addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!onChange) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            onChange(error ? nil : [self _mapDocs:snap.documents], error);
        });
    }];
}

- (void)fetchVetsForUserID:(NSString *)userID completion:(PPVetArrayBlock)completion {
    [[[self col] queryWhereField:@"userID" isEqualTo:userID ?: @""]
     getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        completion(error ? nil : [self _mapDocs:snap.documents], error);
    }];
}

- (void)fetchVetByID:(NSString *)vetID completion:(void (^)(PPVetModel * _Nullable, NSError * _Nullable))completion {
    if (vetID.length == 0) {
        if (completion) completion(nil, PPVetError(400, @"Vet ID is required."));
        return;
    }
    [[[self col] documentWithPath:vetID] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!completion) return;
        if (error) { completion(nil, error); return; }
        if (!snap.exists) { completion(nil, PPVetError(404, @"Vet not found.")); return; }
        completion([self _mapDoc:snap], nil);
    }];
}

#pragma mark - WRITE

- (void)addVet:(PPVetModel *)vet image:(UIImage *)image completion:(PPVetVoidBlock)completion {
    if (!vet) {
        if (completion) completion(PPVetError(400, @"Vet model is required."));
        return;
    }

    NSString *docID = [[NSUUID UUID] UUIDString];
    vet.vetID = docID;

    if (!vet.createdAt) {
        vet.createdAt = [NSDate date];
    }
    vet.updatedAt = [NSDate date];

    if (vet.userID.length == 0) {
        vet.userID = [FIRAuth auth].currentUser.uid ?: @"";
    }

    void (^saveBlock)(NSString *) = ^(NSString *logoURL) {
        vet.logoURL = logoURL.length ? logoURL : vet.logoURL;
        [[[self col] documentWithPath:docID] setData:[vet toDictionary] completion:completion];
    };

    if (image) {
        [self uploadImage:image vetID:docID completion:saveBlock];
    } else {
        saveBlock(@"");
    }
}

- (void)updateVet:(PPVetModel *)vet image:(UIImage *)image completion:(PPVetVoidBlock)completion {
    if (!vet || vet.vetID.length == 0) {
        if (completion) completion(PPVetError(400, @"Valid vet model with ID is required."));
        return;
    }

    vet.updatedAt = [NSDate date];

    void (^updateBlock)(NSString *) = ^(NSString *logoURL) {
        vet.logoURL = logoURL.length ? logoURL : vet.logoURL;
        [[[self col] documentWithPath:vet.vetID] setData:[vet toDictionary] merge:YES completion:completion];
    };

    if (image) {
        [self uploadImage:image vetID:vet.vetID completion:updateBlock];
    } else {
        updateBlock(@"");
    }
}

- (void)deleteVet:(PPVetModel *)vet completion:(PPVetVoidBlock)completion {
    if (!vet || vet.vetID.length == 0) {
        if (completion) completion(PPVetError(400, @"Vet ID is required for deletion."));
        return;
    }
    [[[self col] documentWithPath:vet.vetID] deleteDocumentWithCompletion:completion];
}

#pragma mark - Admin Toggles

- (void)setDisabled:(BOOL)disabled forVetID:(NSString *)vetID completion:(PPVetVoidBlock)completion {
    if (vetID.length == 0) {
        if (completion) completion(PPVetError(400, @"Vet ID is missing."));
        return;
    }
    [[[self col] documentWithPath:vetID]
     updateData:@{
        @"isDisabled": @(disabled),
        @"updatedAt": [FIRTimestamp timestamp]
    }
     completion:completion];
}

- (void)updateSubscriptionForVetID:(NSString *)vetID
                              tier:(NSInteger)tier
                            active:(BOOL)active
                         startDate:(NSDate *)startDate
                           endDate:(NSDate *)endDate
                        completion:(PPVetVoidBlock)completion {
    if (vetID.length == 0) {
        if (completion) completion(PPVetError(400, @"Vet ID is missing."));
        return;
    }
    NSMutableDictionary *data = [@{
        @"subscriptionTier":   @(tier),
        @"subscriptionActive": @(active),
        @"updatedAt":          [FIRTimestamp timestamp]
    } mutableCopy];

    if (startDate) {
        data[@"subscriptionStartDate"] = startDate;
    }
    if (endDate) {
        data[@"subscriptionEndDate"] = endDate;
    }

    [[[self col] documentWithPath:vetID] updateData:data completion:completion];
}

#pragma mark - Image Upload

- (void)uploadImage:(UIImage *)image vetID:(NSString *)vetID completion:(void (^)(NSString *))completion {
    NSData *imageData = UIImagePNGRepresentation(image);
    if (!imageData) {
        if (completion) completion(@"");
        return;
    }
    NSString *path = [NSString stringWithFormat:@"vets/%@.png", vetID];
    FIRStorageReference *ref = [[[FIRStorage storage] reference] child:path];

    FIRStorageMetadata *metadata = [[FIRStorageMetadata alloc] init];
    metadata.contentType = @"image/png";
    metadata.customMetadata = @{
        @"uploaded_by": [FIRAuth auth].currentUser.uid ?: @"",
        @"entity_type": @"veterinarian",
        @"entity_id": vetID ?: @""
    };

    [ref putData:imageData metadata:metadata completion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
        if (error) {
            DLog(@"[PPVetManager] image upload error: %@", error.localizedDescription);
            if (completion) completion(@"");
            return;
        }
        [ref downloadURLWithCompletion:^(NSURL * _Nullable URL, NSError * _Nullable error) {
            if (completion) completion(URL.absoluteString ?: @"");
        }];
    }];
}

#pragma mark - Count

- (id<FIRListenerRegistration>)listenVetCount:(PPVetCountBlock)block {
    return [[self col] addSnapshotListener:^(FIRQuerySnapshot * _Nullable snap, NSError * _Nullable error) {
        if (!block) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            block(error ? 0 : (NSInteger)snap.documents.count);
        });
    }];
}

@end
