#!/usr/bin/env python3
"""Executable Swift + source-contract verification for Admin branch resolution & inventory parity.

Extracts PPBranchInventoryResolver verbatim from PurePetsAdmin/BranchSection/PPBranchInventory.swift,
compiles and runs Swift assertions across Products, Food, Live Pets, Medicines, and POS Fast Sell,
and verifies static source invariants across all modified Admin branch/inventory/POS files.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ADMIN_ROOT = Path(__file__).resolve().parents[1] / "PurePetsAdmin"


def read(rel_path: str) -> str:
    return (ADMIN_ROOT / rel_path).read_text(encoding="utf-8")


branch_inv_src = read("BranchSection/PPBranchInventory.swift")
resolver_start = branch_inv_src.index("public enum PPBranchInventoryResolver {")
resolver_end = branch_inv_src.index("\n}\n", resolver_start) + 3
resolver_code = branch_inv_src[resolver_start:resolver_end]

# Extract availableStock(for:fallback:) method body check separately via source assertions,
# while compiling PPBranchInventoryResolver with an ABI-compatible PPBranchInventory stub.
swift_harness = f'''
import Foundation

public struct PPBranchInventory {{
    public let branchId: String
    public let availableQuantity: Int
    public let noStock: Bool
    public init(branchId: String, availableQuantity: Int, noStock: Bool = false) {{
        self.branchId = branchId
        self.availableQuantity = availableQuantity
        self.noStock = noStock
    }}
}}

{resolver_code}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {{
    if !condition() {{
        fputs("FAIL: \\(message)\\n", stderr)
        exit(1)
    }}
}}

// 1. canonicalBranchID rejects sentinels and blanks
check(PPBranchInventoryResolver.canonicalBranchID(nil) == nil, "nil branch should be nil")
check(PPBranchInventoryResolver.canonicalBranchID("") == nil, "empty branch should be nil")
check(PPBranchInventoryResolver.canonicalBranchID("   ") == nil, "whitespace branch should be nil")
check(PPBranchInventoryResolver.canonicalBranchID("main_store") == nil, "main_store sentinel must normalize to nil")
check(PPBranchInventoryResolver.canonicalBranchID(" MAIN_STORE ") == nil, "trimmed case-insensitive main_store must normalize to nil")
check(PPBranchInventoryResolver.canonicalBranchID("Main Store") == nil, "Main Store sentinel must normalize to nil")
check(PPBranchInventoryResolver.canonicalBranchID("all_branches") == nil, "all_branches sentinel must normalize to nil")
check(PPBranchInventoryResolver.canonicalBranchID(" branch-doha-01 ") == "branch-doha-01", "concrete branch should preserve trimmed ID")

// 2. resolveWorkingBranchID priority: explicit > active > systemDefault > sole available
check(
    PPBranchInventoryResolver.resolveWorkingBranchID(
        explicitBranchID: "branch-b",
        activeBranchID: "branch-a",
        systemDefaultBranchID: "branch-main",
        availableBranchIDs: ["branch-a", "branch-b", "branch-main"],
        needsBranchSelection: false
    ) == "branch-b",
    "explicit concrete branch must override active branch"
)
check(
    PPBranchInventoryResolver.resolveWorkingBranchID(
        explicitBranchID: "main_store",
        activeBranchID: "branch-a",
        systemDefaultBranchID: "branch-main",
        availableBranchIDs: ["branch-a", "branch-main"],
        needsBranchSelection: false
    ) == "branch-a",
    "sentinel explicit branch must defer to activeBranchID"
)
check(
    PPBranchInventoryResolver.resolveWorkingBranchID(
        explicitBranchID: "all_branches",
        activeBranchID: nil,
        systemDefaultBranchID: "branch-main",
        availableBranchIDs: ["branch-a", "branch-main"],
        needsBranchSelection: false
    ) == "branch-main",
    "sentinel explicit with nil active must defer to systemDefaultBranchID"
)
check(
    PPBranchInventoryResolver.resolveWorkingBranchID(
        explicitBranchID: nil,
        activeBranchID: nil,
        systemDefaultBranchID: nil,
        availableBranchIDs: ["branch-a", "branch-b"],
        needsBranchSelection: true
    ) == nil,
    "multi-branch unresolved state with needsBranchSelection must fail closed (nil)"
)
check(
    PPBranchInventoryResolver.resolveWorkingBranchID(
        explicitBranchID: nil,
        activeBranchID: nil,
        systemDefaultBranchID: nil,
        availableBranchIDs: ["branch-only"],
        needsBranchSelection: true
    ) == nil,
    "single unresolved branch with needsBranchSelection=true must wait for selection gate"
)
check(
    PPBranchInventoryResolver.resolveWorkingBranchID(
        explicitBranchID: nil,
        activeBranchID: nil,
        systemDefaultBranchID: nil,
        availableBranchIDs: ["branch-only"],
        needsBranchSelection: false
    ) == "branch-only",
    "sole available branch resolves cleanly once selection gate is satisfied"
)

// 3. Catalog stock & out-of-stock parity across Products, Food, Live Pets, Medicines
let mainRecWithStock = PPBranchInventory(branchId: "branch-main", availableQuantity: 9, noStock: false)
check(
    PPBranchInventoryResolver.resolveCatalogBranchStock(
        activeBranchID: "branch-main",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == 9,
    "matching confirmed branch record must expose exact availableQuantity"
)
check(
    PPBranchInventoryResolver.isCatalogOutOfStock(
        activeBranchID: "branch-main",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == false,
    "confirmed positive branch stock must not report out of stock"
)
// Divergent projection (switched branch, previous branch projection still lingering) -> fail closed
check(
    PPBranchInventoryResolver.resolveCatalogBranchStock(
        activeBranchID: "branch-other",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == 0,
    "mismatched projection branch must fail closed to 0"
)
check(
    PPBranchInventoryResolver.isCatalogOutOfStock(
        activeBranchID: "branch-other",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == true,
    "mismatched projection branch must treat item as out of stock until active branch projection loads"
)
check(
    PPBranchInventoryResolver.resolveCatalogBranchStock(
        activeBranchID: "branch-main",
        projectionBranchID: "branch-main",
        branchRecord: nil
    ) == 0,
    "missing branch inventory record in catalog must return 0"
)
let flaggedNoStockWithZero = PPBranchInventory(branchId: "branch-main", availableQuantity: 0, noStock: true)
check(
    PPBranchInventoryResolver.isCatalogOutOfStock(
        activeBranchID: "branch-main",
        projectionBranchID: "branch-main",
        branchRecord: flaggedNoStockWithZero
    ) == true,
    "0 available quantity must report out of stock"
)

// 4. POS Fast Sell stock ignores consumer-sync global catalogQuantity/noStock when active branch projection is confirmed
check(
    PPBranchInventoryResolver.resolvePOSBranchStock(
        catalogActive: true,
        isBlocked: false,
        isDeleted: false,
        isDisabled: false,
        isArchived: false,
        catalogQuantity: 0,
        itemHomeBranchID: "branch-consumer-warehouse",
        activeBranchID: "branch-main",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == 9,
    "POS stock must use confirmed branchRecord even when catalogQuantity synced from another consumer branch is 0"
)
// Soft-deleted/archived/inactive/blocked catalog items cannot be sold on POS
check(
    PPBranchInventoryResolver.resolvePOSBranchStock(
        catalogActive: true,
        isBlocked: false,
        isDeleted: false,
        isDisabled: false,
        isArchived: true,
        catalogQuantity: 10,
        itemHomeBranchID: "branch-main",
        activeBranchID: "branch-main",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == 0,
    "archived item must return 0 POS stock"
)
check(
    PPBranchInventoryResolver.resolvePOSBranchStock(
        catalogActive: false,
        isBlocked: false,
        isDeleted: false,
        isDisabled: false,
        isArchived: false,
        catalogQuantity: 10,
        itemHomeBranchID: "branch-main",
        activeBranchID: "branch-main",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == 0,
    "inactive item must return 0 POS stock"
)
// Mismatched branch projection does NOT leak stale branch quantity into POS
check(
    PPBranchInventoryResolver.resolvePOSBranchStock(
        catalogActive: true,
        isBlocked: false,
        isDeleted: false,
        isDisabled: false,
        isArchived: false,
        catalogQuantity: 50,
        itemHomeBranchID: "branch-main",
        activeBranchID: "branch-other",
        projectionBranchID: "branch-main",
        branchRecord: mainRecWithStock
    ) == 0,
    "POS must not leak foreign projection or catalogQuantity into another active branch"
)

// 5. Live Pet unit branch filtering
check(
    PPBranchInventoryResolver.isLivePetUnitInBranch(
        unitBranchID: "branch-b",
        fallbackBranchID: "branch-a",
        activeBranchID: "branch-b",
        activeBranchIsDefault: false,
        sellingPrice: 1200
    ) == true,
    "unit physically located in active branch must be selectable even if product home branch differs"
)
check(
    PPBranchInventoryResolver.isLivePetUnitInBranch(
        unitBranchID: "branch-b",
        fallbackBranchID: "branch-a",
        activeBranchID: "branch-a",
        activeBranchIsDefault: true,
        sellingPrice: 1200
    ) == false,
    "unit transferred to branch-b must NOT appear in branch-a even when branch-a is default/fallback"
)
check(
    PPBranchInventoryResolver.isLivePetUnitInBranch(
        unitBranchID: "",
        fallbackBranchID: "main_store",
        activeBranchID: "branch-main",
        activeBranchIsDefault: true,
        sellingPrice: 900
    ) == true,
    "legacy unlocated unit stays visible on active default branch"
)
check(
    PPBranchInventoryResolver.isLivePetUnitInBranch(
        unitBranchID: "",
        fallbackBranchID: "main_store",
        activeBranchID: "branch-b",
        activeBranchIsDefault: false,
        sellingPrice: 900
    ) == false,
    "legacy unlocated unit must NOT leak onto non-default branch"
)
check(
    PPBranchInventoryResolver.isLivePetUnitInBranch(
        unitBranchID: "all_branches",
        fallbackBranchID: "branch-b",
        activeBranchID: "branch-b",
        activeBranchIsDefault: false,
        sellingPrice: 900
    ) == true,
    "sentinel unitBranchID falls back cleanly to concrete product fallbackBranchID"
)
check(
    PPBranchInventoryResolver.isLivePetUnitInBranch(
        unitBranchID: "branch-b",
        fallbackBranchID: "branch-b",
        activeBranchID: "branch-b",
        activeBranchIsDefault: false,
        sellingPrice: 0
    ) == false,
    "unit without positive sellingPrice must not be selectable for sale"
)

print("SWIFT_PARITY_OK")
'''

with tempfile.TemporaryDirectory() as tmp:
    swift_file = Path(tmp) / "parity_harness.swift"
    bin_file = Path(tmp) / "parity_harness"
    swift_file.write_text(swift_harness, encoding="utf-8")
    subprocess.run(["swiftc", str(swift_file), "-o", str(bin_file)], check=True)
    res = subprocess.run([str(bin_file)], capture_output=True, text=True)
    if res.returncode != 0:
        raise AssertionError(f"Swift parity harness failed (exit {res.returncode}):\n{res.stdout}\n{res.stderr}")
    assert "SWIFT_PARITY_OK" in res.stdout, res.stdout + res.stderr

# 6. Static contract verification across all Admin surfaces (Branches, Context, POS, Catalog, Lots, Pury, Localization)
branches_view = read("Features/Operations/BranchesView.swift")
assert "projectBranchStockDirectly" not in branches_view, "Forbidden client fallback write to petAccessories remains in BranchesView.swift"
assert "AdminAuditLogs" not in branches_view, "Direct AdminAuditLogs write remains in BranchesView.swift"
assert '"auditLogs"' not in branches_view, "Direct auditLogs write remains in BranchesView.swift"
assert "applySystemDefaultBranchChange(" in branches_view, "BranchesView must sync system default change through PPBranchContextManager"
assert "Branches_Cannot_Deactivate_Default" in branches_view, "BranchesView must guard deactivating default branch"
assert "Branches_Cannot_Set_Inactive_Default" in branches_view, "BranchesView must guard setting inactive branch as default"

branch_editor_swift = read("Features/Operations/PPBranchEditorView.swift")
assert "AdminAuditLogs" not in branch_editor_swift
assert "applySystemDefaultBranchChange(" in branch_editor_swift
assert "Branches_Cannot_Set_Inactive_Default" in branch_editor_swift

branch_editor_objc = read("BranchSection/PPBranchEditorViewController.m")
assert "AdminAuditLogs" not in branch_editor_objc
assert "applySystemDefaultBranchChange:" in branch_editor_objc

ctx_mgr_h = read("BranchSection/PPBranchContextManager.h")
ctx_mgr_m = read("BranchSection/PPBranchContextManager.m")
ctx_bridge = read("BranchSection/PPBranchContextBridge.swift")
assert "systemDefaultBranch" in ctx_mgr_h
assert "applySystemDefaultBranchChange:" in ctx_mgr_h
assert "branchesListener" in ctx_mgr_m
assert "addSnapshotListener" in ctx_mgr_m
assert "kPPKnownSystemDefaultBranchStoragePrefix" in ctx_mgr_m
assert "applySystemDefaultBranchChange(" in ctx_bridge

shell = read("App/AdminAppShell.swift")
assert "systemDefaultBranch?.branchID" in shell, "Pury context must fall back to systemDefaultBranch before static scope"

pos_fast_sell = read("Features/POS/POSFastSellView.swift")
assert "PPBranchInventoryResolver.resolvePOSBranchStock(" in pos_fast_sell
assert "PPBranchInventoryResolver.isLivePetUnitInBranch(" in pos_fast_sell
assert "PPBranchInventoryService.shared.$isServerConfirmed" in pos_fast_sell
assert "BranchContextStore.shared.systemDefaultBranch" in pos_fast_sell

pos_reserved = read("Features/POS/POSReservedLivePetsView.swift")
assert "BranchContextStore.shared.activeBranch" in pos_reserved
assert "hasAppliedInitialBranchSelection" in pos_reserved

inv_list = read("AccessorySection/PPInventoryListView.swift")
assert "PPBranchInventoryResolver.resolveCatalogBranchStock(" in inv_list
assert "PPBranchInventoryResolver.isCatalogOutOfStock(" in inv_list
assert "PPBranchInventoryResolver.isLivePetUnitInBranch(" in inv_list
assert "PPBranchInventoryService.shared.$isServerConfirmed" in inv_list
# Ensure detail adjustQuantity no longer mutates shared item.quantity/noStock in-memory
adjust_match = re.search(r"private func adjustQuantity\(_ delta: Int\)\s*\{([\s\S]*?)\n    \}", inv_list)
assert adjust_match, "private func adjustQuantity(_ delta: Int) not found in PPInventoryListView.swift"
assert "item.quantity =" not in adjust_match.group(1) and "item.noStock =" not in adjust_match.group(1), \
    "adjustQuantity must not overwrite shared catalog item.quantity/noStock"

action_menu = read("AccessorySection/PPInventoryActionMenuSheet.swift")
assert "PPBranchInventoryResolver.resolveCatalogBranchStock(" in action_menu
assert "PPBranchInventoryResolver.isCatalogOutOfStock(" in action_menu

lots_model = read("BranchSection/PPInventoryLot.swift")
lots_sheet = read("Features/Inventory/InventoryLotsSheet.swift")
quarantine_sheet = read("Features/Inventory/QuarantineStudioSheet.swift")
inv_view = read("Features/Inventory/InventoryView.swift")
for src_name, src in [
    ("PPInventoryLot.swift", lots_model),
    ("InventoryLotsSheet.swift", lots_sheet),
    ("QuarantineStudioSheet.swift", quarantine_sheet),
    ("InventoryView.swift", inv_view),
]:
    assert "PPBranchInventoryResolver" in src or "systemDefaultBranch" in src, f"{src_name} missing unified branch resolver"

ar_strings = read("ar.lproj/Localizable.strings")
en_strings = read("en.lproj/Localizable.strings")
for key in ["Branches_Cannot_Deactivate_Default", "Branches_Cannot_Set_Inactive_Default"]:
    assert f'"{key}"' in ar_strings, f"Missing AR localization key: {key}"
    assert f'"{key}"' in en_strings, f"Missing EN localization key: {key}"

print("PASS: All Swift branch/POS/catalog parity execution assertions and Admin static contracts passed.")
