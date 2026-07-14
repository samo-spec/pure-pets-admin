#import <UIKit/UIKit.h>
@class PPAgentModel;

NS_ASSUME_NONNULL_BEGIN

@interface PPAgentEditorViewController : UITableViewController
- (instancetype)initWithAgent:(nullable PPAgentModel *)agent;
@end

NS_ASSUME_NONNULL_END