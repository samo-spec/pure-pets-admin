//
//  LivePetRefundState.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Financial resolution and refund statuses independent from physical custody.
//

import Foundation
import SwiftUI

// MARK: - Financial Resolution

public enum FinancialResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case none             = "none"
    case fullRefund       = "full_refund"
    case partialRefund    = "partial_refund"
    case exchange         = "exchange"
    case storeCredit      = "store_credit"
    case manualSettlement = "manual_settlement"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .none:
            return Language.get("FinancialResolution_None", alter: "بدون تسوية مالية")
        case .fullRefund:
            return Language.get("FinancialResolution_FullRefund", alter: "استرداد مالي كامل")
        case .partialRefund:
            return Language.get("FinancialResolution_PartialRefund", alter: "استرداد مالي جزئي")
        case .exchange:
            return Language.get("FinancialResolution_Exchange", alter: "استبدال بحيوان/منتج آخر")
        case .storeCredit:
            return Language.get("FinancialResolution_StoreCredit", alter: "رصيد محفظة / قسيمة متجر")
        case .manualSettlement:
            return Language.get("FinancialResolution_ManualSettlement", alter: "تسوية يدوية محاسبية")
        }
    }

    public var iconName: String {
        switch self {
        case .none: return "minus.circle"
        case .fullRefund: return "arrow.uturn.backward.circle.fill"
        case .partialRefund: return "percent"
        case .exchange: return "arrow.triangle.2.circlepath"
        case .storeCredit: return "creditcard.fill"
        case .manualSettlement: return "pencil.and.outline"
        }
    }
}

// MARK: - Live Pet Refund Status

public enum LivePetRefundStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case notRequired   = "not_required"
    case notRequested  = "not_requested"
    case requested     = "requested"
    case processing    = "processing"
    case succeeded     = "succeeded"
    case failed        = "failed"
    case retryRequired = "retry_required"
    case manualReview  = "manual_review"

    public var id: String { rawValue }

    public var isSettled: Bool {
        self == .succeeded
    }

    public var isPendingOrInFlight: Bool {
        self == .requested || self == .processing
    }

    public var requiresAttention: Bool {
        self == .failed || self == .retryRequired || self == .manualReview
    }

    public var localizedTitle: String {
        switch self {
        case .notRequired:
            return Language.get("RefundStatus_NotRequired", alter: "غير مطلوب")
        case .notRequested:
            return Language.get("RefundStatus_NotRequested", alter: "لم يُطلب بعد")
        case .requested:
            return Language.get("RefundStatus_Requested", alter: "تم تقديم الطلب")
        case .processing:
            return Language.get("RefundStatus_Processing", alter: "قيد المعالجة البنكية")
        case .succeeded:
            return Language.get("RefundStatus_Succeeded", alter: "تم الاسترداد بنجاح")
        case .failed:
            return Language.get("RefundStatus_Failed", alter: "فشلت العملية")
        case .retryRequired:
            return Language.get("RefundStatus_RetryRequired", alter: "يتطلب إعادة المحاولة")
        case .manualReview:
            return Language.get("RefundStatus_ManualReview", alter: "بانتظار مراجعة الإدارة المالية")
        }
    }

    public var badgeColor: Color {
        switch self {
        case .notRequired, .notRequested: return Color.gray
        case .requested, .processing: return Color(uiColor: .systemOrange)
        case .succeeded: return Color(uiColor: .systemGreen)
        case .failed, .retryRequired: return Color(uiColor: .systemRed)
        case .manualReview: return Color(uiColor: .systemPurple)
        }
    }

    public var iconName: String {
        switch self {
        case .notRequired, .notRequested: return "circle"
        case .requested: return "clock.arrow.circlepath"
        case .processing: return "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .retryRequired: return "arrow.clockwise"
        case .manualReview: return "person.badge.shield.checkmark.fill"
        }
    }
}

// MARK: - Minor Currency Money Helpers

public struct LivePetMoney: Hashable, Codable, Sendable {
    public let amountMinor: Int64
    public let currency: String

    /// Comprehensive ISO 4217 non-standard minor unit exponents
    private static let iso4217MinorUnits: [String: Int] = [
        // 0 decimals
        "BIF": 0, "CLP": 0, "DJF": 0, "GNF": 0, "ISK": 0, "JPY": 0, "KMF": 0,
        "KRW": 0, "PYG": 0, "RWF": 0, "UGX": 0, "UYI": 0, "VND": 0, "VUV": 0,
        "XAF": 0, "XOF": 0, "XPF": 0,
        // 3 decimals
        "BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3,
        // 4 decimals
        "CLF": 4, "UYW": 4
    ]

    /// Minor unit exponent based on ISO 4217 currency specifications
    public static func minorUnitScale(for currencyCode: String) -> Int {
        let normalized = currencyCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicit = iso4217MinorUnits[normalized] {
            return explicit
        }
        // ISO 4217 standard default for all other currencies (including QAR, USD, EUR, GBP, SAR, AED) is 2
        return 2
    }

    public static func scaleFactor(for currencyCode: String) -> Double {
        pow(10.0, Double(minorUnitScale(for: currencyCode)))
    }

    public init(amountMinor: Int64, currency: String = "QAR") {
        let normalized = currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.currency = normalized.isEmpty ? "QAR" : normalized
        self.amountMinor = amountMinor
    }

    public init(majorAmount: Double, currency: String = "QAR") {
        let normalized = currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCurrency = normalized.isEmpty ? "QAR" : normalized
        let factor = LivePetMoney.scaleFactor(for: resolvedCurrency)
        self.amountMinor = Int64(round(majorAmount * factor))
        self.currency = resolvedCurrency
    }

    public var majorAmount: Double {
        let factor = LivePetMoney.scaleFactor(for: currency)
        return Double(amountMinor) / factor
    }

    public var formatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        let scale = LivePetMoney.minorUnitScale(for: currency)
        formatter.minimumFractionDigits = scale
        formatter.maximumFractionDigits = scale
        return formatter.string(from: NSNumber(value: majorAmount)) ?? "\(String(format: "%.\(scale)f", majorAmount)) \(currency)"
    }
}


