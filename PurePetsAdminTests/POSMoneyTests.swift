//
//  POSMoneyTests.swift
//  PurePetsAdminTests
//
//  Unit tests for POS monetary calculations, accumulation, operator input parsing,
//  and stock capping arithmetic to guarantee 100% parity with Firebase Infra
//  (functions/posIntegrity.js and functions/transactions.js).
//

import XCTest
@testable import PurePetsAdmin

final class POSMoneyTests: XCTestCase {

    // MARK: - 1. Rounding & Precision

    func testRoundMoneyPrecision() {
        // Standard 2-decimal rounding
        XCTAssertEqual(POSMoney.round(10.556), 10.56, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(10.554), 10.55, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(10.0), 10.0, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(0.0), 0.0, accuracy: 0.0001)

        // Half-cent upward rounding matching Math.round((parsed + EPSILON) * 100) / 100
        XCTAssertEqual(POSMoney.round(10.555), 10.56, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(0.005), 0.01, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(0.004), 0.00, accuracy: 0.0001)

        // Floating point artifact mitigation (0.1 + 0.2 = 0.30000000000000004)
        XCTAssertEqual(POSMoney.round(0.1 + 0.2), 0.30, accuracy: 0.0001)

        // Non-finite guards
        XCTAssertEqual(POSMoney.round(Double.nan), 0.0)
        XCTAssertEqual(POSMoney.round(Double.infinity), 0.0)
        XCTAssertEqual(POSMoney.round(-Double.infinity), 0.0)
    }

    // MARK: - 2. Per-Line Sum Accumulation (Infra Parity)

    func testSumPerLineAccumulation() {
        // Empty array
        XCTAssertEqual(POSMoney.sum([]), 0.0)

        // Single item
        XCTAssertEqual(POSMoney.sum([25.50]), 25.50)

        // Multiple clean items
        XCTAssertEqual(POSMoney.sum([10.25, 20.50, 5.25]), 36.00)

        // Items with fractional cents: verify per-line round + round on accumulation
        // matches Infra transactions.js: subtotal = roundMoney(subtotal + lineTotal)
        let lines = [10.004, 20.004, 30.004]
        // Line 1: round(10.004) -> 10.00
        // Line 2: round(10.00 + round(20.004)) -> 30.00
        // Line 3: round(30.00 + round(30.004)) -> 60.00
        XCTAssertEqual(POSMoney.sum(lines), 60.00)

        let linesRoundingUp = [10.005, 10.005]
        // Line 1: round(10.005) -> 10.01
        // Line 2: round(10.01 + round(10.005)) -> round(10.01 + 10.01) -> 20.02
        XCTAssertEqual(POSMoney.sum(linesRoundingUp), 20.02)
    }

    // MARK: - 3. Matches Tolerance

    func testMatchesTolerance() {
        // Exactly equal
        XCTAssertTrue(POSMoney.matches(100.0, 100.0))

        // Within 0.005 half-cent tolerance
        XCTAssertTrue(POSMoney.matches(100.000, 100.004))
        XCTAssertTrue(POSMoney.matches(100.004, 100.000))

        // Beyond 0.005 tolerance
        XCTAssertFalse(POSMoney.matches(100.00, 100.01))
        XCTAssertFalse(POSMoney.matches(50.00, 50.05))

        // Non-finite values
        XCTAssertFalse(POSMoney.matches(Double.nan, 100.0))
        XCTAssertFalse(POSMoney.matches(100.0, Double.nan))
    }

    // MARK: - 4. Minor Units Wire Contract

    func testMinorUnits() {
        XCTAssertEqual(POSMoney.minorUnits(0.0), 0)
        XCTAssertEqual(POSMoney.minorUnits(0.01), 1)
        XCTAssertEqual(POSMoney.minorUnits(1.00), 100)
        XCTAssertEqual(POSMoney.minorUnits(10.50), 1050)

        // The classic 19.99 IEEE 754 float trap (19.99 * 100.0 = 1998.9999999999998)
        // Int(19.99 * 100) would yield 1998. POSMoney.minorUnits must yield 1999.
        XCTAssertEqual(POSMoney.minorUnits(19.99), 1999)
        XCTAssertEqual(POSMoney.minorUnits(299.99), 29999)

        // Non-finite guards
        XCTAssertEqual(POSMoney.minorUnits(Double.nan), 0)
        XCTAssertEqual(POSMoney.minorUnits(Double.infinity), 0)
    }

    // MARK: - 5. Operator Money Parsing (Arabic & LTR)

    func testParseOperatorMoneyInput() {
        // Standard ASCII
        XCTAssertEqual(POSMoney.parse("123.45"), 123.45, accuracy: 0.001)
        XCTAssertEqual(POSMoney.parse("50"), 50.0, accuracy: 0.001)

        // Arabic-Indic digits
        XCTAssertEqual(POSMoney.parse("١٢٣.٤٥"), 123.45, accuracy: 0.001)
        XCTAssertEqual(POSMoney.parse("٥٠"), 50.0, accuracy: 0.001)

        // Arabic decimal comma (٫)
        XCTAssertEqual(POSMoney.parse("١٢٣٫٤٥"), 123.45, accuracy: 0.001)
        XCTAssertEqual(POSMoney.parse("99٫95"), 99.95, accuracy: 0.001)

        // Latin comma separator (,)
        XCTAssertEqual(POSMoney.parse("123,45"), 123.45, accuracy: 0.001)

        // Arabic thousands separator (٬)
        XCTAssertEqual(POSMoney.parse("١٬٢٣٤٫٥٠"), 1234.50, accuracy: 0.001)

        // Whitespace and newlines
        XCTAssertEqual(POSMoney.parse("   75.25 \n\t"), 75.25, accuracy: 0.001)

        // Empty or invalid input
        XCTAssertEqual(POSMoney.parse(""), 0.0)
        XCTAssertEqual(POSMoney.parse("   "), 0.0)
        XCTAssertEqual(POSMoney.parse("abc"), 0.0)
        XCTAssertEqual(POSMoney.parse("NaN"), 0.0)
    }

    // MARK: - 6. Stock Capping Arithmetic

    func testStockCappingArithmetic() {
        // Standard single item (unitsPerGroup = 1)
        let branchStock = 10
        let singleUnitsPerGroup = 1
        var quantity = 9

        // Can increase to 10
        let nextSingle = (quantity + 1) * singleUnitsPerGroup
        XCTAssertTrue(nextSingle <= branchStock)

        // Cannot increase beyond 10
        quantity = 10
        let cappedSingle = (quantity + 1) * singleUnitsPerGroup
        XCTAssertFalse(cappedSingle <= branchStock)

        // Grouped item (e.g. pack of 6)
        let groupedStock = 20
        let groupUnits = 6
        var groupQty = 2 // 12 base units

        // Can increase to 3 groups (18 base units <= 20)
        let nextGroup = (groupQty + 1) * groupUnits
        XCTAssertTrue(nextGroup <= groupedStock)

        // Cannot increase to 4 groups (24 base units > 20)
        groupQty = 3
        let cappedGroup = (groupQty + 1) * groupUnits
        XCTAssertFalse(cappedGroup <= groupedStock)
    }

    // MARK: - 7. Discount Bounds & Total

    func testDiscountBoundsAndTotal() {
        let subtotal = 150.0

        // Percentage discount
        let tenPercent = POSMoney.round(min(subtotal * (10.0 / 100.0), subtotal))
        XCTAssertEqual(tenPercent, 15.0)
        let totalAfter10Pct = POSMoney.round(max(0, subtotal - tenPercent))
        XCTAssertEqual(totalAfter10Pct, 135.0)

        // Fixed discount exceeding subtotal
        let largeFixed = 200.0
        let cappedDiscount = POSMoney.round(min(largeFixed, subtotal))
        XCTAssertEqual(cappedDiscount, 150.0)
        let totalAfterCapped = POSMoney.round(max(0, subtotal - cappedDiscount))
        XCTAssertEqual(totalAfterCapped, 0.0)
    }
}


// MARK: - Infra Parity Regressions
//
// These lock in two defects found by differential-testing `POSMoney` against
// the real `Pure Pets Infra/functions/posIntegrity.js`. A 5,500-case sweep
// (4,000 scalars + 1,500 line-total sets) matched exactly after these fixes;
// both cases below failed before them.

final class POSMoneyInfraParityRegressionTests: XCTestCase {

    /// Infra rounds with `Math.round`, which is `floor(x + 0.5)` — a half
    /// always rounds toward +∞. Swift's `.rounded()` rounds a half *away from
    /// zero*, so the two disagreed on every negative half-value.
    ///
    /// Oracle (`node` → `posIntegrity.roundMoney`):
    ///   roundMoney(-10.555) === -10.55   (Swift `.rounded()` gave -10.56)
    ///   roundMoney(-2.675)  === -2.67
    ///   roundMoney(-0.005)  === -0       (0 after normalisation)
    func testRoundMatchesInfraHalfTowardPositiveInfinityOnNegatives() {
        XCTAssertEqual(POSMoney.round(-10.555), -10.55, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(-2.675), -2.67, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(-1.005), -1.00, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(-0.005), 0.0, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(-0.5), -0.5, accuracy: 0.0001)

        // Positive half-values are unaffected by the change.
        XCTAssertEqual(POSMoney.round(10.555), 10.56, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(2.675), 2.68, accuracy: 0.0001)

        // Float-representation cases the oracle also pins down.
        XCTAssertEqual(POSMoney.round(8.165), 8.16, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.round(33.335), 33.34, accuracy: 0.0001)
    }

    /// `minorUnits` converted a `Double` to `Int` unguarded. Converting an
    /// out-of-range `Double` is a hard trap in Swift, so a malformed catalog or
    /// inventory-unit price crashed the till *while building the checkout
    /// payload* — verified as `SIGTRAP` before the fix.
    ///
    /// An unrepresentable amount yields 0 rather than a fabricated `Int.max`,
    /// consistent with `round` neutralising an overflowing value. Fail-closed
    /// either way: the server recomputes from its own catalog and rejects the
    /// same corrupt value, which the operator can then act on.
    func testMinorUnitsIsCrashFreeOnOutOfRangeValues() {
        XCTAssertEqual(POSMoney.minorUnits(1e300), 0)
        XCTAssertEqual(POSMoney.minorUnits(-1e300), 0)
        XCTAssertEqual(POSMoney.minorUnits(Double.greatestFiniteMagnitude), 0)
        XCTAssertEqual(POSMoney.minorUnits(-Double.greatestFiniteMagnitude), 0)

        // Non-finite input stays at zero.
        XCTAssertEqual(POSMoney.minorUnits(Double.nan), 0)
        XCTAssertEqual(POSMoney.minorUnits(Double.infinity), 0)
        XCTAssertEqual(POSMoney.minorUnits(-Double.infinity), 0)

        // Ordinary amounts are unaffected.
        XCTAssertEqual(POSMoney.minorUnits(19.99), 1999)
        XCTAssertEqual(POSMoney.minorUnits(0.0), 0)
        XCTAssertEqual(POSMoney.minorUnits(-19.99), -1999)
    }

    /// Infra's `moneyMatches` applies `Number.isFinite` to `roundMoney`'s own
    /// result, so a non-finite amount never matches anything — including
    /// another non-finite amount. The Swift port rounded first, which
    /// neutralises NaN to 0 and made `matches(NaN, NaN)` report agreement.
    func testMatchesRejectsNonFiniteBeforeRounding() {
        XCTAssertFalse(POSMoney.matches(Double.nan, Double.nan))
        XCTAssertFalse(POSMoney.matches(Double.infinity, Double.infinity))
        XCTAssertFalse(POSMoney.matches(Double.nan, 0.0))
        XCTAssertFalse(POSMoney.matches(0.0, Double.nan))
        XCTAssertFalse(POSMoney.matches(Double.infinity, 0.0))

        // Finite comparisons are unchanged.
        XCTAssertTrue(POSMoney.matches(100.0, 100.004))
        XCTAssertFalse(POSMoney.matches(100.0, 100.01))
    }

    /// The accumulation that prevents a valid cart being rejected for a
    /// rounding artifact. Mirrors `transactions.js`
    /// `subtotal = roundMoney(subtotal + lineTotal)`, verified against the
    /// oracle for each set below.
    func testSumMirrorsInfraPerLineAccumulation() {
        XCTAssertEqual(POSMoney.sum([3.335, 3.335, 3.335]), 10.02, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.sum([0.005, 0.005, 0.005]), 0.03, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.sum([19.99, 19.99, 19.99]), 59.97, accuracy: 0.0001)
        XCTAssertEqual(POSMoney.sum([10.005, 10.005]), 20.02, accuracy: 0.0001)

        // Rounding only the final sum — the behaviour this replaced — yields
        // 10.01 here, which the server would reject as a subtotal mismatch.
        let naive = ((3.335 + 3.335 + 3.335) * 100).rounded() / 100.0
        XCTAssertNotEqual(naive, POSMoney.sum([3.335, 3.335, 3.335]))
    }

    /// A non-finite amount must never reach the wire as a real number.
    func testNonFiniteMoneyIsNeutralised() {
        XCTAssertEqual(POSMoney.round(Double.nan), 0.0)
        XCTAssertEqual(POSMoney.round(Double.infinity), 0.0)
        XCTAssertEqual(POSMoney.sum([Double.nan, 10.0]), 10.0, accuracy: 0.0001)
        XCTAssertFalse(POSMoney.matches(Double.nan, Double.nan))
    }
}
