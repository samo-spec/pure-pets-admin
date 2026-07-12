//
//  PPAdminButton.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 27/08/2025.
//


// in PPAdminButton.h
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPAdminButton : UIButton
@property (nonatomic, assign, getter=isAdmin) BOOL admin;   // current state
- (void)applyStateAnimated:(BOOL)animated;               // updates image/label/accessibility
@end

NS_ASSUME_NONNULL_END
