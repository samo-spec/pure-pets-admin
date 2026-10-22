#import "PPDriverWorkspaceService.h"
#import "PPFirebaseCompat.h"
@implementation PPDriverWorkspaceService
- (void)load:(NSDictionary *)parameters completion:(void (^)(NSDictionary *, NSError *))completion {
    [self call:@"getDriverDeliveryWorkspace" parameters:parameters completion:completion];
}
- (void)setAvailability:(NSDictionary *)parameters completion:(void (^)(NSDictionary *, NSError *))completion {
    [self call:@"setDriverDeliveryAvailability" parameters:parameters completion:completion];
}
- (void)execute:(NSDictionary *)parameters completion:(void (^)(NSDictionary *, NSError *))completion {
    [self call:@"executeDriverDeliveryTask" parameters:parameters completion:completion];
}
- (void)call:(NSString *)name parameters:(NSDictionary *)parameters completion:(void (^)(NSDictionary *, NSError *))completion {
    FIRHTTPSCallable *callable = [[FIRFunctions functionsForRegion:@"us-central1"] HTTPSCallableWithName:name];
    callable.timeoutInterval = 30;
    [callable callWithObject:parameters completion:^(FIRHTTPSCallableResult *result, NSError *error) {
        NSDictionary *data = [result.data isKindOfClass:NSDictionary.class] ? result.data : nil;
        NSError *failure = error;
        if (!data && !failure) failure = [NSError errorWithDomain:@"PPDriverWorkspace" code:1
            userInfo:@{NSLocalizedDescriptionKey:kLang(@"Driver_Error_Load")}];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(data, failure); });
    }];
}
@end
