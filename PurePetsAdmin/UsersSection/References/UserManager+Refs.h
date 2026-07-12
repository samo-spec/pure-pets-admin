//
//  UserManager 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// UserManager+Refs.h
#import "UserManager.h"

@class FIRCollectionReference;

@interface UserManager (Refs)
+ (nullable FIRCollectionReference *)inboxRefForUID:(NSString * _Nullable)uid;
+ (nullable FIRCollectionReference *)inboxRefForCurrentUser;
@end
