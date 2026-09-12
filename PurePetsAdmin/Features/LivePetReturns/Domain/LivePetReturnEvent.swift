//
//  LivePetReturnEvent.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Append-only immutable event model for case history and operational audit.
//

import Foundation
import SwiftUI
import FirebaseFirestore

public enum ReturnEventType: String, Codable, CaseIterable, Sendable {
    case returnCreated               = "return_created"
    case unitSelected                = "unit_selected"
    case customerHandoffStarted      = "customer_handoff_started"
    case unitReceived                = "unit_received"
    case inspectionStarted           = "inspection_started"
    case inspectionUpdated           = "inspection_updated"
    case inspectionCleared           = "inspection_cleared"
    case quarantineStarted           = "quarantine_started"
    case medicalHoldStarted          = "medical_hold_started"
    case refundRequested             = "refund_requested"
    case refundProcessing            = "refund_processing"
    case refundSucceeded             = "refund_succeeded"
    case refundFailed                = "refund_failed"
    case returnCompleted             = "return_completed"
    case returnCancelled             = "return_cancelled"

    public var localizedTitle: String {
        switch self {
        case .returnCreated:
            return Language.get("ReturnEvent_Created", alter: "إنشاء طلب الاسترجاع")
        case .unitSelected:
            return Language.get("ReturnEvent_UnitSelected", alter: "تحديد الحيوان المسترجع")
        case .customerHandoffStarted:
            return Language.get("ReturnEvent_HandoffStarted", alter: "بدء تسليم العميل للحيوان")
        case .unitReceived:
            return Language.get("ReturnEvent_UnitReceived", alter: "استلام الحيوان في مكتب الفرع")
        case .inspectionStarted:
            return Language.get("ReturnEvent_InspectionStarted", alter: "بدء الفحص والتقييم الصحي")
        case .inspectionUpdated:
            return Language.get("ReturnEvent_InspectionUpdated", alter: "تحديث نتائج الفحص الصحي")
        case .inspectionCleared:
            return Language.get("ReturnEvent_InspectionCleared", alter: "اجتياز الفحص والاعتماد للبيع")
        case .quarantineStarted:
            return Language.get("ReturnEvent_QuarantineStarted", alter: "إدخال الحيوان في الحجر الصحي")
        case .medicalHoldStarted:
            return Language.get("ReturnEvent_MedicalHoldStarted", alter: "تحويل للرعاية والعلاج البيطري")
        case .refundRequested:
            return Language.get("ReturnEvent_RefundRequested", alter: "طلب الاسترداد المالي")
        case .refundProcessing:
            return Language.get("ReturnEvent_RefundProcessing", alter: "معالجة الاسترداد مع بوابة الدفع")
        case .refundSucceeded:
            return Language.get("ReturnEvent_RefundSucceeded", alter: "اكتمال تسوية الاسترداد المالي")
        case .refundFailed:
            return Language.get("ReturnEvent_RefundFailed", alter: "فشل في تسوية الاسترداد المالي")
        case .returnCompleted:
            return Language.get("ReturnEvent_ReturnCompleted", alter: "إغلاق واكتمال ملف الاسترجاع")
        case .returnCancelled:
            return Language.get("ReturnEvent_ReturnCancelled", alter: "إلغاء طلب الاسترجاع")
        }
    }

    public var iconName: String {
        switch self {
        case .returnCreated: return "doc.badge.plus"
        case .unitSelected: return "checkmark.square.fill"
        case .customerHandoffStarted: return "person.line.dotted.person.fill"
        case .unitReceived: return "tray.and.arrow.down.fill"
        case .inspectionStarted, .inspectionUpdated: return "magnifyingglass.circle.fill"
        case .inspectionCleared: return "checkmark.seal.fill"
        case .quarantineStarted: return "shield.lefthalf.filled.badge.checkmark"
        case .medicalHoldStarted: return "cross.case.fill"
        case .refundRequested: return "banknote"
        case .refundProcessing: return "arrow.triangle.2.circlepath"
        case .refundSucceeded: return "checkmark.circle.fill"
        case .refundFailed: return "xmark.octagon.fill"
        case .returnCompleted: return "flag.checkered"
        case .returnCancelled: return "xmark.circle"
        }
    }

    public var tintColor: Color {
        switch self {
        case .returnCreated, .unitSelected, .customerHandoffStarted:
            return Color(uiColor: .systemBlue)
        case .unitReceived, .inspectionStarted, .inspectionUpdated:
            return Color(uiColor: .systemPurple)
        case .inspectionCleared, .refundSucceeded, .returnCompleted:
            return Color(uiColor: .systemGreen)
        case .quarantineStarted, .refundRequested, .refundProcessing:
            return Color(uiColor: .systemOrange)
        case .medicalHoldStarted, .refundFailed, .returnCancelled:
            return Color(uiColor: .systemRed)
        }
    }
}

public struct LivePetReturnEvent: Identifiable, Codable, Hashable, Sendable {
    public let eventId: String
    public let eventType: ReturnEventType
    public let returnCaseId: String
    public let unitId: String?
    public let actorId: String
    public var actorName: String?
    public var actorRole: String?
    public let branchId: String
    public let commandId: String?
    public let occurredAt: Date
    public var notes: String?
    public var metadata: [String: String]?

    public var id: String { eventId }

    public init(
        eventId: String,
        eventType: ReturnEventType,
        returnCaseId: String,
        unitId: String? = nil,
        actorId: String,
        actorName: String? = nil,
        actorRole: String? = nil,
        branchId: String,
        commandId: String? = nil,
        occurredAt: Date = Date(),
        notes: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.eventId = eventId
        self.eventType = eventType
        self.returnCaseId = returnCaseId
        self.unitId = unitId
        self.actorId = actorId
        self.actorName = actorName
        self.actorRole = actorRole
        self.branchId = branchId
        self.commandId = commandId
        self.occurredAt = occurredAt
        self.notes = notes
        self.metadata = metadata
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "eventId": eventId,
            "eventType": eventType.rawValue,
            "returnCaseId": returnCaseId,
            "actorId": actorId,
            "branchId": branchId,
            "occurredAt": occurredAt
        ]
        if let unitId { dict["unitId"] = unitId }
        if let actorName { dict["actorName"] = actorName }
        if let actorRole { dict["actorRole"] = actorRole }
        if let commandId { dict["commandId"] = commandId }
        if let notes { dict["notes"] = notes }
        if let metadata { dict["metadata"] = metadata }
        return dict
    }

    public static func fromDictionary(_ dict: [String: Any], eventId: String) -> LivePetReturnEvent? {
        guard let typeStr = dict["eventType"] as? String,
              let eventType = ReturnEventType(rawValue: typeStr),
              let returnCaseId = dict["returnCaseId"] as? String else {
            return nil
        }

        let actorId = (dict["actorId"] as? String) ?? ""
        let branchId = (dict["branchId"] as? String) ?? ""
        let occurredAt: Date
        if let d = dict["occurredAt"] as? Date {
            occurredAt = d
        } else if let ts = dict["occurredAt"] as? Timestamp {
            occurredAt = ts.dateValue()
        } else if let sec = dict["occurredAt"] as? Double {
            occurredAt = Date(timeIntervalSince1970: sec)
        } else {
            occurredAt = Date()
        }

        return LivePetReturnEvent(
            eventId: eventId,
            eventType: eventType,
            returnCaseId: returnCaseId,
            unitId: dict["unitId"] as? String,
            actorId: actorId,
            actorName: dict["actorName"] as? String,
            actorRole: dict["actorRole"] as? String,
            branchId: branchId,
            commandId: dict["commandId"] as? String,
            occurredAt: occurredAt,
            notes: dict["notes"] as? String,
            metadata: dict["metadata"] as? [String: String]
        )
    }
}
