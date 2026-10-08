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

+ (instancetype)sharedManager NS_SWIFT_NAME(shared());

- (BOOL)currentAdminCanManageServices;
- (BOOL)currentAdminCanReadServices;

- (id<FIRListenerRegistration> _Nullable)observeAllServices:(PPServiceArrayBlock)onChange;
- (void)fetchAllServicesWithCompletion:(PPServiceArrayBlock)completion;
- (void)fetchServiceByID:(NSString *)serviceID completion:(PPServiceModelBlock)completion NS_SWIFT_NAME(fetchService(byID:completion:));

- (id<FIRListenerRegistration> _Nullable)observeServicePageWithLimit:(NSInteger)limit onChange:(PPServiceArrayBlock)onChange NS_SWIFT_NAME(observeServicePage(withLimit:onChange:));
- (void)fetchServicePageAfterServiceID:(nullable NSString *)serviceID limit:(NSInteger)limit completion:(PPServiceArrayBlock)completion NS_SWIFT_NAME(fetchServicePage(afterServiceID:limit:completion:));

+ (BOOL)administrativeState:(PPServiceModel *)observed matchesService:(PPServiceModel *)candidate;

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

- (void)updateAdministrativeStateForService:(PPServiceModel *)service
                            expectedService:(PPServiceModel *)expected
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
