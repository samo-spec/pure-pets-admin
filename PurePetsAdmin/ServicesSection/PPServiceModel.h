//
//  PPServiceModel.h
//  PurePetsAdmin
//
//  Mirrors the iOS ServiceModel contract and safely preserves unknown future
//  fields so Admin can manage current and upcoming service metadata without
//  dropping data written by other apps.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPServiceType) {
    PPServiceTypeTraining = 0,
    PPServiceTypeGrooming = 1
};

@interface PPServiceModel : NSObject <NSCopying>

// Source-of-truth fields from iOS ServiceModel.
@property (nonatomic, copy) NSString *serviceID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *serviceDescriptionText;
@property (nonatomic, assign) double price;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *categoryID;
@property (nonatomic, assign) NSInteger petMainKindID;
@property (nonatomic, strong, nullable) NSDate *availableDate;
@property (nonatomic, strong, nullable) NSDate *timestamp;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic, copy) NSString *serviceOwnerID;
@property (nonatomic, assign) PPServiceType type;
@property (nonatomic, copy) NSString *blurHash;
@property (nonatomic, copy, readonly) NSString *searchTitle;

// Admin extensions.
@property (nonatomic, assign) BOOL isDisabled;
@property (nonatomic, assign) BOOL isBlocked;
@property (nonatomic, assign) BOOL isDeleted;
@property (nonatomic, copy) NSString *verificationStatus;
@property (nonatomic, copy) NSString *subscriptionType;
@property (nonatomic, copy) NSString *subscriptionPlan;
@property (nonatomic, copy) NSString *subscriptionStatus;
@property (nonatomic, assign) BOOL subscriptionActive;
@property (nonatomic, strong, nullable) NSDate *subscriptionStartDate;
@property (nonatomic, strong, nullable) NSDate *subscriptionEndDate;
@property (nonatomic, copy) NSDictionary<NSString *, id> *serviceFlags;
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *updatedAt;
@property (nonatomic, strong, nullable) NSDate *archivedAt;
@property (nonatomic, copy) NSString *archivedBy;
@property (nonatomic, copy) NSString *blockedBy;
@property (nonatomic, copy) NSString *disabledBy;

// Preserved unknown top-level fields for future compatibility.
@property (nonatomic, copy) NSDictionary<NSString *, id> *extraFields;

+ (instancetype)fromDictionary:(NSDictionary *)dictionary withID:(NSString *)serviceID;
- (NSDictionary *)toDictionary;

- (NSString *)localizedTypeName;
- (NSString *)localizedPrimaryStatusTitle;
- (NSString *)localizedVerificationTitle;
- (NSString *)localizedSubscriptionSummary;
- (BOOL)isLive;
- (BOOL)isSubscriptionExpired;

@end

NS_ASSUME_NONNULL_END
