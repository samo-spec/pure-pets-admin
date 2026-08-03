#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT UIColor *PPProviderCanvasColor(void);
FOUNDATION_EXPORT UIColor *PPProviderSurfaceColor(void);
FOUNDATION_EXPORT UIColor *PPProviderRaisedSurfaceColor(void);
FOUNDATION_EXPORT UIColor *PPProviderBrandColor(void);
FOUNDATION_EXPORT UIColor *PPProviderPrimaryTextColor(void);
FOUNDATION_EXPORT UIColor *PPProviderSecondaryTextColor(void);
FOUNDATION_EXPORT UIColor *PPProviderSeparatorColor(void);

FOUNDATION_EXPORT NSString *PPProviderLocalizedType(NSString * _Nullable providerType);
FOUNDATION_EXPORT NSString *PPProviderLocalizedStatus(NSString * _Nullable status);
FOUNDATION_EXPORT NSString *PPProviderLocalizedBillingInterval(NSString * _Nullable interval);
FOUNDATION_EXPORT UIColor *PPProviderStatusColor(NSString * _Nullable status);
FOUNDATION_EXPORT NSString *PPProviderLocalizedText(NSDictionary * _Nullable value, NSString *fallback);
FOUNDATION_EXPORT NSString *PPProviderDateText(NSDate * _Nullable date);
FOUNDATION_EXPORT NSString *PPProviderMoneyText(double amount, NSString * _Nullable currency);

@interface PPProviderContextHeaderView : UIView
@property (nonatomic, strong, readonly) UILabel *metricLabel;
- (instancetype)initWithTitle:(NSString *)title
                     subtitle:(NSString *)subtitle
                       symbol:(NSString *)symbol;
- (void)setMetricText:(NSString *)text;
@end

@interface PPProviderStateView : UIView
@property (nonatomic, copy, nullable) void (^retryHandler)(void);
- (void)showLoadingWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
- (void)showEmptyWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol;
- (void)showErrorWithTitle:(NSString *)title subtitle:(NSString *)subtitle;
@end

@interface PPProviderRecordCell : UITableViewCell
- (void)configureWithTitle:(NSString *)title
                  subtitle:(NSString *)subtitle
                    detail:(NSString *)detail
                    status:(NSString *)status
                    symbol:(NSString *)symbol
                actionable:(BOOL)actionable;
@end

NS_ASSUME_NONNULL_END