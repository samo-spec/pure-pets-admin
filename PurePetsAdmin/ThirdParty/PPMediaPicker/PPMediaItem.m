//
//  PPMediaItem.m
//  Pure Pets
//
//  Created by Gemini CLI on 28/03/2026.
//

#import "PPMediaItem.h"

@implementation PPMediaItem

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.asset.localIdentifier forKey:@"assetLocalIdentifier"];
    [coder encodeObject:self.image forKey:@"image"];
    [coder encodeObject:self.originalImage forKey:@"originalImage"];
    [coder encodeObject:self.videoURL forKey:@"videoURL"];
    [coder encodeBool:self.isVideo forKey:@"isVideo"];
    [coder encodeBool:self.isEdited forKey:@"isEdited"];
    [coder encodeObject:self.uniqueID forKey:@"uniqueID"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        NSString *localIdentifier = [coder decodeObjectOfClass:[NSString class] forKey:@"assetLocalIdentifier"];
        if (localIdentifier) {
            PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil];
            self.asset = result.firstObject;
        }
        self.image = [coder decodeObjectOfClass:[UIImage class] forKey:@"image"];
        self.originalImage = [coder decodeObjectOfClass:[UIImage class] forKey:@"originalImage"];
        self.videoURL = [coder decodeObjectOfClass:[NSURL class] forKey:@"videoURL"];
        self.isVideo = [coder decodeBoolForKey:@"isVideo"];
        self.isEdited = [coder decodeBoolForKey:@"isEdited"];
        self.uniqueID = [coder decodeObjectOfClass:[NSString class] forKey:@"uniqueID"];
    }
    return self;
}

+ (instancetype)itemWithAsset:(PHAsset *)asset {
    PPMediaItem *item = [PPMediaItem new];
    item.asset = asset;
    item.isVideo = (asset.mediaType == PHAssetMediaTypeVideo);
    item.uniqueID = asset.localIdentifier;
    return item;
}

+ (instancetype)itemWithImage:(UIImage *)image {
    PPMediaItem *item = [PPMediaItem new];
    item.image = image;
    item.originalImage = image;
    item.isVideo = NO;
    item.uniqueID = [[NSUUID UUID] UUIDString];
    return item;
}

+ (instancetype)itemWithVideoURL:(NSURL *)videoURL {
    PPMediaItem *item = [PPMediaItem new];
    item.videoURL = videoURL;
    item.isVideo = YES;
    item.uniqueID = [[NSUUID UUID] UUIDString];
    return item;
}

@end
