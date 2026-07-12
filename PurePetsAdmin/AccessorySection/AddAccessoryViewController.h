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

#import "XLForm.h"

@interface AddAccessoryViewController : XLFormViewController

@property (nonatomic, strong, nullable) PetAccessory *editingAccessory; // pass nil for new

/// NEW: controls whether we show the segmented row for choosing Accessory vs Food
/// Default = YES (show the row)
@property (nonatomic, assign) BOOL showTypeRow;

/// NEW: used only when showTypeRow == NO and editingAccessory is nil
/// (lets you preselect which kind to create)
@property (nonatomic, assign) AccessKindType defaultKind;

- (instancetype _Nullable )initWithAccessory:(PetAccessory * _Nullable)accessory;
@end
