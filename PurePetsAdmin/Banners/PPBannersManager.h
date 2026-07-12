//
//  PPBannersManager.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 09/09/2025.
//


// PPBannersManager.h

#import <Foundation/Foundation.h>
@import Firebase;
 @import FirebaseMessaging;
 @class MainBannerModel;
#import "PPBannerViewModel.h"
 
NS_ASSUME_NONNULL_BEGIN

@interface PPBannersManager : NSObject

/// Shared singleton instance for global access.
+ (instancetype)sharedManager;

/// Current list of banner groups fetched from Firestore.
@property (nonatomic, copy, readonly) NSArray<MainBannerModel *> *bannerGroups;

/// Start listening to the banners collection in Firestore. 
/// The completion block is called on initial load and on every update with the full list or an error.
- (void)startListeningForBannersWithCompletion:(void (^)(NSArray<MainBannerModel *> * _Nullable banners, NSError * _Nullable error))completion;

/// Stop listening to Firestore updates (remove the snapshot listener).
- (void)stopListening;

/// Add a new banner group to Firestore.
- (void)addBannerGroup:(MainBannerModel *)bannerGroup completion:(void (^)(NSError * _Nullable error))completion;

/// Modify an existing banner group in Firestore.
- (void)updateBannerGroup:(MainBannerModel *)bannerGroup completion:(void (^)(NSError * _Nullable error))completion;

/// Delete a banner group from Firestore.
- (void)deleteBannerGroup:(MainBannerModel *)bannerGroup completion:(void (^)(NSError * _Nullable error))completion;

/// (Optional) Functions to manage individual child banners could be added here, 
/// e.g., addBannerItem:toGroup:, updateBannerItem:, deleteBannerItem: 
/// depending on app requirements.


// PPBannersManager.h

- (id<FIRListenerRegistration>)observeAllBanner:
    (void (^)(NSArray<MainBannerModel *> * _Nullable items, NSError * _Nullable error))callback;

// Optional alias to match existing call sites (e.g., PPBannersListVC)
- (id<FIRListenerRegistration>)observeAllMainBanners:
    (void (^)(NSArray<MainBannerModel *> * _Nullable items, NSError * _Nullable error))callback;

// Manage child banners in subcollection "ChildBanners" under each MainBanner doc
- (void)addChildBanner:(PPBannerViewModel *)child
               toGroup:(NSString *)bannerViewID
            completion:(void (^)(NSError * _Nullable error))completion;

- (void)updateChildBanner:(PPBannerViewModel *)child
                  inGroup:(MainBannerModel *)group
               completion:(void (^)(NSError * _Nullable error))completion;

- (void)deleteChildBanner:(PPBannerViewModel *)child
                  inGroup:(MainBannerModel *)groub
               completion:(void (^)(NSError * _Nullable))completion;

/// Listen for all child banners inside one group
- (id<FIRListenerRegistration>)observeChildBannersInGroup:(NSString *)bannerViewID
                                               completion:(void (^)(NSArray<PPBannerViewModel *> * _Nullable items,
                                                                   NSError * _Nullable error))completion;


- (void)addBanner:(PPBannerViewModel *)banner
          toGroup:(MainBannerModel *)group
       completion:(void(^)(NSError * _Nullable error))completion ;
@end

NS_ASSUME_NONNULL_END
