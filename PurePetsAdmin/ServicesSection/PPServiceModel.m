//
//  PPServiceModel.m
//  PurePetsAdmin
//

#import "PPServiceModel.h"
#import "ArabicNormalizer.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;

@interface PPServiceModel ()
@property (nonatomic, copy) NSString *searchTitle;
@end

@implementation PPServiceModel

#pragma mark - Factory

+ (instancetype)fromDictionary:(NSDictionary *)dictionary withID:(NSString *)serviceID {
    PPServiceModel *model = [[PPServiceModel alloc] init];
    NSDictionary *safeDict = PPSafeDict(dictionary);

    model.serviceID = PPSafeString(serviceID);
    model.title = PPSafeString(safeDict[@"title"]);
    model.searchTitle = PPSafeString(safeDict[@"searchTitle"]);
    model.serviceDescriptionText = PPSafeString(safeDict[@"description"]);
    model.price = [safeDict[@"price"] respondsToSelector:@selector(doubleValue)] ? [safeDict[@"price"] doubleValue] : 0.0;
    model.category = PPSafeString(safeDict[@"category"]);
    model.categoryID = PPSafeString(safeDict[@"categoryID"]);
    model.petMainKindID = [safeDict[@"petMainKindID"] respondsToSelector:@selector(integerValue)] ? [safeDict[@"petMainKindID"] integerValue] : 0;
    model.availableDate = [self pp_dateFromValue:safeDict[@"availableDate"]];
    model.timestamp = [self pp_dateFromValue:safeDict[@"timestamp"]];
    model.imageURL = PPSafeString(safeDict[@"imageURL"]);
    model.serviceOwnerID = PPSafeString(safeDict[@"serviceOwnerID"]);
    model.type = [safeDict[@"type"] respondsToSelector:@selector(integerValue)] ? [safeDict[@"type"] integerValue] : PPServiceTypeTraining;
    model.blurHash = PPSafeString(safeDict[@"blurHash"]);

    model.isDisabled = [safeDict[@"isDisabled"] boolValue];
    model.isBlocked = [safeDict[@"isBlocked"] boolValue];
    model.isDeleted = [safeDict[@"isDeleted"] boolValue];
    model.verificationStatus = PPSafeString(safeDict[@"verificationStatus"]);
    model.subscriptionType = PPSafeString(safeDict[@"subscriptionType"]);
    model.subscriptionPlan = PPSafeString(safeDict[@"subscriptionPlan"]);
    model.subscriptionStatus = PPSafeString(safeDict[@"subscriptionStatus"]);
    model.subscriptionActive = [safeDict[@"subscriptionActive"] boolValue];
    model.subscriptionStartDate = [self pp_dateFromValue:safeDict[@"subscriptionStartDate"]];
    model.subscriptionEndDate = [self pp_dateFromValue:safeDict[@"subscriptionEndDate"]];
    model.serviceFlags = [safeDict[@"serviceFlags"] isKindOfClass:NSDictionary.class] ? safeDict[@"serviceFlags"] : @{};
    model.createdAt = [self pp_dateFromValue:safeDict[@"createdAt"]];
    model.updatedAt = [self pp_dateFromValue:safeDict[@"updatedAt"]];
    model.archivedAt = [self pp_dateFromValue:safeDict[@"archivedAt"]];
    model.archivedBy = PPSafeString(safeDict[@"archivedBy"]);
    model.blockedBy = PPSafeString(safeDict[@"blockedBy"]);
    model.disabledBy = PPSafeString(safeDict[@"disabledBy"]);

    NSMutableDictionary *extras = [safeDict mutableCopy];
    [extras removeObjectsForKeys:[self pp_knownFieldKeys]];
    model.extraFields = extras.copy ?: @{};

    return model;
}

#pragma mark - Serialization

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    NSMutableDictionary *extras = [PPSafeDict(self.extraFields) mutableCopy];
    [extras removeObjectsForKeys:[self.class pp_knownFieldKeys]];
    [dictionary addEntriesFromDictionary:extras];

    dictionary[@"title"] = PPSafeString(self.title);
    dictionary[@"searchTitle"] = self.searchTitle ?: @"";
    dictionary[@"description"] = PPSafeString(self.serviceDescriptionText);
    dictionary[@"price"] = @(self.price);
    dictionary[@"category"] = PPSafeString(self.category);
    dictionary[@"categoryID"] = PPSafeString(self.categoryID);
    dictionary[@"petMainKindID"] = @(self.petMainKindID);
    dictionary[@"availableDate"] = self.availableDate ?: [NSNull null];
    dictionary[@"timestamp"] = self.timestamp ?: [NSDate date];
    dictionary[@"imageURL"] = PPSafeString(self.imageURL);
    dictionary[@"serviceOwnerID"] = PPSafeString(self.serviceOwnerID);
    dictionary[@"type"] = @(self.type);
    dictionary[@"blurHash"] = PPSafeString(self.blurHash);

    dictionary[@"isDisabled"] = @(self.isDisabled);
    dictionary[@"isBlocked"] = @(self.isBlocked);
    dictionary[@"isDeleted"] = @(self.isDeleted);
    dictionary[@"verificationStatus"] = PPSafeString(self.verificationStatus);
    dictionary[@"subscriptionType"] = PPSafeString(self.subscriptionType);
    dictionary[@"subscriptionPlan"] = PPSafeString(self.subscriptionPlan);
    dictionary[@"subscriptionStatus"] = PPSafeString(self.subscriptionStatus);
    dictionary[@"subscriptionActive"] = @(self.subscriptionActive);
    dictionary[@"subscriptionStartDate"] = self.subscriptionStartDate ?: [NSNull null];
    dictionary[@"subscriptionEndDate"] = self.subscriptionEndDate ?: [NSNull null];
    dictionary[@"serviceFlags"] = PPSafeDict(self.serviceFlags);

    if (self.createdAt) {
        dictionary[@"createdAt"] = self.createdAt;
    }
    if (self.updatedAt) {
        dictionary[@"updatedAt"] = self.updatedAt;
    }
    if (self.archivedAt) {
        dictionary[@"archivedAt"] = self.archivedAt;
    }
    if (self.archivedBy.length > 0) {
        dictionary[@"archivedBy"] = self.archivedBy;
    }
    if (self.blockedBy.length > 0) {
        dictionary[@"blockedBy"] = self.blockedBy;
    }
    if (self.disabledBy.length > 0) {
        dictionary[@"disabledBy"] = self.disabledBy;
    }

    return dictionary.copy;
}

#pragma mark - Derived

- (NSString *)searchTitle {
    if (_searchTitle.length > 0) {
        return _searchTitle;
    }
    return [ArabicNormalizer normalize:self.title ?: @""];
}

- (NSString *)localizedTypeName {
    switch (self.type) {
        case PPServiceTypeTraining:
            return kLang(@"Service_Type_Training");
        case PPServiceTypeGrooming:
            return kLang(@"Service_Type_Grooming");
        default:
            return [NSString stringWithFormat:@"%@ #%ld", kLang(@"Service_Field_Type"), (long)self.type];
    }
}

- (NSString *)localizedPrimaryStatusTitle {
    if (self.isDeleted) {
        return kLang(@"Service_Status_Archived");
    }
    if (self.isBlocked) {
        return kLang(@"Service_Status_Blocked");
    }
    if (self.isDisabled) {
        return kLang(@"Service_Status_Disabled");
    }
    return kLang(@"Service_Status_Active");
}

- (NSString *)localizedVerificationTitle {
    NSString *normalized = [self pp_normalizedVerificationStatus];
    if (normalized.length == 0) {
        return kLang(@"Service_Verification_NotSet");
    }
    if ([normalized isEqualToString:@"verified"]) {
        return kLang(@"Service_Verification_Verified");
    }
    if ([normalized isEqualToString:@"pending"] ||
        [normalized isEqualToString:@"pending_review"] ||
        [normalized isEqualToString:@"verification_pending"]) {
        return kLang(@"Service_Verification_Pending");
    }
    if ([normalized isEqualToString:@"rejected"] || [normalized isEqualToString:@"blocked"]) {
        return kLang(@"Service_Verification_Rejected");
    }
    if ([normalized isEqualToString:@"unverified"]) {
        return kLang(@"Service_Verification_Unverified");
    }
    return self.verificationStatus;
}

- (NSString *)localizedSubscriptionSummary {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *plan = PPSafeString(self.subscriptionPlan);
    NSString *status = PPSafeString(self.subscriptionStatus);
    NSString *type = PPSafeString(self.subscriptionType);

    if (plan.length > 0) {
        [parts addObject:plan];
    }
    if (status.length > 0) {
        [parts addObject:status];
    }
    if (parts.count == 0 && type.length > 0) {
        [parts addObject:type];
    }
    if (parts.count == 0) {
        [parts addObject:(self.subscriptionActive ? kLang(@"Service_Subscription_Active") : kLang(@"Service_Subscription_None"))];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (BOOL)isLive {
    return !self.isDeleted && !self.isBlocked && !self.isDisabled;
}

- (BOOL)isSubscriptionExpired {
    if (!self.subscriptionEndDate) {
        return NO;
    }
    return [self.subscriptionEndDate compare:[NSDate date]] == NSOrderedAscending;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    PPServiceModel *copy = [[PPServiceModel allocWithZone:zone] init];
    copy.serviceID = self.serviceID;
    copy.title = self.title;
    copy.serviceDescriptionText = self.serviceDescriptionText;
    copy.price = self.price;
    copy.category = self.category;
    copy.categoryID = self.categoryID;
    copy.petMainKindID = self.petMainKindID;
    copy.availableDate = self.availableDate;
    copy.timestamp = self.timestamp;
    copy.imageURL = self.imageURL;
    copy.serviceOwnerID = self.serviceOwnerID;
    copy.type = self.type;
    copy.blurHash = self.blurHash;
    copy.searchTitle = self.searchTitle;
    copy.isDisabled = self.isDisabled;
    copy.isBlocked = self.isBlocked;
    copy.isDeleted = self.isDeleted;
    copy.verificationStatus = self.verificationStatus;
    copy.subscriptionType = self.subscriptionType;
    copy.subscriptionPlan = self.subscriptionPlan;
    copy.subscriptionStatus = self.subscriptionStatus;
    copy.subscriptionActive = self.subscriptionActive;
    copy.subscriptionStartDate = self.subscriptionStartDate;
    copy.subscriptionEndDate = self.subscriptionEndDate;
    copy.serviceFlags = self.serviceFlags ?: @{};
    copy.createdAt = self.createdAt;
    copy.updatedAt = self.updatedAt;
    copy.archivedAt = self.archivedAt;
    copy.archivedBy = self.archivedBy;
    copy.blockedBy = self.blockedBy;
    copy.disabledBy = self.disabledBy;
    copy.extraFields = self.extraFields ?: @{};
    return copy;
}

#pragma mark - Private

- (NSString *)pp_normalizedVerificationStatus {
    return [[PPSafeString(self.verificationStatus) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

+ (NSDate *)pp_dateFromValue:(id)value {
    if ([value isKindOfClass:NSDate.class]) {
        return value;
    }
    if ([value isKindOfClass:FIRTimestamp.class]) {
        return ((FIRTimestamp *)value).dateValue;
    }
    if ([value respondsToSelector:@selector(dateValue)]) {
        return [value dateValue];
    }
    return nil;
}

+ (NSArray<NSString *> *)pp_knownFieldKeys {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            @"title",
            @"searchTitle",
            @"description",
            @"price",
            @"category",
            @"categoryID",
            @"petMainKindID",
            @"availableDate",
            @"timestamp",
            @"imageURL",
            @"serviceOwnerID",
            @"type",
            @"blurHash",
            @"isDisabled",
            @"isBlocked",
            @"isDeleted",
            @"verificationStatus",
            @"subscriptionType",
            @"subscriptionPlan",
            @"subscriptionStatus",
            @"subscriptionActive",
            @"subscriptionStartDate",
            @"subscriptionEndDate",
            @"serviceFlags",
            @"createdAt",
            @"updatedAt",
            @"archivedAt",
            @"archivedBy",
            @"blockedBy",
            @"disabledBy"
        ];
    });
    return keys;
}

@end
