//
//  AppManager.h
//  PurePetsAdmin
//

#import "AppManager.h"
#import "MainKindsModel.h"

@class FIRUser;
@protocol FIRListenerRegistration;


typedef NS_ENUM(NSInteger, DataSource)
{
    DataSourceServer = 1,
    DataSourceCache = 2
};

NS_ASSUME_NONNULL_BEGIN

@interface AppManager : NSObject
  

@property (nonatomic, strong, nullable) id<FIRListenerRegistration> adsListener;

@property (nonatomic, strong, nullable) id<FIRListenerRegistration> usersListener;

@property (nonatomic, strong, nullable) id<FIRListenerRegistration> accessoriesListener;


/// Singleton
+ (instancetype)shared;

/// Firebase setup
- (void)configureFirebase;

/// Current user
@property (nonatomic, strong, nullable) FIRUser *currentUser;

/// Check if current user is admin
- (void)checkIfAdmin:(void(^)(BOOL isAdmin))completion;

/// App version string
@property (nonatomic, copy, readonly) NSString *appVersion;


// Arrays
@property (strong, nonatomic) NSMutableArray<MainKindsModel *> *MainKindsArray;


- (void)fetchMainKindsWithCompletion:(void(^)(NSArray<MainKindsModel *> * _Nullable kinds, NSError * _Nullable error))completion;
- (void)stopCountsListening;
- (void)startListeningCountsWithCallback:(void(^)(NSInteger adsCount, NSInteger usersCount, NSInteger accessoriesCount, NSError *error))callback;
@end

NS_ASSUME_NONNULL_END


// ✅ Shortcut macro for easy access
#define AppMgr [AppManager shared]
#define UsrMgr [UserManager shared]
#define UsrMgrCls [UserManager class]
#define RPM [RPManager shared]
#define RPM [RPManager shared]
#define PPNotifications [PPNotificationsManager sharedManager]
#define PPNotificationsClass [PPNotificationsManager class]
#define PPFIRInstallation [FIRInstallations installations]
