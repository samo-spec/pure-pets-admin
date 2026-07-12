//
//  PetImageItem.m
//  Pure Pets
//
//  Created by Mohammed Ahmed on 14/01/2026.
//


#import "PetImageItem.h"
#pragma mark - PetImageItem


@implementation PetImageItem

+ (BOOL)supportsSecureCoding {
    return YES;
}

#pragma mark - NSSecureCoding

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.url forKey:@"url"];
    [coder encodeDouble:self.width forKey:@"width"];
    [coder encodeDouble:self.height forKey:@"height"];
    [coder encodeObject:self.blurHash forKey:@"blurHash"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init]) {

        _url = [coder decodeObjectOfClass:NSString.class forKey:@"url"];
        _width = [coder decodeDoubleForKey:@"width"];
        _height = [coder decodeDoubleForKey:@"height"];
        _blurHash = [coder decodeObjectOfClass:NSString.class forKey:@"blurHash"];
    }
    return self;
}
 
+ (instancetype)itemWithURL:(NSString *)url width:(CGFloat)width height:(CGFloat)height blurHash:(nullable NSString *)blurHash {
    return [[self alloc] initWithURL:url width:width height:height blurHash:blurHash];
}

- (instancetype)initWithURL:(NSString *)url width:(CGFloat)width height:(CGFloat)height blurHash:(nullable NSString *)blurHash{
    if (self = [super init]) {
        _url = [url copy] ?: @"";
        _width = width;
        _height = height;
        _blurHash = blurHash;
    }
    return self;
}

- (CGFloat)ratio {
    return (_width > 0 ? _height / _width : 1.0);
}


#pragma mark - Serialization

- (NSDictionary *)toDictionary
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    dict[@"url"]    = self.url ?: @"";
    dict[@"width"]  = @(self.width);
    dict[@"height"] = @(self.height);
    dict[@"ratio"]  = @(self.ratio);

    if (self.blurHash.length > 0) {
        dict[@"blurHash"] = self.blurHash;
    }

    return dict;
}


+ (instancetype)itemFromDictionary:(NSDictionary *)dict
{
    if (![dict isKindOfClass:NSDictionary.class]) {
        return nil;
    }

    NSString *url = dict[@"url"];
    if (url.length == 0) {
        return nil;
    }

    CGFloat width  = [dict[@"width"] doubleValue];
    CGFloat height = [dict[@"height"] doubleValue];
    NSString *blurHash = dict[@"blurHash"];

    return [[self alloc] initWithURL:url
                               width:width
                              height:height
                            blurHash:blurHash];
}

@end
