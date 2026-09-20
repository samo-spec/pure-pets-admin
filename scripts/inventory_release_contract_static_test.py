#!/usr/bin/env python3
"""Release-contract checks for Admin live pets/accessories/food inventory paths.

These checks intentionally fail closed on direct Firestore inventory mutations from
staff UI code. Canonical mutations must pass through the audited callable facade.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCOPES = [
    ROOT / "PurePetsAdmin" / "AccessorySection",
    ROOT / "PurePetsAdmin" / "Features" / "Inventory",
    ROOT / "PurePetsAdmin" / "BranchSection",
]

sources = []
for scope in SCOPES:
    sources.extend(scope.rglob("*.swift"))
    sources.extend(scope.rglob("*.m"))

violations = []
mutation = re.compile(r"\.(?:updateData|setData|delete|deleteDocument|addDocument)\s*\(")
for path in sources:
    text = path.read_text(encoding="utf-8")
    for match in mutation.finditer(text):
        # A Firestore chain can span a few lines, but should never require a
        # multi-kilobyte look-behind. Keep this tight so an earlier read does
        # not get falsely paired with a later callable-safe mutation.
        statement_start = max(
            text.rfind("\n\n", 0, match.start()),
            text.rfind(";", 0, match.start()),
            match.start() - 900,
        )
        context = text[statement_start:match.end()]
        if 'collection("petAccessories")' not in context:
            continue
        line = text.count("\n", 0, match.start()) + 1
        excerpt = " ".join(context.split())[-220:]
        violations.append(f"{path.relative_to(ROOT)}:{line}: {excerpt}")

if violations:
    raise AssertionError(
        "Protected inventory must not be mutated directly from Admin UI code:\n" + "\n".join(violations)
    )

command_service = (ROOT / "PurePetsAdmin" / "AccessorySection" / "PPInventoryCommandService.swift").read_text(encoding="utf-8")
assert 'httpsCallable("validateInventoryChange")' in command_service
assert 'httpsCallable("adjustBranchStock")' in command_service

quarantine = (ROOT / "PurePetsAdmin" / "Features" / "Inventory" / "QuarantineStudioSheet.swift").read_text(encoding="utf-8")
assert 'action: "update_unit_profile"' in quarantine, "Quarantine clinical-note updates must use the audited unit-profile command"

inventory_list = (ROOT / "PurePetsAdmin" / "AccessorySection" / "PPInventoryListView.swift").read_text(encoding="utf-8")
toggle_start = inventory_list.index("func toggleStockAvailability(for item: PetAccessory)")
toggle_end = inventory_list.index("// MARK: - Quick App Market Visibility Toggle", toggle_start)
toggle_body = inventory_list[toggle_start:toggle_end]
assert "adjustStock(" not in toggle_body, "Availability controls must never reconcile factual stock quantities"
assert "marked_no_stock" not in inventory_list, "Legacy destructive availability reason must not remain in Admin inventory UI"
assert "reconciled_in_stock" not in inventory_list, "Legacy destructive availability reason must not remain in Admin inventory UI"

print("inventory release contract static checks passed")
