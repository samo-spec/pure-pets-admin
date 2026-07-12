//
//  PPVetModel.m
//  PurePetsAdmin
//

#import "PPVetModel.h"

@implementation PPVetModel

#pragma mark - Derived

- (NSString *)name_lowercase {
    return self.title.lowercaseString ?: @"";
}

#pragma mark - Serialization

- (NSDictionary *)toDictionary {
    NSString *safeTitle = self.title ?: @"";
    NSMutableDictionary *dict = [@{
        @"type":            @(self.type),
        @"userID":          self.userID ?: @"",
        @"petMainKindID":   @(self.petMainKindID),
        @"logoURL":         self.logoURL ?: @"",
        @"title":           safeTitle,
        @"name_lowercase":  safeTitle.lowercaseString,
        @"descriptionText": self.descriptionText ?: @"",
        @"phone":           self.phone ?: @"",
        @"whatsapp":        self.whatsapp ?: @"",
        @"blurHash":        self.blurHash ?: @"",
        @"availableDate":   self.availableDate ?: [NSNull null],
        @"vetCost":         @(self.vetCost),
        @"isDisabled":      @(self.isDisabled),
        @"subscriptionTier":      @(self.subscriptionTier),
        @"subscriptionActive":    @(self.subscriptionActive),
        @"subscriptionStartDate": self.subscriptionStartDate ?: [NSNull null],
        @"subscriptionEndDate":   self.subscriptionEndDate   ?: [NSNull null],
    } mutableCopy];

    if (self.createdAt) {
        dict[@"createdAt"] = self.createdAt;
    }
    dict[@"updatedAt"] = [NSDate date];

    return [dict copy];
}

+ (instancetype)fromDictionary:(NSDictionary *)dict withID:(NSString *)vetID {
    PPVetModel *m = [[PPVetModel alloc] init];
    m.vetID           = vetID ?: @"";
    m.type            = [dict[@"type"] integerValue];
    m.userID          = dict[@"userID"] ?: @"";
    m.petMainKindID   = [dict[@"petMainKindID"] integerValue];
    m.logoURL         = dict[@"logoURL"] ?: @"";
    m.title           = dict[@"title"] ?: @"";
    m.descriptionText = dict[@"descriptionText"] ?: @"";
    m.phone           = dict[@"phone"] ?: @"";
    m.whatsapp        = dict[@"whatsapp"] ?: @"";
    m.blurHash        = dict[@"blurHash"] ?: @"";
    m.vetCost         = [dict[@"vetCost"] doubleValue];

    // Dates — handle both FIRTimestamp and NSDate
    m.availableDate         = [self dateFromValue:dict[@"availableDate"]];
    m.createdAt             = [self dateFromValue:dict[@"createdAt"]];
    m.updatedAt             = [self dateFromValue:dict[@"updatedAt"]];
    m.subscriptionStartDate = [self dateFromValue:dict[@"subscriptionStartDate"]];
    m.subscriptionEndDate   = [self dateFromValue:dict[@"subscriptionEndDate"]];

    // Admin
    m.isDisabled        = [dict[@"isDisabled"] boolValue];
    m.subscriptionTier  = [dict[@"subscriptionTier"] integerValue];
    m.subscriptionActive = [dict[@"subscriptionActive"] boolValue];

    return m;
}

#pragma mark - Helpers

+ (nullable NSDate *)dateFromValue:(id)value {
    if (!value || [value isKindOfClass:[NSNull class]]) return nil;
    if ([value isKindOfClass:[NSDate class]]) return value;
    // FIRTimestamp
    if ([value respondsToSelector:@selector(dateValue)]) return [value dateValue];
    return nil;
}

- (NSString *)localizedTypeName {
    switch (self.type) {
        case PPVetTypePersonal: return kLang(@"Vet_Type_Personal");
        case PPVetTypeCompany:  return kLang(@"Vet_Type_Company");
        default:                return @"";
    }
}

- (NSString *)localizedSubscriptionTierName {
    switch (self.subscriptionTier) {
        case PPVetSubscriptionFree:    return kLang(@"Vet_Sub_Free");
        case PPVetSubscriptionBasic:   return kLang(@"Vet_Sub_Basic");
        case PPVetSubscriptionPremium: return kLang(@"Vet_Sub_Premium");
        default:                       return @"";
    }
}

- (BOOL)isSubscriptionExpired {
    if (!self.subscriptionEndDate) return NO;
    return [self.subscriptionEndDate compare:[NSDate date]] == NSOrderedAscending;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    PPVetModel *copy = [[PPVetModel allocWithZone:zone] init];
    copy.vetID           = self.vetID;
    copy.type            = self.type;
    copy.userID          = self.userID;
    copy.petMainKindID   = self.petMainKindID;
    copy.logoURL         = self.logoURL;
    copy.title           = self.title;
    copy.descriptionText = self.descriptionText;
    copy.phone           = self.phone;
    copy.whatsapp        = self.whatsapp;
    copy.blurHash        = self.blurHash;
    copy.availableDate   = self.availableDate;
    copy.vetCost         = self.vetCost;
    copy.isDisabled      = self.isDisabled;
    copy.subscriptionTier    = self.subscriptionTier;
    copy.subscriptionStartDate = self.subscriptionStartDate;
    copy.subscriptionEndDate   = self.subscriptionEndDate;
    copy.subscriptionActive    = self.subscriptionActive;
    copy.createdAt       = self.createdAt;
    copy.updatedAt       = self.updatedAt;
    return copy;
}

@end
