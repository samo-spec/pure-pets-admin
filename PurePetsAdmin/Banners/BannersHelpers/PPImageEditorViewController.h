//
//  PPImageEditorViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 11/09/2025.
//


//
//  PPImageEditorViewController.h
//  PurePets
//
//  Created by Admin on 11/09/2025.
//

#import <UIKit/UIKit.h>
#import "PPImageEditor.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^PPImageEditorCompletion)(UIImage * _Nullable editedImage);

@interface PPImageEditorViewController : UIViewController

- (instancetype)initWithImage:(UIImage *)image
                   completion:(PPImageEditorCompletion)completion;

@end

NS_ASSUME_NONNULL_END
