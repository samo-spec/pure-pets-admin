//
//  CustomerWantedPet.swift
//  Pure Pets Admin
//
//  Created for Pure Pets Platform.
//  Category-defining Apple-grade model for the Wanted Pets operational demand system.
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Wanted Pet Status

public enum WantedPetStatus: String, CaseIterable, Identifiable, Codable {
    case waiting = "waiting"
    case contacted = "contacted"
    case interested = "interested"
    case fulfilled = "fulfilled"
    case closed = "closed"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .waiting:
            return Language.get("WantedPet_Status_Waiting", alter: "قيد الانتظار")
        case .contacted:
            return Language.get("WantedPet_Status_Contacted", alter: "تم التواصل")
        case .interested:
            return Language.get("WantedPet_Status_Interested", alter: "مهتم")
        case .fulfilled:
            return Language.get("WantedPet_Status_Fulfilled", alter: "مكتمل")
        case .closed:
            return Language.get("WantedPet_Status_Closed", alter: "مغلق")
        }
    }

    public var iconName: String {
        switch self {
        case .waiting: return "clock.fill"
        case .contacted: return "phone.bubble.left.fill"
        case .interested: return "star.fill"
        case .fulfilled: return "checkmark.circle.fill"
        case .closed: return "xmark.circle.fill"
        }
    }

    public var tintColor: Color {
        switch self {
        case .waiting: return Color(uiColor: .ppWarning)
        case .contacted: return Color(uiColor: .systemBlue)
        case .interested: return Color(uiColor: .systemPurple)
        case .fulfilled: return Color(uiColor: .ppSuccess)
        case .closed: return Color(uiColor: .systemGray)
        }
    }

    public var isActive: Bool {
        return self == .waiting || self == .contacted || self == .interested
    }
}

// MARK: - Contact Source

public enum WantedPetContactSource: String, CaseIterable, Identifiable, Codable {
    case whatsapp = "whatsapp"
    case phone = "phone"
    case inStore = "inStore"
    case instagram = "instagram"
    case facebook = "facebook"
    case existingCustomer = "existingCustomer"
    case other = "other"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .whatsapp:
            return Language.get("WantedPet_Source_WhatsApp", alter: "واتساب")
        case .phone:
            return Language.get("WantedPet_Source_Phone", alter: "اتصال هاتفي")
        case .inStore:
            return Language.get("WantedPet_Source_InStore", alter: "زيارة المتجر")
        case .instagram:
            return Language.get("WantedPet_Source_Instagram", alter: "إنستغرام")
        case .facebook:
            return Language.get("WantedPet_Source_Facebook", alter: "فيسبوك")
        case .existingCustomer:
            return Language.get("WantedPet_Source_ExistingCustomer", alter: "عميل حالي")
        case .other:
            return Language.get("WantedPet_Source_Other", alter: "أخرى")
        }
    }

    public var iconName: String {
        switch self {
        case .whatsapp: return "message.fill"
        case .phone: return "phone.fill"
        case .inStore: return "storefront.fill"
        case .instagram: return "camera.fill"
        case .facebook: return "bubble.left.and.bubble.right.fill"
        case .existingCustomer: return "person.crop.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Sex Preference

public enum WantedPetSexPreference: String, CaseIterable, Identifiable, Codable {
    case any = "any"
    case male = "male"
    case female = "female"
    case pair = "pair"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any:
            return Language.get("WantedPet_Sex_Any", alter: "أي جنس")
        case .male:
            return Language.get("WantedPet_Sex_Male", alter: "ذكر")
        case .female:
            return Language.get("WantedPet_Sex_Female", alter: "أنثى")
        case .pair:
            return Language.get("WantedPet_Sex_Pair", alter: "زوج")
        }
    }
}

// MARK: - Priority

public enum WantedPetPriority: String, CaseIterable, Identifiable, Codable {
    case normal = "normal"
    case high = "high"
    case urgent = "urgent"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: return Language.get("WantedPet_Priority_Normal", alter: "عادي")
        case .high: return Language.get("WantedPet_Priority_High", alter: "مهم")
        case .urgent: return Language.get("WantedPet_Priority_Urgent", alter: "عاجل")
        }
    }

    public var color: Color {
        switch self {
        case .normal: return Color(uiColor: .systemGray)
        case .high: return Color(uiColor: .ppWarning)
        case .urgent: return Color(uiColor: .ppError)
        }
    }
}

// MARK: - Match Level

public enum WantedPetMatchLevel: String, CaseIterable, Identifiable, Codable {
    case exact = "exact"
    case compatible = "compatible"
    case broad = "broad"
    case none = "none"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .exact:
            return Language.get("WantedPet_Match_Exact", alter: "تطابق تام")
        case .compatible:
            return Language.get("WantedPet_Match_Compatible", alter: "متوافق")
        case .broad:
            return Language.get("WantedPet_Match_Broad", alter: "طلب عام")
        case .none:
            return Language.get("WantedPet_Match_None", alter: "لا يوجد تطابق")
        }
    }

    public var tintColor: Color {
        switch self {
        case .exact: return Color(uiColor: .ppSuccess)
        case .compatible: return Color(uiColor: .ppWarning)
        case .broad: return Color(uiColor: .systemIndigo)
        case .none: return Color(uiColor: .systemGray)
        }
    }

    public var iconName: String {
        switch self {
        case .exact: return "checkmark.seal.fill"
        case .compatible: return "slider.horizontal.2.square"
        case .broad: return "square.grid.2x2"
        case .none: return "xmark.circle"
        }
    }
}

// MARK: - CustomerWantedPet Model

public struct CustomerWantedPet: Identifiable, Hashable {
    public let id: String
    public var customerId: String?
    public var customerName: String
    public var phoneNumber: String
    public var normalizedPhoneNumber: String
    public var contactSource: WantedPetContactSource
    public var mainKindId: Int
    public var mainKindName: String?
    public var subkindId: Int?
    public var subkindName: String?
    public var breedId: String?
    public var speciesId: String?
    public var sexPreference: WantedPetSexPreference
    public var agePreference: String?
    public var colorPreference: String?
    public var sizePreference: String?
    public var budgetMin: Double?
    public var budgetMax: Double?
    public var branchPreferenceId: String?
    public var notes: String?
    public var status: WantedPetStatus
    public var priority: WantedPetPriority
    public var createdAt: Date
    public var updatedAt: Date
    public var lastContactedAt: Date?
    public var lastContactedByUserId: String?
    public var lastContactChannel: String?
    public var fulfilledAt: Date?
    public var fulfilledPetId: String?
    public var closedAt: Date?
    public var closeReason: String?
    public var createdByUserId: String
    public var updatedByUserId: String

    public init(
        id: String,
        customerId: String? = nil,
        customerName: String,
        phoneNumber: String,
        normalizedPhoneNumber: String,
        contactSource: WantedPetContactSource = .whatsapp,
        mainKindId: Int,
        mainKindName: String? = nil,
        subkindId: Int? = nil,
        subkindName: String? = nil,
        breedId: String? = nil,
        speciesId: String? = nil,
        sexPreference: WantedPetSexPreference = .any,
        agePreference: String? = nil,
        colorPreference: String? = nil,
        sizePreference: String? = nil,
        budgetMin: Double? = nil,
        budgetMax: Double? = nil,
        branchPreferenceId: String? = nil,
        notes: String? = nil,
        status: WantedPetStatus = .waiting,
        priority: WantedPetPriority = .normal,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastContactedAt: Date? = nil,
        lastContactedByUserId: String? = nil,
        lastContactChannel: String? = nil,
        fulfilledAt: Date? = nil,
        fulfilledPetId: String? = nil,
        closedAt: Date? = nil,
        closeReason: String? = nil,
        createdByUserId: String = "",
        updatedByUserId: String = ""
    ) {
        self.id = id
        self.customerId = customerId
        self.customerName = customerName
        self.phoneNumber = phoneNumber
        self.normalizedPhoneNumber = normalizedPhoneNumber
        self.contactSource = contactSource
        self.mainKindId = mainKindId
        self.mainKindName = mainKindName
        self.subkindId = subkindId
        self.subkindName = subkindName
        self.breedId = breedId
        self.speciesId = speciesId
        self.sexPreference = sexPreference
        self.agePreference = agePreference
        self.colorPreference = colorPreference
        self.sizePreference = sizePreference
        self.budgetMin = budgetMin
        self.budgetMax = budgetMax
        self.branchPreferenceId = branchPreferenceId
        self.notes = notes
        self.status = status
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastContactedAt = lastContactedAt
        self.lastContactedByUserId = lastContactedByUserId
        self.lastContactChannel = lastContactChannel
        self.fulfilledAt = fulfilledAt
        self.fulfilledPetId = fulfilledPetId
        self.closedAt = closedAt
        self.closeReason = closeReason
        self.createdByUserId = createdByUserId
        self.updatedByUserId = updatedByUserId
    }

    public init?(documentId: String, data: [String: Any]) {
        self.id = documentId
        self.customerId = data["customerId"] as? String
        self.customerName = (data["customerName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.phoneNumber = (data["phoneNumber"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.normalizedPhoneNumber = (data["normalizedPhoneNumber"] as? String) ?? ""

        let sourceRaw = (data["contactSource"] as? String) ?? ""
        self.contactSource = WantedPetContactSource(rawValue: sourceRaw) ?? .other

        if let mId = data["mainKindId"] as? Int {
            self.mainKindId = mId
        } else if let mStr = data["mainKindId"] as? String, let mInt = Int(mStr) {
            self.mainKindId = mInt
        } else {
            self.mainKindId = 0
        }
        self.mainKindName = data["mainKindName"] as? String

        if let sId = data["subkindId"] as? Int {
            self.subkindId = sId
        } else if let sStr = data["subkindId"] as? String, let sInt = Int(sStr) {
            self.subkindId = sInt
        } else {
            self.subkindId = nil
        }
        self.subkindName = data["subkindName"] as? String

        self.breedId = data["breedId"] as? String
        self.speciesId = data["speciesId"] as? String

        let sexRaw = (data["sexPreference"] as? String) ?? "any"
        self.sexPreference = WantedPetSexPreference(rawValue: sexRaw) ?? .any

        self.agePreference = data["agePreference"] as? String
        self.colorPreference = data["colorPreference"] as? String
        self.sizePreference = data["sizePreference"] as? String

        if let bMin = data["budgetMin"] as? Double {
            self.budgetMin = bMin
        } else if let bMinNum = data["budgetMin"] as? NSNumber {
            self.budgetMin = bMinNum.doubleValue
        } else {
            self.budgetMin = nil
        }

        if let bMax = data["budgetMax"] as? Double {
            self.budgetMax = bMax
        } else if let bMaxNum = data["budgetMax"] as? NSNumber {
            self.budgetMax = bMaxNum.doubleValue
        } else {
            self.budgetMax = nil
        }

        self.branchPreferenceId = data["branchPreferenceId"] as? String
        self.notes = data["notes"] as? String

        let statusRaw = (data["status"] as? String) ?? "waiting"
        self.status = WantedPetStatus(rawValue: statusRaw) ?? .waiting

        let prioRaw = (data["priority"] as? String) ?? "normal"
        self.priority = WantedPetPriority(rawValue: prioRaw) ?? .normal

        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else {
            self.createdAt = Date()
        }

        if let ts = data["updatedAt"] as? Timestamp {
            self.updatedAt = ts.dateValue()
        } else {
            self.updatedAt = Date()
        }

        if let ts = data["lastContactedAt"] as? Timestamp {
            self.lastContactedAt = ts.dateValue()
        } else {
            self.lastContactedAt = nil
        }
        self.lastContactedByUserId = data["lastContactedByUserId"] as? String
        self.lastContactChannel = data["lastContactChannel"] as? String

        if let ts = data["fulfilledAt"] as? Timestamp {
            self.fulfilledAt = ts.dateValue()
        } else {
            self.fulfilledAt = nil
        }
        self.fulfilledPetId = data["fulfilledPetId"] as? String

        if let ts = data["closedAt"] as? Timestamp {
            self.closedAt = ts.dateValue()
        } else {
            self.closedAt = nil
        }
        self.closeReason = data["closeReason"] as? String

        self.createdByUserId = (data["createdByUserId"] as? String) ?? ""
        self.updatedByUserId = (data["updatedByUserId"] as? String) ?? ""

        guard !self.customerName.isEmpty, !self.phoneNumber.isEmpty else { return nil }
    }

    // MARK: - Computed Presentation Helpers

    public var requestedPetTitle: String {
        if let sub = subkindName, !sub.isEmpty {
            return sub
        }
        if let main = mainKindName, !main.isEmpty {
            return main
        }
        return Language.get("WantedPet_UnknownPet", alter: "حيوان غير محدد")
    }

    public var formattedPhoneDisplay: String {
        let digits = normalizedPhoneNumber.isEmpty ? phoneNumber : normalizedPhoneNumber
        if digits.hasPrefix("201") && digits.count == 12 {
            let prefix = digits.prefix(4)
            let mid = digits.dropFirst(4).prefix(4)
            let end = digits.suffix(4)
            return "+20 \(prefix.suffix(2)) \(mid) \(end)"
        }
        if digits.hasPrefix("974") && digits.count == 11 {
            return "+974 \(digits.dropFirst(3).prefix(4)) \(digits.suffix(4))"
        }
        return phoneNumber
    }

    public var waitingDurationText: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour], from: createdAt, to: Date())
        let days = components.day ?? 0
        if days == 0 {
            let hours = components.hour ?? 0
            if hours <= 1 {
                return Language.get("WantedPet_Duration_JustNow", alter: "اليوم")
            }
            return String(format: Language.get("WantedPet_Duration_Hours", alter: "منذ %d ساعة"), hours)
        } else if days == 1 {
            return Language.get("WantedPet_Duration_Yesterday", alter: "منذ يوم واحد")
        } else if days == 2 {
            return Language.get("WantedPet_Duration_TwoDays", alter: "منذ يومين")
        } else if days <= 10 {
            return String(format: Language.get("WantedPet_Duration_DaysFew", alter: "منذ %d أيام"), days)
        } else {
            return String(format: Language.get("WantedPet_Duration_DaysMany", alter: "منذ %d يوماً"), days)
        }
    }

    public var preferencesSummary: String {
        var parts: [String] = []

        if sexPreference != .any {
            parts.append(sexPreference.title)
        }
        if let color = colorPreference, !color.isEmpty {
            parts.append(color)
        }
        if let budget = budgetMax, budget > 0 {
            let formatted = String(format: "≤ %.0f", budget)
            parts.append(formatted)
        }
        if let age = agePreference, !age.isEmpty {
            parts.append(age)
        }

        return parts.isEmpty ? Language.get("WantedPet_AnySpecimen", alter: "أي مواصفات") : parts.joined(separator: " · ")
    }
}

// MARK: - Match Result

public struct WantedPetMatchResult: Identifiable, Hashable {
    public var id: String { wantedPet.id }
    public let wantedPet: CustomerWantedPet
    public let matchLevel: WantedPetMatchLevel
    public let matchReason: String

    public init(wantedPet: CustomerWantedPet, matchLevel: WantedPetMatchLevel, matchReason: String) {
        self.wantedPet = wantedPet
        self.matchLevel = matchLevel
        self.matchReason = matchReason
    }
}
