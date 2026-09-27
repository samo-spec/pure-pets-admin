#!/usr/bin/env python3
"""Execute the shipping Foundation decimal helper; no app/simulator is launched."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "PurePetsAdmin/AccessorySection/PPAccessoryEditorView.swift").read_text()
start = source.index("enum PPInventoryDecimalText {")
end = source.index("\n}\n", start) + len("\n}\n")
helper = source[start:end]
assert not re.search(r'(?:priceText|costPriceText|discountPercentText|discountAmountText|wholesalePriceText)\s*=\s*String\(format:\s*"%g"', source, re.I), "Lossy money hydration returned"
assert source.count("PPInventoryDecimalText.editable(") == 10, "Review every editor money hydration path"

draft_start = source.index("    var retailPriceMinor: Int? {")
draft_end = source.index("    var localizedName:", draft_start)
draft = "struct Draft { var retailEnabled = true; var wholesaleEnabled = true; var retailPriceText: String; var wholesalePriceText: String\n" + source[draft_start:draft_end] + "}\n"

checks = r'''
import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
// Reproduce the original reopen corruption, then exercise the live helper.
check(String(format: "%g", 123456.78) == "123457", "Reproduction changed")
for raw in ["0", "0.01", "19.99", "12345.67", "123456.78", "999999999.99", "12.345", "0.000001"] {
    let input = NSDecimalNumber(string: raw)
    let reopened = PPInventoryDecimalText.editable(input)
    check(NSDecimalNumber(string: reopened) == input, "Decimal changed: \(raw) -> \(reopened)")
    check(!reopened.lowercased().contains("e"), "Exponent leaked into decimal keypad")
}
// Firestore NSNumber(Double) values and the actual editor Double save boundary.
var state: UInt64 = 49199
for _ in 0..<10000 {
    state = state &* 6364136223846793005 &+ 1
    let cents = state % 100_000_000_000
    let stored = Double(cents) / 100
    let reopened = PPInventoryDecimalText.editable(NSNumber(value: stored))
    guard let saved = Double(reopened), saved.isFinite else { fatalError("Invalid reopened money") }
    check(Int64((saved * 100).rounded()) == Int64(cents), "Cents changed: \(stored) -> \(reopened)")
    let recoveredPayload = try JSONSerialization.data(withJSONObject: ["price": NSNumber(value: saved)])
    let payload = try JSONSerialization.jsonObject(with: recoveredPayload) as! [String: NSNumber]
    check(Int64((payload["price"]!.doubleValue * 100).rounded()) == Int64(cents), "Recovery payload lost cents")
}
for (raw, cents) in [("0", 0), ("0.01", 1), (".5", 50), ("1.", 100), ("19.99", 1999), ("١٩٫٩٩", 1999), ("19,99", 1999), ("999999999.99", 99_999_999_999)] {
    check(PPInventoryDecimalText.minorUnits(raw) == cents, "Exact parsing failed: \(raw)")
}
for raw in ["", "NaN", "inf", "1e20", "100000000000000000000", "1000000000", "-1", "12.345", "0.001", "1.00000000000000000001", "1,234.56", "abc"] {
    check(PPInventoryDecimalText.minorUnits(raw) == nil, "Invalid money accepted: \(raw)")
    let invalidDraft = Draft(retailPriceText: raw, wholesalePriceText: raw)
    check(invalidDraft.retailPriceMinor == nil && invalidDraft.wholesalePriceMinor == nil, "Unsafe draft conversion: \(raw)")
}
check(PPInventoryDecimalText.minorUnits("100.01", maximum: 100) == nil, "Percentage bound ignored")
check(PPInventoryDecimalText.discountedMinor(price: 1999, percent: 5000, amount: 0) == 1000, "Half-cent round failed")
check(PPInventoryDecimalText.discountedMinor(price: 1999, percent: 1000, amount: 1) == 1798, "Discount calculation drift")
check(PPInventoryDecimalText.discountedMinor(price: 99_999_999_999, percent: 0, amount: 0) == 99_999_999_999, "Maximum price changed")
check(PPInventoryDecimalText.discountedMinor(price: Int.max, percent: 0, amount: 0) == nil, "Overflow not rejected")
let disabled = Draft(retailEnabled: false, wholesaleEnabled: false, retailPriceText: "invalid", wholesalePriceText: "invalid")
check(disabled.retailPriceMinor == nil && disabled.wholesalePriceMinor == nil, "Disabled channel fabricated a price")
print("CATALOG_DECIMAL_INPUT_TEST: PASS (8 reopen cases, 10000 round trips, 8 exact parses, 12 malformed/overflow cases, safe group conversion, discount arithmetic, 10 hydration paths)")
'''
with tempfile.TemporaryDirectory(prefix="pp-catalog-decimal-") as temp:
    script = Path(temp) / "CatalogDecimal.swift"
    script.write_text("import Foundation\n" + helper + "\n" + draft + "\n" + checks)
    subprocess.run(["swift", str(script)], check=True)
