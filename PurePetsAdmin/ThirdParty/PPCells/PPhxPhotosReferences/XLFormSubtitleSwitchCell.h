//
//  XLFormSubtitleSwitchCell.h
//  PurePetsAdmin
//

#import "XLFormBaseCell.h"

@interface XLFormSubtitleSwitchCell : XLFormBaseCell
@property (nonatomic, strong) UIView *bgCardView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UserModel *ppUser;
@property (assign, nonatomic) UserRole  ppUserRole;
@end
