#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface PPPaymentManagementRecordCell : UITableViewCell

@property (nonatomic, strong, readonly) UIButton *actionButton;

- (void)configureWithOrderTitle:(NSString *)orderTitle
                     amountText:(NSString *)amountText
                   customerText:(NSString *)customerText
                   subtitleText:(NSString *)subtitleText
                    statusTitle:(NSString *)statusTitle
                    statusColor:(UIColor *)statusColor
                   statusSymbol:(NSString *)statusSymbol
                    actionTitle:(NSString *)actionTitle
                     actionTint:(UIColor *)actionTint
                prominentAction:(BOOL)prominentAction;

@end

NS_ASSUME_NONNULL_END
