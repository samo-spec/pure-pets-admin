//
//  PPUserCell.h
//

#import <UIKit/UIKit.h>
@class UserModel;
@class PPUserCell;

NS_ASSUME_NONNULL_BEGIN

/// What the cell should show
typedef NS_ENUM(NSInteger, ViewFor) {
    ViewForDefault = 0,               // avatar + labels + both buttons visible
    ViewForAdminToggle = 1,           // show only setAdminButton
    ViewForEditRoleAndPermissions = 2, // show only actionButton
    ViewForEditAccount = 3, // show only actionButton
    ViewForPicker = 4 // Selection mode
};

@protocol UserCellDelegate <NSObject>
@optional
- (void)userCellDidTapAction:(PPUserCell *)cell user:(UserModel *)user;
- (void)userCellDidTapSetAdmin:(PPUserCell *)cell user:(UserModel *)user;
@end

@interface PPUserCell : UITableViewCell

@property (nonatomic, strong) UIImageView *avatarImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIButton *setAdminButton;

@property (nonatomic, strong) UILabel *statusPill;      // Added for status (Blocked, Active, etc.)
@property (nonatomic, strong) UIImageView *verifiedBadge; // Added for blue checkmark

/// Guard async image reuse
@property (nonatomic, strong,nullable) NSString *representedUID;

/// Model & context
@property (nonatomic, strong,nullable) UserModel *cellUser;
@property (nonatomic, strong) NSIndexPath *indexPath;
@property (nonatomic, weak) id<UserCellDelegate> delegate;
@property (nonatomic, assign) ViewFor viewFor;

/// Configure cell with user (keeps old API, defaults to ViewForDefault)
- (void)configureWithUser:(UserModel *)user indexPath:(NSIndexPath *)indexPath;

/// Preferred API: pass the view mode explicitly
- (void)configureWithUser:(UserModel *)user
                indexPath:(NSIndexPath *)indexPath
                  viewFor:(ViewFor)viewFor;

+ (NSString *)reuseIdentifier;

@end

NS_ASSUME_NONNULL_END
