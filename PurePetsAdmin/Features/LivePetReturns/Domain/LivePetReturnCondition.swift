//
//  LivePetReturnCondition.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Physical condition at intake and health/commercial disposition enums.
//

import Foundation
import SwiftUI

// MARK: - Physical Return Condition

public enum ReturnPhysicalCondition: String, Codable, CaseIterable, Identifiable, Sendable {
    case appearsNormal          = "appears_normal"
    case minorConcern           = "minor_concern"
    case injured                = "injured"
    case illnessSuspected       = "illness_suspected"
    case urgentMedicalAttention = "urgent_medical_attention"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .appearsNormal:
            return Language.get("ReturnCondition_AppearsNormal", alter: "سليم ونشط ظاهرياً")
        case .minorConcern:
            return Language.get("ReturnCondition_MinorConcern", alter: "ملاحظة سلوكية أو مظهرية طفيفة")
        case .injured:
            return Language.get("ReturnCondition_Injured", alter: "إصابة جسدية / كدمات / جروح")
        case .illnessSuspected:
            return Language.get("ReturnCondition_IllnessSuspected", alter: "اشتباه بأعراض مرضية أو خمول")
        case .urgentMedicalAttention:
            return Language.get("ReturnCondition_UrgentMedical", alter: "حالة حرجة تتطلب تدخلاً بيطرياً فورياً")
        }
    }

    public var iconName: String {
        switch self {
        case .appearsNormal: return "checkmark.seal.fill"
        case .minorConcern: return "info.circle.fill"
        case .injured: return "bandage.fill"
        case .illnessSuspected: return "cross.case.fill"
        case .urgentMedicalAttention: return "exclamationmark.triangle.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .appearsNormal: return Color(uiColor: .systemGreen)
        case .minorConcern: return Color(uiColor: .systemOrange)
        case .injured: return Color(uiColor: .systemBrown)
        case .illnessSuspected: return Color(uiColor: .systemPurple)
        case .urgentMedicalAttention: return Color(uiColor: .systemRed)
        }
    }

    /// Suggested default health disposition upon intake.
    public var suggestedHealthDisposition: HealthDisposition {
        switch self {
        case .appearsNormal: return .inspectionRequired
        case .minorConcern: return .inspectionRequired
        case .injured: return .veterinaryAssessment
        case .illnessSuspected: return .quarantine
        case .urgentMedicalAttention: return .veterinaryAssessment
        }
    }

    /// Suggested default commercial disposition upon intake.
    public var suggestedCommercialDisposition: CommercialDisposition {
        switch self {
        case .appearsNormal, .minorConcern:
            return .hold
        case .injured, .illnessSuspected:
            return .hold
        case .urgentMedicalAttention:
            return .permanentNonResale
        }
    }
}

// MARK: - Health Disposition

public enum HealthDisposition: String, Codable, CaseIterable, Identifiable, Sendable {
    case inspectionRequired   = "inspection_required"
    case quarantine           = "quarantine"
    case veterinaryAssessment = "veterinary_assessment"
    case cleared              = "cleared"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .inspectionRequired:
            return Language.get("HealthDisposition_InspectionRequired", alter: "فحص روتيني مطلوب")
        case .quarantine:
            return Language.get("HealthDisposition_Quarantine", alter: "حجر صحي وعزل وقائي")
        case .veterinaryAssessment:
            return Language.get("HealthDisposition_VetAssessment", alter: "كشف بيطري تخصصي")
        case .cleared:
            return Language.get("HealthDisposition_Cleared", alter: "معتمد طبياً (سليم)")
        }
    }

    public var iconName: String {
        switch self {
        case .inspectionRequired: return "stethoscope"
        case .quarantine: return "shield.lefthalf.filled.badge.checkmark"
        case .veterinaryAssessment: return "cross.case.fill"
        case .cleared: return "checkmark.seal.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .inspectionRequired: return Color(uiColor: .systemBlue)
        case .quarantine: return Color(uiColor: .systemPurple)
        case .veterinaryAssessment: return Color(uiColor: .systemOrange)
        case .cleared: return Color(uiColor: .systemGreen)
        }
    }
}

// MARK: - Commercial Disposition

public enum CommercialDisposition: String, Codable, CaseIterable, Identifiable, Sendable {
    case hold               = "hold"
    case eligibleForResale  = "eligible_for_resale"
    case permanentNonResale = "permanent_non_resale"
    case transferToCare     = "transfer_to_care"

    public var id: String { rawValue }

    public var localizedTitle: String {
        switch self {
        case .hold:
            return Language.get("CommercialDisposition_Hold", alter: "حجز معلق حتى الفحص")
        case .eligibleForResale:
            return Language.get("CommercialDisposition_EligibleResale", alter: "مؤهل للبيع (بانتظار الاعتماد)")
        case .permanentNonResale:
            return Language.get("CommercialDisposition_NonResale", alter: "استبعاد دائم من البيع")
        case .transferToCare:
            return Language.get("CommercialDisposition_CareTransfer", alter: "تحويل لمركز رعاية / تبني")
        }
    }

    public var iconName: String {
        switch self {
        case .hold: return "pause.circle.fill"
        case .eligibleForResale: return "arrow.3.trianglepath"
        case .permanentNonResale: return "slash.circle.fill"
        case .transferToCare: return "heart.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .hold: return Color(uiColor: .systemOrange)
        case .eligibleForResale: return Color(uiColor: .systemGreen)
        case .permanentNonResale: return Color(uiColor: .systemRed)
        case .transferToCare: return Color(uiColor: .systemIndigo)
        }
    }
}
