#!/bin/zsh
#
# POS money verification gate.
#
# Proves the Admin POS client agrees with the Firebase Infra money contract.
# `processTransaction` recomputes every amount server-side and rejects a
# mismatched client assertion with `failed-precondition` ("… does not match the
# server-calculated amount") using a half-cent tolerance, so any client/server
# rounding drift fails an otherwise valid checkout at the till.
#
# What it does
#   1. Extracts `POSMoney` and `String.normalizedEnglishDigits` from live Admin
#      source, so the gate can never drift from the shipping implementation.
#   2. Evaluates every assertion in PurePetsAdminTests/POSMoneyTests.swift
#      (both test classes).
#   3. Differentially compares Swift against the REAL
#      `Pure Pets Infra/functions/posIntegrity.js` over a deterministic corpus
#      of 4,000 scalars and 1,500 line-total sets, mirroring the per-line
#      accumulation in `functions/transactions.js`
#      (`subtotal = roundMoney(subtotal + lineTotal)`).
#
# Why this exists instead of `xcodebuild test`
#   The Podfile integrates only `target 'PurePetsAdmin'`. Neither
#   PurePetsAdminTests nor PurePetsAdminUITests receives a Pods xcconfig, so
#   both fail to compile the app's PrefixHeader.pch / bridging header
#   ("'Lottie.h' file not found"). Until the test targets are added to the
#   Podfile, XCTest cannot execute; this gate covers the same assertions and
#   adds real server parity on top.
#
# Requirements: node, swiftc (Xcode toolchain), python3.
# Exit 0 = every assertion passed AND Swift/JS agreed on every case.

set -e
set -o pipefail

HERE=${0:a:h}
ADMIN=${HERE:h}
ROOT=${ADMIN:h}
INFRA="$ROOT/Pure Pets Infra"
POS="$ADMIN/PurePetsAdmin/Features/POS/POSFastSellView.swift"
SHARED="$ADMIN/PurePetsAdmin/Shared/Components/AdminSharedComponents.swift"

for f in "$POS" "$SHARED" "$INFRA/functions/posIntegrity.js"; do
  if [[ ! -f "$f" ]]; then print -u2 "missing required input: $f"; exit 2; fi
done

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pos-money-gate.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

print "== extracting POSMoney + digit folding from live source =="
python3 - "$POS" "$SHARED" <<'PY'
import io, sys
pos, shared = sys.argv[1], sys.argv[2]
s = io.open(pos, encoding='utf-8').read()
i = s.index('enum POSMoney {')
j = s.index('\n}\n', s.index('static func parse', i))
money = s[i:j+3]

t = io.open(shared, encoding='utf-8').read()
k = t.index('public var normalizedEnglishDigits: String {')
end = t.index('\n    }\n', k) + len('\n    }\n')
digits = 'extension String {\n    ' + t[k:end].strip() + '\n}\n'

io.open('Extracted.swift', 'w', encoding='utf-8').write(
    'import Foundation\n\n' + digits + '\n' + money)
print('  POSMoney %d bytes, digit folding %d bytes' % (len(money), len(digits)))
PY

print "== generating deterministic differential corpus =="
python3 - <<'PY'
import random
random.seed(20260920)
vals = []
for _ in range(4000):
    k = random.choice([0,1,2,3,4])
    if k == 0: v = round(random.uniform(-1000,1000), random.randint(0,4))
    elif k == 1: v = random.randint(-100000,100000)/100.0
    elif k == 2: v = random.randint(-100000,100000)/1000.0
    elif k == 3: v = random.choice([-1,1])*(random.randint(0,999999)+0.005)
    else: v = random.uniform(-1e6,1e6)
    vals.append(repr(float(v)))
sets = []
for _ in range(1500):
    n = random.randint(0,8)
    sets.append([repr(round(random.uniform(0,500), random.randint(0,4))) for _ in range(n)])
open('vals.txt','w').write('\n'.join(vals))
open('sets.txt','w').write('\n'.join(','.join(s) for s in sets))
print('  %d scalars, %d line-total sets' % (len(vals), len(sets)))
PY

print "== oracle: real Infra functions/posIntegrity.js =="
cat > oracle.js <<EOF
const fs = require("fs");
const { roundMoney } = require("$INFRA/functions/posIntegrity.js");
const vals = fs.readFileSync("vals.txt","utf8").trim().split("\n").map(Number);
const sets = fs.readFileSync("sets.txt","utf8").split("\n")
  .map(l => l.length ? l.split(",").map(Number) : []);
const out = [];
for (const v of vals) out.push(roundMoney(v).toFixed(4));
for (const s of sets) {
  let st = 0;
  for (const l of s) st = roundMoney(st + roundMoney(l));
  out.push(st.toFixed(4));
}
fs.writeFileSync("js.txt", out.join("\n"));
EOF
node oracle.js
print "  oracle rows: $(wc -l < js.txt | tr -d ' ')"

print "== assertions + swift differential side =="
cat > main.swift <<'SWIFT'
import Foundation

var checks = 0, failures = 0
func expect(_ cond: Bool, _ what: String) {
    checks += 1
    if !cond { failures += 1; print("  FAIL: \(what)") }
}
func eq(_ a: Double, _ b: Double, _ what: String, _ tol: Double = 0.0001) {
    expect(abs(a - b) <= tol, "\(what)  (got \(a), want \(b))")
}
func eqi(_ a: Int, _ b: Int, _ what: String) {
    expect(a == b, "\(what)  (got \(a), want \(b))")
}

// POSMoneyTests.testRoundMoneyPrecision
eq(POSMoney.round(10.556), 10.56, "round 10.556")
eq(POSMoney.round(10.554), 10.55, "round 10.554")
eq(POSMoney.round(10.0), 10.0, "round 10.0")
eq(POSMoney.round(0.0), 0.0, "round 0.0")
eq(POSMoney.round(10.555), 10.56, "round 10.555 half-up")
eq(POSMoney.round(0.005), 0.01, "round 0.005")
eq(POSMoney.round(0.004), 0.00, "round 0.004")
eq(POSMoney.round(0.1 + 0.2), 0.30, "round 0.1+0.2 artifact")
eq(POSMoney.round(Double.nan), 0.0, "round NaN")
eq(POSMoney.round(Double.infinity), 0.0, "round +inf")
eq(POSMoney.round(-Double.infinity), 0.0, "round -inf")

// POSMoneyTests.testSumPerLineAccumulation
eq(POSMoney.sum([]), 0.0, "sum empty")
eq(POSMoney.sum([25.50]), 25.50, "sum single")
eq(POSMoney.sum([10.25, 20.50, 5.25]), 36.00, "sum clean")
eq(POSMoney.sum([10.004, 20.004, 30.004]), 60.00, "sum sub-half residues")
eq(POSMoney.sum([10.005, 10.005]), 20.02, "sum half residues")

// POSMoneyTests.testMatchesTolerance
expect(POSMoney.matches(100.0, 100.0), "matches equal")
expect(POSMoney.matches(100.000, 100.004), "matches within tolerance")
expect(POSMoney.matches(100.004, 100.000), "matches within tolerance reversed")
expect(!POSMoney.matches(100.00, 100.01), "rejects 1 cent")
expect(!POSMoney.matches(50.00, 50.05), "rejects 5 cents")
expect(!POSMoney.matches(Double.nan, 100.0), "rejects NaN lhs")
expect(!POSMoney.matches(100.0, Double.nan), "rejects NaN rhs")

// POSMoneyTests.testMinorUnits
eqi(POSMoney.minorUnits(0.0), 0, "minor 0")
eqi(POSMoney.minorUnits(0.01), 1, "minor 0.01")
eqi(POSMoney.minorUnits(1.00), 100, "minor 1.00")
eqi(POSMoney.minorUnits(10.50), 1050, "minor 10.50")
eqi(POSMoney.minorUnits(19.99), 1999, "minor 19.99 IEEE trap")
eqi(POSMoney.minorUnits(299.99), 29999, "minor 299.99")
eqi(POSMoney.minorUnits(Double.nan), 0, "minor NaN")
eqi(POSMoney.minorUnits(Double.infinity), 0, "minor +inf")

// POSMoneyTests.testParseOperatorMoneyInput
eq(POSMoney.parse("123.45"), 123.45, "parse ascii", 0.001)
eq(POSMoney.parse("50"), 50.0, "parse int", 0.001)
eq(POSMoney.parse("١٢٣.٤٥"), 123.45, "parse arabic-indic digits", 0.001)
eq(POSMoney.parse("٥٠"), 50.0, "parse arabic-indic int", 0.001)
eq(POSMoney.parse("١٢٣٫٤٥"), 123.45, "parse arabic decimal sep", 0.001)
eq(POSMoney.parse("99٫95"), 99.95, "parse mixed decimal sep", 0.001)
eq(POSMoney.parse("123,45"), 123.45, "parse latin comma", 0.001)
eq(POSMoney.parse("١٬٢٣٤٫٥٠"), 1234.50, "parse arabic thousands sep", 0.001)
eq(POSMoney.parse("   75.25 \n\t"), 75.25, "parse whitespace", 0.001)
eq(POSMoney.parse(""), 0.0, "parse empty")
eq(POSMoney.parse("   "), 0.0, "parse blank")
eq(POSMoney.parse("abc"), 0.0, "parse garbage")
eq(POSMoney.parse("NaN"), 0.0, "parse NaN literal")

// POSMoneyTests.testDiscountBoundsAndTotal
eq(POSMoney.round(min(150.0 * (10.0/100.0), 150.0)), 15.0, "10% of 150")
eq(POSMoney.round(max(0, 150.0 - 15.0)), 135.0, "total after 10%")
eq(POSMoney.round(min(200.0, 150.0)), 150.0, "fixed discount clamped to subtotal")
eq(POSMoney.round(max(0, 150.0 - 150.0)), 0.0, "total floors at zero")

// Regression: Infra rounds a half toward +inf (Math.round == floor(x+0.5)).
eq(POSMoney.round(-10.555), -10.55, "neg half parity -10.555")
eq(POSMoney.round(-2.675), -2.67, "neg half parity -2.675")
eq(POSMoney.round(-1.005), -1.00, "neg half parity -1.005")
eq(POSMoney.round(-0.005), 0.0, "neg half parity -0.005")
eq(POSMoney.round(-0.5), -0.5, "neg half parity -0.5")
eq(POSMoney.round(2.675), 2.68, "pos half unaffected 2.675")
eq(POSMoney.round(8.165), 8.16, "float repr 8.165")
eq(POSMoney.round(33.335), 33.34, "float repr 33.335")

// Regression: an unrepresentable amount must not trap the Int conversion.
eqi(POSMoney.minorUnits(1e300), 0, "minor unrepresentable +1e300 -> 0")
eqi(POSMoney.minorUnits(-1e300), 0, "minor unrepresentable -1e300 -> 0")
eqi(POSMoney.minorUnits(Double.greatestFiniteMagnitude), 0, "minor overflow greatest -> 0")
eqi(POSMoney.minorUnits(-Double.greatestFiniteMagnitude), 0, "minor overflow -greatest -> 0")
eqi(POSMoney.minorUnits(-19.99), -1999, "minor negative ordinary")

// Regression: sum mirrors Infra per-line accumulation.
eq(POSMoney.sum([3.335, 3.335, 3.335]), 10.02, "sum 3x3.335")
eq(POSMoney.sum([0.005, 0.005, 0.005]), 0.03, "sum 3x0.005")
eq(POSMoney.sum([19.99, 19.99, 19.99]), 59.97, "sum 3x19.99")
eq(POSMoney.sum([10.005, 10.005]), 20.02, "sum 2x10.005")
let naive = ((3.335 + 3.335 + 3.335) * 100).rounded() / 100.0
expect(naive != POSMoney.sum([3.335, 3.335, 3.335]),
       "naive final-sum rounding differs from per-line accumulation")

// Regression: non-finite money is never treated as a real amount.
eq(POSMoney.sum([Double.nan, 10.0]), 10.0, "sum ignores NaN line")
expect(!POSMoney.matches(Double.nan, Double.nan), "NaN never matches NaN")
expect(!POSMoney.matches(Double.infinity, Double.infinity), "inf never matches inf")
expect(!POSMoney.matches(Double.infinity, 0.0), "inf never matches finite")

// Differential sweep.
let vals = try! String(contentsOfFile: "vals.txt", encoding: .utf8)
    .split(separator: "\n").map { Double($0)! }
let setLines = try! String(contentsOfFile: "sets.txt", encoding: .utf8)
    .components(separatedBy: "\n")
var rows: [String] = []
for v in vals { rows.append(String(format: "%.4f", POSMoney.round(v))) }
for line in setLines {
    let parts = line.isEmpty ? [] : line.split(separator: ",").map { Double($0)! }
    rows.append(String(format: "%.4f", POSMoney.sum(parts)))
}
try! rows.joined(separator: "\n").write(toFile: "swift.txt", atomically: true, encoding: .utf8)

print("ASSERTIONS: \(checks) evaluated, \(failures) failed")
if failures > 0 { exit(1) }
SWIFT
swiftc -O Extracted.swift main.swift -o gate
./gate

print "== differential diff (must be empty) =="
if diff -q js.txt swift.txt > /dev/null; then
  print "  PARITY OK: $(wc -l < js.txt | tr -d ' ') rows identical (Swift vs real Infra posIntegrity.js)"
else
  print "  PARITY FAILED:"
  diff js.txt swift.txt | head -20
  exit 1
fi

print ""
print "GATE PASSED"
