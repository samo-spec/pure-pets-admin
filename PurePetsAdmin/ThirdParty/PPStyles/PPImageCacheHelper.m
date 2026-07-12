//
//  PPImageCacheHelper 2.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 13/09/2025.
//


//
//  PPImageCacheHelper.m
//  PurePets
//
//  Created by Admin on 13/09/2025.
//

#import "PPImageCacheHelper.h"

@interface PPImageCacheHelper ()
@property (nonatomic, strong) YYCache *cache;
@end

@implementation PPImageCacheHelper

+ (instancetype)shared {
    static PPImageCacheHelper *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PPImageCacheHelper alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        // Create a cache named "PPImageCache"
        _cache = [[YYCache alloc] initWithName:@"PPImageCache"];
        _cache.memoryCache.shouldRemoveAllObjectsOnMemoryWarning = YES;
        _cache.memoryCache.shouldRemoveAllObjectsWhenEnteringBackground = YES;
    }
    return self;
}

// Block normal init
- (instancetype)init {
    @throw [NSException exceptionWithName:@"Singleton"
                                   reason:@"Use +[PPImageCacheHelper shared]"
                                 userInfo:nil];
    return nil;
}

#pragma mark - Public Methods

- (void)saveImage:(UIImage *)image forKey:(NSString *)key {
    if (!image || !key) return;
    NSData *imageData = UIImagePNGRepresentation(image);
    if (imageData) {
        [self.cache setObject:imageData forKey:key];
    }
}

- (nullable UIImage *)imageForKey:(NSString *)key {
    if (!key) return nil;
    NSData *data = (id)[self.cache objectForKey:key];
    if ([data isKindOfClass:[NSData class]]) {
        return [UIImage imageWithData:data];
    }
    return nil;
}

- (void)imageForKey:(NSString *)key completion:(void(^)(UIImage * _Nullable image))completion {
    if (!key) {
        if (completion) completion(nil);
        return;
    }
    [self.cache objectForKey:key withBlock:^(NSString * _Nonnull key, id<NSCoding>  _Nullable object) {
        UIImage *image = nil;
        id obj = (id)object;
        if ([obj isKindOfClass:[NSData class]]) {
            image = [UIImage imageWithData:(NSData *)object];
        }
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(image);
            });
        }
    }];
}

- (void)removeImageForKey:(NSString *)key {
    if (!key) return;
    [self.cache removeObjectForKey:key];
}

- (void)clearAllCache {
    [self.cache removeAllObjects];
}

@end
