//
//  AnimalKindsClass.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "subKindItemsModel.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import <Firebase.h>
@implementation subKindItemsModel
- (instancetype)initWithDict:(NSDictionary *)dict{
    self = [super init];
    if (self) {
        self.ID = [dict[@"ID"] integerValue];
        self.subSubKindID = [dict[@"subSubKindID"] integerValue];
        self.itemNameAr = dict[@"itemNameAr"];
        self.itemNameAr = dict[@"itemNameAr"];
        self.itemNameEn = dict[@"itemNameEn"];
        self.Male = dict[@"Male"];
        self.Female = dict[@"Female"];
    }
    return self;
}

- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot {
    self = [super init];
    if (self) {
        self.ID = [snapshot.data[@"ID"] integerValue];
        self.subSubKindID = [snapshot.data[@"subSubKindID"] integerValue];
        self.itemNameAr = snapshot.data[@"itemNameAr"];
        self.itemNameAr = snapshot.data[@"itemNameAr"];
        self.itemNameEn = snapshot.data[@"itemNameEn"];
        self.Male = snapshot.data[@"Male"];
        self.Female = snapshot.data[@"Female"];
    }
    return self;
}

#pragma mark - To Dictionary
- (NSDictionary *)toDict {
    return @{
        @"ID": @(self.ID),
        @"subSubKindID": @(self.subSubKindID),
        @"itemNameAr": self.itemNameAr ?: @"",
        @"itemNameEn": self.itemNameEn ?: @"",
        @"Male": self.Male ?: @"",
        @"Female": self.Female ?: @""
    };
}

- (nonnull NSString *)formDisplayText { 
    return  [Language languageVal] == 0 ? self.itemNameEn : self.itemNameAr;
}

- (nonnull id)formValue { 
    return self;
}

@end
