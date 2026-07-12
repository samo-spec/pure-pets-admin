//
//  PPImageCollectionRow.h
//  PurePetsAdmin
//
//  XLForm cell wrapping PPImageCollection.
//  Replaces PPPickerRow — matches iOS source-of-truth flow.
//

#import <UIKit/UIKit.h>
#import "XLForm.h"
#import "PPImageCollection.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const XLFormRowDescriptorTypePPImageCollection;

/// Registers the row type with XLForm. Call once at app launch.
void PPImageCollectionRow_register(void);

@interface PPImageCollectionRow : XLFormBaseCell <PPImageCollectionDelegate>

/// Embedded picker view (read-only after configure).
@property (nonatomic, strong, readonly) PPImageCollection *imageCollection;

/// Maximum number of images (default 8). Set via cellConfigAtConfigure.
@property (nonatomic, assign) NSInteger maxImages;

/// Optional preload URL string (single-image mode). Loads image and shows in collection.
@property (nonatomic, copy, nullable) NSString *preloadImageURL;

/// Optional preload URL array (multi-image mode, e.g. editing accessories).
/// Set via cellConfigAtConfigure before the cell appears.
@property (nonatomic, copy, nullable) NSArray<NSString *> *preloadImageURLs;

/// YES once the user adds/removes images after the initial preload.
/// Use this to detect whether images actually changed when saving.
@property (nonatomic, assign, readonly) BOOL imagesModified;

@end

NS_ASSUME_NONNULL_END
