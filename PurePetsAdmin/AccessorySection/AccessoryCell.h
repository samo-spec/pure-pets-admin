//
//  AccessoryCell.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


//
//  AccessoryCell.h
//  PurePetsAdmin
//
//  Created by Admin on 22/08/2025.
//

#import <UIKit/UIKit.h>
@class PetAccessory;

@interface AccessoryCell : UITableViewCell
- (void)configureWithAccessory:(PetAccessory *)accessory;
@end
