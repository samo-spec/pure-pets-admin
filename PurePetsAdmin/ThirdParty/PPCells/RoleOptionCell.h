//
//  RoleOptionCell.h
//  PurePetsAdmin
//

#import "XLFormBaseCell.h"

@interface RoleOptionCell : XLFormBaseCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
- (void)pp_setSelectedState:(BOOL)selected;
@end
