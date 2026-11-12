#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Presentation only. These views receive formatted content; they never read
// Firebase, infer eligibility, retain a command, or perform an operation.
FOUNDATION_EXPORT UILabel *PPSubscriptionLabel(UIFontTextStyle style, CGFloat size, BOOL bold);
FOUNDATION_EXPORT UIView *PPSubscriptionIdentity(NSString *name, NSString *type, NSString *status, UIColor *statusColor);
FOUNDATION_EXPORT UIView *PPSubscriptionPlanSummary(NSString *caption, NSString *name, NSString *price, NSString *interval);
FOUNDATION_EXPORT UIView *PPSubscriptionNotice(NSString *message, NSString *symbol, BOOL warning);
FOUNDATION_EXPORT UITableViewCell *PPSubscriptionHostedCell(UIView *content);
FOUNDATION_EXPORT UITableViewCell *PPSubscriptionFactCell(NSString *title, NSString *value, NSString *symbol);
FOUNDATION_EXPORT UITableViewCell *PPSubscriptionActionCell(NSString *title, NSString *impact, NSString *symbol, BOOL destructive, BOOL emphasized, BOOL enabled);
FOUNDATION_EXPORT UIView *PPSubscriptionSectionText(NSString *text, BOOL heading);
FOUNDATION_EXPORT UIButton *PPSubscriptionCommitButton(NSString *title, BOOL destructive);

@interface PPSubscriptionReasonView : UIView
@property (nonatomic, strong, readonly) UITextView *textView;
- (void)updateCount:(NSUInteger)count limit:(NSUInteger)limit placeholderVisible:(BOOL)placeholderVisible exceedsLimit:(BOOL)exceedsLimit;
- (void)setEditing:(BOOL)editing;
@end

NS_ASSUME_NONNULL_END
