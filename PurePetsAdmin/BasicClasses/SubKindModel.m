//
//  SubKindModel.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 04/08/2024.
//

#import "SubKindModel.h"
#import "Language.h"
@import Firebase;
@import FirebaseAuth;
@import FirebaseMessaging;
@import FirebaseAuth;
#import "SDImageCache.h"
#import "SDWebImageManager.h"

@implementation SubKindModel

-(id)formValue
{
    return self;
}

- (nonnull NSString *)formDisplayText {
    return [Language languageVal] == 0 ? self.SubKindNameEn : self.SubKindNameAr;
}

-(NSString *)SubKindName
{
    return [Language languageVal] == 0 ? self.SubKindNameEn : self.SubKindNameAr;
}

- (instancetype)initWithDict:(NSDictionary *)dict{
    self = [super init];
    if (self) {
        
        self.ID = [dict[@"ID"] integerValue];
        self.MainKindID = [dict[@"MainKindID"] integerValue];

        self.SubKindNameAr = dict[@"SubKindNameAr"];
        self.SubKindNameEn = dict[@"SubKindNameEn"];

        self.subKindIcon = dict[@"subKindIcon"];
        self.subKindIconUrl = dict[@"subKindIconUrl"];
        self.subKindIconBlurHash = dict[@"subKindIconBlurHash"];
        self.have_subSub = [dict[@"have_subSub"] integerValue];
        self.have_items = [dict[@"have_items"] integerValue];
        self.adultHood = [dict[@"adultHood"] integerValue];
        self.SubKindImageName = dict[@"SubKindImageName"];
        
        self.subSubKindArray = [[NSMutableArray<subSubKindModel *> alloc] init];
        NSArray *dic = dict[@"subSubKindArray"];
        for (NSDictionary *subSubKind in dic) {
           // NSLog(@"subSubKind: %@", subSubKind);
            subSubKindModel *subSubKindMD = [[subSubKindModel alloc] initWithDict:subSubKind];
            [self.subSubKindArray addObject:subSubKindMD];
        }
        
    }
    return self;
}
- (NSDictionary *)toDict {
    NSMutableArray *subSubArray = [NSMutableArray array];
    for (subSubKindModel *model in self.subSubKindArray) {
        if ([model respondsToSelector:@selector(toDict)]) {
            [subSubArray addObject:[model toDict]];
        }
    }
    
    return @{
        @"ID": @(self.ID),
        @"MainKindID": @(self.MainKindID),
        @"SubKindNameAr": self.SubKindNameAr ?: @"",
        @"SubKindImageName": self.SubKindImageName ?: @"",
        @"SubKindNameEn": self.SubKindNameEn ?: @"",
        @"subKindIcon": self.subKindIcon ?: @"",
        @"subKindIconUrl": self.subKindIconUrl ?: @"",
        @"subKindIconBlurHash": self.subKindIconBlurHash ?: @"",
        @"have_subSub": @(self.have_subSub),
        @"have_items": @(self.have_items),
        @"adultHood": @(self.adultHood),
        @"subSubKindArray": subSubArray
    };
}

- (instancetype)initWithSnapshot:(FIRDocumentSnapshot *)snapshot {
    self = [super init];
    if (self) {
        
        NSDictionary *data = snapshot.data;

        self.ID = [data[@"ID"] integerValue];
        self.MainKindID = [data[@"MainKindID"] integerValue];

        self.SubKindNameAr = data[@"SubKindNameAr"];
        self.SubKindNameEn = data[@"SubKindNameEn"];
        self.SubKindImageName = data[@"SubKindImageName"];
        self.subKindIcon = data[@"subKindIcon"];
        self.subKindIconUrl = data[@"subKindIconUrl"];
        self.subKindIconBlurHash = data[@"subKindIconBlurHash"];
        
        self.have_subSub = [data[@"have_subSub"] integerValue];
        self.have_items = [data[@"have_items"] integerValue];
        self.adultHood = [data[@"adultHood"] integerValue];
        
    }
    return self;
}

// Helper function to get the SubKind name (moved out of the cellForRowAtIndexPath method)
+(NSString*)getSubKindName:(NSInteger)subKindID subKindsArrayLocal:(NSArray<SubKindModel*> *)subKindsArrayLocal {
    for (SubKindModel *subKind in subKindsArrayLocal) {
        if (subKind.ID == subKindID) {
            return subKind.SubKindName;
        }
    }
    return @""; // Return an empty string if not found or use your localized "not found" string.
}

+(NSInteger)getSubKindID:(NSString *)subKindName subKindsArrayLocal:(NSArray<SubKindModel *> *)subKindsArrayLocal
{
    for (SubKindModel *subKind in subKindsArrayLocal) {
        if ([subKind.SubKindName isEqualToString:subKindName]) {
            return subKind.ID;
        }
    }
    return 0; // Return an empty string if not found or use your localized "not found" string.
}

+ (void)addSubKind:(NSDictionary *)subKind
     toMainKindID:(NSString *)mainID
       completion:(void(^)(NSError * _Nullable error))completion
{
    if (mainID.length == 0 || ![subKind isKindOfClass:NSDictionary.class]) {
        if (completion) completion([NSError errorWithDomain:@"Input" code:400 userInfo:@{NSLocalizedDescriptionKey: @"Invalid input"}]);
        return;
    }

    FIRFirestore *db = [FIRFirestore firestore];
    FIRDocumentReference *doc = [[db collectionWithPath:@"MainKindsCollection"] documentWithPath:mainID];

    // Optional: ensure subKind has required keys / sane defaults
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    clean[@"ID"] = subKind[@"ID"] ?: @(arc4random_uniform(1000000));
    clean[@"MainKindID"] = subKind[@"MainKindID"] ?: mainID;
    clean[@"SubKindImageName"] = subKind[@"SubKindImageName"] ?: @"";
    clean[@"SubKindNameAr"] = subKind[@"SubKindNameAr"] ?: @"";
    clean[@"SubKindImageName"] = subKind[@"SubKindImageName"] ?: @"";
    clean[@"SubKindNameEn"] = subKind[@"SubKindNameEn"] ?: @"";
    clean[@"adultHood"] = subKind[@"adultHood"] ?: @0;
    clean[@"have_items"] = subKind[@"have_items"] ?: @NO;
    clean[@"have_subSub"] = subKind[@"have_subSub"] ?: @NO;

    // Prevent duplicates by ID using a transaction
    [db runTransactionWithBlock:^id _Nullable(FIRTransaction * _Nonnull tx, NSError * _Nullable * _Nonnull errorPointer) {

        FIRDocumentSnapshot *snap = [tx getDocument:doc error:errorPointer];
        if (*errorPointer) return nil;

        NSMutableArray *arr = [NSMutableArray arrayWithArray:(snap[@"SubKindsArray"] ?: @[])];

        BOOL exists = NO;
        for (NSDictionary *it in arr) {
            if ([it[@"ID"] isKindOfClass:NSNumber.class] && [it[@"ID"] isEqual:clean[@"ID"]]) {
                exists = YES; break;
            }
        }
        if (exists) {
            // replace existing map with same ID
            for (NSInteger i = 0; i < arr.count; i++) {
                NSDictionary *it = arr[i];
                if ([it[@"ID"] isEqual:clean[@"ID"]]) {
                    arr[i] = clean;
                    break;
                }
            }
        } else {
            [arr addObject:clean];
        }

        [tx updateData:@{ @"SubKindsArray": arr } forDocument:doc];
        return nil;

    } completion:^(id  _Nullable result, NSError * _Nullable error) {
        if (completion) completion(error);
    }];
}


#pragma mark - Icon Loader (Cache → URL → Fallback)

- (void)loadSubKindIconWithCompletion:(void(^)(UIImage * _Nullable image))completion {

    // 1️⃣ Already resolved in memory
    if (self.cachedIconImage) {
        if (completion) completion(self.cachedIconImage);
        return;
    }

    // 2️⃣ Try SDWebImage cache by URL
    if (self.subKindIconUrl.length) {
        NSURL *url = [NSURL URLWithString:self.subKindIconUrl];

        UIImage *cached = [[SDImageCache sharedImageCache] imageFromCacheForKey:url.absoluteString];
        if (cached) {
            
            if (self.cachedIconImage) {
                NSLog(@"[SubKindIcon] Memory cache hit | subKindID=%ld", (long)self.ID);
                if (completion) completion(self.cachedIconImage);
                return;
            }
            
            self.cachedIconImage = cached;
            if (completion) completion(cached);
            return;
        }

        // 3️⃣ Download & cache
        [[SDWebImageManager sharedManager] loadImageWithURL:url
                                                    options:SDWebImageRetryFailed | SDWebImageScaleDownLargeImages
                                                   progress:nil
                                                  completed:^(UIImage * _Nullable image,
                                                              NSData * _Nullable data,
                                                              NSError * _Nullable error,
                                                              SDImageCacheType cacheType,
                                                              BOOL finished,
                                                              NSURL * _Nullable imageURL)
        {
            if (image) {
                NSLog(@"[SubKindIcon] Downloaded | subKindID=%ld | size=%@",
                      (long)self.ID,
                      NSStringFromCGSize(image.size));

                self.cachedIconImage = image;

                // 🔥 BlurHash backfill
                [self pp_generateAndSaveBlurHashIfNeededWithImage:image];

                if (completion) completion(image);
            } else {
                NSLog(@"[SubKindIcon] Download failed | subKindID=%ld | error=%@",
                      (long)self.ID,
                      error.localizedDescription);
                [self loadFallbackIcon:completion];
            }
        }];
        return;
    }

    // 4️⃣ Fallback
    [self loadFallbackIcon:completion];
}

- (void)loadFallbackIcon:(void(^)(UIImage * _Nullable image))completion {
    if (self.subKindIcon.length) {
        UIImage *img = [UIImage imageNamed:self.subKindIcon];
        self.cachedIconImage = img;
        if (completion) completion(img);
    } else {
        self.cachedIconImage = PPSYSImage(@"iconPlaceholder");
        if (completion) completion(PPSYSImage(@"iconPlaceholder"));
    }
}


#pragma mark - BlurHash Backfill

- (void)pp_generateAndSaveBlurHashIfNeededWithImage:(UIImage *)image
{
    
   // NSLog(@"[SubKindIcon] Start | subKindID=%ld | url=%@ | localIcon=%@ | blurHash=%@",
   //      (long)self.ID,
     //     self.subKindIconUrl,
     //     self.subKindIcon,
      //    self.subKindIconBlurHash);
    
    
    if (self.subKindIconBlurHash.length > 0) return;
    if (!image) return;

    NSString *hash ;;
    if (hash.length == 0) return;
    
    NSLog(@"[BlurHash] Generated | subKindID=%ld | hash=%@",
          (long)self.ID,
          hash);

    self.subKindIconBlurHash = hash;

    FIRFirestore *db = [FIRFirestore firestore];

    NSString *mainKindID = [NSString stringWithFormat:@"%ld", (long)self.MainKindID];
    FIRDocumentReference *doc =
    [[db collectionWithPath:@"MainKindsCollection"] documentWithPath:mainKindID];

    [db runTransactionWithBlock:^id _Nullable(FIRTransaction * _Nonnull tx,
                                             NSError * _Nullable * _Nonnull errorPointer)
    {
        FIRDocumentSnapshot *snap = [tx getDocument:doc error:errorPointer];
        if (*errorPointer) return nil;

        NSMutableArray *subKinds =
        [NSMutableArray arrayWithArray:(snap[@"SubKindsArray"] ?: @[])];

        BOOL updated = NO;

        for (NSInteger i = 0; i < subKinds.count; i++) {
            NSMutableDictionary *item =
            [subKinds[i] mutableCopy];

            if ([item[@"ID"] integerValue] == self.ID) {
                item[@"subKindIconBlurHash"] = hash;
                subKinds[i] = item;
                updated = YES;
                break;
            }
        }

        if (!updated) return nil;

        [tx updateData:@{
            @"SubKindsArray": subKinds
        } forDocument:doc];

        return nil;

    } completion:^(id  _Nullable result, NSError * _Nullable error) {
        NSLog(@"[BlurHash] Firestore updated | mainKindID=%@ | subKindID=%ld",
              mainKindID,
              (long)self.ID);
    }];
}

@end
