//
//  PPItem.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 26/08/2025.
//


// In PPItem.m
#import "PPItem.h"

@implementation PPItem

+ (BOOL)supportsSecureCoding { return YES; }

#pragma mark - Init


+ (instancetype)itemWithPetAccessory:(PetAccessory *)access firstBtnImageName:(nullable NSString *)firstBtnImageName secBtnImageName:(nullable NSString *)secBtnImageName {
    PPItem *it = [PPItem new];
    it.itemID = access.accessoryID ?: @"";
    it.title = access.name ?: @"";
    it.subtitle  = access.desc ?: @"";
    it.firstButtonImageName  = firstBtnImageName.length ? firstBtnImageName : nil;
    it.secondButtonImageName  = secBtnImageName.length ? secBtnImageName : nil;
    it.imageURLString = access.imageURLsArray.count > 0 ? access.imageURLsArray.firstObject : nil;
    return it;
}


+ (instancetype)itemWithID:(NSString *)itemID title:(NSString *)title {
    PPItem *it = [PPItem new];
    it.itemID = itemID ?: @"";
    it.title  = title ?: @"";
    return it;
}

+ (instancetype)itemWithID:(NSString *)itemID
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
                 imageName:(NSString *)imageName
{
    PPItem *it = [self itemWithID:itemID title:title];
    it.subtitle = subtitle;
    it.imageName = imageName;
    return it;
}

+ (instancetype)itemWithDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return [PPItem new];

    NSString *itemID  = dict[@"itemID"] ?: dict[@"id"] ?: dict[@"ID"] ?: dict[@"uid"] ?: @"";
    NSString *title   = dict[@"title"] ?: dict[@"name"] ?: dict[@"UserName"] ?: dict[@"displayName"] ?: @"";
    NSString *subtitle= dict[@"subtitle"] ?: dict[@"email"] ?: dict[@"UserEmail"] ?: @"";

    PPItem *it = [PPItem itemWithID:itemID title:title];
    it.subtitle = subtitle;

    // image preference order: UIImage -> imageName -> imageURL
    UIImage *img = dict[@"image"];
    if ([img isKindOfClass:UIImage.class]) { it.image = img; }

    NSString *imgName = dict[@"imageName"] ?: dict[@"UserImageName"];
    if ([imgName isKindOfClass:NSString.class] && imgName.length) { it.imageName = imgName; }

    NSString *imgURL = dict[@"imageURL"] ?: dict[@"imageURLString"] ?: dict[@"photoURL"] ?: dict[@"UserImageUrl"];
    if ([imgURL isKindOfClass:NSString.class] && imgURL.length) { it.imageURLString = imgURL; }

    // carry everything else
    it.userInfo = dict;
    return it;
}

+ (instancetype)itemFromUserDictionary:(NSDictionary *)dict {
    // Map using your UserModel keys
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:dict ?: @{}];
    // Normalize keys to the ones itemWithDictionary expects
    if (d[@"uid"]) d[@"itemID"] = d[@"uid"];
    if (d[@"UserName"]) d[@"title"] = d[@"UserName"];
    if (d[@"UserEmail"]) d[@"subtitle"] = d[@"UserEmail"];
    if (d[@"UserImageName"]) d[@"imageName"] = d[@"UserImageName"];
    if (d[@"UserImageUrl"])  d[@"imageURL"]  = d[@"UserImageUrl"];
    return [self itemWithDictionary:d];
}

- (void)mergeFrom:(PPItem *)other {
    if (!other) return;
    if (other.itemID.length) self.itemID = other.itemID;
    if (other.title.length)  self.title  = other.title;
    if (other.subtitle.length) self.subtitle = other.subtitle;
    if (other.image) self.image = other.image;
    if (other.imageName.length) self.imageName = other.imageName;
    if (other.imageURLString.length) self.imageURLString = other.imageURLString;

    if (other.userInfo.count) {
        NSMutableDictionary *m = [self.userInfo mutableCopy] ?: [NSMutableDictionary new];
        [m addEntriesFromDictionary:other.userInfo];
        self.userInfo = m.copy;
    }
}

#pragma mark - XLFormOptionObject

- (NSString *)formDisplayText {
    return self.title ?: @"";
}

- (id)formValue {
    // let the row hold the item itself (XLForm accepts objects)
    return self;
}

#pragma mark - NSCoding (secure)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.itemID forKey:@"itemID"];
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeObject:self.subtitle forKey:@"subtitle"];
    [coder encodeObject:self.image forKey:@"image"];
    [coder encodeObject:self.imageName forKey:@"imageName"];
    [coder encodeObject:self.imageURLString forKey:@"imageURLString"];
    [coder encodeObject:self.userInfo forKey:@"userInfo"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _itemID = [coder decodeObjectOfClass:NSString.class forKey:@"itemID"] ?: @"";
        _title  = [coder decodeObjectOfClass:NSString.class forKey:@"title"] ?: @"";
        _subtitle = [coder decodeObjectOfClass:NSString.class forKey:@"subtitle"];
        _image   = [coder decodeObjectOfClass:UIImage.class forKey:@"image"];
        _imageName = [coder decodeObjectOfClass:NSString.class forKey:@"imageName"];
        _imageURLString = [coder decodeObjectOfClass:NSString.class forKey:@"imageURLString"];
        _userInfo = [coder decodeObjectOfClass:NSDictionary.class forKey:@"userInfo"];
    }
    return self;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    PPItem *it = [[PPItem allocWithZone:zone] init];
    it.itemID = self.itemID;
    it.title = self.title;
    it.subtitle = self.subtitle;
    it.image = self.image;
    it.imageName = self.imageName;
    it.imageURLString = self.imageURLString;
    it.userInfo = self.userInfo;
    return it;
}

@end
