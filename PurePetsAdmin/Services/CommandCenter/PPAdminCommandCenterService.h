#import <Foundation/Foundation.h>

@class PPAdminSessionSnapshot;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_SENDABLE
@interface PPAdminCommandSnapshot : NSObject

@property (nonatomic, strong) NSDate *generatedAt;
@property (nonatomic, assign) NSInteger activeOrdersCount;
@property (nonatomic, assign) NSInteger awaitingFulfillmentCount;
@property (nonatomic, assign) NSInteger activeDeliveryCount;
@property (nonatomic, assign) NSInteger pendingProviderApplicationCount;
@property (nonatomic, assign) NSInteger adsCount;
@property (nonatomic, assign) NSInteger usersCount;
@property (nonatomic, assign) NSInteger accessoriesCount;
@property (nonatomic, copy) NSArray<NSString *> *requestedAreas;
@property (nonatomic, copy) NSArray<NSString *> *failedAreas;

@end

typedef void (^PPAdminCommandSnapshotCompletion)(PPAdminCommandSnapshot *snapshot) NS_SWIFT_SENDABLE;

@interface PPAdminCommandCenterService : NSObject

+ (instancetype)shared;
- (void)loadSnapshotForSession:(PPAdminSessionSnapshot *)session
                    completion:(PPAdminCommandSnapshotCompletion)completion
    NS_SWIFT_NAME(loadSnapshot(for:completion:));

@end

NS_ASSUME_NONNULL_END
