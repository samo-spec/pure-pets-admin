#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PPAlertType) {
    PPAlertTypeSuccess,
    PPAlertTypeError,
    PPAlertTypeWarning,
    PPAlertTypeInfo,
    PPAlertTypeConfirmation,
    PPAlertTypeTextInput
};
typedef void (^AlertCompletionBlock)(NSString * _Nullable text, BOOL didConfirm);
typedef void (^PPAlertSimpleActionBlock)(void);

@interface PPAlert : UIView

- (instancetype)initWithType:(PPAlertType)type
                      title:(NSString *)title
                   subtitle:(NSString *)subtitle
                       icon:(UIImage *)icon
                confirmTitle:(NSString * _Nullable)confirmTitle
                 cancelTitle:(NSString * _Nullable)cancelTitle
               confirmAction:(AlertCompletionBlock _Nullable)confirmAction
                cancelAction:(void(^ _Nullable)(void))cancelAction;

- (void)showInViewController:(UIViewController *)vc;

@end

@interface AlertHelper : NSObject

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
             OKAction:(AlertCompletionBlock _Nullable)okAction;

+ (void)showFailIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion;

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString *)cancelTitle
                      icon:(UIImage * _Nullable)icon
              confirmBlock:(AlertCompletionBlock _Nullable)confirmBlock
               cancelBlock:(void(^ _Nullable)(void))cancelBlock;

+ (void)showThreeActionConfirmationIn:(UIViewController *)vc
                                title:(NSString *)title
                             subtitle:(NSString * _Nullable)subtitle
                        primaryButton:(NSString *)primaryTitle
                         primaryStyle:(UIAlertActionStyle)primaryStyle
                      secondaryButton:(NSString *)secondaryTitle
                       secondaryStyle:(UIAlertActionStyle)secondaryStyle
                       tertiaryButton:(NSString *)tertiaryTitle
                        tertiaryStyle:(UIAlertActionStyle)tertiaryStyle
                         primaryBlock:(PPAlertSimpleActionBlock _Nullable)primaryBlock
                       secondaryBlock:(PPAlertSimpleActionBlock _Nullable)secondaryBlock
                        tertiaryBlock:(PPAlertSimpleActionBlock _Nullable)tertiaryBlock;

+ (void)showTextFieldAlertIn:(UIViewController *)vc
                       title:(NSString *)title
                    subtitle:(NSString * _Nullable)subtitle
                 placeholder:(NSString * _Nullable)placeholder
                 initialText:(NSString * _Nullable)initialText
                 confirmText:(NSString * _Nullable)confirmText
                  cancelText:(NSString * _Nullable)cancelText
                 completion:(AlertCompletionBlock)completion;

+ (void)showSuccessIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle;
+ (void)showErrorIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle;
+ (void)showWarningIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle;
+ (void)showInfoIn:(UIViewController *)vc title:(NSString *)title subtitle:(NSString * _Nullable)subtitle;

+ (void)showSuccessIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString *)subtitle
        confirmAction:(AlertCompletionBlock _Nullable)confirmAction
         cancelAction:(void (^)(void))cancelAction;

+ (void)showWarningIn:(UIViewController *)vc
                title:(NSString *)title
             subtitle:(NSString * _Nullable)subtitle
           completion:(void (^ _Nullable)(void))completion;

+ (void)showInfoIn:(UIViewController *)vc
             title:(NSString *)title
          subtitle:(NSString * _Nullable)subtitle
        completion:(void (^ _Nullable)(void))completion;

#pragma mark - Backward-compatible (old AlertHelper API)

+ (void)showAlertIn:(UIViewController *)vc
              title:(NSString *)title
           subtitle:(NSString *)subtitle;

+ (void)showAlertIn:(UIViewController *)vc
              title:(NSString *)title
           subtitle:(NSString *)subtitle
        placeholder:(NSString *)placeholder
           withType:(NSString *)type;

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
               placeholder:(NSString * _Nullable)placeholder
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString * _Nullable)cancelTitle
              confirmBlock:(void(^_Nullable)(void))confirmBlock
               cancelBlock:(void(^_Nullable)(void))cancelBlock;

+ (void)showConfirmationIn:(UIViewController *)vc
                     title:(NSString *)title
                  subtitle:(NSString *)subtitle
               placeholder:(NSString * _Nullable)placeholder
             confirmButton:(NSString *)confirmTitle
              cancelButton:(NSString * _Nullable)cancelTitle
                      icon:(UIImage * _Nullable)icon
              confirmBlock:(void(^_Nullable)(void))confirmBlock
               cancelBlock:(void(^_Nullable)(void))cancelBlock;

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
                subtitle:(NSString * _Nullable)subtitle
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
             confirmText:(NSString * _Nullable)confirmText
              cancelText:(NSString * _Nullable)cancelText
              completion:(void(^)(NSString * _Nullable text))completion;

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
                subtitle:(NSString * _Nullable)subtitle
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
             confirmText:(NSString * _Nullable)confirmText
              cancelText:(NSString * _Nullable)cancelText
             secureEntry:(BOOL)secureEntry
            keyboardType:(UIKeyboardType)keyboardType
              completion:(void(^)(NSString * _Nullable text))completion;

+ (void)showTextPromptIn:(UIViewController *)vc
                   title:(NSString *)title
             placeholder:(NSString * _Nullable)placeholder
             initialText:(NSString * _Nullable)initialText
              completion:(void(^)(NSString * _Nullable text))completion;

@end

NS_ASSUME_NONNULL_END
