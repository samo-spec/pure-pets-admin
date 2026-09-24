import Foundation

/// Pure, dependency-free Hotel policies shared by reception and suite management.
/// Keeping these rules outside SwiftUI prevents presentation code from inventing
/// operational defaults that disagree with the backend.
public enum AdminHotelSpeciesPolicy {
    public static func defaultSpecies(forWingRawValue rawValue: String) -> [String] {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dogs": return ["dog"]
        case "cats": return ["cat"]
        case "birds": return ["bird"]
        case "small_pets": return ["small_pets"]
        case "isolation", "medical_observation", "daycare": return []
        default: return []
        }
    }
}

public struct AdminHotelAvailabilityUnit: Hashable, Sendable, Identifiable {
    public let accommodationId: String
    public let accommodationTypeId: String
    public let code: String
    public let name: String
    public let wing: String
    public let status: String
    public let isAssignable: Bool
    public let isReservedForThisStay: Bool
    public let allowedMainKindIds: [Int]
    public let rejections: [String]
    public let remainingCapacity: Int
    public let occupiedInWindow: Int
    public let maxCapacity: Int
    public let holdingStayIds: [String]
    public let nightlyRateMinor: Int?

    public var id: String { accommodationId }

    public init(
        accommodationId: String,
        accommodationTypeId: String = "",
        code: String = "",
        name: String = "",
        wing: String = "",
        status: String = "available",
        isAssignable: Bool = true,
        isReservedForThisStay: Bool = false,
        allowedMainKindIds: [Int] = [],
        rejections: [String] = [],
        remainingCapacity: Int = 1,
        occupiedInWindow: Int = 0,
        maxCapacity: Int = 1,
        holdingStayIds: [String] = [],
        nightlyRateMinor: Int? = nil
    ) {
        self.accommodationId = accommodationId
        self.accommodationTypeId = accommodationTypeId
        self.code = code
        self.name = name
        self.wing = wing
        self.status = status
        self.isAssignable = isAssignable
        self.isReservedForThisStay = isReservedForThisStay
        self.allowedMainKindIds = allowedMainKindIds
        self.rejections = rejections
        self.remainingCapacity = remainingCapacity
        self.occupiedInWindow = occupiedInWindow
        self.maxCapacity = maxCapacity
        self.holdingStayIds = holdingStayIds
        self.nightlyRateMinor = nightlyRateMinor
    }

    public static func fromDictionary(_ dictionary: [String: Any]) -> AdminHotelAvailabilityUnit? {
        guard let rawId = dictionary["accommodationId"] as? String else { return nil }
        let accommodationId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accommodationId.isEmpty else { return nil }

        let isReserved = (dictionary["isReservedForThisStay"] as? Bool)
            ?? (dictionary["heldByCurrentStay"] as? Bool)
            ?? false

        let allowedKinds: [Int]
        if let direct = dictionary["allowedMainKindIds"] as? [Int] {
            allowedKinds = direct
        } else if let nsNumbers = dictionary["allowedMainKindIds"] as? [NSNumber] {
            allowedKinds = nsNumbers.map(\.intValue)
        } else {
            allowedKinds = []
        }

        return AdminHotelAvailabilityUnit(
            accommodationId: accommodationId,
            accommodationTypeId: string(dictionary["accommodationTypeId"]),
            code: string(dictionary["code"]),
            name: string(dictionary["name"]),
            wing: string(dictionary["wing"]),
            status: string(dictionary["status"]),
            isAssignable: dictionary["assignable"] as? Bool ?? false,
            isReservedForThisStay: isReserved,
            allowedMainKindIds: allowedKinds,
            rejections: dictionary["rejections"] as? [String] ?? [],
            remainingCapacity: integer(dictionary["remainingInWindow"]),
            occupiedInWindow: integer(dictionary["occupiedInWindow"]),
            maxCapacity: max(1, integer(dictionary["maxCapacity"], fallback: 1)),
            holdingStayIds: dictionary["holdingStayIds"] as? [String] ?? [],
            nightlyRateMinor: integerOptional(dictionary["nightlyRateMinor"])
        )
    }

    private static func string(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func integer(_ value: Any?, fallback: Int = 0) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return fallback
    }

    private static func integerOptional(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

public struct AdminHotelCompatibleAlternativeType: Hashable, Sendable, Identifiable {
    public let accommodationTypeId: String
    public let nameAr: String
    public let nameEn: String
    public let wing: String
    public let nightlyRateMinor: Int
    public let rateDeltaMinor: Int
    public let assignableUnits: [AdminHotelAvailabilityUnit]

    public var id: String { accommodationTypeId }

    public var displayName: String {
        !nameAr.isEmpty ? nameAr : nameEn
    }

    public static func fromDictionary(_ dictionary: [String: Any]) -> AdminHotelCompatibleAlternativeType? {
        guard let typeId = dictionary["accommodationTypeId"] as? String, !typeId.isEmpty else { return nil }
        let nameAr = dictionary["nameAr"] as? String ?? ""
        let nameEn = dictionary["nameEn"] as? String ?? ""
        let wing = dictionary["wing"] as? String ?? ""
        let nightlyRateMinor = (dictionary["nightlyRateMinor"] as? NSNumber)?.intValue
            ?? (dictionary["nightlyRateMinor"] as? Int)
            ?? 0
        let rateDeltaMinor = (dictionary["rateDeltaMinor"] as? NSNumber)?.intValue
            ?? (dictionary["rateDeltaMinor"] as? Int)
            ?? 0
        let rawUnits = dictionary["assignableUnits"] as? [[String: Any]] ?? []
        let assignableUnits = rawUnits.compactMap(AdminHotelAvailabilityUnit.fromDictionary)

        return AdminHotelCompatibleAlternativeType(
            accommodationTypeId: typeId,
            nameAr: nameAr,
            nameEn: nameEn,
            wing: wing,
            nightlyRateMinor: nightlyRateMinor,
            rateDeltaMinor: rateDeltaMinor,
            assignableUnits: assignableUnits
        )
    }
}

public struct AdminHotelAvailabilitySnapshot: Hashable, Sendable {
    public let units: [AdminHotelAvailabilityUnit]
    public let exactTypeAssignable: [AdminHotelAvailabilityUnit]
    public let exactTypeRejected: [AdminHotelAvailabilityUnit]
    public let compatibleAlternativeTypes: [AdminHotelCompatibleAlternativeType]

    public init(
        units: [AdminHotelAvailabilityUnit],
        exactTypeAssignable: [AdminHotelAvailabilityUnit] = [],
        exactTypeRejected: [AdminHotelAvailabilityUnit] = [],
        compatibleAlternativeTypes: [AdminHotelCompatibleAlternativeType] = []
    ) {
        self.units = units
        self.exactTypeAssignable = exactTypeAssignable.isEmpty ? units.filter(\.isAssignable) : exactTypeAssignable
        self.exactTypeRejected = exactTypeRejected.isEmpty ? units.filter { !$0.isAssignable } : exactTypeRejected
        self.compatibleAlternativeTypes = compatibleAlternativeTypes
    }

    public var assignableUnits: [AdminHotelAvailabilityUnit] {
        exactTypeAssignable.isEmpty ? units.filter(\.isAssignable) : exactTypeAssignable
    }

    public var rejectedUnits: [AdminHotelAvailabilityUnit] {
        exactTypeRejected.isEmpty ? units.filter { !$0.isAssignable } : exactTypeRejected
    }

    public var assignableIds: Set<String> {
        Set(assignableUnits.map(\.accommodationId))
    }

    public static func fromDictionary(_ dictionary: [String: Any]) -> AdminHotelAvailabilitySnapshot? {
        guard let rawUnits = dictionary["units"] as? [[String: Any]] else { return nil }
        let units = rawUnits.compactMap(AdminHotelAvailabilityUnit.fromDictionary)
        guard units.count == rawUnits.count else { return nil }

        let rawExactAssignable = dictionary["exactTypeAssignable"] as? [[String: Any]] ?? []
        let exactAssignable = rawExactAssignable.compactMap(AdminHotelAvailabilityUnit.fromDictionary)

        let rawExactRejected = dictionary["exactTypeRejected"] as? [[String: Any]] ?? []
        let exactRejected = rawExactRejected.compactMap(AdminHotelAvailabilityUnit.fromDictionary)

        let rawAlternatives = dictionary["compatibleAlternativeTypes"] as? [[String: Any]] ?? []
        let alternatives = rawAlternatives.compactMap(AdminHotelCompatibleAlternativeType.fromDictionary)

        return AdminHotelAvailabilitySnapshot(
            units: units,
            exactTypeAssignable: exactAssignable.isEmpty ? units.filter(\.isAssignable) : exactAssignable,
            exactTypeRejected: exactRejected.isEmpty ? units.filter { !$0.isAssignable } : exactRejected,
            compatibleAlternativeTypes: alternatives
        )
    }
}

public enum AdminHotelCustomerIdentityPolicy {
    /// Hotel reservations must always point at a real, server-backed customer.
    /// Local guest placeholders are presentation state only and can never become
    /// reservation ownership identifiers.
    public static func resolvedCustomerUid(providedUid: String?, lookedUpUid: String?) -> String? {
        if let provided = usableUid(providedUid) { return provided }
        return usableUid(lookedUpUid)
    }

    private static func usableUid(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("guest-") else { return nil }
        return trimmed
    }
}

public struct AdminHotelCheckInReadiness: Hashable, Sendable {
    public let isComplete: Bool
    public let completedCount: Int
    public let totalCount: Int
    public let missingRequirementCodes: [String]
}

public enum AdminHotelCheckInReadinessPolicy {
    public static func evaluate(
        hasAuthoritativeStay: Bool,
        petIdentityVerified: Bool,
        vaccinationVerified: Bool,
        healthInspectionCompleted: Bool,
        dietConfirmed: Bool,
        emergencyContactConfirmed: Bool,
        agreementAcknowledged: Bool,
        medicationRequired: Bool,
        medicationConfirmed: Bool,
        depositRequired: Bool,
        depositSettled: Bool
    ) -> AdminHotelCheckInReadiness {
        var requirements: [(String, Bool)] = [
            ("pet_owner_identity", petIdentityVerified),
            ("vaccination_certificate", vaccinationVerified),
            ("clinical_inspection", healthInspectionCompleted),
            ("diet_allergy_confirmation", dietConfirmed),
            ("emergency_contact", emergencyContactConfirmed),
            ("boarding_agreement", agreementAcknowledged)
        ]
        if medicationRequired {
            requirements.append(("medication_confirmation", medicationConfirmed))
        }
        if depositRequired {
            requirements.append(("deposit_settlement", depositSettled))
        }

        var missing = requirements.compactMap { $0.1 ? nil : $0.0 }
        if !hasAuthoritativeStay {
            missing.insert("authoritative_stay", at: 0)
        }
        let completed = requirements.reduce(into: 0) { count, requirement in
            if requirement.1 { count += 1 }
        }
        return AdminHotelCheckInReadiness(
            isComplete: hasAuthoritativeStay && missing.isEmpty,
            completedCount: completed,
            totalCount: requirements.count,
            missingRequirementCodes: missing
        )
    }
}

public enum AdminHotelRatePolicy {
    /// A physical suite may override its category rate. Otherwise the category
    /// is the canonical pricing projection for reception and room management.
    public static func resolvedNightlyRate(unitRateMinor: Int?, typeRateMinor: Int?) -> Int? {
        if let unitRateMinor, unitRateMinor >= 0 { return unitRateMinor }
        if let typeRateMinor, typeRateMinor >= 0 { return typeRateMinor }
        return nil
    }
}

public struct AdminHotelBillingProjection: Hashable, Sendable {
    public let totalMinor: Int?
    public let settledMinor: Int?
    public let depositMinor: Int?
}

public enum AdminHotelBillingProjectionPolicy {
    public static func resolve(_ source: [String: Any]) -> AdminHotelBillingProjection {
        let pricing = source["pricing"] as? [String: Any] ?? [:]
        let billing = source["billingSummary"] as? [String: Any] ?? [:]

        let billingGrandTotal = integer(billing["grandTotalMinor"])
        let pricingQuotedTotal = integer(pricing["quotedTotalMinor"])
        let rawTotal = integer(source["totalAmountMinor"])

        let resolvedTotal: Int?
        if let billingGrandTotal, billingGrandTotal > 0 {
            resolvedTotal = billingGrandTotal
        } else if let pricingQuotedTotal, pricingQuotedTotal > 0 {
            resolvedTotal = pricingQuotedTotal
        } else if let rawTotal, rawTotal > 0 {
            resolvedTotal = rawTotal
        } else {
            resolvedTotal = billingGrandTotal ?? pricingQuotedTotal ?? rawTotal
        }

        let billingDeposit = integer(billing["depositMinor"]) ?? integer(billing["deposit"])
        let pricingDeposit = integer(pricing["depositMinor"]) ?? integer(pricing["deposit"])
        let rawDeposit = integer(source["depositMinor"]) ?? integer(source["deposit"])

        let resolvedDeposit: Int?
        if let billingDeposit, billingDeposit > 0 {
            resolvedDeposit = billingDeposit
        } else if let pricingDeposit, pricingDeposit > 0 {
            resolvedDeposit = pricingDeposit
        } else if let rawDeposit, rawDeposit > 0 {
            resolvedDeposit = rawDeposit
        } else {
            resolvedDeposit = billingDeposit ?? pricingDeposit ?? rawDeposit
        }

        let billingSettled = integer(billing["settledMinor"]) ?? integer(billing["settled"])
        let rawSettled = integer(source["paidAmountMinor"]) ?? integer(source["paidMinor"])

        let resolvedSettled: Int?
        if let billingSettled, billingSettled > 0 {
            resolvedSettled = billingSettled
        } else if let rawSettled, rawSettled > 0 {
            resolvedSettled = rawSettled
        } else {
            resolvedSettled = billingSettled ?? rawSettled
        }

        var finalSettled = resolvedSettled
        if let dep = resolvedDeposit, dep > 0 {
            if finalSettled == nil || finalSettled == 0 {
                finalSettled = dep
            } else if let current = finalSettled, current < dep {
                finalSettled = dep
            }
        }

        return AdminHotelBillingProjection(
            totalMinor: resolvedTotal,
            settledMinor: finalSettled,
            depositMinor: resolvedDeposit
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(exactly: value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        if let string = value as? String, let parsed = Int(string) { return parsed }
        return nil
    }
}

public struct AdminHotelPermissionCapabilities: Hashable, Sendable {
    public let canViewHotel: Bool
    public let canManageReservations: Bool
    public let canCheckIn: Bool
    public let canCheckOut: Bool
    public let canManageAccommodations: Bool
    public let canViewCare: Bool
    public let canExecuteCareTasks: Bool
    public let canViewBilling: Bool
    public let canManageBilling: Bool
}

public enum AdminHotelPermissionPolicy {
    public static func resolve(_ permissions: Set<String>) -> AdminHotelPermissionCapabilities {
        AdminHotelPermissionCapabilities(
            canViewHotel: permissions.contains("hotel.view"),
            canManageReservations: permissions.contains("hotel.reservations.manage"),
            canCheckIn: permissions.contains("hotel.checkin"),
            canCheckOut: permissions.contains("hotel.checkout"),
            canManageAccommodations: permissions.contains("hotel.accommodations.manage"),
            canViewCare: permissions.contains("hotel.care.view"),
            canExecuteCareTasks: permissions.contains("hotel.task.execute"),
            canViewBilling: !permissions.isDisjoint(with: ["hotel.billing.view", "hotel.billing.manage", "hotel.billing.adjust"]),
            canManageBilling: permissions.contains("hotel.billing.manage")
        )
    }
}

public enum AdminHotelReservationActionPolicy {
    private static let reservationManageActions: Set<String> = [
        "create_customer_pet", "create_reservation", "update_reservation",
        "submit_reservation", "confirm_reservation", "reject_reservation",
        "cancel_reservation", "mark_pre_arrival", "mark_ready_for_checkin",
        "mark_no_show", "extend_reservation"
    ]

    public static func requiredPermission(for action: String) -> String? {
        let normalized = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if reservationManageActions.contains(normalized) { return "hotel.reservations.manage" }
        if normalized == "complete_reservation" { return "hotel.billing.manage" }
        return nil
    }
}

public struct AdminHotelReservationPetIdentity: Hashable, Sendable {
    public let petId: String
    public let species: String
}

public enum AdminHotelReservationUpdatePolicy {
    public static func identity(petId: String, species: String) -> AdminHotelReservationPetIdentity? {
        let normalizedPetId = petId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSpecies = species.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPetId.isEmpty, !normalizedSpecies.isEmpty else { return nil }
        return AdminHotelReservationPetIdentity(petId: normalizedPetId, species: normalizedSpecies)
    }
}

// MARK: - Branch Readiness Diagnostics
public struct AdminHotelDiagnostics: Hashable, Sendable {
    public let branchId: String
    public let hasBranchSettings: Bool
    public let hasAccommodationTypes: Bool
    public let hasPhysicalUnits: Bool
    public let totalTypesCount: Int
    public let activeTypesCount: Int
    public let totalUnitsCount: Int
    public let activeUnitsCount: Int
    public let typesWithoutUnits: [String]
    public let unitsWithoutValidTypes: [String]
    public let totalCapacity: Int
    public let isReadyForOperations: Bool
    public let blockers: [String]
    public let warnings: [String]

    /// The setup assistant is onboarding-only. Once the branch has at least one
    /// accommodation type and one physical unit, readiness blockers belong to
    /// operational diagnostics instead of keeping setup permanently visible.
    public var needsSetup: Bool { !hasAccommodationTypes || !hasPhysicalUnits }
    public var isReady: Bool { isReadyForOperations }

    public static func fromDictionary(_ dict: [String: Any]) -> AdminHotelDiagnostics? {
        guard let branchId = dict["branchId"] as? String else { return nil }
        return AdminHotelDiagnostics(
            branchId: branchId,
            hasBranchSettings: dict["hasBranchSettings"] as? Bool ?? false,
            hasAccommodationTypes: dict["hasAccommodationTypes"] as? Bool ?? false,
            hasPhysicalUnits: dict["hasPhysicalUnits"] as? Bool ?? false,
            totalTypesCount: (dict["totalTypesCount"] as? NSNumber)?.intValue ?? (dict["totalTypesCount"] as? Int) ?? 0,
            activeTypesCount: (dict["activeTypesCount"] as? NSNumber)?.intValue ?? (dict["activeTypesCount"] as? Int) ?? 0,
            totalUnitsCount: (dict["totalUnitsCount"] as? NSNumber)?.intValue ?? (dict["totalUnitsCount"] as? Int) ?? 0,
            activeUnitsCount: (dict["activeUnitsCount"] as? NSNumber)?.intValue ?? (dict["activeUnitsCount"] as? Int) ?? 0,
            typesWithoutUnits: dict["typesWithoutUnits"] as? [String] ?? [],
            unitsWithoutValidTypes: dict["unitsWithoutValidTypes"] as? [String] ?? [],
            totalCapacity: (dict["totalCapacity"] as? NSNumber)?.intValue ?? (dict["totalCapacity"] as? Int) ?? 0,
            isReadyForOperations: dict["isReadyForOperations"] as? Bool ?? false,
            blockers: dict["blockers"] as? [String] ?? [],
            warnings: dict["warnings"] as? [String] ?? []
        )
    }
}

// MARK: - Reprice Policy
public enum AdminHotelRepricePolicy {
    public static func requiresConfirmation(rateDeltaMinor: Int) -> Bool {
        rateDeltaMinor != 0
    }

    public static func formattedDelta(rateDeltaMinor: Int, currency: String = "QAR") -> String {
        let major = Double(abs(rateDeltaMinor)) / 100.0
        if rateDeltaMinor > 0 {
            return String(format: "+%.2f %@", major, currency)
        } else if rateDeltaMinor < 0 {
            return String(format: "-%.2f %@", major, currency)
        } else {
            return String(format: "0 %@", currency)
        }
    }
}

// MARK: - Dominant Rejection Reason Policy
public enum AdminHotelDominantReasonPolicy {
    public static func dominantReason(from rejections: [String]) -> String? {
        if rejections.contains("main_kind_not_allowed") || rejections.contains("species_not_allowed") {
            return "main_kind_not_allowed"
        }
        if rejections.contains("unit_out_of_service") {
            return "unit_out_of_service"
        }
        if rejections.contains("capacity_exceeded") || rejections.contains("dates_conflict") {
            return "capacity_exceeded"
        }
        if rejections.contains("shared_occupancy_forbidden") {
            return "shared_occupancy_forbidden"
        }
        return rejections.first
    }

    public static func localizedReason(for code: String) -> String {
        switch code {
        case "main_kind_not_allowed", "species_not_allowed":
            return Language.get("Hotel_Policy_Reason_SpeciesNotAllowed", alter: "نوع أو فصيلة الحيوان غير مسموح بها في الأجنحة المتاحة.")
        case "capacity_exceeded", "dates_conflict":
            return Language.get("Hotel_Policy_Reason_CapacityOrDates", alter: "جميع الأجنحة المتوافقة محجوزة أو مشغولة خلال التواريخ المحددة.")
        case "unit_out_of_service":
            return Language.get("Hotel_Policy_Reason_OutOfService", alter: "الأجنحة قيد التنظيف أو الصيانة الدورية حالياً.")
        case "shared_occupancy_forbidden":
            return Language.get("Hotel_Policy_Reason_SharedForbidden", alter: "الجناح مشغول ولا يسمح بالإشغال المشترك لنزلاء مختلفين.")
        default:
            return Language.get("Hotel_Policy_Reason_Default", alter: "لا توجد أجنحة مطابقة متاحة للشروط المدخلة.")
        }
    }
}
