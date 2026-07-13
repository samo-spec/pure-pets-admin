//
//  AccessoryCell.h
//  PurePetsAdmin
//
//  Created by Admin on 22/08/2025.
//

#import <UIKit/UIKit.h>

@class PetAccessory;
@class AccessoryCell;

NS_ASSUME_NONNULL_BEGIN

@protocol AccessoryCellDelegate <NSObject>
@optional
- (void)accessoryCell:(AccessoryCell *)cell didTapAdjustQuantityBy:(NSInteger)delta;
- (void)accessoryCellDidTapEdit:(AccessoryCell *)cell;
@end

@interface AccessoryCell : UITableViewCell

@property (nonatomic, weak, nullable) id<AccessoryCellDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) PetAccessory *accessory;
@property (nonatomic, assign) BOOL hasAnimated;

- (void)configureWithAccessory:(PetAccessory *)accessory;

@end

NS_ASSUME_NONNULL_END
