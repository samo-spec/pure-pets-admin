// In PPSelectOptionViewController.h
#import <UIKit/UIKit.h>
@class XLFormViewController, XLFormRowDescriptor;
//NS_ASSUME_NONNULL_BEGIN
//NS_ASSUME_NONNULL_END
// Simple selection callback
NS_ASSUME_NONNULL_BEGIN
typedef void(^PPSelectOptionBlock)(id _Nullable selectedObject);
 


@interface PPSelectUsersViewController : UITableViewController <UISearchBarDelegate>

/// ✅ You MUST set these when presenting from an XLForm controller
@property (nonatomic, weak) XLFormViewController *parentForm;   // used by updateRowValue:
@property (nonatomic, weak) XLFormRowDescriptor *rowDescriptor; // the row to update
@property (nonatomic, assign) BOOL  imageLoaded;
/// Data
@property (nonatomic, copy)   NSArray *allOptions;
@property (nonatomic, copy)   NSArray *filteredOptions;
@property (nonatomic, strong) id selectedOption;
@property (nonatomic, copy)   NSArray<NSString *> *preselectedOptionIDs;

/// UI/behavior
@property (nonatomic, assign) BOOL showSearchBar; // default YES
@property (nonatomic, assign) PPSelectOptionPresentationStyle presentationStyle; // default .Sheet
@property (nonatomic, strong) UIView *searchContainer;

/// Callback fired on Done:
/// - single select -> selected object
/// - multi select  -> NSArray of selected objects
@property (nonatomic, copy) PPSelectOptionBlock onSelectOption;

/// Designated initializer
- (instancetype)initWithOptions:(NSArray *)options
                          title:(NSString *)title
                            row:(XLFormRowDescriptor *)row
               presentationStyle:(PPSelectOptionPresentationStyle)style
                     completion:(PPSelectOptionBlock _Nullable)completion;

/// ✅ Convenience initializer you’re calling
- (instancetype)initWithCompletion:(PPSelectOptionBlock _Nullable)completion;

@end
NS_ASSUME_NONNULL_END
