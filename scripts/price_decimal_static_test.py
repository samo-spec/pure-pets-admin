#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1] / "PurePetsAdmin"
failures: list[str] = []

money_terms = re.compile(
    r"price|amount|subtotal|total|fee|cost|discount|refund|balance|deposit|rate|"
    r"valuation|gross|profit|qar|sar|currency|cash|tender|selling|retail|wholesale|ر\.ق|ر\.س",
    re.I,
)
allowed_whole_money_markers = (
    "commissionRate * 100",
    "String(format: \"%.0f\", val)",       # fixed denomination/preset chip labels
    "String(format: \"%.0f\", preset)",    # fixed discount preset labels
)

for path in ROOT.rglob("*.swift"):
    lines = path.read_text(errors="ignore").splitlines()
    for idx, line in enumerate(lines):
        if "%.0f" not in line or "%%" in line:
            continue
        context = " ".join(lines[max(0, idx - 2): min(len(lines), idx + 3)])
        if money_terms.search(context) and not any(marker in line for marker in allowed_whole_money_markers):
            failures.append(f"whole-unit money format {path.relative_to(ROOT)}:{idx + 1}: {line.strip()}")
suites = (ROOT / "Features/Hotel/AdminPetsHotelSuitesManagementViews.swift").read_text()
reservations = (ROOT / "Features/Hotel/AdminPetsHotelReservationsManagementViews.swift").read_text()
vet = (ROOT / "VeterinarianSection/PPVetsListView.swift").read_text()

required_absent = {
    "unrounded hotel major→minor conversion": "let rateMinor = Int(rateDouble * 100)",
    "integer hotel minor→major load": 'nightlyRateMajor = "\\(t.nightlyRateMinor / 100)"',
    "whole-number hotel rate keypad": 'TextField("150", text: $nightlyRateMajor)\n                            .keyboardType(.numberPad)',
    "whole-number reservation deposit keypad": 'TextField("0", text: $depositPaidQAR)\n                        .keyboardType(.numberPad)',
    "vet cost Int truncation": 'Text("\\(Int(vet.vetCost))',
}
for label, needle in required_absent.items():
    haystack = suites if "hotel" in label else reservations if "reservation" in label else vet
    if needle in haystack:
        failures.append(label)

if failures:
    print("PRICE_DECIMAL_STATIC_TEST: FAIL")
    for failure in failures:
        print(f" - {failure}")
    raise SystemExit(1)
print("PRICE_DECIMAL_STATIC_TEST: PASS")
