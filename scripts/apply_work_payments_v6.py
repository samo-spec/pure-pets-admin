#!/usr/bin/env python3
from pathlib import Path
import re

vc_path = Path("PurePetsAdmin/Payments/PPPaymentManagementViewController.m")
cell_path = Path("PurePetsAdmin/Payments/PPPaymentManagementRecordCell.m")

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
if old not in cell:
    raise SystemExit("Payment record accessibility block not found")
cell = cell.replace(old, new)
cell_path.write_text(cell, encoding="utf-8")

print("Applied Work/Payments V6 refinements")
