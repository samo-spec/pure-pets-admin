//
//  PPItem.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 26/08/2025.
//


// In PPItem.h
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <XLForm/XLForm.h>

NS_ASSUME_NONNULL_BEGIN

/// A small, reusable item model that can represent:
/// - a user (id, name, avatarURL)
/// - an accessory/species/category (id, title, icon)
/// - any "selectable" entity in your admin app
///
/// XLForm: Conforms to XLFormOptionObject so it can be used directly as a row value.
@interface PPItem : NSObject <NSCopying, NSSecureCoding, XLFormOptionObject>

/// Canonical identifier (e.g., uid for users, document id for items)
@property (nonatomic, copy)   NSString *itemID;

/// Primary title (e.g., user name, accessory name, species name)
@property (nonatomic, copy)   NSString *title;

/// Optional subtitle or secondary text (e.g., email, short description)
@property (nonatomic, copy, nullable) NSString *subtitle;

/// Image sources (choose one): direct UIImage, or imageName in bundle, or remote URL string
@property (nonatomic, strong, nullable) UIImage  *image;
@property (nonatomic, copy,   nullable) NSString *imageName;
@property (nonatomic, copy,   nullable) NSString *imageURLString;

/// Arbitrary metadata bag
@property (nonatomic, copy,   nullable) NSDictionary *userInfo;

/// MARK: - Init
+ (instancetype)itemWithID:(NSString *)itemID
                     title:(NSString *)title;

+ (instancetype)itemWithID:(NSString *)itemID
                     title:(NSString *)title
                  subtitle:(nullable NSString *)subtitle
                 imageName:(nullable NSString *)imageName;


+ (instancetype)itemWithPetAccessory:(PetAccessory *)access firstBtnImageName:(nullable NSString *)firstBtnImageName secBtnImageName:(nullable NSString *)secBtnImageName;

/// Build from a generic dictionary (safe lookups for common keys)
+ (instancetype)itemWithDictionary:(NSDictionary *)dict;

/// Convenience for building from your UserModel-shaped dict (keys per your UserModel)
/// Expected keys: uid/ID, UserName, UserEmail, UserImageName, UserImageUrl, etc.
+ (instancetype)itemFromUserDictionary:(NSDictionary *)dict;

/// Merge / update fields from another PPItem (non-nil fields override)
- (void)mergeFrom:(PPItem *)other;

/// MARK: - XLFormOptionObject
/// XLForm asks these two:
///   - (NSString *)formDisplayText;
///   - (id)formValue;
- (NSString *)formDisplayText;
- (id)formValue;


//  PP CELL WITH BUTTONS
@property (nonatomic, copy, nullable) NSString *firstButtonImageName;
@property (nonatomic, copy, nullable) NSString *secondButtonImageName;

@end

NS_ASSUME_NONNULL_END
