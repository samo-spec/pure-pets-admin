#!/usr/bin/env python3
from pathlib import Path


def require_replace(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new and new in text:
            return
        raise RuntimeError(f"Expected block missing in {path}: {old!r}")
    p.write_text(text.replace(old, new, 1))

accessory = "PurePetsAdmin/AccessorySection/AddAccessoryViewController.m"
require_replace(accessory, "    PPApplyElevatedShadow(dock);\n", "")

models = "PurePetsAdmin/Payments/PPPaymentManagementModels.m"
require_replace(
    models,
    "    if ([normalized isEqualToString:@\"shipped\"]) return PPPaymentAdminDisplayTitleForOrderStatus(@\"shipped\");\n"
    "    if ([normalized isEqualToString:@\"delivered\"]) return PPPaymentAdminDisplayTitleForOrderStatus(@\"delivered\");\n",
    "",
)

print("Finalized runtime screenshot V6 source.")
