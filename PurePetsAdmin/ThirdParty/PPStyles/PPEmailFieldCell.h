//
//  EmailFieldCell.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//
// PPEmailFieldCell.h

// PPEmailFieldCell.h
@protocol PPEmailFieldCellDelegate <NSObject>
- (void)emailFieldCellDidTapPick:(XLFormRowDescriptor *_Nullable)row;
@end


@interface PPEmailFieldCell : XLFormBaseCell
@property (nonatomic, strong) UILabel *_Nullable titleLabel;
@property (nonatomic, strong) UITextField *_Nullable textField;
@property (nonatomic, strong) UIButton *_Nullable pickButton;   // 👈 new button

@property (nonatomic, weak) id<PPEmailFieldCellDelegate> delegate;

// 🔹 Add these so XLForm can KVC-set them
@property (nonatomic ,assign) BOOL showPickButton;       // expect @YES/@NO
@property NSString *_Nullable pickButtonSystemName;
@property (copy) void (^ _Nullable onPickTap)(XLFormRowDescriptor *_Nullable);
// In .h
@property (nonatomic,weak) XLFormRowDescriptor *_Nullable rowDescriptor;

// In ConfigLogger.h
void LogCurrentConfig(void);
@end


