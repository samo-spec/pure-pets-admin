#!/usr/bin/env python3
from pathlib import Path
import re

vc_path = Path("PurePetsAdmin/Payments/PPPaymentManagementViewController.m")
cell_path = Path("PurePetsAdmin/Payments/PPPaymentManagementRecordCell.m")
settings_path = Path("PurePetsAdmin/Payments/PPPaymentBasicsSettingsViewController.m")

vc = vc_path.read_text(encoding="utf-8")
vc = re.sub(
    r"\n/\*\nAct as a multi-agent system with 3 roles:.*?\n\*/\n",
    "\n",
    vc,
    flags=re.S,
)
vc = vc.replace("CGFloat horizontal = 16.0;", "CGFloat horizontal = PPScreenMargin;")
vc = vc.replace("CGFloat vertical = 10.0;", "CGFloat vertical = PPSpaceSM;")
vc = vc.replace("CGFloat searchHeight = 50.0;", "CGFloat searchHeight = PPButtonHeightLG;")
vc = vc.replace("search.backgroundColor = AppForgroundColr;", "search.backgroundColor = [UIColor ppSurface];")
vc = vc.replace("self.refreshControl.tintColor = [UIColor ppPrimaryShiner];", "self.refreshControl.tintColor = [UIColor ppPrimary];")
vc = vc.replace(
    "[AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:error.localizedDescription ?: kLang(@\"PaymentMgmt_Error_LoadPayments\")];",
    "[AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:kLang(@\"PaymentMgmt_Error_LoadPayments\")];",
)
vc = vc.replace(
    "[PPToast toast:error.localizedDescription ?: kLang(@\"PPOrder_Error_PartialRead\")",
    "[PPToast toast:kLang(@\"PPOrder_Error_PartialRead\")",
)
vc = vc.replace(
    "cell.textLabel.font = [Styling fontBold:15];\n        cell.detailTextLabel.font = [Styling fontRegular:13];",
    "cell.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:15]];\n        cell.textLabel.adjustsFontForContentSizeCategory = YES;\n        cell.detailTextLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontRegular:13]];\n        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;",
)
vc = vc.replace(
    "cell.textLabel.font = [Styling fontBold:16];\n        cell.detailTextLabel.font = [Styling fontRegular:13];",
    "cell.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontBold:16]];\n        cell.textLabel.adjustsFontForContentSizeCategory = YES;\n        cell.detailTextLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:[Styling fontRegular:13]];\n        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;",
)
vc_path.write_text(vc, encoding="utf-8")

cell = cell_path.read_text(encoding="utf-8")
old = '''    [self pp_refreshAdaptiveLayout];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [@[orderTitle ?: @"", amountText ?: @"", customerText ?: @"", statusTitle ?: @""] componentsJoinedByString:@", "];
    self.accessibilityHint = actionTitle ?: @"";
    self.accessibilityTraits = UIAccessibilityTraitButton;
'''
new = '''    [self pp_refreshAdaptiveLayout];
    self.isAccessibilityElement = NO;
    _surfaceView.isAccessibilityElement = NO;
    _statusContainer.isAccessibilityElement = YES;
    _statusContainer.accessibilityLabel = statusTitle ?: @"";
    _statusContainer.accessibilityTraits = UIAccessibilityTraitStaticText;
    _statusIconView.accessibilityElementsHidden = YES;
    _statusLabel.isAccessibilityElement = NO;
    _actionButton.accessibilityLabel = actionTitle ?: @"";
'''
if old in cell:
    cell = cell.replace(old, new)
elif "_statusContainer.isAccessibilityElement = YES;" not in cell:
    raise SystemExit("Payment record accessibility contract not found")
cell_path.write_text(cell, encoding="utf-8")

settings = settings_path.read_text(encoding="utf-8")
settings = settings.replace("button.contentEdgeInsets = UIEdgeInsetsMake(7, 14, 7, 14);", "button.contentEdgeInsets = UIEdgeInsetsMake(PPSpaceSM, PPSpaceBase, PPSpaceSM, PPSpaceBase);")
settings = settings.replace("button.layer.cornerRadius = 18.0;", "button.layer.cornerRadius = PPCorner16;")
settings = settings.replace("button.titleLabel.font = [Styling fontMedium:17];", "button.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCallout] scaledFontForFont:[Styling fontBold:15]];\n        button.titleLabel.adjustsFontForContentSizeCategory = YES;")
settings = settings.replace("[button.heightAnchor constraintEqualToConstant:36.0].active = YES;", "[button.heightAnchor constraintGreaterThanOrEqualToConstant:PPTouchTargetMin].active = YES;")
settings = settings.replace("[button.widthAnchor constraintGreaterThanOrEqualToConstant:58.0].active = YES;", "[button.widthAnchor constraintGreaterThanOrEqualToConstant:72.0].active = YES;")
settings = settings.replace("        [PPButtonHelper attachTapAnimationToButton:button style:PPButtonAnimationStylePulse];\n", "")
settings = settings.replace("UIColor *titleColor = [UIColor ppTextPrimary];", "UIColor *titleColor = UIColor.whiteColor;")
settings = settings.replace("self.saveButton.titleLabel.font = [Styling fontMedium:17];", "self.saveButton.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCallout] scaledFontForFont:[Styling fontBold:15]];\n    self.saveButton.titleLabel.adjustsFontForContentSizeCategory = YES;")
settings = settings.replace("self.saveButton.backgroundColor = AppBackgroundClr;", "self.saveButton.backgroundColor = enabled ? [UIColor ppPrimary] : [[UIColor ppPrimary] colorWithAlphaComponent:0.16];")
settings = settings.replace("self.saveButton.layer.borderColor = [borderColor colorWithAlphaComponent:0.18].CGColor;", "self.saveButton.layer.borderColor = UIColor.clearColor.CGColor;")
settings = settings.replace("self.saveButton.alpha = enabled ? 1.0 : 0.65;", "self.saveButton.alpha = enabled ? 1.0 : 0.72;")
settings = settings.replace(
    "[AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:error.localizedDescription ?: kLang(@\"PaymentMgmt_Error_LoadPayments\")];",
    "[AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:kLang(@\"PaymentMgmt_Error_LoadPayments\")];",
)
settings = settings.replace(
    "[AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:error.localizedDescription ?: kLang(@\"PaymentMgmt_Error_UpdateOrder\")];",
    "[AlertHelper showErrorIn:self title:kLang(@\"Error\") subtitle:kLang(@\"PaymentMgmt_Error_UpdateOrder\")];",
)
settings = settings.replace(
    "header.textLabel.font = [Styling fontMedium:15];",
    "header.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleHeadline] scaledFontForFont:[Styling fontMedium:15]];\n    header.textLabel.adjustsFontForContentSizeCategory = YES;",
)
settings = settings.replace(
    "footer.textLabel.font = [Styling fontRegular:13];",
    "footer.textLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:[Styling fontRegular:13]];\n    footer.textLabel.adjustsFontForContentSizeCategory = YES;",
)
settings_path.write_text(settings, encoding="utf-8")

print("Applied Work/Payments V6 refinements")
