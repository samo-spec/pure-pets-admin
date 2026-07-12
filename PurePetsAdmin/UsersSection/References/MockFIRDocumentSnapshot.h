//
//  UserModelTests.m
//  PurePetsAdminTests
//
//  Created by Mohammed Ahmed on 14/09/2025.
//

#import <XCTest/XCTest.h>
#import "UserModel.h"

#pragma mark - Mock Firestore

@interface MockFIRDocumentSnapshot : NSObject
@property (nonatomic, assign) BOOL exists;
@property (nonatomic, strong) NSString *documentID;
@property (nonatomic, strong) NSDictionary *data;
@end

@implementation MockFIRDocumentSnapshot
@end

#pragma mark - Mock Firebase Auth

@interface MockFIRUser : NSObject
@property (nonatomic, strong) NSString *uid;
@property (nonatomic, strong) NSString *email;
@property (nonatomic, strong) NSString *displayName;
@property (nonatomic, strong) NSURL *photoURL;
@end

@implementation MockFIRUser
@end

#pragma mark - UserModelTests

@interface UserModelTests : XCTestCase
@property (nonatomic, strong) NSDictionary *mockDict;
@end

@implementation UserModelTests

- (void)setUp {
    [super setUp];
    self.mockDict = @{
        @"ID": @"123",
        @"uid": @"abc-uid",
        @"UserName": @"testuser",
        @"FirstName": @"John",
        @"LastName": @"Doe",
        @"MobileNo": @"123456789",
        @"UserEmail": @"john@example.com",
        @"UserImageName": @"avatar.png",
        @"UserAbout": @"About me",
        @"UserImageUrl": @"https://example.com/img.png",
        @"loginDate": @([NSDate date].timeIntervalSince1970 * 1000),
        @"updatedAt": @([NSDate date].timeIntervalSince1970 * 1000),
        @"CountryID": @(44),
        @"PPUserTokenID": @"device-xyz",
        @"isAdmin": @YES,
        @"isSuperAdmin": @NO,
        @"isBlocked": @NO,
        @"role": @(2),
        @"verified": @YES,
        @"plan": @"premium",
        @"loginSource": @(UserLoginSourcePPAdmin),
        @"displayName": @"Test User",
        @"email": @"test@example.com",
        @"photoURL": @"https://example.com/avatar.jpg",
        @"permissions": @{ @"canPostAds": @YES, @"canSellUsed": @NO }
    };
}

#pragma mark - Init & Dict Conversion

- (void)testInitWithDict {
    UserModel *u = [[UserModel alloc] initWithDict:self.mockDict];
    XCTAssertNotNil(u);
    XCTAssertEqualObjects(u.uid, @"abc-uid");
    XCTAssertEqualObjects(u.UserName, @"testuser");
    XCTAssertEqual(u.role, 2);
    XCTAssertTrue(u.verified);
}

- (void)testToDictionarySymmetry {
    UserModel *u = [[UserModel alloc] initWithDict:self.mockDict];
    NSDictionary *dict = [u toDictionary];
    XCTAssertEqualObjects(dict[@"uid"], @"abc-uid");
    XCTAssertEqualObjects(dict[@"UserName"], @"testuser");
    XCTAssertEqualObjects(dict[@"plan"], @"premium");
}

#pragma mark - NSSecureCoding

- (void)testEncodingDecoding {
    UserModel *u = [[UserModel alloc] initWithDict:self.mockDict];
    NSData *archived = [NSKeyedArchiver archivedDataWithRootObject:u
                                           requiringSecureCoding:YES
                                                           error:nil];
    XCTAssertNotNil(archived);

    UserModel *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:UserModel.class
                                                           fromData:archived
                                                              error:nil];
    XCTAssertNotNil(decoded);
    XCTAssertEqualObjects(decoded.uid, u.uid);
    XCTAssertEqualObjects(decoded.UserName, u.UserName);
}

#pragma mark - Permissions

- (void)testPermissionChecking {
    UserModel *u = [[UserModel alloc] initWithDict:self.mockDict];
    XCTAssertTrue([u hasPermissionNamed:@"canPostAds"]);
    XCTAssertFalse([u hasPermissionNamed:@"canSellUsed"]);
}

#pragma mark - Convenience

- (void)testFormDisplayText {
    UserModel *u = [[UserModel alloc] initWithDict:self.mockDict];
    NSString *displayText = [u formDisplayText];
    XCTAssertTrue(displayText.length > 0);
}

#pragma mark - Firestore Snapshot

- (void)testInitWithSnapshot {
    MockFIRDocumentSnapshot *snap = [MockFIRDocumentSnapshot new];
    snap.exists = YES;
    snap.documentID = @"snap-uid";
    snap.data = self.mockDict;

    UserModel *u = [[UserModel alloc] initWithSnapshot:(id)snap];
    XCTAssertNotNil(u);
    XCTAssertEqualObjects(u.uid, @"snap-uid");
}

#pragma mark - From Auth User

- (void)testFromAuthUser {
    MockFIRUser *auth = [MockFIRUser new];
    auth.uid = @"auth-uid";
    auth.email = @"auth@example.com";
    auth.displayName = @"Auth Name";
    auth.photoURL = [NSURL URLWithString:@"https://example.com/pic.jpg"];

    NSDictionary *root = @{@"FirstName": @"Alice", @"plan": @"gold"};
    NSDictionary *perms = @{@"canAdoption": @YES};
    NSDictionary *claims = @{@"isAdmin": @YES};

    UserModel *u = [UserModel fromAuthUser:(id)auth
                                   rootDoc:root
                               permissions:perms
                                    claims:claims];
    XCTAssertNotNil(u);
    XCTAssertEqualObjects(u.uid, @"auth-uid");
    XCTAssertTrue(u.isAdmin);
    XCTAssertEqualObjects(u.FirstName, @"Alice");
    XCTAssertEqualObjects(u.plan, @"gold");
    XCTAssertTrue([u hasPermissionNamed:@"canAdoption"]);
}

@end
