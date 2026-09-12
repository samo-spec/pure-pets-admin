//
//  LivePetReturnState.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Strict state machine preventing direct SOLD -> AVAILABLE shortcuts.
//

import Foundation
import SwiftUI

// MARK: - Live Pet Lifecycle Status

public enum LivePetLifecycleStatus: String, Codable, CaseIterable, Sendable {
    case available            = "available"
    case reserved             = "reserved"
    case sold                 = "sold"
    case returnRequested      = "return_requested"
    case returnInTransit      = "return_in_transit"
    case returnReceived       = "return_received"
    case underInspection      = "under_inspection"
    case quarantined          = "quarantined"
    case medicalHold          = "medical_hold"
    case cleared              = "cleared"
    case notForResale         = "not_for_resale"
    case transferredToCare    = "transferred_to_care"
    case writtenOff           = "written_off"

    /// Whether this animal is physically in inventory and available for customer purchase.
    public var isSellable: Bool {
        self == .available
    }

    /// Whether this status represents an active post-sale custody hold.
    public var isUnderCustodyHold: Bool {
        switch self {
        case .returnRequested, .returnInTransit, .returnReceived, .underInspection, .quarantined, .medicalHold:
            return true
        default:
            return false
        }
    }

    /// Authoritative validation of allowed state transitions.
    public func canTransition(to next: LivePetLifecycleStatus) -> Bool {
        switch self {
        case .available:
            return next == .reserved || next == .sold || next == .writtenOff
        case .reserved:
            return next == .available || next == .sold
        case .sold:
            // Non-negotiable invariant: Sold cannot jump directly to available!
            return next == .returnRequested || next == .returnReceived
        case .returnRequested:
            return next == .returnInTransit || next == .returnReceived || next == .sold // (if cancelled)
        case .returnInTransit:
            return next == .returnReceived
        case .returnReceived:
            return next == .underInspection || next == .quarantined
        case .underInspection:
            return next == .cleared || next == .quarantined || next == .medicalHold || next == .notForResale
        case .quarantined:
            return next == .underInspection || next == .medicalHold || next == .notForResale
        case .medicalHold:
            return next == .underInspection || next == .notForResale || next == .transferredToCare
        case .cleared:
            // Explicit clearance moves cleared animal to available
            return next == .available || next == .sold
        case .notForResale:
            return next == .transferredToCare || next == .writtenOff
        case .transferredToCare, .writtenOff:
            return false // Terminal states
        }
    }

    public var localizedTitle: String {
        switch self {
        case .available:
            return Language.get("LivePet_ReturnStatus_Available", alter: "متاح للبيع")
        case .reserved:
            return Language.get("LivePet_ReturnStatus_Reserved", alter: "محجوز لعميل")
        case .sold:
            return Language.get("LivePet_ReturnStatus_Sold", alter: "مباع")
        case .returnRequested:
            return Language.get("LivePet_ReturnStatus_ReturnRequested", alter: "طلب استرجاع قيد الانتظار")
        case .returnInTransit:
            return Language.get("LivePet_ReturnStatus_ReturnInTransit", alter: "في طريق الاسترجاع")
        case .returnReceived:
            return Language.get("LivePet_ReturnStatus_ReturnReceived", alter: "تم الاستلام في المتجر")
        case .underInspection:
            return Language.get("LivePet_ReturnStatus_UnderInspection", alter: "قيد الفحص والتقييم")
        case .quarantined:
            return Language.get("LivePet_ReturnStatus_Quarantined", alter: "في الحجر الصحي")
        case .medicalHold:
            return Language.get("LivePet_ReturnStatus_MedicalHold", alter: "حجز رعاية بيطرية")
        case .cleared:
            return Language.get("LivePet_ReturnStatus_Cleared", alter: "معتمد بعد الفحص")
        case .notForResale:
            return Language.get("LivePet_ReturnStatus_NotForResale", alter: "غير قابل لإعادة البيع")
        case .transferredToCare:
            return Language.get("LivePet_ReturnStatus_TransferredToCare", alter: "محول لمركز رعاية متخصص")
        case .writtenOff:
            return Language.get("LivePet_ReturnStatus_WrittenOff", alter: "تم الشطب")
        }
    }

    public var iconName: String {
        switch self {
        case .available: return "checkmark.seal.fill"
        case .reserved: return "bookmark.fill"
        case .sold: return "bag.fill"
        case .returnRequested: return "arrow.uturn.backward.circle"
        case .returnInTransit: return "truck.box.fill"
        case .returnReceived: return "tray.and.arrow.down.fill"
        case .underInspection: return "cross.case.fill"
        case .quarantined: return "shield.lefthalf.filled.badge.checkmark"
        case .medicalHold: return "stethoscope"
        case .cleared: return "checkmark.circle.badge.questionmark.fill"
        case .notForResale: return "slash.circle.fill"
        case .transferredToCare: return "heart.fill"
        case .writtenOff: return "xmark.bin.fill"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .available, .cleared: return Color(uiColor: .systemGreen)
        case .reserved: return Color(uiColor: .systemBlue)
        case .sold: return Color(uiColor: .systemGray)
        case .returnRequested, .returnInTransit: return Color(uiColor: .systemOrange)
        case .returnReceived, .underInspection: return Color(uiColor: .systemPurple)
        case .quarantined, .medicalHold: return Color(uiColor: .systemRed)
        case .notForResale, .transferredToCare, .writtenOff: return Color(uiColor: .systemBrown)
        }
    }
}

// MARK: - Live Pet Custody Status

public enum LivePetCustodyStatus: String, Codable, CaseIterable, Sendable {
    case store                = "store"
    case reservedForCustomer  = "reserved_for_customer"
    case customer             = "customer"
    case inTransit            = "in_transit"
    case returnDesk           = "return_desk"
    case quarantine           = "quarantine"
    case medical              = "medical"
    case externalCare         = "external_care"
    case closed               = "closed"

    public var localizedTitle: String {
        switch self {
        case .store:
            return Language.get("Custody_Store", alter: "في المتجر / القفص")
        case .reservedForCustomer:
            return Language.get("Custody_ReservedForCustomer", alter: "محجوز للعميل في الفرع")
        case .customer:
            return Language.get("Custody_Customer", alter: "في عهدة العميل")
        case .inTransit:
            return Language.get("Custody_InTransit", alter: "في النقل")
        case .returnDesk:
            return Language.get("Custody_ReturnDesk", alter: "مكتب استلام المرتجعات بالفرع")
        case .quarantine:
            return Language.get("Custody_Quarantine", alter: "وحدة الحجر والعزل")
        case .medical:
            return Language.get("Custody_Medical", alter: "العيادة البيطرية")
        case .externalCare:
            return Language.get("Custody_ExternalCare", alter: "مركز رعاية خارجي")
        case .closed:
            return Language.get("Custody_Closed", alter: "أغلقت العهدة")
        }
    }
}

// MARK: - Live Pet Health Status

public enum LivePetHealthStatus: String, Codable, CaseIterable, Sendable {
    case unknown             = "unknown"
    case appearsNormal       = "appears_normal"
    case inspectionRequired  = "inspection_required"
    case quarantineRequired  = "quarantine_required"
    case medicalAttention    = "medical_attention"
    case cleared             = "cleared"
    case notForResale        = "not_for_resale"

    public var localizedTitle: String {
        switch self {
        case .unknown:
            return Language.get("Health_Unknown", alter: "غير محدد")
        case .appearsNormal:
            return Language.get("Health_AppearsNormal", alter: "يبدو بحالة طبيعية")
        case .inspectionRequired:
            return Language.get("Health_InspectionRequired", alter: "يتطلب فحصاً بيطرياً")
        case .quarantineRequired:
            return Language.get("Health_QuarantineRequired", alter: "يتطلب حجراً صحياً")
        case .medicalAttention:
            return Language.get("Health_MedicalAttention", alter: "يحتاج رعاية طبية عاجلة")
        case .cleared:
            return Language.get("Health_Cleared", alter: "سليم ومعتمد")
        case .notForResale:
            return Language.get("Health_NotForResale", alter: "غير مؤهل صحياً للبيع")
        }
    }
}

// MARK: - Return Case Aggregate Status

public enum ReturnCaseStatus: String, Codable, CaseIterable, Sendable {
    case draft            = "draft"
    case initiated        = "initiated"
    case awaitingReceive  = "awaiting_receive"
    case received         = "received"
    case underInspection  = "under_inspection"
    case approved         = "approved"
    case rejected         = "rejected"
    case completed        = "completed"
    case cancelled        = "cancelled"

    public var isFinal: Bool {
        self == .completed || self == .cancelled || self == .rejected
    }

    public var localizedTitle: String {
        switch self {
        case .draft:
            return Language.get("ReturnCase_Draft", alter: "مسودة غير مرسلة")
        case .initiated:
            return Language.get("ReturnCase_Initiated", alter: "تم فتح الطلب")
        case .awaitingReceive:
            return Language.get("ReturnCase_AwaitingReceive", alter: "بانتظار وصول الحيوان")
        case .received:
            return Language.get("ReturnCase_Received", alter: "تم الاستلام الفعلي")
        case .underInspection:
            return Language.get("ReturnCase_UnderInspection", alter: "قيد الفحص والتقييم")
        case .approved:
            return Language.get("ReturnCase_Approved", alter: "معتمد")
        case .rejected:
            return Language.get("ReturnCase_Rejected", alter: "مرفوض")
        case .completed:
            return Language.get("ReturnCase_Completed", alter: "مكتمل نهائياً")
        case .cancelled:
            return Language.get("ReturnCase_Cancelled", alter: "ملغي")
        }
    }

    public var badgeColor: Color {
        switch self {
        case .draft: return Color.gray
        case .initiated, .awaitingReceive: return Color(uiColor: .systemBlue)
        case .received, .underInspection: return Color(uiColor: .systemPurple)
        case .approved, .completed: return Color(uiColor: .systemGreen)
        case .rejected, .cancelled: return Color(uiColor: .systemRed)
        }
    }
}
