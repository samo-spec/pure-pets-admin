#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface PPDriverWorkspaceService : NSObject
- (void)load:(NSDictionary *)parameters completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion;
- (void)setAvailability:(NSDictionary *)parameters completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion;
- (void)execute:(NSDictionary *)parameters completion:(void (^)(NSDictionary * _Nullable, NSError * _Nullable))completion;
@end
NS_ASSUME_NONNULL_END
