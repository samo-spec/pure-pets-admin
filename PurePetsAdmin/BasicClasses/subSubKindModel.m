//
//  AnimalKindsClass.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "subSubKindModel.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import <Firebase.h>
@implementation subSubKindModel

- (instancetype)initWithDict:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        self.ID        = [dict[@"ID"] integerValue];
        self.subKindID = [dict[@"subKindID"] integerValue];
        self.nameAr    = dict[@"nameAr"] ?: @"";
        self.nameEn    = dict[@"nameEn"] ?: @"";

        self.subKindItemsArray = [[NSMutableArray alloc] init];
        NSArray *arr = dict[@"subKindItemsArray"];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *itemDict in arr) {
                if ([itemDict isKindOfClass:[NSDictionary class]]) {
                    subKindItemsModel *item = [[subKindItemsModel alloc] initWithDict:itemDict];
                    [self.subKindItemsArray addObject:item];
                }
            }
        }
    }
    return self;
}

- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot {
    self = [super init];
    if (self) {
        NSDictionary *d = snapshot.data ?: @{};
        self.ID        = [d[@"ID"] integerValue];
        self.subKindID = [d[@"subKindID"] integerValue];
        self.nameAr    = d[@"nameAr"] ?: @"";
        self.nameEn    = d[@"nameEn"] ?: @"";

        // optional: load items if you store them in the same doc
        self.subKindItemsArray = [[NSMutableArray alloc] init];
        NSArray *arr = d[@"subKindItemsArray"];
        if ([arr isKindOfClass:[NSArray class]]) {
            for (NSDictionary *itemDict in arr) {
                if ([itemDict isKindOfClass:[NSDictionary class]]) {
                    subKindItemsModel *item = [[subKindItemsModel alloc] initWithDict:itemDict];
                    [self.subKindItemsArray addObject:item];
                }
            }
        }
    }
    return self;
}

#pragma mark - To Dictionary

- (NSDictionary *)toDict {
    NSMutableArray *itemsOut = [NSMutableArray array];
    for (subKindItemsModel *item in self.subKindItemsArray) {
        if ([item respondsToSelector:@selector(toDict)]) {
            [itemsOut addObject:[item toDict]];
        }
    }

    return @{
        @"ID": @(self.ID),
        @"subKindID": @(self.subKindID),
        @"nameAr": self.nameAr ?: @"",
        @"nameEn": self.nameEn ?: @"",
        @"subKindItemsArray": itemsOut
    };
}

#pragma mark - XLForm (if you use it)

- (NSString *)formDisplayText {
    return [Language languageVal] == 0 ? self.nameEn : self.nameAr;
}

- (id)formValue {
    return self;
}

@end
