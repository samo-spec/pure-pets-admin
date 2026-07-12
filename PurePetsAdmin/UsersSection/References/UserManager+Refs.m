//
//  UserManager 2.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// UserManager+Refs.m
#import "UserManager+Refs.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "FirebaseAuth/FIRAuth.h"
@import Firebase;
@import FirebaseAuth;
@implementation UserManager (Refs)

+ (nullable FIRCollectionReference *)inboxRefForUID:(NSString * _Nullable)uid {
    // Trim & validate
    NSString *safeUID = [uid isKindOfClass:NSString.class] ? [uid stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    if (safeUID.length == 0) {
        DLog(@"❌ inboxRefForUID: UID is nil/empty");
        return nil;
    }
    FIRFirestore *db = [FIRFirestore firestore];
    return [[[db collectionWithPath:@"UsersCol"]
              documentWithPath:safeUID]
             collectionWithPath:@"inbox"]; // (retain only if ARC is off)
}

+ (nullable FIRCollectionReference *)inboxRefForCurrentUser {
    NSString *uid = [FIRAuth auth].currentUser.uid;
    if (uid.length == 0) {
        DLog(@"❌ inboxRefForCurrentUser: not signed in");
        return nil;
    }
    return [self inboxRefForUID:uid];
}

@end
