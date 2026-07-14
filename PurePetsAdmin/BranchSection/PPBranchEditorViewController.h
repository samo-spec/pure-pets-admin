#import <UIKit/UIKit.h>
@class PPBranchModel;

NS_ASSUME_NONNULL_BEGIN

@interface PPBranchEditorViewController : UITableViewController
- (instancetype)initWithBranch:(nullable PPBranchModel *)branch;
@end

NS_ASSUME_NONNULL_END

