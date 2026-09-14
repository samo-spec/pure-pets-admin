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
    public let rejections: [String]
    public let remainingCapacity: Int
    public let occupiedInWindow: Int
    public let maxCapacity: Int
    public let holdingStayIds: [String]

    public var id: String { accommodationId }

    public static func fromDictionary(_ dictionary: [String: Any]) -> AdminHotelAvailabilityUnit? {
        guard let rawId = dictionary["accommodationId"] as? String else { return nil }
        let accommodationId = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accommodationId.isEmpty else { return nil }

        return AdminHotelAvailabilityUnit(
            accommodationId: accommodationId,
            accommodationTypeId: string(dictionary["accommodationTypeId"]),
            code: string(dictionary["code"]),
            name: string(dictionary["name"]),
            wing: string(dictionary["wing"]),
            status: string(dictionary["status"]),
            isAssignable: dictionary["assignable"] as? Bool ?? false,
            rejections: dictionary["rejections"] as? [String] ?? [],
            remainingCapacity: integer(dictionary["remainingInWindow"]),
            occupiedInWindow: integer(dictionary["occupiedInWindow"]),
            maxCapacity: max(1, integer(dictionary["maxCapacity"], fallback: 1)),
            holdingStayIds: dictionary["holdingStayIds"] as? [String] ?? []
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
}

public struct AdminHotelAvailabilitySnapshot: Hashable, Sendable {
    public let units: [AdminHotelAvailabilityUnit]

    public var assignableUnits: [AdminHotelAvailabilityUnit] {
        units.filter(\.isAssignable)
    }

    public var rejectedUnits: [AdminHotelAvailabilityUnit] {
        units.filter { !$0.isAssignable }
    }

    public var assignableIds: Set<String> {
        Set(assignableUnits.map(\.accommodationId))
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
