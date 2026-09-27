#!/usr/bin/env python3
"""Execute the shipping commerce-load callback with scripted responses."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / "PurePetsAdmin/AccessorySection/PPAccessoryEditorView.swift").read_text()
method = source[source.index("    func loadCommerceIfAvailable() {"):source.index("    func loadCostSummaryIfAvailable() {")]
assert "if isLoadingCommerce {" in source[source.index("    func validate() ->"):]
assert "if let commerceLoadError = commerceLoadError { return (false, commerceLoadError) }" in source
assert "!hasPendingStandardSave && commerceLoadError != nil" in source
fixture = r'''
import Foundation
struct Accessory { var accessoryID = "fixture"; var wholesalePrice: NSNumber? = nil }
struct PPQuantityGroupDraft {
 var id: String; var nameAr: String; var nameEn: String; var unitsPerGroup: Int
 var barcode: String; var sku: String; var sortOrder: Int; var retailEnabled: Bool
 var wholesaleEnabled: Bool; var retailPriceText: String; var wholesalePriceText: String
 var defaultForRetail: Bool; var defaultForWholesale: Bool; var active: Bool
}
enum Language { static func get(_ key: String, alter: String) -> String { key } }
enum PPInventoryDecimalText { static func editable(_ value: NSNumber) -> String { value.stringValue } }
struct DispatchQueue { static let main = DispatchQueue(); func async(execute: () -> Void) { execute() } }
struct Reply { let data: Any }
final class Functions {
 static let shared = Functions(); var result: Reply?; var error: Error?
 static func functions() -> Functions { shared }
 func httpsCallable(_ name: String) -> Functions { precondition(name == "getProductCommerce"); return self }
 func call(_ payload: [String: Any], completion: (Reply?, Error?) -> Void) { completion(result, error) }
}
final class Editor {
 var editingAccessory: Accessory? = Accessory(); var isIndividualLivePet = false
 var wholesaleEnabled = false; var wholesalePriceText = ""; var isLoadingCommerce = false
 var commerceLoadError: String?; var errorMessage: String?; var fabricatedDefaults = 0
 var pricingRevision = 1; var commerceBaseUnitID = "piece"; var commerceBaseUnitNameAr = ""; var commerceBaseUnitNameEn = ""
 var quantityGroups: [PPQuantityGroupDraft] = []
 func ensureDefaultSingleGroup() { fabricatedDefaults += 1 }
 // SHIPPING_METHOD
}
for code in [4, 7, 14] {
 let editor = Editor(); Functions.shared.result = nil
 Functions.shared.error = NSError(domain: "com.firebase.functions", code: code)
 editor.loadCommerceIfAvailable()
 precondition(editor.fabricatedDefaults == 0, "Failed reads must not fabricate selling groups")
 precondition(editor.commerceLoadError != nil && editor.errorMessage != nil, "Read failure must remain visible and block saving")
 precondition(!editor.isLoadingCommerce)
}
Functions.shared.error = nil
for malformed: Any in [[:], ["productCommerce": [:]], ["productCommerce": ["quantityGroups": [["id": "bad"]]]]] {
 let editor = Editor(); Functions.shared.result = Reply(data: malformed); editor.loadCommerceIfAvailable()
 precondition(editor.fabricatedDefaults == 0 && editor.commerceLoadError != nil, "Malformed commerce must fail closed")
}
let valid: [String: Any] = ["productCommerce": ["pricingRevision": 2,
 "baseUnit": ["id": "piece", "nameAr": "حبة", "nameEn": "Piece"],
 "quantityGroups": [["id": "single", "nameAr": "حبة", "nameEn": "Single", "unitsPerGroup": 1,
 "retailEnabled": true, "wholesaleEnabled": false, "retailPriceMinor": 1999, "defaultForRetail": true]]]]
let editor = Editor(); editor.commerceLoadError = "previous failure"
Functions.shared.result = Reply(data: valid); editor.loadCommerceIfAvailable()
precondition(editor.commerceLoadError == nil && editor.quantityGroups.first?.id == "single")
precondition(editor.quantityGroups.first?.retailPriceText == "19.99" && editor.pricingRevision == 2)
print("CATALOG_COMMERCE_LOAD_TEST: PASS (denied/timeout/offline, malformed responses, retry and legacy-shaped valid response)")
'''
with tempfile.TemporaryDirectory(prefix="pp-commerce-load-") as temp:
 p = Path(temp)/"Load.swift"; p.write_text(fixture.replace(" // SHIPPING_METHOD", method))
 subprocess.run(["swift", str(p)], check=True)
