//
//  AddAccessoryViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


//
//  AddAccessoryViewController.h
//  PurePetsAdmin
//
//  Created by Admin on 22/08/2025.
//

#import <UIKit/UIKit.h>
#import "BasicClasses/PetAccessory.h"

NS_ASSUME_NONNULL_BEGIN

@interface AddAccessoryViewController : UIViewController

@property (nonatomic, strong, nullable) PetAccessory *editingAccessory; // pass nil for new

/// controls whether we show the segmented row for choosing Accessory vs Food vs Live Pets
/// Default = YES (show the row)
@property (nonatomic, assign) BOOL showTypeRow;

/// used only when showTypeRow == NO and editingAccessory is nil
/// (lets you preselect which kind to create)
@property (nonatomic, assign) AccessKindType defaultKind;

- (instancetype)initWithAccessory:(nullable PetAccessory *)accessory;

@end

NS_ASSUME_NONNULL_END
