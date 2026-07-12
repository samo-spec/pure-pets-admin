//
//  MainKindsArrayManager.h
//  Pure Pets
//
//  Created by Mohammed Ahmed on 08/08/2025.
//


// MainKindsArrayManager.h
NS_ASSUME_NONNULL_BEGIN
static NSString * const PPMainKindsUpdatedNotification = @"MainKindsUpdatedNotification";
@class MainKindsModel;



/// Global immutable snapshot of the latest loaded MainKinds


@interface MainKindsArrayManager : NSObject
+ (instancetype)shared;
- (void)fetchMainKindByID:(NSString *)mainID completion:(void(^)(NSDictionary *doc, NSError *err))completion;
- (void)addOrReplaceSubKind:(SubKindModel *)sub toMainID:(NSString *)mainID completion:(void(^)(NSError *err))completion;
- (void)removeSubKindID:(NSString *)subID fromMainID:(NSString *)mainID completion:(void(^)(NSError *err))completion;
- (void)loadMainDataCompletionHandler:(void (^)(int result))completionHandler;

- (void)FillMainKindsArray;
@property (nonatomic, strong) NSMutableArray<MainKindsModel *> *MainKindsArray;
@property (nonatomic, strong, nullable) id<FIRListenerRegistration> mainKindsListener;
@property (nonatomic, assign) BOOL didSeedMainKinds;




//Get Sub Kinds Array From MainKinds By subKindsID
-(NSArray<SubKindModel *> *)getSubKindArray:(NSInteger)MainKindID;
@property (strong, nonatomic) NSMutableArray<SubKindModel *> *subKindsArrayForFilter;
- (MainKindsModel *)mainKindForID:(NSInteger)kindID ;

- (void)listenForMainKindsChangesWithBlock:(void (^)(NSArray<MainKindsModel *> *mainKinds, NSError *error))block ;

@end

NS_ASSUME_NONNULL_END
