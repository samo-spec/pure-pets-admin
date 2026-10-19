//
//  PPVetModel.h
//  PurePetsAdmin
//
//  Veterinarian model — mirrors iOS VetModel fields exactly.
//  Firestore collection: "veterinarians"
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPVetType) {
    PPVetTypePersonal = 0,
    PPVetTypeCompany  = 1
};

typedef NS_ENUM(NSInteger, PPVetSubscriptionTier) {
    PPVetSubscriptionFree    = 0,
    PPVetSubscriptionBasic   = 1,
    PPVetSubscriptionPremium = 2
};

@interface PPVetModel : NSObject <NSCopying>

// ── Core (mirrored from iOS VetModel) ──
@property (nonatomic, copy)   NSString *vetID;
@property (nonatomic, assign) PPVetType type;
@property (nonatomic, copy)   NSString *userID;
@property (nonatomic, assign) NSInteger petMainKindID;
@property (nonatomic, copy, nullable) NSString *logoURL;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *descriptionText;
@property (nonatomic, copy, nullable) NSString *phone;
@property (nonatomic, copy, nullable) NSString *whatsapp;
@property (nonatomic, copy, nullable) NSString *blurHash;
@property (nonatomic, strong, nullable) NSDate *availableDate;
@property (nonatomic, assign) double vetCost;
@property (nonatomic, readonly) NSString *name_lowercase;

// ── Admin extensions ──
@property (nonatomic, assign) BOOL isDisabled;
@property (nonatomic, assign) PPVetSubscriptionTier subscriptionTier;
@property (nonatomic, strong, nullable) NSDate *subscriptionStartDate;
@property (nonatomic, strong, nullable) NSDate *subscriptionEndDate;
@property (nonatomic, assign) BOOL subscriptionActive;
@property (nonatomic, strong, nullable) NSDate *createdAt;
@property (nonatomic, strong, nullable) NSDate *updatedAt;

// ── Geographic Coverage & Specializations ──
@property (nonatomic, copy, nullable) NSString *cityID;
@property (nonatomic, copy, nullable) NSString *cityName;
@property (nonatomic, copy, nullable) NSArray<NSString *> *workingAreas;
@property (nonatomic, copy, nullable) NSArray<NSString *> *animalTypes;
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *supportedKindIDs;
@property (nonatomic, copy, nullable) NSString *address;
@property (nonatomic, copy, nullable) NSString *licenseNumber;
@property (nonatomic, copy, nullable) NSString *workingHours;
@property (nonatomic, assign) BOOL emergency247;
@property (nonatomic, assign) BOOL homeVisitAvailable;
@property (nonatomic, assign) BOOL readyToContact;

// ── Serialization ──
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict withID:(NSString *)vetID;

// ── Helpers ──
- (NSString *)localizedTypeName;
- (NSString *)localizedSubscriptionTierName;
- (BOOL)isSubscriptionExpired;

@end

NS_ASSUME_NONNULL_END
