//
//  PPNavigationController.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 07/09/2025.
//


// In PPNavigationController.m
#import "PPNavigationController.h"
#import "Language.h"

@implementation PPNavigationController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self pp_applyPurePetsNavigationAppearance];
}

- (void)pp_applyPurePetsNavigationAppearance {
    UIFont *titleFont = [UIFontMetrics.defaultMetrics scaledFontForFont:[Styling fontBold:20.0]];
    NSDictionary *titleAttributes = @{
        NSFontAttributeName: titleFont,
        NSForegroundColorAttributeName: PrimaryTextClr ?: UIColor.labelColor
    };

    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = UIColor.clearColor;
    appearance.shadowColor = UIColor.clearColor;
    appearance.titleTextAttributes = titleAttributes;
    appearance.largeTitleTextAttributes = titleAttributes;

    self.navigationBar.standardAppearance = appearance;
    self.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationBar.compactAppearance = appearance;
    self.navigationBar.tintColor = AppPrimaryClr ?: UIColor.systemBlueColor;
    self.navigationBar.prefersLargeTitles = NO;
}

#pragma mark - Background Button Factory

+ (UIButton *)setButtonAsBackroundButtonWithStyle:(UIButtonConfigurationCornerStyle)style {
    if (@available(iOS 26.0, *)) {
        return [self setButtonAsBackroundButtonWithStyle:style configType:PPButtonConfigrationGlass];
    } else {
        return [self setButtonAsBackroundButtonWithStyle:style configType:PPButtonConfigrationFilled];
    }
}

+ (UIButton *)setButtonAsBackroundButtonWithStyle:(UIButtonConfigurationCornerStyle)style
                                       configType:(PPButtonConfigration)configType {
    UIButton *bgButton;

    if (@available(iOS 26.0, *)) {
        UIButtonConfiguration *cfg = configType == PPButtonConfigrationGlass ? [UIButtonConfiguration glassButtonConfiguration] :
        configType == PPButtonConfigrationClearGlass ? [UIButtonConfiguration clearGlassButtonConfiguration] :
        configType == PPButtonConfigrationFilled ? [UIButtonConfiguration filledButtonConfiguration] :
        configType == PPButtonConfigrationPromp ? [UIButtonConfiguration prominentGlassButtonConfiguration] :
        configType == PPButtonConfigrationClearPromp ? [UIButtonConfiguration prominentClearGlassButtonConfiguration] :
        configType == PPButtonConfigrationTintedBorderd ? [UIButtonConfiguration borderedTintedButtonConfiguration] :
        configType == PPButtonConfigrationTinted ? [UIButtonConfiguration tintedButtonConfiguration] : [UIButtonConfiguration plainButtonConfiguration];

        cfg.cornerStyle = style;
        cfg.contentInsets = NSDirectionalEdgeInsetsMake(12, 12, 12, 12);
        cfg.background.cornerRadius = 0;
        cfg.background.backgroundColor = [UIColor clearColor];
        cfg.baseBackgroundColor = [UIColor clearColor];

        bgButton = [UIButton buttonWithType:UIButtonTypeSystem];
        bgButton.configuration = cfg;
        bgButton.clipsToBounds = NO;
        bgButton.backgroundColor = [UIColor clearColor];
        bgButton.layer.masksToBounds = NO;
    } else {
        bgButton = [UIButton buttonWithType:UIButtonTypeSystem];
        bgButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        bgButton.layer.cornerRadius = 16;
        bgButton.layer.masksToBounds = YES;
        bgButton.layer.shadowColor = AppShadowColor.CGColor;
        bgButton.layer.shadowOpacity = 0.15;
        bgButton.layer.shadowRadius = 8;
        bgButton.layer.shadowOffset = CGSizeMake(0, 4);
    }

    bgButton.translatesAutoresizingMaskIntoConstraints = NO;
    return bgButton;
}

#pragma mark - Navigation Overrides

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (animated && [Language isRTL]) {
        CATransition *transition = [CATransition animation];
        transition.duration = 0.35;
        transition.type = kCATransitionPush;
        transition.subtype = kCATransitionFromRight; // 👈 RTL push
        [self.view.layer addAnimation:transition forKey:kCATransition];
        [super pushViewController:viewController animated:NO];
    } else {
        [super pushViewController:viewController animated:animated];
    }
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    if (animated && [Language isRTL]) {
        CATransition *transition = [CATransition animation];
        transition.duration = 0.35;
        transition.type = kCATransitionPush;
        transition.subtype = kCATransitionFromLeft; // 👈 RTL pop
        [self.view.layer addAnimation:transition forKey:kCATransition];
        return [super popViewControllerAnimated:NO];
    } else {
        return [super popViewControllerAnimated:animated];
    }
}

@end
