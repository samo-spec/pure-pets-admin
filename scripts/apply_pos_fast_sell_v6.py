#!/usr/bin/env python3
from pathlib import Path

path = Path("PurePetsAdmin/POS/PPPOSFastSellViewController.m")
text = path.read_text()


def replace(old: str, new: str, count: int = 1) -> None:
    global text
    if text.count(old) < count:
        raise RuntimeError(f"Missing POS source block: {old[:100]!r}")
    text = text.replace(old, new, count)

# Remove one-off ivory/gold visual language. POS now uses the same semantic
# surface/primary/hairline system as every other Admin workflow.
start = text.index("// Warm till surface")
end = text.index("static BOOL PPFastSellAccessibilitySize", start)
text = text[:start] + text[end:]
text = text.replace("PPFastSellWarmIvory()", "[UIColor ppSurface]")
text = text.replace("PPFastSellOpsGold()", "[UIColor ppPrimary]")
text = text.replace("PPFastSellGoldHairline()", "[UIColor ppSurfaceBorder]")

replace(
    "static NSInteger const kPPPOSSearchFieldTag = 6101;\n",
    "static NSInteger const kPPPOSSearchFieldTag = 6101;\nstatic NSInteger const kPPPOSCatalogStateAuxTag = 6102;\n",
)
replace(
    "@property (nonatomic, assign) BOOL didPrepareEntrance;\n@property (nonatomic, strong) UILabel *countChip;",
    "@property (nonatomic, assign) BOOL didPrepareEntrance;\n@property (nonatomic, assign) BOOL isSubmittingOrder;\n@property (nonatomic, strong) UILabel *countChip;",
)

# Dense table rhythm and safe action-dock clearance.
replace("    self.tableView.estimatedRowHeight = 92.0;", "    self.tableView.estimatedRowHeight = 84.0;")
replace(
    "    UIEdgeInsets insets = UIEdgeInsetsMake(PPSpaceBase, 0.0, CGRectGetHeight(self.checkoutButton.superview.bounds) + PPSpaceLG, 0.0);",
    "    UIEdgeInsets insets = UIEdgeInsetsMake(PPSpaceSM, 0.0, CGRectGetHeight(self.checkoutButton.superview.bounds) + PPSpaceSM, 0.0);",
)

# Never expose raw backend errors to staff UI.
replace(
    "            self.catalogErrorMessage = error.localizedDescription;",
    "            self.catalogErrorMessage = error ? kLang(@\"POS_CatalogLoadFailed\") : nil;",
)

# Prevent double submission while keeping the exact service payload and method.
replace(
    "- (void)didTapCheckout {\n    if (self.cart.count == 0) {",
    "- (void)didTapCheckout {\n    if (self.isSubmittingOrder) return;\n    if (self.cart.count == 0) {",
)
replace(
    "    [self presentViewController:alert animated:YES completion:nil];\n}\n\n- (void)submitOrder:(NSString *)method {",
    "    UIPopoverPresentationController *popover = alert.popoverPresentationController;\n    if (popover) {\n        popover.sourceView = self.checkoutButton;\n        popover.sourceRect = self.checkoutButton.bounds;\n    }\n    [self presentViewController:alert animated:YES completion:nil];\n}\n\n- (void)submitOrder:(NSString *)method {\n    if (self.isSubmittingOrder) return;\n    self.isSubmittingOrder = YES;\n    [self refreshCartPresentation];",
)
replace(
    "        dispatch_async(dispatch_get_main_queue(), ^{\n            if (error) {\n                [AlertHelper showAlertIn:self title:kLang(@\"Error_Title\") subtitle:error.localizedDescription];\n            } else {",
    "        dispatch_async(dispatch_get_main_queue(), ^{\n            self.isSubmittingOrder = NO;\n            if (error) {\n                [self refreshCartPresentation];\n                [AlertHelper showAlertIn:self title:kLang(@\"Error_Title\") subtitle:kLang(@\"POS_OrderSubmitFailed\")];\n            } else {",
)

# Checkout is a safe-area action dock, not a floating decorative card.
replace("    dock.backgroundColor = [UIColor ppSurface];\n    dock.layer.cornerRadius = PPCornerCard;", "    dock.backgroundColor = [UIColor ppSurface];\n    dock.layer.cornerRadius = 0.0;")
replace("    dock.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;\n    dock.layer.shadowColor = UIColor.blackColor.CGColor;\n    dock.layer.shadowOpacity = PPShadowSubtleOpacity;\n    dock.layer.shadowRadius = PPShadowCardRadius;\n    dock.layer.shadowOffset = CGSizeMake(0.0, PPShadowCardOffsetY);", "    dock.layer.borderColor = [UIColor ppSurfaceBorder].CGColor;")
replace(
    "        [dock.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],\n        [dock.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],\n        [dock.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],\n        [dock.heightAnchor constraintGreaterThanOrEqualToConstant:84.0],",
    "        [dock.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],\n        [dock.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],\n        [dock.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],\n        [dock.heightAnchor constraintGreaterThanOrEqualToConstant:PPButtonHeightLG + PPSpaceXL],",
)
replace("        [captionLabel.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:PPSpaceLG],", "        [captionLabel.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:PPScreenMargin],")
replace("        [countChip.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-PPSpaceLG],", "        [countChip.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-PPScreenMargin],")
replace("    self.checkoutButton.layer.cornerRadius = PPCornerMedium;", "    self.checkoutButton.layer.cornerRadius = PPCorner16;")
replace(
    "    [self.checkoutButton setImage:[UIImage systemImageNamed:@\"arrow.left.circle.fill\"] forState:UIControlStateNormal];",
    "    NSString *checkoutSymbol = [Language isRTL] ? @\"arrow.left.circle.fill\" : @\"arrow.right.circle.fill\";\n    [self.checkoutButton setImage:[UIImage systemImageNamed:checkoutSymbol] forState:UIControlStateNormal];",
)

# Search chrome is compact and the search glyph follows language direction.
replace("    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 76.0)];", "    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 64.0)];")
replace(
    "    field.leftView = searchGlyph;\n    field.leftViewMode = UITextFieldViewModeAlways;",
    "    if ([Language isRTL]) {\n        field.rightView = searchGlyph;\n        field.rightViewMode = UITextFieldViewModeAlways;\n    } else {\n        field.leftView = searchGlyph;\n        field.leftViewMode = UITextFieldViewModeAlways;\n    }",
)

# The checkout state itself owns whether the primary action can run.
replace(
    "    self.checkoutButton.enabled = self.cart.count > 0;\n    self.checkoutButton.alpha = self.checkoutButton.enabled ? 1.0 : 0.55;",
    "    [self.checkoutButton setTitle:kLang(@\"POS_Checkout\") forState:UIControlStateNormal];\n    self.checkoutButton.enabled = self.cart.count > 0 && !self.isSubmittingOrder;\n    self.checkoutButton.alpha = self.checkoutButton.enabled ? 1.0 : 0.55;",
)

# Calmer inventory rows and compliant 44x44 stepper hit targets.
replace("        cell.contentView.layer.cornerRadius = PPCornerMedium;", "        cell.contentView.layer.cornerRadius = PPCorner16;")
replace("        cell.layoutMargins = UIEdgeInsetsMake(PPSpaceLG, PPSpaceLG, PPSpaceLG, PPSpaceLG);", "        cell.layoutMargins = UIEdgeInsetsMake(PPSpaceMD, PPSpaceBase, PPSpaceMD, PPSpaceBase);")
replace("    minus.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.10];", "    minus.backgroundColor = [[UIColor ppPrimary] colorWithAlphaComponent:0.08];")
replace("    minus.layer.cornerRadius = 12.0;", "    minus.layer.cornerRadius = PPCornerSmall;")
replace("    plus.layer.cornerRadius = 12.0;", "    plus.layer.cornerRadius = PPCornerSmall;")
replace("        [minus.widthAnchor constraintEqualToConstant:36.0],", "        [minus.widthAnchor constraintEqualToConstant:PPTouchTargetMin],")
replace("        [plus.widthAnchor constraintEqualToConstant:36.0],", "        [plus.widthAnchor constraintEqualToConstant:PPTouchTargetMin],")

replace("    button.layer.cornerRadius = PPCornerMedium;", "    button.layer.cornerRadius = PPCorner16;", 1)

# Catalog state reuse previously removed UIKit's built-in labels from the cell.
# Only remove transient spinner/retry views that we explicitly tag.
replace(
    "        [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];\n        [self configureCatalogStateCell:cell];",
    "        for (UIView *subview in cell.contentView.subviews.copy) {\n            if (subview.tag == kPPPOSCatalogStateAuxTag) [subview removeFromSuperview];\n        }\n        [self configureCatalogStateCell:cell];",
)
replace("        spinner.translatesAutoresizingMaskIntoConstraints = NO;", "        spinner.translatesAutoresizingMaskIntoConstraints = NO;\n        spinner.tag = kPPPOSCatalogStateAuxTag;", 1)
replace("        retry.translatesAutoresizingMaskIntoConstraints = NO;", "        retry.translatesAutoresizingMaskIntoConstraints = NO;\n        retry.tag = kPPPOSCatalogStateAuxTag;", 1)

path.write_text(text)

# Add only the user-facing error strings needed by this production pass.
strings = {
    Path("PurePetsAdmin/en.lproj/Localizable.strings"): {
        "POS_CatalogLoadFailed": "Couldn’t load the catalog. Try again.",
        "POS_OrderSubmitFailed": "Couldn’t complete the sale. Try again.",
    },
    Path("PurePetsAdmin/ar.lproj/Localizable.strings"): {
        "POS_CatalogLoadFailed": "تعذر تحميل المنتجات. حاول مرة أخرى.",
        "POS_OrderSubmitFailed": "تعذر إتمام عملية البيع. حاول مرة أخرى.",
    },
}
for strings_path, additions in strings.items():
    source = strings_path.read_text()
    for key, value in additions.items():
        if f'"{key}"' not in source:
            source += f'\n"{key}" = "{value}";\n'
    strings_path.write_text(source)

print("Applied POS Fast Sell V6 pass.")
