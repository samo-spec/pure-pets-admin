// In PPPickOptionCell.h



// In PPPickOptionCell.h
#import <UIKit/UIKit.h>
#import <XLForm/XLForm.h>
#import "PPItem.h"
#import "PPAdminButton.h"
@class PPPickOptionCell;

@protocol PPPickOptionCellDelegate <NSObject>
@optional
- (void)pickOptionCellDidTapPick:(XLFormRowDescriptor *_Nullable)row;
@end

/// Clean, reusable XLForm cell:
///  - Title label (e.g., "Select User")
///  - Optional optionImageView (left)
///  - Pick button (right)
///  - KVC-safe (tolerates XIB runtime attributes like pickButtonSystemName)
FOUNDATION_EXPORT NSString * _Nullable const XLFormRowDescriptorTypePickOption;

@interface PPPickOptionCell : XLFormBaseCell

@property (nonatomic, weak) id<PPPickOptionCellDelegate> delegate;

/// UI
///
@property (nonatomic, strong) UIImageView *_Nullable optionImageView;
//@property (nonatomic, strong) UILabel     *titleLabel;

@property (nonatomic, strong) UIButton    *_Nullable moreButton;
@property (nonatomic, strong) PPAdminButton    *_Nullable pickButton;
@property (nonatomic, assign) BOOL reverseButtonAlign;



@property (nonatomic, strong) UIImage *_Nullable pickImage;


@property (nonatomic, assign) BOOL  imageLoaded;
/// Config toggles
@property (nonatomic, assign) BOOL showPickButton;   // default YES
@property (nonatomic, assign) BOOL showOptionImage;  // default YES

/// KVC-friendly prop so XIB "User Defined Runtime Attributes" won't crash
@property (nonatomic, copy, nullable) NSString *pickButtonSystemName;
@property (nonatomic, copy, nullable) NSString *moreButtonSystemName;
@property (nonatomic, copy, nullable) NSString *titleString;

/// Optional inline tap block via cellConfig[@"onPickTap"]
@property (nonatomic, copy, nullable) void (^onPickTap)(XLFormRowDescriptor *_Nullable row);


// In PPPickOptionCell.m
- (id _Nullable )valueForUndefinedKey:(NSString *_Nullable)key ;
- (void)updateCellLayout;

- (void)setValue:(id _Nullable)value forUndefinedKey:(NSString *_Nullable)key;

@property (nonatomic, strong) UIView *_Nullable adminBadgeContainer;
@property (nonatomic, strong) UIImageView *_Nullable adminBadgeIcon;
@property (nonatomic, strong) UILabel *_Nullable adminBadgeLabel;
@property (nonatomic, copy) NSString *_Nullable representedUID;
-(void)setUserModelToCell:(UserModel *_Nullable)userModel;
@end
