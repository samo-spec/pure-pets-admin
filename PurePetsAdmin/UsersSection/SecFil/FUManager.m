//
//  FUUserDoc.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 02/09/2025.
//


//  FUManager.m
#import "FUManager.h"
#import "PPStaffAuth.h"
 
#import <GoogleSignIn/GoogleSignIn.h>
#import <FirebaseAuth/FirebaseAuth.h>
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

@import GoogleSignIn;
@import FirebaseAuth;

@interface PPStaffAuth (FUManagerCacheAccess)
@property (nonatomic, strong, nullable, readwrite) PPStaffDoc *cachedCurrentStaff;
@end

#pragma mark - Constants

static NSString * const kFUUsersCollection = @"UsersCol";
static NSString * const FUErrorDomain = @"FUManagerError";
static NSString * const kFUFIRAuthInternalErrorDomain = @"FIRAuthInternalErrorDomain";
static NSString * const kFUFIRAuthDeserializedResponseKey = @"FIRAuthErrorUserInfoDeserializedResponseKey";

#pragma mark - Small helpers (safe casts)

static inline NSString *FUString(id v) {
    if ([v isKindOfClass:NSString.class]) return v;
    if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
    return nil;
}
static inline NSNumber *FUNumber(id v) {
    if ([v isKindOfClass:NSNumber.class]) return v;
    if ([v isKindOfClass:NSString.class]) return @([(NSString *)v longLongValue]);
    return nil;
}
static inline NSURL *FUURL(id v) {
    NSString *s = FUString(v); return s.length ? [NSURL URLWithString:s] : nil;
}
static inline NSDate *FUDate(id v) {
    if ([v isKindOfClass:NSDate.class]) return v;
    if ([v isKindOfClass:[FIRTimestamp class]]) return ((FIRTimestamp *)v).dateValue;
    return nil;
}

static inline BOOL FUIsFirebaseAuthDomain(NSString * _Nullable domain) {
    if ([domain isEqualToString:FIRAuthErrorDomain]) return YES;
    if ([domain isEqualToString:kFUFIRAuthInternalErrorDomain]) return YES;
    return NO;
}

static inline BOOL FUHasUnderlyingFirebaseAuthError(NSError * _Nullable error) {
    if (!error) return NO;
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (![underlying isKindOfClass:NSError.class]) return NO;
    return FUIsFirebaseAuthDomain(underlying.domain);
}

static inline FIRAuthErrorCode FUNormalizedAuthCode(NSError * _Nullable error) {
    if (!error) return 0;
    if ([error.domain isEqualToString:FIRAuthErrorDomain]) {
        return (FIRAuthErrorCode)error.code;
    }

    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if ([underlying isKindOfClass:NSError.class] &&
        [underlying.domain isEqualToString:FIRAuthErrorDomain]) {
        return (FIRAuthErrorCode)underlying.code;
    }
    return (FIRAuthErrorCode)error.code;
}


static inline BOOL FUShouldTreatAuthErrorAsTransient(NSError * _Nullable error) {
    if (!error) return NO;
    if (!FUIsFirebaseAuthDomain(error.domain)) {
        NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
        if (![underlying isKindOfClass:NSError.class] || !FUIsFirebaseAuthDomain(underlying.domain)) {
            return NO;
        }
    }

    FIRAuthErrorCode code = FUNormalizedAuthCode(error);
    switch (code) {
        case FIRAuthErrorCodeInternalError:
        case FIRAuthErrorCodeNetworkError:
            return YES;
        default:
            if (![error.domain isEqualToString:kFUFIRAuthInternalErrorDomain]) {
                return NO;
            }
            // Internal wrappers can carry a concrete underlying auth code.
            // Keep those non-transient so callers can surface the real failure.
            return !FUHasUnderlyingFirebaseAuthError(error);
    }
}

#pragma mark - FUUserDoc

@implementation FUUserDoc
@end

#pragma mark - Combined Registration (auth + user doc)

@interface FUCompositeRegistration : NSObject <FIRListenerRegistration>
@property (nonatomic) FIRAuthStateDidChangeListenerHandle authHandle;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> docReg;

@end

@implementation FUCompositeRegistration
- (void)remove {
    if (self.authHandle) {
        [[FIRAuth auth] removeAuthStateDidChangeListener:self.authHandle];
        self.authHandle = 0;
    }
    [self.docReg remove];
    self.docReg = nil;
}
@end

#pragma mark - Private

@interface FUManager ()
@property (nonatomic) FIRAuthStateDidChangeListenerHandle bootstrapAuthHandle;
@property (nonatomic) FIRAuthStateDidChangeListenerHandle authHandle;
@property (nonatomic, strong, nullable)  FIRDocumentReference *ref;
@end

@implementation FUManager

+ (instancetype)shared {
    static FUManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [FUManager new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _db        = [FIRFirestore firestore];
        _storage   = [FIRStorage storage];
        _functions = [FIRFunctions functionsForRegion:@"us-central1"]; // adjust if needed

        __weak typeof(self) weakSelf = self;
        self.bootstrapAuthHandle =
        [[FIRAuth auth] addAuthStateDidChangeListener:^(FIRAuth * _Nonnull auth, FIRUser * _Nullable user) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            if (!user) { self.currentUserDoc = nil; return; }

            [[self userDocumentRefForUID:user.uid] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
                if (!snapshot.exists || !snapshot.data) { self.currentUserDoc = nil; return; }

                FUUserDoc *d = [FUUserDoc new];
                d.uid         = user.uid;
                d.email       = FUString(snapshot[@"email"]) ?: user.email;
                d.displayName = FUString(snapshot[@"displayName"]) ?: user.displayName;
                d.photoURL    = FUURL(snapshot[@"photoURL"]) ?: user.photoURL;
                d.raw         = snapshot.data;
                self.currentUserDoc = d;
            }];
        }];
    }
    return self;
}

#pragma mark - Accessors

- (FIRUser *)currentUser { return [FIRAuth auth].currentUser; }

#pragma mark - Errors & finish

- (NSError *)p_err:(NSString *)msg code:(NSInteger)code {
    return [NSError errorWithDomain:FUErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: msg ?: @"Error"}];
}

- (void)p_finishUser:(FIRUser * _Nullable)user
               error:(NSError * _Nullable)error
          completion:(FUUserBlock)completion {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{ completion(user, error); });
}

#pragma mark - Profile helpers

- (void)p_applyDisplayName:(NSString * _Nullable)displayName
                  photoURL:(NSURL * _Nullable)photoURL
                    toUser:(FIRUser *)user
                completion:(FUErrorBlock)completion
{
    FIRUserProfileChangeRequest *req = [user profileChangeRequest];
    if (displayName) req.displayName = displayName;
    if (photoURL)    req.photoURL    = photoURL;
    [req commitChangesWithCompletion:^(NSError * _Nullable error) {
            if (completion) completion(error);
    }];
}

- (NSArray<NSString *> *)p_providerIDsForUser:(FIRUser *)user {
    NSMutableArray *ids = [NSMutableArray array];
    for (id<FIRUserInfo> info in user.providerData) {
        if (info.providerID) [ids addObject:info.providerID];
    }
    return ids.copy;
}

- (UIImage *)p_scaleImage:(UIImage *)image maxDimension:(NSUInteger)maxDim {
    if (maxDim == 0) return image;
    CGSize s = image.size;
    CGFloat maxSide = MAX(s.width, s.height);
    if (maxSide <= maxDim) return image;

    CGFloat scale = (CGFloat)maxDim / maxSide;
    CGSize newSize = CGSizeMake(floor(s.width * scale), floor(s.height * scale));

    UIGraphicsBeginImageContextWithOptions(newSize, YES, 1.0);
    [image drawInRect:(CGRect){.origin = CGPointZero, .size = newSize}];
    UIImage *res = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return res ?: image;
}

- (NSData *)p_pngDataForImage:(UIImage *)image targetMaxBytes:(NSUInteger)maxBytes {
    NSData *data = UIImagePNGRepresentation(image);
    if (!data) return nil;
    if (maxBytes == 0 || data.length <= maxBytes) return data;

    UIImage *current = image;
    for (int i = 0; i < 6; i++) {
        CGSize s = current.size;
        NSUInteger dim = (NSUInteger)(MAX(s.width, s.height) * 0.8);
        current = [self p_scaleImage:current maxDimension:dim];
        data = UIImagePNGRepresentation(current);
        if (!data) return nil;
        if (data.length <= maxBytes) return data;
    }
    return data;
}

- (void)p_uploadProfileImage:(UIImage *)image
                      forUID:(NSString *)uid
                      maxDim:(NSUInteger)maxDim
                    maxBytes:(NSUInteger)maxBytes
                  completion:(FUURLBlock)completion
{
    UIImage *scaled = [self p_scaleImage:image maxDimension:maxDim];
    NSData  *data   = [self p_pngDataForImage:scaled targetMaxBytes:maxBytes];

    NSString *path = [NSString stringWithFormat:@"users/%@/profile.png", uid];
    FIRStorageReference *ref = [[self.storage reference] child:path];

    FIRStorageMetadata *meta = [FIRStorageMetadata new];
    meta.contentType  = @"image/png";
    meta.cacheControl = @"public, max-age=3600";

    [ref putData:data metadata:meta completion:^(FIRStorageMetadata * _Nullable metadata, NSError * _Nullable error) {
        if (error) { if (completion) completion(nil, error); return; }
        [ref downloadURLWithCompletion:^(NSURL * _Nullable URL, NSError * _Nullable error2) {
            if (completion) completion(URL, error2);
        }];
    }];
}

- (void)p_linkCredential:(FIRAuthCredential *)cred
              completion:(FUUserBlock)completion {
    FIRUser *u = self.currentUser;
    if (!u) { if (completion) completion(nil, [self p_err:@"No current user" code:121]); return; }
    [u linkWithCredential:cred completion:^(FIRAuthDataResult * _Nullable result, NSError * _Nullable error) {
        if (result.user) {
            [self ensureUserDocumentExistsForCurrentUserWithExtra:nil completion:^(NSError * _Nullable e) {}];
        }
        if (completion) completion(result.user, error);
    }];
}

#pragma mark - Auth lifecycle

- (void)createUserWithEmail:(NSString *)email
                   password:(NSString *)password
                displayName:(NSString *)displayName
                      photo:(UIImage *)photo
                   metadata:(NSDictionary *)metadata
                 completion:(FUUserBlock)completion
{
    [[FIRAuth auth] createUserWithEmail:email password:password completion:^(FIRAuthDataResult * _Nullable res, NSError * _Nullable err) {
        if (err || !res.user) { [self p_finishUser:nil error:err completion:completion]; return; }
        FIRUser *user = res.user;

        [self p_applyDisplayName:displayName photoURL:nil toUser:user completion:^(NSError * _Nullable e1) {
            if (e1) { [self p_finishUser:user error:e1 completion:completion]; return; }

            void (^finish)(NSError *) = ^(NSError *e){ [self p_finishUser:user error:e completion:completion]; };

            if (photo) {
                [self p_uploadProfileImage:photo forUID:user.uid maxDim:800 maxBytes:(250*1024) completion:^(NSURL * _Nullable url, NSError * _Nullable e2) {
                    if (e2) { finish(e2); return; }
                    [self p_applyDisplayName:displayName photoURL:url toUser:user completion:^(NSError * _Nullable e3) {
                        if (e3) { finish(e3); return; }
                        [self p_createOrMergeUserDocFor:user extra:metadata completion:finish];
                    }];
                }];
            } else {
                [self p_createOrMergeUserDocFor:user extra:metadata completion:finish];
            }
        }];
    }];
}

- (void)signInWithEmail:(NSString *)email
               password:(NSString *)password
             completion:(FUUserBlock)completion
{
    NSString *trimmedEmail = [email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *safePassword = password ?: @"";

    [[FIRAuth auth] signInWithEmail:trimmedEmail password:safePassword completion:^(FIRAuthDataResult * _Nullable res, NSError * _Nullable err) {
        FIRUser *effectiveUser = res.user ?: [FIRAuth auth].currentUser;
        NSError *effectiveError = err;

        if (effectiveError) {
            NSError *underlying = effectiveError.userInfo[NSUnderlyingErrorKey];
            NSDictionary *deserialized = effectiveError.userInfo[kFUFIRAuthDeserializedResponseKey];
            NSLog(@"[FUManager] signIn error domain=%@ code=%ld normalizedCode=%ld name=%@ desc=%@ underlyingDomain=%@ underlyingCode=%ld deserialized=%@",
                  effectiveError.domain ?: @"",
                  (long)effectiveError.code,
                  (long)FUNormalizedAuthCode(effectiveError),
                  effectiveError.userInfo[FIRAuthErrorUserInfoNameKey] ?: @"",
                  effectiveError.localizedDescription ?: @"",
                  underlying.domain ?: @"",
                  (long)underlying.code,
                  deserialized ?: @{});
        }

        // Firebase can occasionally return an internal error while a user session is still created.
        if (effectiveError && effectiveUser && FUShouldTreatAuthErrorAsTransient(effectiveError)) {
            NSLog(@"[FUManager] signIn recovered from transient auth error with uid=%@", effectiveUser.uid ?: @"");
            effectiveError = nil;
        }

        [self p_finishUser:effectiveUser error:effectiveError completion:completion];
        if (effectiveUser && !effectiveError) {
            [self ensureUserDocumentExistsForCurrentUserWithExtra:nil completion:^(NSError * _Nullable e){}];
        }
    }];
}

- (void)signInWithGoogle:(UIViewController *)presentingVC
              completion:(FUUserBlock)completion
{
    NSString *clientID = [FIRApp defaultApp].options.clientID;
    if (clientID.length == 0) {
        [self p_finishUser:nil
                     error:[self p_err:@"Google Sign-In is not configured for this app." code:108]
                completion:completion];
        return;
    }

    GIDSignIn.sharedInstance.configuration = [[GIDConfiguration alloc] initWithClientID:clientID];
    [GIDSignIn.sharedInstance signInWithPresentingViewController:presentingVC completion:^(GIDSignInResult * _Nullable signInResult, NSError * _Nullable error) {
        if (error) {
            [self p_finishUser:nil error:error completion:completion];
            return;
        }

        GIDGoogleUser *googleUser = signInResult.user;
        NSString *idToken = googleUser.idToken.tokenString;
        NSString *accessToken = googleUser.accessToken.tokenString;
        if (idToken.length == 0 || accessToken.length == 0) {
            [self p_finishUser:nil
                         error:[self p_err:@"Google Sign-In did not return valid auth tokens." code:109]
                    completion:completion];
            return;
        }

        FIRAuthCredential *credential = [FIRGoogleAuthProvider credentialWithIDToken:idToken
                                                                         accessToken:accessToken];
        
        

        [[FIRAuth auth] signInWithCredential:credential completion:^(FIRAuthDataResult * _Nullable res, NSError * _Nullable err) {
            FIRUser *effectiveUser = res.user ?: [FIRAuth auth].currentUser;
            [self p_finishUser:effectiveUser error:err completion:completion];
            if (effectiveUser && !err) {
                [self ensureUserDocumentExistsForCurrentUserWithExtra:nil completion:^(NSError * _Nullable e){}];
            }
        }];
    }];
}

- (BOOL)signOut:(NSError * _Nullable * _Nullable)error {
    [GIDSignIn.sharedInstance signOut];
    [PPStaffAuth shared].cachedCurrentStaff = nil;
    return [[FIRAuth auth] signOut:error];
}

- (void)deleteCurrentUserWithCompletion:(FUErrorBlock)completion {
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion(nil); return; }
    [u deleteWithCompletion:^(NSError * _Nullable error) { if (completion) completion(error); }];
}

#pragma mark - Reauth / reload

- (void)reauthenticateWithEmail:(NSString *)email
                       password:(NSString *)password
                     completion:(FUErrorBlock)completion
{
    FIRAuthCredential *cred = [FIREmailAuthProvider credentialWithEmail:email password:password];
    [self reauthenticateWithCredential:cred completion:completion];
}

- (void)reauthenticateWithCredential:(FIRAuthCredential *)credential
                          completion:(FUErrorBlock)completion
{
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion([self p_err:@"No current user" code:100]); return; }
    [u reauthenticateWithCredential:credential completion:^(FIRAuthDataResult * _Nullable result, NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}

- (void)reloadCurrentUser:(FUErrorBlock)completion {
    [self.currentUser reloadWithCompletion:^(NSError * _Nullable error) { if (completion) completion(error); }];
}

#pragma mark - Profile updates

- (void)updateDisplayName:(NSString *)displayName completion:(FUErrorBlock)completion {
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion([self p_err:@"No current user" code:101]); return; }
    [self p_applyDisplayName:displayName photoURL:nil toUser:u completion:^(NSError * _Nullable error) {
        if (error) { if (completion) completion(error); return; }
        [self updateUserDocumentFields:@{@"displayName": displayName ?: [NSNull null]} completion:completion];
    }];
}

- (void)updateEmail:(NSString *)email completion:(FUErrorBlock)completion {
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion([self p_err:@"No current user" code:102]); return; }
    [u updateEmail:email completion:^(NSError * _Nullable error) {
        if (error) { if (completion) completion(error); return; }
        [self updateUserDocumentFields:@{@"email": email ?: [NSNull null]} completion:completion];
    }];
}

- (void)updatePassword:(NSString *)newPassword completion:(FUErrorBlock)completion {
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion([self p_err:@"No current user" code:103]); return; }
    [u updatePassword:newPassword completion:^(NSError * _Nullable error) { if (completion) completion(error); }];
}

- (void)updatePhotoImage:(UIImage *)image
         maxDimension_px:(NSUInteger)maxDim
               maxBytes:(NSUInteger)maxBytes
              completion:(FUURLBlock)completion
{
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion(nil, [self p_err:@"No current user" code:104]); return; }
    [self p_uploadProfileImage:image forUID:u.uid maxDim:maxDim maxBytes:maxBytes completion:^(NSURL * _Nullable url, NSError * _Nullable error) {
        if (error || !url) { if (completion) completion(nil, error); return; }
        [self p_applyDisplayName:nil photoURL:url toUser:u completion:^(NSError * _Nullable e2) {
            if (e2) { if (completion) completion(nil, e2); return; }
            [self updateUserDocumentFields:@{@"photoURL": url.absoluteString ?: [NSNull null]}
                                 completion:^(NSError * _Nullable e3) {
                if (completion) completion(url, e3);
            }];
        }];
    }];
}

#pragma mark - Firestore user doc

- (FIRDocumentReference *)userDocumentRefForUID:(NSString *)uid {
    return [[self.db collectionWithPath:kFUUsersCollection] documentWithPath:uid];
}

- (void)p_createOrMergeUserDocFor:(FIRUser *)user
                            extra:(NSDictionary * _Nullable)extra
                       completion:(FUErrorBlock)completion
{
    self.ref = [self userDocumentRefForUID:user.uid];
    NSMutableDictionary *doc = [@{
        @"uid": user.uid ?: @"",
        @"email": user.email ?: [NSNull null],
        @"displayName": user.displayName ?: [NSNull null],
        @"photoURL": user.photoURL.absoluteString ?: [NSNull null],
        @"providerIds": [self p_providerIDsForUser:user],
        @"createdAt": [FIRFieldValue fieldValueForServerTimestamp],
        @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp],
        @"lastLoginAt": [FIRFieldValue fieldValueForServerTimestamp]
    } mutableCopy];
    if (extra.count) [doc addEntriesFromDictionary:extra];

    __weak typeof(self) weakSelf = self;
    [self.ref setData:doc merge:YES completion:^(NSError * _Nullable error) {
        if (error) { if (completion) completion(error); return; }
        [weakSelf.ref getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable e2) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { if (completion) completion(e2); return; }

            if (snap.exists && snap.data) {
                FUUserDoc *d = [FUUserDoc new];
                d.uid         = user.uid;
                d.email       = FUString(snap[@"email"]) ?: user.email;
                d.displayName = FUString(snap[@"displayName"]) ?: user.displayName;
                d.photoURL    = FUURL(snap[@"photoURL"]) ?: user.photoURL;
                d.raw         = snap.data;
                self.currentUserDoc = d;
            }
            if (completion) completion(e2);
        }];
    }];
}

- (void)ensureUserDocumentExistsForCurrentUserWithExtra:(NSDictionary *)extra
                                             completion:(FUErrorBlock)completion
{
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion([self p_err:@"No current user" code:105]); return; }
    [self p_createOrMergeUserDocFor:u extra:extra completion:completion];
}

- (void)updateUserDocumentFields:(NSDictionary *)fields completion:(FUErrorBlock)completion {
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion([self p_err:@"No current user" code:106]); return; }
    FIRDocumentReference *ref = [self userDocumentRefForUID:u.uid];
    NSMutableDictionary *payload = fields.mutableCopy ?: [NSMutableDictionary new];
    payload[@"updatedAt"] = [FIRFieldValue fieldValueForServerTimestamp];
    [ref setData:payload merge:YES completion:^(NSError * _Nullable error) { if (completion) completion(error); }];
}

- (id<FIRListenerRegistration>)listenToCurrentUserDoc:(void(^)(FUUserDoc * _Nullable doc,
                                                                NSError * _Nullable error))block
{
    FIRUser *u = self.currentUser; if (!u) { if (block) block(nil, [self p_err:@"No current user" code:107]); return (id)nil; }
    FIRDocumentReference *ref = [self userDocumentRefForUID:u.uid];
    return [ref addSnapshotListener:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error || !snapshot) { if (block) block(nil, error); return; }
        FUUserDoc *d = [FUUserDoc new];
        d.uid         = u.uid;
        d.email       = FUString(snapshot[@"email"]) ?: u.email;
        d.displayName = FUString(snapshot[@"displayName"]) ?: u.displayName;
        d.photoURL    = FUURL(snapshot[@"photoURL"]) ?: u.photoURL;
        d.raw         = snapshot.data ?: @{};
        if (block) block(d, nil);
    }];
}

- (void)unlinkProvider:(NSString *)providerID completion:(FUUserBlock)completion {
    FIRUser *u = self.currentUser; if (!u) { if (completion) completion(nil, [self p_err:@"No current user" code:121]); return; }
    [u unlinkFromProvider:providerID completion:^(FIRUser * _Nullable user, NSError * _Nullable error) {
        if (completion) completion(user, error);
    }];
}

#pragma mark - Apple nonce helpers

+ (NSString *)randomNonceString:(NSUInteger)length {
    NSAssert(length > 0, @"randomNonceString length must be > 0");
    static NSString * const kCharset = @"0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._";
    const NSUInteger n = kCharset.length;

    NSMutableString *result = [NSMutableString stringWithCapacity:length];
    while (result.length < length) {
        uint8_t rnd = 0;
        OSStatus s = SecRandomCopyBytes(kSecRandomDefault, 1, &rnd);
        if (s != errSecSuccess) rnd = (uint8_t)arc4random_uniform(255);
        unichar ch = [kCharset characterAtIndex:(rnd % n)];
        [result appendFormat:@"%C", ch];
    }
    return result;
}

+ (NSString *)sha256:(NSString *)input {
    if (input.length == 0) return @"";
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    static const char hexdigits[] = "0123456789abcdef";
    char buf[CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0, j = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        buf[j++] = hexdigits[(digest[i] >> 4) & 0xF];
        buf[j++] = hexdigits[digest[i] & 0xF];
    }
    return [[NSString alloc] initWithBytes:buf length:sizeof(buf) encoding:NSASCIIStringEncoding];
}

#pragma mark - Mapping to your UserModel (minimal, no roles/permissions logic)

- (UserModel * _Nullable)userModelFromAuth:(FIRUser * _Nullable)auth
                                       doc:(FUUserDoc * _Nullable)doc
{
    if (!auth && !doc) return nil;
    NSDictionary *raw = doc.raw ?: @{};
    UserModel *m = [UserModel new];

    // IDs
    m.uid = auth.uid ?: doc.uid ?: FUString(raw[@"uid"]) ?: @"";

    // Names
    NSString *displayName = doc.displayName ?: auth.displayName ?: FUString(raw[@"displayName"]) ?: FUString(raw[@"UserName"]);
    m.UserName  = displayName ?: @"";
    m.FirstName = FUString(raw[@"firstName"]) ?: FUString(raw[@"FirstName"]);
    m.LastName  = FUString(raw[@"lastName"])  ?: FUString(raw[@"LastName"]);

    // Email / phone
    m.UserEmail = doc.email ?: auth.email ?: FUString(raw[@"email"]) ?: FUString(raw[@"UserEmail"]) ?: @"";
    m.MobileNo  = FUString(raw[@"mobile"]) ?: FUString(raw[@"phone"]) ?: FUString(raw[@"MobileNo"]);

    // Avatar
    NSURL *photoURL = doc.photoURL ?: auth.photoURL ?: FUURL(raw[@"photoURL"]) ?: FUURL(raw[@"UserImageUrl"]);
    m.UserImageUrl  = photoURL;
    m.UserImageName = FUString(raw[@"UserImageName"]) ?: photoURL.lastPathComponent ?: @"";

    // Dates / misc
    m.loginDate = FUDate(raw[@"lastLoginAt"]) ?: FUDate(raw[@"loginDate"]);
    m.verified  = [FUNumber(raw[@"verified"]) boolValue] || auth.isEmailVerified;
    m.plan      = FUString(raw[@"plan"]);

    return m;
}

- (id<FIRListenerRegistration>)listenCombinedUser:(void(^)(UserModel * _Nullable, NSError * _Nullable))callback {
    FUCompositeRegistration *combo = [FUCompositeRegistration new];
    __weak typeof(self) weakSelf = self;
    void (^cb)(UserModel * _Nullable, NSError * _Nullable) = [callback copy];

    combo.authHandle = [[FIRAuth auth] addAuthStateDidChangeListener:^(FIRAuth * _Nonnull auth, FIRUser * _Nullable user) {
        __strong typeof(weakSelf) mgr = weakSelf;
        if (!mgr) return;

        if (!user) {
            if (combo.docReg) { [combo.docReg remove]; combo.docReg = nil; }
            if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(nil, nil); });
            return;
        }

        if (combo.docReg) { [combo.docReg remove]; combo.docReg = nil; }
        FIRDocumentReference *ref = [mgr userDocumentRefForUID:user.uid];
        combo.docReg = [ref addSnapshotListener:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) { if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(nil, error); }); return; }

            FUUserDoc *d = [FUUserDoc new];
            d.uid         = user.uid;
            d.email       = FUString(snapshot[@"email"])       ?: user.email;
            d.displayName = FUString(snapshot[@"displayName"]) ?: user.displayName;
            d.photoURL    = FUURL(snapshot[@"photoURL"])       ?: user.photoURL;
            d.raw         = snapshot.data ?: @{};

            UserModel *merged = [mgr userModelFromAuth:user doc:d];
            if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(merged, nil); });
        }];
    }];

    return combo;
}

#pragma mark - Users listing

+ (FIRQuery *)usersBaseQueryOrderedBy:(NSString * _Nullable)orderField
                            ascending:(BOOL)ascending
{
    FIRCollectionReference *col = [[FIRFirestore firestore] collectionWithPath:kFUUsersCollection];

    // Primary sort: UserName (or the provided field)
    NSString *field = orderField.length ? orderField : @"UserName";

    // Stable tiebreaker: uid (assumes it exists in each doc)
    FIRQuery *q = [col queryOrderedByField:field descending:!ascending];
    return q;
}

- (id<FIRListenerRegistration>)listenAllUsersOrderedBy:(NSString *)orderField
                                             ascending:(BOOL)ascending
                                  includeMetadataChanges:(BOOL)includeMetadata
                                                 queue:(dispatch_queue_t)callbackQueue
                                            completion:(FUUsersCompletion)completion
{
    return [self listenAllUsersWithDiffsOrderedBy:orderField
                                        ascending:ascending
                             includeMetadataChanges:includeMetadata
                                            queue:callbackQueue
                                         completion:^(NSArray<UserModel *> * _Nullable users,
                                                      NSArray<FIRDocumentChange *> * _Nullable changes,
                                                      FIRSnapshotMetadata * _Nullable metadata,
                                                      NSError * _Nullable error)
    {
        if (completion) completion(users, metadata, error);
    }];
}

- (id<FIRListenerRegistration>)listenAllUsersWithDiffsOrderedBy:(NSString *)orderField
                                                       ascending:(BOOL)ascending
                                            includeMetadataChanges:(BOOL)includeMetadata
                                                           queue:(dispatch_queue_t)callbackQueue
                                                        completion:(FUUsersDiffCompletion)completion
{
    if (!completion) return nil;

    FIRQuery *q = [self.class usersBaseQueryOrderedBy:orderField ascending:ascending];
    void (^handler)(FIRQuerySnapshot * _Nullable, NSError * _Nullable)
    = ^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) { if (completion) completion(nil, nil, nil, error); return; }
        if (!snapshot) { if (completion) completion(@[], @[], nil, nil); return; }

        // Parse models off-main
        dispatch_queue_t workQ = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_async(workQ, ^{
            NSMutableArray<UserModel *> *arr = [NSMutableArray arrayWithCapacity:snapshot.documents.count];
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                UserModel *u = [[UserModel alloc] initWithSnapshot:doc];
                if (u) [arr addObject:u];
            }
            NSArray<UserModel *> *users = arr.copy;
            NSArray<FIRDocumentChange *> *changes = snapshot.documentChanges ?: @[];

            dispatch_block_t deliver = ^{
                if (completion) completion(users, changes, snapshot.metadata, nil);
            };
            if (callbackQueue) dispatch_async(callbackQueue, deliver);
            else dispatch_async(dispatch_get_main_queue(), deliver);
        });
    };

    if (includeMetadata) {
        return [q addSnapshotListenerWithIncludeMetadataChanges:YES listener:handler];
    } else {
        return [q addSnapshotListener:handler];
    }
}

- (void)fetchAllUsersOrderedBy:(NSString *)orderField
                      ascending:(BOOL)ascending
                          queue:(dispatch_queue_t)callbackQueue
                     completion:(FUUsersCompletion)completion
{
    if (!completion) return;

    FIRQuery *q = [self.class usersBaseQueryOrderedBy:orderField ascending:ascending];
    dispatch_queue_t workQ = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

    [q getDocumentsWithCompletion:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            void (^blk)(void) = ^{ completion(nil, nil, error); };
            if (callbackQueue) dispatch_async(callbackQueue, blk);
            else dispatch_async(dispatch_get_main_queue(), blk);
            return;
        }

        dispatch_async(workQ, ^{
            NSMutableArray<UserModel *> *arr = [NSMutableArray arrayWithCapacity:snapshot.documents.count];
            for (FIRDocumentSnapshot *doc in snapshot.documents) {
                UserModel *u = [[UserModel alloc] initWithSnapshot:doc];
                if (u) [arr addObject:u];
            }
            NSArray<UserModel *> *users = arr.copy;

            dispatch_block_t deliver = ^{ completion(users, snapshot.metadata, nil); };
            if (callbackQueue) dispatch_async(callbackQueue, deliver);
            else dispatch_async(dispatch_get_main_queue(), deliver);
        });
    }];
}

#pragma mark - Auth listener (top level)

- (void)startAuthListenerWithChangeBlock:(void(^)(FIRUser * _Nullable authUser,
                                                  UserModel * _Nullable userModel))block
{
    if (self.authHandle) {
        [[FIRAuth auth] removeAuthStateDidChangeListener:self.authHandle];
        self.authHandle = 0;
    }

    __weak typeof(self) weakSelf = self;
    self.authHandle = [[FIRAuth auth] addAuthStateDidChangeListener:^(FIRAuth *auth, FIRUser * _Nullable authUser) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (!authUser) { if (block) block(nil, nil); return; }

        [[self userDocumentRefForUID:authUser.uid] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable err) {
            FUUserDoc *d = nil;
            if (snap.exists && snap.data) {
                d = [FUUserDoc new];
                d.uid         = authUser.uid;
                d.email       = FUString(snap[@"email"])       ?: authUser.email;
                d.displayName = FUString(snap[@"displayName"]) ?: authUser.displayName;
                d.photoURL    = FUURL(snap[@"photoURL"])       ?: authUser.photoURL;
                d.raw         = snap.data;
            }
            UserModel *merged = [self userModelFromAuth:authUser doc:d];
            if (block) block(authUser, merged);
        }];
    }];
}

- (void)reloadCurrentUserWithCompletion:(void(^)(UserModel * _Nullable user,
                                                 NSError * _Nullable error))completion
{
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser) { if (completion) completion(nil, nil); return; }

    [[self userDocumentRefForUID:authUser.uid] getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable err) {
        if (err) { if (completion) completion(nil, err); return; }
        FUUserDoc *d = nil;
        if (snap.exists && snap.data) {
            d = [FUUserDoc new];
            d.uid         = authUser.uid;
            d.email       = FUString(snap[@"email"])       ?: authUser.email;
            d.displayName = FUString(snap[@"displayName"]) ?: authUser.displayName;
            d.photoURL    = FUURL(snap[@"photoURL"])       ?: authUser.photoURL;
            d.raw         = snap.data;
        }
        UserModel *merged = [self userModelFromAuth:authUser doc:d];
        if (completion) completion(merged, nil);
    }];
}

- (id<FIRListenerRegistration>)listenStaffUsersWithCompletion:(void(^)(NSArray<UserModel *> * _Nullable staff, NSError * _Nullable error))completion
{
    FIRQuery *q = [[self.db collectionWithPath:kFUUsersCollection] queryWhereField:@"accountType" isEqualTo:@"staff"];
    
    return [q addSnapshotListener:^(FIRQuerySnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            if (completion) completion(nil, error);
            return;
        }
        
        NSMutableArray<UserModel *> *arr = [NSMutableArray array];
        for (FIRDocumentSnapshot *doc in snapshot.documents) {
            UserModel *u = [[UserModel alloc] initWithSnapshot:doc];
            if (u) [arr addObject:u];
        }
        if (completion) completion(arr.copy, nil);
    }];
}

#pragma mark - Arbitrary field updates

- (void)updateUserFieldsForUID:(NSString *)uid
                        fields:(NSDictionary<NSString *,id> *)fields
                    completion:(FUErrorBlock)completion
{
    if (uid.length == 0 || fields.count == 0) { if (completion) completion([self p_err:@"Invalid uid or empty fields" code:-1]); return; }

    [[[self.db collectionWithPath:kFUUsersCollection] documentWithPath:uid]
     updateData:fields
     completion:^(NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}

- (void)removeUserWithUID:(NSString *)uid
               completion:(FUErrorBlock)completion
{
    [[RPManager shared] removeUserByUID:uid completion:completion];
}

#pragma mark - Admin-side account creation (minimal write-through)


- (void)createUserWithEmail:(NSString *)email
                   password:(NSString *)password
                   username:(NSString *)username
                       role:(NSInteger)role
                permissions:(NSDictionary<NSString *, NSNumber *> *)perms
                    isAdmin:(BOOL)isAdmin
                 completion:(void(^)(NSError * _Nullable error))completion
{
    [[FIRAuth auth] createUserWithEmail:email password:password completion:^(FIRAuthDataResult * _Nullable res, NSError * _Nullable err) {
        if (err) { if (completion) completion(err); return; }

        NSString *uid = res.user.uid ?: @"";
        NSDictionary *fields = @{
            @"uid": uid,
            @"UserEmail": email ?: @"",
            @"UserName": username ?: @"",
            @"role": @(role),
            @"permissions": perms ?: @{},
            @"isAdmin": @(isAdmin),
            @"createdAt": [FIRFieldValue fieldValueForServerTimestamp],
            @"updatedAt": [FIRFieldValue fieldValueForServerTimestamp]
        };

        [[[self.db collectionWithPath:kFUUsersCollection] documentWithPath:uid]
          setData:fields merge:YES  completion:^(NSError * _Nullable e) {
            if (completion) completion(e);
        }];
    }];
}



/* ==================================================================================================================================================*/

/// Internal: write URL into Auth + Firestore
- (void)p_applyPhotoURL:(NSURL *)url
               toUserID:(NSString *)uid
             completion:(FUErrorBlock)completion
{
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser || uid.length == 0) {
        if (completion) completion([self p_err:@"No signed-in user" code:-10]);
        return;
    }

    // 1) Auth profile
    FIRUserProfileChangeRequest *req = [authUser profileChangeRequest];
    req.photoURL = url;
    [req commitChangesWithCompletion:^(__unused NSError * _Nullable e1) {
        // 2) Firestore user doc
        FIRDocumentReference *doc =
            [[[FIRFirestore firestore] collectionWithPath:kUsersCol] documentWithPath:uid];
        NSString *abs = url.absoluteString ?: @"";
        NSDictionary *fields = @{
            @"UserImageUrl": abs,
            @"photoURL": abs,
            // Optional: keep last storage path if you use upload helpers
            // @"UserImagePath": @"avatars/<uid>/<ts>.png"
        };
        [doc setData:fields merge:YES completion:^(NSError * _Nullable e2) {
            // Keep in-memory mirror if you maintain one
            self.currentUserDoc.photoURL = url;
            if (completion) completion(e1 ?: e2);
        }];
    }];
}


- (void)uploadAvatarPNGData:(NSData *)pngData
                completion:(FUURLBlock)completion
{
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser || pngData.length == 0) {
        if (completion) completion(nil, [self p_err:@"Missing user or data" code:-11]);
        return;
    }

    NSString *uid = authUser.uid;

    // Read old avatar path before uploading new one
    FIRDocumentReference *userDoc =
        [[[FIRFirestore firestore] collectionWithPath:kUsersCol] documentWithPath:uid];
    [userDoc getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable readErr) {
        NSString *oldAvatarPath = (snap.exists ? snap[@"UserImagePath"] : nil);

        NSString *file = [NSString stringWithFormat:@"avatars/%@/%lld.png",
                          uid, (long long)[NSDate date].timeIntervalSince1970];

        FIRStorageReference *ref = [[[FIRStorage storage] reference] child:file];
        FIRStorageMetadata *meta = [FIRStorageMetadata new];
        meta.contentType = @"image/png";

        [ref putData:pngData metadata:meta completion:^(__unused FIRStorageMetadata * _Nullable metadata, NSError * _Nullable putErr) {
            if (putErr) { if (completion) completion(nil, putErr); return; }

            [ref downloadURLWithCompletion:^(NSURL * _Nullable url, NSError * _Nullable urlErr) {
                if (urlErr || !url) { if (completion) completion(nil, urlErr); return; }

                // Persist the new path so we can clean up later if needed
                [userDoc setData:@{ @"UserImagePath": file } merge:YES];

                // Delete old avatar from Storage (best-effort, fire-and-forget)
                if (oldAvatarPath.length > 0 && ![oldAvatarPath isEqualToString:file]) {
                    FIRStorageReference *oldRef = [[[FIRStorage storage] reference] child:oldAvatarPath];
                    [oldRef deleteWithCompletion:^(NSError * _Nullable delErr) {
                        if (delErr) {
                            DLog(@"[Avatar] failed to delete old avatar: %@", delErr.localizedDescription);
                        } else {
                            DLog(@"[Avatar] deleted old avatar: %@", oldAvatarPath);
                        }
                    }];
                }

                // Apply URL to Auth + Firestore
                [self p_applyPhotoURL:url toUserID:uid completion:^(NSError * _Nullable e) {
                    if (completion) completion(url, e);
                }];
            }];
        }];
    }];
}

- (void)updatePhotoURL:(NSURL *)url
            completion:(FUErrorBlock)completion
{
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser || !url) {
        if (completion) completion([self p_err:@"Missing user or URL" code:-12]);
        return;
    }
    [self p_applyPhotoURL:url toUserID:authUser.uid completion:completion];
}

- (void)updatePhotoURLString:(NSString *)urlString
                  completion:(FUErrorBlock)completion
{
    NSURL *u = (urlString.length ? [NSURL URLWithString:urlString] : nil);
    [self updatePhotoURL:u completion:completion];
}

- (void)fetchCurrentUserPhotoURL:(FUURLBlock)completion
{
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser) { if (completion) completion(nil, [self p_err:@"No signed-in user" code:-13]); return; }

    if (authUser.photoURL) {
        if (completion) completion(authUser.photoURL, nil);
        return;
    }

    [self fetchPhotoURLForUID:authUser.uid completion:completion];
}

- (void)fetchCurrentUserPhotoURLString:(void(^)(NSString * _Nullable abs, NSError * _Nullable err))completion
{
    [self fetchCurrentUserPhotoURL:^(NSURL * _Nullable url, NSError * _Nullable error) {
        if (completion) completion(url.absoluteString, error);
    }];
}

- (void)fetchPhotoURLForUID:(NSString *)uid
                 completion:(FUURLBlock)completion
{
    if (uid.length == 0) {
        if (completion) completion(nil, [self p_err:@"Missing uid" code:-14]);
        return;
    }
    FIRDocumentReference *doc =
        [[[FIRFirestore firestore] collectionWithPath:kUsersCol] documentWithPath:uid];
    [doc getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable err) {
        if (err || !snap.exists) { if (completion) completion(nil, err); return; }

        NSString *abs =
            snap[@"UserImageUrl"] ?: snap[@"photoURL"]; // support either field
        NSURL *url = abs.length ? [NSURL URLWithString:abs] : nil;
        if (completion) completion(url, nil);
    }];
}

- (void)removeCurrentUserPhotoWithDeleteFromStorage:(BOOL)deleteFromStorage
                                         completion:(FUErrorBlock)completion
{
    FIRUser *authUser = [FIRAuth auth].currentUser;
    if (!authUser) { if (completion) completion([self p_err:@"No signed-in user" code:-15]); return; }

    // Try to read last stored path first (best effort)
    FIRDocumentReference *doc =
        [[[FIRFirestore firestore] collectionWithPath:kUsersCol] documentWithPath:authUser.uid];

    [doc getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snap, NSError * _Nullable err) {
        NSString *path = (snap.exists ? (snap[@"UserImagePath"] ?: @"") : @"");

        // 1) Clear Auth.photoURL
        FIRUserProfileChangeRequest *req = [authUser profileChangeRequest];
        req.photoURL = nil;
        [req commitChangesWithCompletion:^(__unused NSError * _Nullable e1) {

            // 2) Clear Firestore fields
            NSDictionary *fields = @{
                @"UserImageUrl": [NSNull null],
                @"photoURL":     [NSNull null]
            };
            [doc setData:fields merge:YES completion:^(NSError * _Nullable e2) {

                // 3) Optionally delete last stored object
                if (deleteFromStorage && path.length) {
                    FIRStorageReference *ref = [[[FIRStorage storage] reference] child:path];
                    [ref deleteWithCompletion:^(__unused NSError * _Nullable e3) {
                        if (completion) completion(e1 ?: e2 ?: e3);
                    }];
                } else {
                    if (completion) completion(e1 ?: e2);
                }
            }];
        }];
    }];
}

- (void)updatePhotoImage:(UIImage *)image
         maxDimension_px:(NSUInteger)maxDim
                maxBytes:(NSUInteger)maxBytes
                progress:(FUProgressBlock)progress
              completion:(FUURLBlock)completion
{
    FIRUser *user = [FIRAuth auth].currentUser;
    if (!user) { if (completion) completion(nil, [self p_err:@"No auth user" code:-1]); return; }

    // 1) scale + compress (sync, quick)
    UIImage *scaled = [self p_scaleImage:image maxDimension:maxDim];
    NSData  *png    = [self p_pngDataForImage:scaled targetMaxBytes:maxBytes];
    if (!png) { if (completion) completion(nil, [self p_err:@"Encoding failed" code:-2]); return; }

    // 2) storage path
    NSString *path = [NSString stringWithFormat:@"users/%@/avatar.png", user.uid];
    FIRStorageReference *ref = [[self.storage reference] child:path];

    // 3) upload with progress
    FIRStorageUploadTask *task = [ref putData:png metadata:nil];

    // progress
    [task observeStatus:FIRStorageTaskStatusProgress handler:^(FIRStorageTaskSnapshot * _Nonnull snapshot) {
        if (progress && snapshot.progress.totalUnitCount > 0) {
            double frac = (double)snapshot.progress.completedUnitCount / (double)snapshot.progress.totalUnitCount;
            dispatch_async(dispatch_get_main_queue(), ^{ progress(frac); });
        }
    }];

    // success
    __weak typeof(self) weakSelf = self;
    [task observeStatus:FIRStorageTaskStatusSuccess handler:^(__unused FIRStorageTaskSnapshot * _Nonnull s) {
        [ref downloadURLWithCompletion:^(NSURL * _Nullable url, NSError * _Nullable err) {
            if (err || !url) { if (completion) completion(nil, err ?: [weakSelf p_err:@"No URL" code:-3]); return; }

            // update Auth profile + UsersCol doc
            [weakSelf p_applyDisplayName:nil photoURL:url toUser:user completion:^(__unused NSError * _Nullable e1) {
                NSDictionary *fields = @{@"UserImageUrl": url.absoluteString ?: @"",
                                         @"photoURL"    : url.absoluteString ?: @""};
                [weakSelf updateUserDocumentFields:fields completion:^(__unused NSError * _Nullable e2) {
                    if (completion) completion(url, nil);
                }];
            }];
        }];
    }];

    // failure
    [task observeStatus:FIRStorageTaskStatusFailure handler:^(FIRStorageTaskSnapshot * _Nonnull snap) {
        if (completion) completion(nil, snap.error ?: [self p_err:@"Upload failed" code:-4]);
    }];
}


@end
