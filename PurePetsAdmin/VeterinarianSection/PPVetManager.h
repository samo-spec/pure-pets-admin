//
//  PPVetManager.h
//  PurePetsAdmin
//
//  Singleton manager for Firestore "veterinarians" collection.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPVetModel;
@protocol FIRListenerRegistration;

typedef void(^PPVetArrayBlock)(NSArray<PPVetModel *> * _Nullable vets, NSError * _Nullable error);
typedef void(^PPVetVoidBlock)(NSError * _Nullable error);
typedef void(^PPVetCountBlock)(NSInteger count);

@interface PPVetManager : NSObject

+ (instancetype)sharedManager;

// ── READ ──
- (void)fetchAllVetsWithCompletion:(PPVetArrayBlock)completion;
- (id<FIRListenerRegistration>)observeAllVets:(PPVetArrayBlock)onChange;
- (void)fetchVetsForUserID:(NSString *)userID completion:(PPVetArrayBlock)completion;
- (void)fetchVetByID:(NSString *)vetID completion:(void(^)(PPVetModel * _Nullable vet, NSError * _Nullable error))completion;

// ── WRITE ──
- (void)addVet:(PPVetModel *)vet
         image:(UIImage * _Nullable)image
    completion:(PPVetVoidBlock)completion;

- (void)updateVet:(PPVetModel *)vet
            image:(UIImage * _Nullable)image
       completion:(PPVetVoidBlock)completion;

- (void)deleteVet:(PPVetModel *)vet
       completion:(PPVetVoidBlock)completion;

// ── Admin toggles ──
- (void)setDisabled:(BOOL)disabled
           forVetID:(NSString *)vetID
         completion:(PPVetVoidBlock)completion;

- (void)updateSubscriptionForVetID:(NSString *)vetID
                              tier:(NSInteger)tier
                            active:(BOOL)active
                         startDate:(NSDate * _Nullable)startDate
                           endDate:(NSDate * _Nullable)endDate
                        completion:(PPVetVoidBlock)completion;

// ── Image ──
- (void)uploadImage:(UIImage *)image
              vetID:(NSString *)vetID
         completion:(void(^)(NSString *imageURL))completion;

// ── Count ──
- (id<FIRListenerRegistration>)listenVetCount:(PPVetCountBlock)block;

@end

NS_ASSUME_NONNULL_END
