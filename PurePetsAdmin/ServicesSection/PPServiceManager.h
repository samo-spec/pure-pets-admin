//
//  PPServiceManager.h
//  PurePetsAdmin
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class PPServiceModel;
@protocol FIRListenerRegistration;

typedef void (^PPServiceVoidBlock)(NSError * _Nullable error);
typedef void (^PPServiceArrayBlock)(NSArray<PPServiceModel *> * _Nullable services, NSError * _Nullable error);
typedef void (^PPServiceModelBlock)(PPServiceModel * _Nullable service, NSError * _Nullable error);

@interface PPServiceManager : NSObject

+ (instancetype)sharedManager;

- (BOOL)currentAdminCanManageServices;

- (id<FIRListenerRegistration> _Nullable)observeAllServices:(PPServiceArrayBlock)onChange;
- (void)fetchAllServicesWithCompletion:(PPServiceArrayBlock)completion;
- (void)fetchServiceByID:(NSString *)serviceID completion:(PPServiceModelBlock)completion;

- (void)addService:(PPServiceModel *)service
             image:(nullable UIImage *)image
         auditNote:(nullable NSString *)auditNote
        completion:(PPServiceVoidBlock)completion;

- (void)updateService:(PPServiceModel *)service
                image:(nullable UIImage *)image
            auditNote:(nullable NSString *)auditNote
           completion:(PPServiceVoidBlock)completion;

- (void)updateAdministrativeStateForService:(PPServiceModel *)service
                                  auditNote:(nullable NSString *)auditNote
                                 completion:(PPServiceVoidBlock)completion;

- (void)setDisabled:(BOOL)disabled
       forServiceID:(NSString *)serviceID
          auditNote:(nullable NSString *)auditNote
         completion:(PPServiceVoidBlock)completion;

- (void)setBlocked:(BOOL)blocked
      forServiceID:(NSString *)serviceID
         auditNote:(nullable NSString *)auditNote
        completion:(PPServiceVoidBlock)completion;

- (void)archiveServiceID:(NSString *)serviceID
               auditNote:(nullable NSString *)auditNote
              completion:(PPServiceVoidBlock)completion;

- (void)restoreServiceID:(NSString *)serviceID
               auditNote:(nullable NSString *)auditNote
              completion:(PPServiceVoidBlock)completion;

- (void)deleteServicePermanently:(NSString *)serviceID
                       auditNote:(nullable NSString *)auditNote
                      completion:(PPServiceVoidBlock)completion;

@end

NS_ASSUME_NONNULL_END
