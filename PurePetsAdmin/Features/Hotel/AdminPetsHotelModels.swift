//
//  AdminPetsHotelModels.swift
//  PurePetsAdmin
//
//  Category-defining domain models and state representations for
//  Pets Hotel (فندق ورعاية الحيوانات الأليفة) in Pure Pets Admin.
//  Mirrors Pure Pets Infra functions/hotel/constants.js and Console domain.
//

import SwiftUI
import Foundation
import FirebaseFirestore

// MARK: - Collections Constant
public enum HotelFirestoreCollections {
    public static let accommodationTypes = "HotelAccommodationTypes"
    public static let accommodations = "HotelAccommodations"
    public static let reservations = "HotelReservations"
    public static let stays = "HotelStays"
    public static let branchSettings = "HotelBranchSettings"
}

// MARK: - Wing / Animal Section
public enum HotelWing: String, CaseIterable, Identifiable, Codable {
    case dogs = "dogs"
    case cats = "cats"
    case birds = "birds"
    case smallPets = "small_pets"
    case isolation = "isolation"
    case medicalObservation = "medical_observation"
    case daycare = "daycare"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dogs: return Language.get("Hotel_Wing_Dogs", alter: "جناح الكلاب")
        case .cats: return Language.get("Hotel_Wing_Cats", alter: "جناح القطط")
        case .birds: return Language.get("Hotel_Wing_Birds", alter: "جناح الطيور")
        case .smallPets: return Language.get("Hotel_Wing_SmallPets", alter: "جناح الحيوانات الصغيرة")
        case .isolation: return Language.get("Hotel_Wing_Isolation", alter: "قسم العزل")
        case .medicalObservation: return Language.get("Hotel_Wing_MedicalObservation", alter: "الملاحظة الطبية")
        case .daycare: return Language.get("Hotel_Wing_Daycare", alter: "قسم الرعاية النهارية")
        }
    }

    public var localizedTitle: String { title }

    public var icon: String {
        switch self {
        case .dogs: return "dog.fill"
        case .cats: return "cat.fill"
        case .birds: return "bird.fill"
        case .smallPets: return "hare.fill"
        case .isolation: return "cross.case.fill"
        case .medicalObservation: return "waveform.path.ecg.rectangle.fill"
        case .daycare: return "sun.max.fill"
        }
    }

    public var tint: Color {
        switch self {
        case .dogs: return Color(red: 0.85, green: 0.40, blue: 0.15)
        case .cats: return Color(red: 0.65, green: 0.25, blue: 0.85)
        case .birds: return Color(red: 0.15, green: 0.65, blue: 0.85)
        case .smallPets: return Color(red: 0.20, green: 0.75, blue: 0.45)
        case .isolation: return Color(red: 0.90, green: 0.25, blue: 0.25)
        case .medicalObservation: return Color(red: 0.78, green: 0.20, blue: 0.38)
        case .daycare: return Color(red: 0.95, green: 0.70, blue: 0.10)
        }
    }

    public static func wing(forSpecies species: String) -> HotelWing? {
        if let direct = HotelWing(rawValue: species) {
            return direct
        }
        switch species.lowercased() {
        case "dog", "dogs": return .dogs
        case "cat", "cats": return .cats
        case "bird", "birds": return .birds
        case "small_pet", "small_pets": return .smallPets
        case "isolation": return .isolation
        case "medical_observation": return .medicalObservation
        case "daycare": return .daycare
        default: return nil
        }
    }
}

// MARK: - Accommodation / Room Status
public enum HotelAccommodationStatus: String, CaseIterable, Identifiable, Codable {
    case available = "available"
    case reserved = "reserved"
    case occupied = "occupied"
    case cleaning = "cleaning"
    case inspection = "inspection"
    case maintenance = "maintenance"
    case blocked = "blocked"
    case isolation = "isolation"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .available: return Language.get("Hotel_Room_Available", alter: "شاغر")
        case .reserved: return Language.get("Hotel_Room_Reserved", alter: "محجوز")
        case .occupied: return Language.get("Hotel_Room_Occupied", alter: "مشغول")
        case .cleaning: return Language.get("Hotel_Room_Cleaning", alter: "تنظيف")
        case .inspection: return Language.get("Hotel_Room_Inspection", alter: "تم الفحص")
        case .maintenance: return Language.get("Hotel_Room_Maintenance", alter: "صيانة")
        case .blocked: return Language.get("Hotel_Room_Blocked", alter: "خارج الخدمة")
        case .isolation: return Language.get("Hotel_Room_Isolation", alter: "عزل صحي")
        }
    }

    public var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .reserved: return "calendar.badge.clock"
        case .occupied: return "door.left.hand.closed"
        case .cleaning: return "sparkles"
        case .inspection: return "eye.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .blocked: return "nosign"
        case .isolation: return "cross.case.fill"
        }
    }

    public var color: Color {
        switch self {
        case .available: return Color(red: 0.16, green: 0.72, blue: 0.44)
        case .reserved: return Color(red: 0.10, green: 0.55, blue: 0.85)
        case .occupied: return Color(red: 0.82, green: 0.15, blue: 0.35)
        case .cleaning: return Color(red: 0.95, green: 0.65, blue: 0.15)
        case .inspection: return Color(red: 0.55, green: 0.30, blue: 0.85)
        case .maintenance: return Color(red: 0.90, green: 0.45, blue: 0.15)
        case .blocked: return Color(red: 0.50, green: 0.50, blue: 0.55)
        case .isolation: return Color(red: 0.78, green: 0.20, blue: 0.38)
        }
    }
}

// MARK: - Reservation / Stay Status
public enum HotelReservationStatus: String, CaseIterable, Identifiable, Codable {
    case draft = "draft"
    case pendingConfirmation = "pending_confirmation"
    case confirmed = "confirmed"
    case preArrival = "pre_arrival"
    case readyForCheckin = "ready_for_checkin"
    case checkedIn = "checked_in"
    case inStay = "in_stay"
    case readyForCheckout = "ready_for_checkout"
    case checkedOut = "checked_out"
    case completed = "completed"
    case cancelled = "cancelled"
    case noShow = "no_show"
    case rejected = "rejected"
    case earlyCheckout = "early_checkout"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .draft: return Language.get("Hotel_Res_Draft", alter: "مسودة")
        case .pendingConfirmation: return Language.get("Hotel_Res_Pending", alter: "معلق")
        case .confirmed: return Language.get("Hotel_Res_Confirmed", alter: "مؤكد")
        case .preArrival: return Language.get("Hotel_Res_PreArrival", alter: "قبل الوصول")
        case .readyForCheckin: return Language.get("Hotel_Res_ReadyCheckin", alter: "جاهز لتسجيل الوصول")
        case .checkedIn, .inStay: return Language.get("Hotel_Res_InStay", alter: "مقيم")
        case .readyForCheckout: return Language.get("Hotel_Res_ReadyCheckout", alter: "جاهز للمغادرة")
        case .checkedOut, .completed: return Language.get("Hotel_Res_Completed", alter: "مكتمل")
        case .cancelled: return Language.get("Hotel_Res_Cancelled", alter: "ملغي")
        case .noShow: return Language.get("Hotel_Res_NoShow", alter: "عدم حضور")
        case .rejected: return Language.get("Hotel_Res_Rejected", alter: "مرفوض")
        case .earlyCheckout: return Language.get("Hotel_Res_EarlyCheckout", alter: "مغادرة مبكرة")
        }
    }

    public var localizedTitle: String { title }

    public var color: Color {
        switch self {
        case .confirmed, .readyForCheckin: return Color(red: 0.10, green: 0.55, blue: 0.85)
        case .checkedIn, .inStay: return Color(red: 0.16, green: 0.72, blue: 0.44)
        case .readyForCheckout: return Color(red: 0.95, green: 0.65, blue: 0.15)
        case .completed, .checkedOut, .earlyCheckout: return Color(red: 0.40, green: 0.45, blue: 0.55)
        case .cancelled, .rejected, .noShow: return Color(red: 0.85, green: 0.25, blue: 0.25)
        case .draft, .pendingConfirmation, .preArrival: return Color(red: 0.95, green: 0.55, blue: 0.15)
        }
    }

    public var badgeColor: Color { color }
}

// MARK: - Guest Clinical & Behavioral Status
public enum HotelGuestStatus: String, CaseIterable, Identifiable, Codable {
    case normal = "normal"
    case specialCare = "special_care"
    case monitor = "monitor"
    case attention = "attention"
    case critical = "critical"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .normal: return Language.get("Hotel_Guest_Normal", alter: "طبيعي / مستقر")
        case .specialCare: return Language.get("Hotel_Guest_SpecialCare", alter: "رعاية خاصة")
        case .monitor: return Language.get("Hotel_Guest_Monitor", alter: "تحت الملاحظة")
        case .attention: return Language.get("Hotel_Guest_Attention", alter: "تنبيه رعاية")
        case .critical: return Language.get("Hotel_Guest_Critical", alter: "حرج / رعاية بيطرية")
        }
    }

    public var icon: String {
        switch self {
        case .normal: return "heart.fill"
        case .specialCare: return "sparkles"
        case .monitor: return "eye.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .critical: return "cross.circle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .normal: return Color(red: 0.16, green: 0.72, blue: 0.44)
        case .specialCare: return Color(red: 0.10, green: 0.55, blue: 0.85)
        case .monitor: return Color(red: 0.95, green: 0.65, blue: 0.15)
        case .attention: return Color(red: 0.90, green: 0.45, blue: 0.15)
        case .critical: return Color(red: 0.90, green: 0.20, blue: 0.20)
        }
    }
}

// MARK: - Daily Care Task Type
public enum HotelCareTaskType: String, CaseIterable, Identifiable, Codable {
    case feeding = "feeding"
    case water = "water"
    case walk = "walk"
    case play = "play"
    case medication = "medication"
    case cleaning = "cleaning"
    case roomInspection = "room_inspection"
    case grooming = "grooming"
    case healthCheck = "health_check"
    case photoUpdate = "photo_update"
    case checkInPreparation = "checkin_preparation"
    case checkOutPreparation = "checkout_preparation"
    case transport = "transport"
    case custom = "custom"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .feeding: return Language.get("Hotel_Task_Feeding", alter: "تقديم الوجبة")
        case .water: return Language.get("Hotel_Task_Water", alter: "تجديد المياه")
        case .walk: return Language.get("Hotel_Task_Walk", alter: "تمشية")
        case .play: return Language.get("Hotel_Task_Play", alter: "وقت اللعب")
        case .medication: return Language.get("Hotel_Task_Medication", alter: "إعطاء الدواء")
        case .cleaning: return Language.get("Hotel_Task_Cleaning", alter: "تنظيف الجناح")
        case .roomInspection: return Language.get("Hotel_Task_RoomInspection", alter: "فحص الجناح")
        case .grooming: return Language.get("Hotel_Task_Grooming", alter: "تمشيط وعناية")
        case .healthCheck: return Language.get("Hotel_Task_HealthCheck", alter: "فحص المؤشرات الحيوية")
        case .photoUpdate: return Language.get("Hotel_Task_PhotoUpdate", alter: "إرسال صورة للعميل")
        case .checkInPreparation: return Language.get("Hotel_Task_CheckInPreparation", alter: "تجهيز الوصول")
        case .checkOutPreparation: return Language.get("Hotel_Task_CheckOutPreparation", alter: "تجهيز المغادرة")
        case .transport: return Language.get("Hotel_Task_Transport", alter: "نقل النزيل")
        case .custom: return Language.get("Hotel_Task_Custom", alter: "مهمة مخصصة")
        }
    }

    public var icon: String {
        switch self {
        case .feeding: return "fork.knife"
        case .water: return "drop.fill"
        case .walk: return "figure.walk"
        case .play: return "pawprint.fill"
        case .medication: return "pill.fill"
        case .cleaning: return "sparkles"
        case .roomInspection: return "door.left.hand.open"
        case .grooming: return "scissors"
        case .healthCheck: return "stethoscope"
        case .photoUpdate: return "camera.fill"
        case .checkInPreparation: return "door.left.hand.open"
        case .checkOutPreparation: return "door.right.hand.open"
        case .transport: return "car.fill"
        case .custom: return "checklist"
        }
    }
}

// MARK: - Verification Checklists
public struct AdminHotelCheckInVerification: Sendable {
    public var petIdentityVerified: Bool = false
    public var vaccinationVerified: Bool = false
    public var healthInspectionCompleted: Bool = false
    public var healthInspectionNotes: String = ""
    public var behaviourNotes: String = ""
    public var dietConfirmed: Bool = false
    public var medicationConfirmed: Bool = false
    public var emergencyContactConfirmed: Bool = false
    public var agreementAcknowledged: Bool = false
    public var agreementVersion: String = ""
    public var depositSettled: Bool = false

    public init() {}

    public func toDictionary() -> [String: Any] {
        return [
            "petIdentityVerified": petIdentityVerified,
            "vaccinationVerified": vaccinationVerified,
            "healthInspectionCompleted": healthInspectionCompleted,
            "healthInspectionNotes": healthInspectionNotes,
            "behaviourNotes": behaviourNotes,
            "dietConfirmed": dietConfirmed,
            "medicationConfirmed": medicationConfirmed,
            "emergencyContactConfirmed": emergencyContactConfirmed,
            "agreementAcknowledged": agreementAcknowledged,
            "agreementVersion": agreementVersion,
            "depositSettled": depositSettled
        ]
    }
}

public struct AdminHotelCheckOutVerification: Sendable {
    public var healthCheckCompleted: Bool = false
    public var healthCheckNotes: String = ""
    public var roomInspectionCompleted: Bool = false
    public var roomInspectionNotes: String = ""
    public var belongingsReturned: Bool = false
    public var incidentsAcknowledged: Bool = false
    public var medicationResolved: Bool = false
    public var handoverVerified: Bool = false

    public init() {}

    public func toDictionary() -> [String: Any] {
        return [
            "healthCheckCompleted": healthCheckCompleted,
            "healthCheckNotes": healthCheckNotes,
            "roomInspectionCompleted": roomInspectionCompleted,
            "roomInspectionNotes": roomInspectionNotes,
            "belongingsReturned": belongingsReturned,
            "incidentsAcknowledged": incidentsAcknowledged,
            "medicationResolved": medicationResolved,
            "handoverVerified": handoverVerified
        ]
    }
}

// MARK: - Parsing Helpers
private func parseHotelDate(_ value: Any?) -> Date? {
    if let d = value as? Date { return d }
    if let ts = value as? Timestamp { return ts.dateValue() }
    if let str = value as? String {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: str) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let d = f.date(from: str) { return d }
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f.date(from: str)
    }
    return nil
}

private func resolvedHotelWing(rawValue: String?, species: String?) -> HotelWing {
    if let rawValue, let wing = HotelWing(rawValue: rawValue) {
        return wing
    }

    let normalizedSpecies = (species ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalizedSpecies.contains("cat") || normalizedSpecies.contains("قط") { return .cats }
    if normalizedSpecies.contains("bird") || normalizedSpecies.contains("طير") || normalizedSpecies.contains("طائر") { return .birds }
    if normalizedSpecies.contains("dog") || normalizedSpecies.contains("كلب") { return .dogs }
    return .smallPets
}

// MARK: - Data Records

public struct AdminHotelAccommodationType: Identifiable, Hashable {
    public let id: String
    public var code: String
    public var nameAr: String
    public var nameEn: String
    public var wing: HotelWing
    public var allowedSpecies: [String]
    public var allowedMainKindIds: [Int]
    public var defaultCapacity: Int
    public var nightlyRateMinor: Int
    public var allowSharedOccupancy: Bool
    public var sortOrder: Int
    public var active: Bool
    public var description: String?
    public var currency: String

    public init(
        id: String,
        code: String,
        nameAr: String,
        nameEn: String,
        wing: HotelWing,
        allowedSpecies: [String] = [],
        allowedMainKindIds: [Int] = [],
        defaultCapacity: Int = 1,
        nightlyRateMinor: Int = 0,
        allowSharedOccupancy: Bool = false,
        sortOrder: Int = 0,
        active: Bool = true,
        description: String? = nil,
        currency: String = "QAR"
    ) {
        self.id = id
        self.code = code
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.wing = wing
        self.allowedSpecies = allowedSpecies
        self.allowedMainKindIds = allowedMainKindIds
        self.defaultCapacity = defaultCapacity
        self.nightlyRateMinor = nightlyRateMinor
        self.allowSharedOccupancy = allowSharedOccupancy
        self.sortOrder = sortOrder
        self.active = active
        self.description = description
        self.currency = currency
    }

    public var displayName: String {
        Language.isRTL() ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn)
    }

    public var formattedRate: String {
        let major = Double(nightlyRateMinor) / 100.0
        return String(format: "%.2f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public static func fromDictionary(_ dict: [String: Any], id: String) -> AdminHotelAccommodationType {
        let names = dict["name"] as? [String: String] ?? [:]
        let nameAr = dict["nameAr"] as? String ?? names["ar"] ?? ""
        let nameEn = dict["nameEn"] as? String ?? names["en"] ?? ""
        let wingRaw = dict["wing"] as? String ?? "dogs"

        let allowedMainKinds: [Int]
        if let direct = dict["allowedMainKindIds"] as? [Int] {
            allowedMainKinds = direct
        } else if let nsNumbers = dict["allowedMainKindIds"] as? [NSNumber] {
            allowedMainKinds = nsNumbers.map(\.intValue)
        } else {
            allowedMainKinds = []
        }

        return AdminHotelAccommodationType(
            id: id,
            code: dict["code"] as? String ?? "",
            nameAr: nameAr,
            nameEn: nameEn,
            wing: HotelWing(rawValue: wingRaw) ?? .dogs,
            allowedSpecies: dict["allowedSpecies"] as? [String] ?? [],
            allowedMainKindIds: allowedMainKinds,
            nightlyRateMinor: (dict["nightlyRateMinor"] as? NSNumber)?.intValue
                ?? (dict["nightlyRateMinor"] as? Int)
                ?? (dict["nightlyRate"] as? NSNumber)?.intValue
                ?? 0,
            sortOrder: dict["sortOrder"] as? Int ?? 0,
            active: dict["active"] as? Bool ?? true,
            description: dict["description"] as? String,
            currency: dict["currency"] as? String ?? "QAR"
        )
    }
}

public struct AdminHotelPetDraft: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var categoryName: String
    public var breed: String
    public var weightKg: Double
    public var accommodationTypeId: String
    public var specialDiet: String
    public var allergies: String
    public var requiresMedication: Bool
    public var medicationsText: String
    public var accommodationId: String?
    public var mainKindId: Int?
    public var mainKindDocumentId: String?
    public var mainKindNameAr: String?
    public var mainKindNameEn: String?
    public var subKindId: Int?
    public var subKindDocumentId: String?
    public var subKindNameAr: String?
    public var subKindNameEn: String?

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        categoryName: String = "dog",
        breed: String = "",
        weightKg: Double = 5.0,
        accommodationTypeId: String = "",
        accommodationId: String? = nil,
        specialDiet: String = "",
        allergies: String = "",
        requiresMedication: Bool = false,
        medicationsText: String = "",
        mainKindId: Int? = nil,
        mainKindDocumentId: String? = nil,
        mainKindNameAr: String? = nil,
        mainKindNameEn: String? = nil,
        subKindId: Int? = nil,
        subKindDocumentId: String? = nil,
        subKindNameAr: String? = nil,
        subKindNameEn: String? = nil
    ) {
        self.id = id
        self.name = name
        self.categoryName = categoryName
        self.breed = breed
        self.weightKg = weightKg
        self.accommodationTypeId = accommodationTypeId
        self.accommodationId = accommodationId
        self.specialDiet = specialDiet
        self.allergies = allergies
        self.requiresMedication = requiresMedication
        self.medicationsText = medicationsText
        self.mainKindId = mainKindId
        self.mainKindDocumentId = mainKindDocumentId
        self.mainKindNameAr = mainKindNameAr
        self.mainKindNameEn = mainKindNameEn
        self.subKindId = subKindId
        self.subKindDocumentId = subKindDocumentId
        self.subKindNameAr = subKindNameAr
        self.subKindNameEn = subKindNameEn
    }
}

public struct AdminHotelCustomerOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let uid: String
    public let name: String
    public let phone: String
    public let email: String
    public let photoURL: String

    public init(uid: String, name: String, phone: String, email: String = "", photoURL: String = "") {
        self.id = uid
        self.uid = uid
        self.name = name
        self.phone = phone
        self.email = email
        self.photoURL = photoURL
    }
}

public struct AdminHotelCustomerPetOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let petId: String
    public let name: String
    public let breed: String
    public let species: String
    public let ageInMonths: Int
    public let imageURL: String
    public let isDefaultPet: Bool
    public let mainKindId: Int?
    public let mainKindDocumentId: String?
    public let mainKindNameAr: String?
    public let mainKindNameEn: String?
    public let subKindId: Int?
    public let subKindDocumentId: String?
    public let subKindNameAr: String?
    public let subKindNameEn: String?

    public init(
        petId: String,
        name: String,
        breed: String = "",
        species: String = "dog",
        ageInMonths: Int = 0,
        imageURL: String = "",
        isDefaultPet: Bool = false,
        mainKindId: Int? = nil,
        mainKindDocumentId: String? = nil,
        mainKindNameAr: String? = nil,
        mainKindNameEn: String? = nil,
        subKindId: Int? = nil,
        subKindDocumentId: String? = nil,
        subKindNameAr: String? = nil,
        subKindNameEn: String? = nil
    ) {
        self.id = petId
        self.petId = petId
        self.name = name
        self.breed = breed
        self.species = species
        self.ageInMonths = ageInMonths
        self.imageURL = imageURL
        self.isDefaultPet = isDefaultPet
        self.mainKindId = mainKindId
        self.mainKindDocumentId = mainKindDocumentId
        self.mainKindNameAr = mainKindNameAr
        self.mainKindNameEn = mainKindNameEn
        self.subKindId = subKindId
        self.subKindDocumentId = subKindDocumentId
        self.subKindNameAr = subKindNameAr
        self.subKindNameEn = subKindNameEn
    }
}

public struct AdminHotelAccommodation: Identifiable, Hashable {
    public let id: String
    public var accommodationNumber: String
    public var name: String
    public var wing: HotelWing
    public var accommodationTypeId: String
    public var status: HotelAccommodationStatus
    public var capacity: Int
    public var currentOccupancy: Int
    public var currentStayId: String?
    public var currentGuestName: String?
    public var currentGuestSpecies: String?
    public var nightlyRateMinor: Int?
    public var branchId: String
    public var notes: String?
    public var lastCleanedAt: Date?
    public var active: Bool
    public var code: String
    public var allowedSpecies: [String]
    public var allowedMainKindIds: [Int]
    public var allowSharedOccupancy: Bool
    public var unitCode: String {
        accommodationNumber.isEmpty ? code : accommodationNumber
    }
    public var floor: String? {
        nil
    }

    public init(
        id: String,
        accommodationNumber: String,
        name: String,
        wing: HotelWing,
        accommodationTypeId: String = "",
        status: HotelAccommodationStatus = .available,
        capacity: Int = 1,
        currentOccupancy: Int = 0,
        currentStayId: String? = nil,
        currentGuestName: String? = nil,
        currentGuestSpecies: String? = nil,
        nightlyRateMinor: Int? = nil,
        branchId: String = "",
        notes: String? = nil,
        lastCleanedAt: Date? = nil,
        active: Bool = true,
        code: String = "",
        allowedSpecies: [String] = [],
        allowedMainKindIds: [Int] = [],
        allowSharedOccupancy: Bool = false
    ) {
        self.id = id
        self.accommodationNumber = accommodationNumber
        self.name = name
        self.wing = wing
        self.accommodationTypeId = accommodationTypeId
        self.status = status
        self.capacity = capacity
        self.currentOccupancy = currentOccupancy
        self.currentStayId = currentStayId
        self.currentGuestName = currentGuestName
        self.currentGuestSpecies = currentGuestSpecies
        self.nightlyRateMinor = nightlyRateMinor
        self.branchId = branchId
        self.notes = notes
        self.lastCleanedAt = lastCleanedAt
        self.active = active
        self.code = code.isEmpty ? accommodationNumber : code
        self.allowedSpecies = allowedSpecies
        self.allowedMainKindIds = allowedMainKindIds
        self.allowSharedOccupancy = allowSharedOccupancy
    }

    public var formattedRate: String {
        guard let nightlyRateMinor else {
            return Language.get("Hotel_RateUnavailable", alter: "السعر غير متاح")
        }
        let major = Double(nightlyRateMinor) / 100.0
        return String(format: "%.2f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }
}

public struct AdminHotelReservation: Identifiable, Hashable {
    public let id: String
    public var reservationNumber: String
    public var customerId: String
    public var customerName: String
    public var customerPhone: String
    public var customerEmail: String?
    public var petId: String
    public var petName: String
    public var petBreed: String
    public var petSpecies: String
    public var mainKindId: Int?
    public var mainKindDocumentId: String?
    public var mainKindNameAr: String?
    public var mainKindNameEn: String?
    public var subKindId: Int?
    public var subKindDocumentId: String?
    public var subKindNameAr: String?
    public var subKindNameEn: String?
    public var wing: HotelWing
    public var accommodationTypeId: String
    public var assignedAccommodationId: String?
    public var assignedRoomNumber: String?
    public var status: HotelReservationStatus
    public var checkInDate: Date
    public var checkOutDate: Date
    public var numberOfNights: Int
    public var nightlyRateMinor: Int?
    public var totalAmountMinor: Int?
    public var paidAmountMinor: Int?
    /// Present only when the billing projection permits it; nil means redacted.
    public var depositMinor: Int?
    public var paymentStatus: String
    public var branchId: String
    public var specialInstructions: String?
    public var feedingNotes: String?
    public var medicationRequired: Bool
    public var stayIds: [String]
    public var emergencyContactName: String?
    public var emergencyContactPhone: String?
    public var notes: String?
    public var createdAt: Date

    public init(
        id: String,
        reservationNumber: String,
        customerId: String = "",
        customerName: String,
        customerPhone: String,
        customerEmail: String? = nil,
        petId: String = "",
        petName: String,
        petBreed: String,
        petSpecies: String,
        mainKindId: Int? = nil,
        mainKindDocumentId: String? = nil,
        mainKindNameAr: String? = nil,
        mainKindNameEn: String? = nil,
        subKindId: Int? = nil,
        subKindDocumentId: String? = nil,
        subKindNameAr: String? = nil,
        subKindNameEn: String? = nil,
        wing: HotelWing,
        accommodationTypeId: String = "",
        assignedAccommodationId: String? = nil,
        assignedRoomNumber: String? = nil,
        status: HotelReservationStatus,
        paymentStatus: String = "",
        checkInDate: Date,
        checkOutDate: Date,
        numberOfNights: Int = 1,
        nightlyRateMinor: Int? = nil,
        totalAmountMinor: Int? = nil,
        paidAmountMinor: Int? = nil,
        depositMinor: Int? = nil,
        branchId: String = "",
        specialInstructions: String? = nil,
        feedingNotes: String? = nil,
        medicationRequired: Bool = false,
        stayIds: [String] = [],
        emergencyContactName: String? = nil,
        emergencyContactPhone: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.reservationNumber = reservationNumber
        self.customerId = customerId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.customerEmail = customerEmail
        self.petId = petId
        self.petName = petName
        self.petBreed = petBreed
        self.petSpecies = petSpecies
        self.mainKindId = mainKindId
        self.mainKindDocumentId = mainKindDocumentId
        self.mainKindNameAr = mainKindNameAr
        self.mainKindNameEn = mainKindNameEn
        self.subKindId = subKindId
        self.subKindDocumentId = subKindDocumentId
        self.subKindNameAr = subKindNameAr
        self.subKindNameEn = subKindNameEn
        self.wing = wing
        self.accommodationTypeId = accommodationTypeId
        self.assignedAccommodationId = assignedAccommodationId
        self.assignedRoomNumber = assignedRoomNumber
        self.status = status
        self.paymentStatus = paymentStatus
        self.checkInDate = checkInDate
        self.checkOutDate = checkOutDate
        self.numberOfNights = numberOfNights
        self.nightlyRateMinor = nightlyRateMinor
        self.totalAmountMinor = totalAmountMinor
        self.paidAmountMinor = paidAmountMinor
        self.depositMinor = depositMinor
        self.branchId = branchId
        self.specialInstructions = specialInstructions
        self.feedingNotes = feedingNotes
        self.medicationRequired = medicationRequired
        self.stayIds = stayIds
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.notes = notes
        self.createdAt = createdAt
    }

    public var isCheckInDueToday: Bool {
        Calendar.current.isDateInToday(checkInDate)
    }

    public var isCheckOutDueToday: Bool {
        Calendar.current.isDateInToday(checkOutDate)
    }

    public var formattedTotal: String {
        guard let totalAmountMinor else {
            return Language.get("Hotel_BillingRestricted", alter: "الحساب غير متاح")
        }
        let major = Double(totalAmountMinor) / 100.0
        return String(format: "%.2f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public var formattedNightlyRate: String? {
        guard let nightlyRateMinor, nightlyRateMinor > 0 else { return nil }
        let major = Double(nightlyRateMinor) / 100.0
        return String(format: "%.2f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public var balanceDueMinor: Int? {
        guard let total = totalAmountMinor, total > 0 else { return nil }
        let paid = max(paidAmountMinor ?? 0, depositMinor ?? 0)
        return max(0, total - paid)
    }

    public var formattedDeposit: String? {
        guard let depositMinor, depositMinor > 0 else { return nil }
        let major = Double(depositMinor) / 100.0
        return String(format: "%.2f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public var formattedPaidAmount: String? {
        guard let paidAmountMinor, paidAmountMinor > 0 else { return nil }
        let major = Double(paidAmountMinor) / 100.0
        return String(format: "%.2f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public var formattedBalanceDue: String? {
        guard let balanceDueMinor else { return nil }
        let major = Double(balanceDueMinor) / 100.0
        return String(format: "%.2f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public static func fromDictionary(_ dict: [String: Any], id: String) -> AdminHotelReservation {
        let customer = dict["customerSnapshot"] as? [String: Any] ?? [:]
        let rawPets = dict["pets"] as? [[String: Any]] ?? []
        let firstPetLine = rawPets.first ?? [:]
        let petSnapshot = firstPetLine["petSnapshot"] as? [String: Any] ?? [:]
        let emergency = dict["emergencyContact"] as? [String: Any] ?? [:]

        let wingRaw = (dict["wing"] as? String) ?? (firstPetLine["wing"] as? String)
        let statusRaw = dict["status"] as? String ?? "draft"

        let arrivalAt = parseHotelDate(dict["arrivalAt"]) ?? Date()
        let departureAt = parseHotelDate(dict["departureAt"]) ?? Date().addingTimeInterval(86400)
        let nights = dict["nights"] as? Int ?? max(1, Int(departureAt.timeIntervalSince(arrivalAt) / 86400))

        let pricing = dict["pricing"] as? [String: Any] ?? [:]
        let quoteLines = pricing["quoteLines"] as? [[String: Any]] ?? []
        let firstQuoteLine = quoteLines.first ?? [:]

        let nightlyRate = (firstPetLine["nightlyRateMinor"] as? NSNumber)?.intValue
            ?? (firstPetLine["nightlyRateMinor"] as? Int)
            ?? (firstQuoteLine["nightlyRateMinor"] as? NSNumber)?.intValue
            ?? (firstQuoteLine["nightlyRateMinor"] as? Int)
            ?? (dict["nightlyRateMinor"] as? NSNumber)?.intValue
            ?? (dict["nightlyRate"] as? NSNumber)?.intValue

        let billingProjection = AdminHotelBillingProjectionPolicy.resolve(dict)

        var resolvedTotal = billingProjection.totalMinor
        if (resolvedTotal == nil || resolvedTotal == 0), let rate = nightlyRate, rate > 0 {
            resolvedTotal = rate * nights
        }

        // A pet identifier is never a valid stay-command identifier. Keep only
        // the server-projected stay IDs and fail closed when none are available.
        let stayIds = ((dict["stayIds"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let mainKindId = (petSnapshot["mainKindId"] as? NSNumber)?.intValue
            ?? (petSnapshot["mainKindId"] as? Int)
            ?? (firstPetLine["mainKindId"] as? NSNumber)?.intValue
            ?? (firstPetLine["mainKindId"] as? Int)
        let mainKindDocId = petSnapshot["mainKindDocumentId"] as? String
            ?? firstPetLine["mainKindDocumentId"] as? String
        let mainKindAr = petSnapshot["mainKindNameAr"] as? String
            ?? firstPetLine["mainKindNameAr"] as? String
        let mainKindEn = petSnapshot["mainKindNameEn"] as? String
            ?? firstPetLine["mainKindNameEn"] as? String
        let subKindId = (petSnapshot["subKindId"] as? NSNumber)?.intValue
            ?? (petSnapshot["subKindId"] as? Int)
            ?? (firstPetLine["subKindId"] as? NSNumber)?.intValue
            ?? (firstPetLine["subKindId"] as? Int)
        let subKindDocId = petSnapshot["subKindDocumentId"] as? String
            ?? firstPetLine["subKindDocumentId"] as? String
        let subKindAr = petSnapshot["subKindNameAr"] as? String
            ?? firstPetLine["subKindNameAr"] as? String
        let subKindEn = petSnapshot["subKindNameEn"] as? String
            ?? firstPetLine["subKindNameEn"] as? String

        return AdminHotelReservation(
            id: id,
            reservationNumber: dict["reservationNumber"] as? String ?? "",
            customerId: dict["customerUid"] as? String ?? "",
            customerName: customer["name"] as? String ?? dict["customerName"] as? String ?? "",
            customerPhone: customer["phone"] as? String ?? dict["customerPhone"] as? String ?? "",
            customerEmail: customer["email"] as? String ?? dict["customerEmail"] as? String,
            petId: petSnapshot["petId"] as? String ?? firstPetLine["petId"] as? String ?? "",
            petName: petSnapshot["name"] as? String ?? "",
            petBreed: petSnapshot["breed"] as? String ?? "",
            petSpecies: petSnapshot["species"] as? String ?? "",
            mainKindId: mainKindId,
            mainKindDocumentId: mainKindDocId,
            mainKindNameAr: mainKindAr,
            mainKindNameEn: mainKindEn,
            subKindId: subKindId,
            subKindDocumentId: subKindDocId,
            subKindNameAr: subKindAr,
            subKindNameEn: subKindEn,
            wing: resolvedHotelWing(rawValue: wingRaw, species: petSnapshot["species"] as? String),
            accommodationTypeId: firstPetLine["accommodationTypeId"] as? String ?? "",
            assignedAccommodationId: (firstPetLine["accommodationId"] as? String)
                ?? (dict["assignedAccommodationId"] as? String)
                ?? (dict["accommodationId"] as? String),
            assignedRoomNumber: (firstPetLine["accommodationCode"] as? String)
                ?? (dict["assignedRoomNumber"] as? String)
                ?? (dict["accommodationCode"] as? String)
                ?? (dict["roomNumber"] as? String),
            status: HotelReservationStatus(rawValue: statusRaw) ?? .draft,
            paymentStatus: dict["paymentStatus"] as? String ?? "",
            checkInDate: arrivalAt,
            checkOutDate: departureAt,
            numberOfNights: nights,
            nightlyRateMinor: nightlyRate,
            totalAmountMinor: resolvedTotal,
            paidAmountMinor: billingProjection.settledMinor,
            depositMinor: billingProjection.depositMinor,
            branchId: dict["branchId"] as? String ?? "",
            specialInstructions: dict["notes"] as? String,
            feedingNotes: dict["specialInstructions"] as? String,
            medicationRequired: (firstPetLine["medicationDeclarationCount"] as? Int ?? 0) > 0,
            stayIds: stayIds,
            emergencyContactName: emergency["name"] as? String,
            emergencyContactPhone: emergency["phone"] as? String,
            notes: dict["notes"] as? String,
            createdAt: parseHotelDate(dict["createdAt"]) ?? Date()
        )
    }
}

public struct AdminHotelStay: Identifiable, Hashable {
    public let id: String
    public var stayNumber: String
    public var reservationId: String
    public var customerId: String
    public var customerName: String
    public var customerPhone: String
    public var petId: String
    public var petName: String
    public var petBreed: String
    public var petSpecies: String
    public var mainKindId: Int?
    public var mainKindDocumentId: String?
    public var mainKindNameAr: String?
    public var mainKindNameEn: String?
    public var subKindId: Int?
    public var subKindDocumentId: String?
    public var subKindNameAr: String?
    public var subKindNameEn: String?
    public var petPhotoUrl: String?
    public var wing: HotelWing
    public var accommodationId: String
    public var roomNumber: String
    public var status: HotelReservationStatus
    public var guestStatus: HotelGuestStatus
    public var checkInTime: Date
    public var expectedCheckOutTime: Date
    public var actualCheckOutTime: Date?
    public var belongings: [AdminHotelBelongingItem]
    public var dailyCareTasks: [AdminHotelCareTask]
    public var branchId: String
    public var internalNotes: String?
    public var openTaskCount: Int
    public var overdueTaskCount: Int
    public var belongingCount: Int
    public var medicationConfirmationRequired: Bool
    public var pendingMedicationCount: Int
    public var criticalIncidentCount: Int
    public var grandTotalMinor: Int
    public var outstandingMinor: Int
    public var paymentStatus: String

    public init(
        id: String,
        stayNumber: String,
        reservationId: String = "",
        customerId: String = "",
        customerName: String,
        customerPhone: String,
        petId: String = "",
        petName: String,
        petBreed: String,
        petSpecies: String,
        mainKindId: Int? = nil,
        mainKindDocumentId: String? = nil,
        mainKindNameAr: String? = nil,
        mainKindNameEn: String? = nil,
        subKindId: Int? = nil,
        subKindDocumentId: String? = nil,
        subKindNameAr: String? = nil,
        subKindNameEn: String? = nil,
        petPhotoUrl: String? = nil,
        wing: HotelWing,
        accommodationId: String,
        roomNumber: String,
        status: HotelReservationStatus = .checkedIn,
        guestStatus: HotelGuestStatus = .normal,
        checkInTime: Date,
        expectedCheckOutTime: Date,
        actualCheckOutTime: Date? = nil,
        belongings: [AdminHotelBelongingItem] = [],
        dailyCareTasks: [AdminHotelCareTask] = [],
        branchId: String = "",
        internalNotes: String? = nil,
        openTaskCount: Int = 0,
        overdueTaskCount: Int = 0,
        belongingCount: Int = 0,
        medicationConfirmationRequired: Bool = false,
        pendingMedicationCount: Int = 0,
        criticalIncidentCount: Int = 0,
        grandTotalMinor: Int = 0,
        outstandingMinor: Int = 0,
        paymentStatus: String = "unpaid"
    ) {
        self.id = id
        self.stayNumber = stayNumber
        self.reservationId = reservationId
        self.customerId = customerId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.petId = petId
        self.petName = petName
        self.petBreed = petBreed
        self.petSpecies = petSpecies
        self.mainKindId = mainKindId
        self.mainKindDocumentId = mainKindDocumentId
        self.mainKindNameAr = mainKindNameAr
        self.mainKindNameEn = mainKindNameEn
        self.subKindId = subKindId
        self.subKindDocumentId = subKindDocumentId
        self.subKindNameAr = subKindNameAr
        self.subKindNameEn = subKindNameEn
        self.petPhotoUrl = petPhotoUrl
        self.wing = wing
        self.accommodationId = accommodationId
        self.roomNumber = roomNumber
        self.status = status
        self.guestStatus = guestStatus
        self.checkInTime = checkInTime
        self.expectedCheckOutTime = expectedCheckOutTime
        self.actualCheckOutTime = actualCheckOutTime
        self.belongings = belongings
        self.dailyCareTasks = dailyCareTasks
        self.branchId = branchId
        self.internalNotes = internalNotes
        self.openTaskCount = openTaskCount
        self.overdueTaskCount = overdueTaskCount
        self.belongingCount = belongingCount
        self.medicationConfirmationRequired = medicationConfirmationRequired
        self.pendingMedicationCount = pendingMedicationCount
        self.criticalIncidentCount = criticalIncidentCount
        self.grandTotalMinor = grandTotalMinor
        self.outstandingMinor = outstandingMinor
        self.paymentStatus = paymentStatus
    }

    public var stayProgress: Double {
        let totalDuration = expectedCheckOutTime.timeIntervalSince(checkInTime)
        guard totalDuration > 0 else { return 1.0 }
        let elapsed = Date().timeIntervalSince(checkInTime)
        return min(max(elapsed / totalDuration, 0.0), 1.0)
    }

    public static func fromDictionary(_ dict: [String: Any], id: String) -> AdminHotelStay {
        let customer = dict["customerSnapshot"] as? [String: Any] ?? [:]
        let pet = dict["petSnapshot"] as? [String: Any] ?? [:]
        let ledger = dict["ledger"] as? [String: Any] ?? [:]
        let checkInReadiness = dict["checkInReadiness"] as? [String: Any] ?? [:]

        let wingRaw = (dict["wing"] as? String) ?? (pet["wing"] as? String)
        let statusRaw = dict["status"] as? String ?? "checked_in"
        let guestStatusRaw = dict["guestStatus"] as? String ?? "normal"

        let checkInDate = parseHotelDate(dict["actualArrivalAt"])
            ?? parseHotelDate(dict["plannedArrivalAt"])
            ?? parseHotelDate(dict["checkInTime"])
            ?? Date()

        let checkOutDate = parseHotelDate(dict["actualDepartureAt"])
            ?? parseHotelDate(dict["plannedDepartureAt"])
            ?? parseHotelDate(dict["expectedCheckOutTime"])
            ?? Date().addingTimeInterval(86400 * 3)

        let resolvedStayNumber = dict["stayNumber"] as? String
            ?? dict["reservationNumber"] as? String
            ?? dict["bookingNumber"] as? String
            ?? (!id.isEmpty ? String(id.prefix(8)).uppercased() : "")

        let resolvedCustomerName = customer["name"] as? String
            ?? customer["fullName"] as? String
            ?? dict["customerName"] as? String
            ?? dict["ownerName"] as? String
            ?? dict["userName"] as? String
            ?? ""

        let resolvedCustomerPhone = customer["phone"] as? String
            ?? customer["mobile"] as? String
            ?? dict["customerPhone"] as? String
            ?? dict["ownerPhone"] as? String
            ?? dict["userPhone"] as? String
            ?? dict["phone"] as? String
            ?? ""

        let resolvedRoomNumber = dict["accommodationCode"] as? String
            ?? dict["roomNumber"] as? String
            ?? dict["roomName"] as? String
            ?? ""

        let mainKindId = (pet["mainKindId"] as? NSNumber)?.intValue
            ?? (pet["mainKindId"] as? Int)
            ?? (dict["mainKindId"] as? NSNumber)?.intValue
            ?? (dict["mainKindId"] as? Int)
        let mainKindDocId = pet["mainKindDocumentId"] as? String
            ?? dict["mainKindDocumentId"] as? String
        let mainKindAr = pet["mainKindNameAr"] as? String
            ?? dict["mainKindNameAr"] as? String
        let mainKindEn = pet["mainKindNameEn"] as? String
            ?? dict["mainKindNameEn"] as? String
        let subKindId = (pet["subKindId"] as? NSNumber)?.intValue
            ?? (pet["subKindId"] as? Int)
            ?? (dict["subKindId"] as? NSNumber)?.intValue
            ?? (dict["subKindId"] as? Int)
        let subKindDocId = pet["subKindDocumentId"] as? String
            ?? dict["subKindDocumentId"] as? String
        let subKindAr = pet["subKindNameAr"] as? String
            ?? dict["subKindNameAr"] as? String
        let subKindEn = pet["subKindNameEn"] as? String
            ?? dict["subKindNameEn"] as? String

        return AdminHotelStay(
            id: id,
            stayNumber: resolvedStayNumber,
            reservationId: dict["reservationId"] as? String ?? "",
            customerId: dict["customerUid"] as? String ?? dict["customerId"] as? String ?? "",
            customerName: resolvedCustomerName,
            customerPhone: resolvedCustomerPhone,
            petId: pet["petId"] as? String ?? dict["petId"] as? String ?? "",
            petName: pet["name"] as? String ?? dict["petName"] as? String ?? "",
            petBreed: pet["breed"] as? String ?? dict["petBreed"] as? String ?? "",
            petSpecies: pet["species"] as? String ?? dict["petSpecies"] as? String ?? "",
            mainKindId: mainKindId,
            mainKindDocumentId: mainKindDocId,
            mainKindNameAr: mainKindAr,
            mainKindNameEn: mainKindEn,
            subKindId: subKindId,
            subKindDocumentId: subKindDocId,
            subKindNameAr: subKindAr,
            subKindNameEn: subKindEn,
            petPhotoUrl: pet["imageURL"] as? String ?? dict["petPhotoUrl"] as? String,
            wing: resolvedHotelWing(rawValue: wingRaw, species: pet["species"] as? String ?? dict["petSpecies"] as? String),
            accommodationId: dict["accommodationId"] as? String ?? "",
            roomNumber: resolvedRoomNumber,
            status: HotelReservationStatus(rawValue: statusRaw) ?? .draft,
            guestStatus: HotelGuestStatus(rawValue: guestStatusRaw) ?? .normal,
            checkInTime: checkInDate,
            expectedCheckOutTime: checkOutDate,
            actualCheckOutTime: parseHotelDate(dict["actualDepartureAt"]),
            belongings: [],
            dailyCareTasks: [],
            branchId: dict["branchId"] as? String ?? "",
            internalNotes: dict["internalNotes"] as? String,
            openTaskCount: dict["openTaskCount"] as? Int ?? 0,
            overdueTaskCount: dict["overdueTaskCount"] as? Int ?? 0,
            belongingCount: max(0, dict["belongingCount"] as? Int ?? 0),
            medicationConfirmationRequired:
                (checkInReadiness["medicationConfirmationRequired"] as? Bool)
                ?? ((dict["medicationDeclarationCount"] as? Int ?? dict["medicationPlanCount"] as? Int ?? 0) > 0),
            pendingMedicationCount: dict["pendingMedicationCount"] as? Int ?? 0,
            criticalIncidentCount: dict["criticalIncidentCount"] as? Int ?? 0,
            grandTotalMinor: ledger["grandTotalMinor"] as? Int ?? 0,
            outstandingMinor: {
                let gt = ledger["grandTotalMinor"] as? Int ?? 0
                let out = ledger["outstandingMinor"] as? Int ?? 0
                let dep = (ledger["depositMinor"] as? Int) ?? (dict["depositMinor"] as? Int) ?? 0
                if out == gt && dep > 0 && gt > 0 {
                    return max(0, gt - dep)
                }
                return out
            }(),
            paymentStatus: dict["paymentStatus"] as? String ?? "unpaid"
        )
    }
}

public struct AdminHotelBelongingItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var quantity: Int
    public var isReturned: Bool

    public init(id: String = UUID().uuidString, name: String, quantity: Int = 1, isReturned: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.isReturned = isReturned
    }

    public static func fromDictionary(_ dict: [String: Any], id: String) -> AdminHotelBelongingItem {
        AdminHotelBelongingItem(
            id: id,
            name: dict["description"] as? String ?? dict["name"] as? String ?? "",
            // Current Infra projections use `quantity`; retain `count` only
            // for historical read compatibility.
            quantity: dict["quantity"] as? Int ?? dict["count"] as? Int ?? 1,
            isReturned: dict["returned"] as? Bool ?? dict["isReturned"] as? Bool ?? false
        )
    }
}

public struct AdminHotelCareTask: Identifiable, Hashable {
    public let id: String
    public var taskType: HotelCareTaskType
    public var scheduledTime: String
    public var isCompleted: Bool
    public var completedAt: Date?
    public var completedByStaffName: String?
    public var notes: String?
    public var status: String

    public init(id: String = UUID().uuidString, taskType: HotelCareTaskType, scheduledTime: String, isCompleted: Bool = false, completedAt: Date? = nil, completedByStaffName: String? = nil, notes: String? = nil, status: String = "scheduled") {
        self.id = id
        self.taskType = taskType
        self.scheduledTime = scheduledTime
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.completedByStaffName = completedByStaffName
        self.notes = notes
        self.status = status
    }

    public static func fromDictionary(_ dict: [String: Any], id: String) -> AdminHotelCareTask {
        let typeRaw = dict["type"] as? String ?? "custom"
        let statusRaw = dict["status"] as? String ?? "scheduled"
        let completed = statusRaw == "completed"

        let scheduledAt = parseHotelDate(dict["scheduledAt"])
        let timeString: String
        if let s = scheduledAt {
            let f = DateFormatter()
            f.dateFormat = "hh:mm a"
            timeString = f.string(from: s)
        } else {
            timeString = dict["scheduledTime"] as? String ?? Language.get("Hotel_TimeUnavailable", alter: "—")
        }

        return AdminHotelCareTask(
            id: id,
            taskType: HotelCareTaskType(rawValue: typeRaw) ?? .custom,
            scheduledTime: timeString,
            isCompleted: completed,
            completedAt: parseHotelDate(dict["completedAt"]),
            completedByStaffName: dict["assignedStaffName"] as? String,
            notes: dict["instructions"] as? String ?? dict["notes"] as? String,
            status: statusRaw
        )
    }
}

// MARK: - Animal Taxonomy Store (MainKinds Bridge)

public struct PPAnimalTaxonomySubKind: Identifiable, Hashable, Sendable {
    public let id: Int
    public let documentID: String
    public let nameAr: String
    public let nameEn: String
    public let mainKindID: Int

    public var displayName: String {
        Language.isRTL() ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn)
    }

    public var localizedName: String {
        displayName
    }

    public var documentId: String {
        documentID
    }
}

public struct PPAnimalTaxonomyKind: Identifiable, Hashable, Sendable {
    public let id: Int
    public let documentID: String
    public let nameAr: String
    public let nameEn: String
    public let subKinds: [PPAnimalTaxonomySubKind]

    public var displayName: String {
        Language.isRTL() ? (nameAr.isEmpty ? nameEn : nameAr) : (nameEn.isEmpty ? nameAr : nameEn)
    }

    public var localizedName: String {
        displayName
    }

    public var documentId: String {
        documentID
    }

    public var iconName: String {
        switch speciesEquivalent {
        case "dog": return "dog.fill"
        case "cat": return "cat.fill"
        case "bird": return "bird.fill"
        case "small_pets": return "hare.fill"
        default:
            let lowerAr = nameAr.lowercased()
            let lowerEn = nameEn.lowercased()
            if lowerAr.contains("صقر") || lowerAr.contains("صقور") || lowerEn.contains("falcon") {
                return "bird.fill"
            } else if lowerAr.contains("خيل") || lowerAr.contains("خيول") || lowerEn.contains("horse") {
                return "figure.equestrian.sports"
            } else if lowerAr.contains("إبل") || lowerEn.contains("camel") {
                return "pawprint.fill"
            }
            return "pawprint.fill"
        }
    }

    public var speciesEquivalent: String {
        let lowerEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerDoc = documentID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if id == 6 || lowerEn.contains("dog") || lowerAr.contains("كلاب") || lowerAr.contains("كلب") || lowerDoc == "dogs" || lowerDoc == "dog" {
            return "dog"
        }
        if id == 5 || lowerEn.contains("cat") || lowerAr.contains("قطط") || lowerAr.contains("قط") || lowerDoc == "cats" || lowerDoc == "cat" {
            return "cat"
        }
        if id == 1 || id == 11 || id == 12 || lowerEn.contains("bird") || lowerEn.contains("parrot") || lowerEn.contains("falcon") || lowerAr.contains("طيور") || lowerAr.contains("طير") || lowerAr.contains("صقور") || lowerDoc == "birds" || lowerDoc == "bird" {
            return "bird"
        }
        if id == 8 || id == 4 || id == 7 || id == 9 || id == 10 || lowerEn.contains("rabbit") || lowerEn.contains("small") || lowerAr.contains("أرانب") || lowerAr.contains("حيوانات صغيرة") || lowerDoc.contains("small") {
            return "small_pets"
        }
        if !lowerDoc.isEmpty && lowerDoc != "\(id)" {
            return lowerDoc
        }
        return lowerEn.isEmpty ? (lowerAr.isEmpty ? "other" : lowerAr) : lowerEn
    }
}

@MainActor
public final class PPAnimalTaxonomyStore: ObservableObject {
    public static let shared = PPAnimalTaxonomyStore()

    @Published public private(set) var kinds: [PPAnimalTaxonomyKind] = []

    private var mainKindsListener: ListenerRegistration?
    private var subKindListeners: [String: ListenerRegistration] = [:]

    private init() {
        // Start immediately with canonical taxonomy matching PurePets Firestore
        self.kinds = Self.defaultFallbackKinds

        // Hydrate from existing memory managers if available
        loadFromManagers()

        // Kick off asynchronous hydration from MainKindsArrayManager and live Firestore
        loadTaxonomy()

        // Observe notifications from MainKindsArrayManager
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MainKindsUpdatedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadFromManagers()
        }

        // Attach live Firestore listener to MainKindsCollection + SubKinds subcollections
        attachFirestoreListeners()
    }

    public func loadFromManagers() {
        let rawArray: [MainKindsModel] = {
            if let arr = MainKindsArrayManager.shared().mainKindsArray as? [MainKindsModel], !arr.isEmpty {
                return arr
            }
            if let arr = AppManager.shared().mainKindsArray as? [MainKindsModel], !arr.isEmpty {
                return arr
            }
            return []
        }()

        guard !rawArray.isEmpty else { return }

        var updatedKinds: [PPAnimalTaxonomyKind] = []
        for m in rawArray {
            let mainID = Int(m.id)
            let docID = m.documentID ?? "\(mainID)"
            let ar = m.kindNameAr ?? ""
            let en = m.kindNameEn ?? ""

            var subKinds: [PPAnimalTaxonomySubKind] = []
            if let subs = m.subKindsArray as? [SubKindModel] {
                for s in subs {
                    subKinds.append(PPAnimalTaxonomySubKind(
                        id: Int(s.id),
                        documentID: s.documentID ?? "\(s.id)",
                        nameAr: s.subKindNameAr ?? "",
                        nameEn: s.subKindNameEn ?? "",
                        mainKindID: mainID
                    ))
                }
            }

            // If manager model has no subkinds yet, preserve existing subkinds if any
            if subKinds.isEmpty, let existing = self.kinds.first(where: { $0.id == mainID || $0.documentID == docID }), !existing.subKinds.isEmpty {
                subKinds = existing.subKinds
            }

            updatedKinds.append(PPAnimalTaxonomyKind(
                id: mainID,
                documentID: docID,
                nameAr: ar,
                nameEn: en,
                subKinds: subKinds
            ))
        }

        if !updatedKinds.isEmpty {
            self.kinds = updatedKinds
        }
    }

    public func loadTaxonomy() {
        loadFromManagers()

        // Request MainKindsArrayManager to hydrate if needed
        MainKindsArrayManager.shared().loadMainDataCompletionHandler { [weak self] _ in
            Task { @MainActor in
                self?.loadFromManagers()
            }
        }
    }

    private func attachFirestoreListeners() {
        guard mainKindsListener == nil else { return }
        let db = Firestore.firestore()
        mainKindsListener = db.collection("MainKindsCollection").order(by: "sortingKey").addSnapshotListener { [weak self] snapshot, error in
            guard let self = self, let docs = snapshot?.documents, !docs.isEmpty else { return }
            Task { @MainActor in
                self.processMainKindsSnapshot(docs)
            }
        }
    }

    private func processMainKindsSnapshot(_ docs: [QueryDocumentSnapshot]) {
        var newKinds: [PPAnimalTaxonomyKind] = []

        for doc in docs {
            let data = doc.data()
            let mainID = (data["ID"] as? NSNumber)?.intValue ?? Int(doc.documentID) ?? 0
            let docID = doc.documentID
            let ar = (data["KindNameAr"] as? String) ?? ""
            let en = (data["KindNameEn"] as? String) ?? ""

            // Check embedded SubKindsArray
            var subKinds: [PPAnimalTaxonomySubKind] = []
            if let rawSubs = data["SubKindsArray"] as? [[String: Any]] {
                for sDict in rawSubs {
                    let sId = (sDict["ID"] as? NSNumber)?.intValue ?? 0
                    let sDocId = (sDict["documentID"] as? String) ?? "\(sId)"
                    let sAr = (sDict["SubKindNameAr"] as? String) ?? (sDict["nameAr"] as? String) ?? ""
                    let sEn = (sDict["SubKindNameEn"] as? String) ?? (sDict["nameEn"] as? String) ?? ""
                    if !sAr.isEmpty || !sEn.isEmpty {
                        subKinds.append(PPAnimalTaxonomySubKind(
                            id: sId,
                            documentID: sDocId,
                            nameAr: sAr,
                            nameEn: sEn,
                            mainKindID: mainID
                        ))
                    }
                }
            }

            // If empty, preserve current known subkinds
            if subKinds.isEmpty, let existing = self.kinds.first(where: { $0.id == mainID || $0.documentID == docID }), !existing.subKinds.isEmpty {
                subKinds = existing.subKinds
            }

            newKinds.append(PPAnimalTaxonomyKind(
                id: mainID,
                documentID: docID,
                nameAr: ar,
                nameEn: en,
                subKinds: subKinds
            ))

            // Attach listener to SubKinds subcollection for this document
            attachSubKindsListener(for: doc)
        }

        if !newKinds.isEmpty {
            self.kinds = newKinds
        }
    }

    private func attachSubKindsListener(for doc: QueryDocumentSnapshot) {
        let docID = doc.documentID
        guard subKindListeners[docID] == nil else { return }

        let mainID = (doc.data()["ID"] as? NSNumber)?.intValue ?? Int(docID) ?? 0
        let listener = doc.reference.collection("SubKinds").order(by: "ID").addSnapshotListener { [weak self] subSnapshot, error in
            guard let self = self, let subDocs = subSnapshot?.documents, !subDocs.isEmpty else { return }
            Task { @MainActor in
                self.processSubKindsSnapshot(mainKindDocID: docID, mainKindID: mainID, subDocs: subDocs)
            }
        }
        subKindListeners[docID] = listener
    }

    private func processSubKindsSnapshot(mainKindDocID: String, mainKindID: Int, subDocs: [QueryDocumentSnapshot]) {
        var fetchedSubKinds: [PPAnimalTaxonomySubKind] = []
        for sDoc in subDocs {
            let data = sDoc.data()
            let sId = (data["ID"] as? NSNumber)?.intValue ?? Int(sDoc.documentID) ?? 0
            let sAr = (data["SubKindNameAr"] as? String) ?? (data["nameAr"] as? String) ?? ""
            let sEn = (data["SubKindNameEn"] as? String) ?? (data["nameEn"] as? String) ?? ""
            let mId = (data["MainKindID"] as? NSNumber)?.intValue ?? mainKindID

            if !sAr.isEmpty || !sEn.isEmpty {
                fetchedSubKinds.append(PPAnimalTaxonomySubKind(
                    id: sId,
                    documentID: sDoc.documentID,
                    nameAr: sAr,
                    nameEn: sEn,
                    mainKindID: mId
                ))
            }
        }

        guard !fetchedSubKinds.isEmpty else { return }

        // Update the kind in kinds array
        if let idx = self.kinds.firstIndex(where: { $0.documentID == mainKindDocID || $0.id == mainKindID }) {
            let current = self.kinds[idx]
            // Merge subkinds keeping uniqueness by id or documentID
            var mergedMap: [String: PPAnimalTaxonomySubKind] = [:]
            for s in current.subKinds {
                mergedMap[s.documentID] = s
            }
            for s in fetchedSubKinds {
                mergedMap[s.documentID] = s
            }
            let sortedSubKinds = Array(mergedMap.values).sorted(by: { $0.id < $1.id })
            self.kinds[idx] = PPAnimalTaxonomyKind(
                id: current.id,
                documentID: current.documentID,
                nameAr: current.nameAr,
                nameEn: current.nameEn,
                subKinds: sortedSubKinds
            )
        }
    }

    public static let defaultFallbackKinds: [PPAnimalTaxonomyKind] = [
        PPAnimalTaxonomyKind(id: 6, documentID: "6", nameAr: "كلاب", nameEn: "Dogs", subKinds: [
            PPAnimalTaxonomySubKind(id: 28, documentID: "28", nameAr: "جولدن ريتريفر", nameEn: "Golden Retriever", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 22, documentID: "22", nameAr: "جيرمان شيبرد", nameEn: "German Shepherd", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 27, documentID: "27", nameAr: "بومرينيان", nameEn: "Pomeranian", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 23, documentID: "23", nameAr: "مالينو", nameEn: "Malinois", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 25, documentID: "25", nameAr: "الدوبرمان", nameEn: "Doberman", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 26, documentID: "26", nameAr: "الروت وايلر", nameEn: "Rottweiler", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 24, documentID: "24", nameAr: "البول ماستيف", nameEn: "Bullmastiff", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 29, documentID: "29", nameAr: "بيتبول", nameEn: "Pitbull", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 102, documentID: "husky", nameAr: "هاسكي سيبيري", nameEn: "Siberian Husky", mainKindID: 6),
            PPAnimalTaxonomySubKind(id: 104, documentID: "mixed_dog", nameAr: "سلالة مختلطة", nameEn: "Mixed Breed", mainKindID: 6)
        ]),
        PPAnimalTaxonomyKind(id: 5, documentID: "5", nameAr: "قطط", nameEn: "Cats", subKinds: [
            PPAnimalTaxonomySubKind(id: 16, documentID: "16", nameAr: "شيرازي", nameEn: "Persian", mainKindID: 5),
            PPAnimalTaxonomySubKind(id: 17, documentID: "17", nameAr: "سيامي", nameEn: "Siamese", mainKindID: 5),
            PPAnimalTaxonomySubKind(id: 18, documentID: "18", nameAr: "سكوتش فولد", nameEn: "Scottish Fold", mainKindID: 5),
            PPAnimalTaxonomySubKind(id: 19, documentID: "19", nameAr: "هيمالايا", nameEn: "Himalayan", mainKindID: 5),
            PPAnimalTaxonomySubKind(id: 20, documentID: "20", nameAr: "البيرمان", nameEn: "Birman", mainKindID: 5),
            PPAnimalTaxonomySubKind(id: 21, documentID: "21", nameAr: "فرعوني", nameEn: "Sphynx", mainKindID: 5),
            PPAnimalTaxonomySubKind(id: 202, documentID: "british", nameAr: "بريطاني قصير الشعر", nameEn: "British Shorthair", mainKindID: 5),
            PPAnimalTaxonomySubKind(id: 204, documentID: "mixed_cat", nameAr: "سلالة مختلطة / بلدي", nameEn: "Domestic / Mixed", mainKindID: 5)
        ]),
        PPAnimalTaxonomyKind(id: 1, documentID: "1", nameAr: "طيور", nameEn: "Birds", subKinds: [
            PPAnimalTaxonomySubKind(id: 1, documentID: "1", nameAr: "كاسكو", nameEn: "African grey", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 6, documentID: "6", nameAr: "الكوكاتيل", nameEn: "Cockatiel", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 3, documentID: "3", nameAr: "الدره", nameEn: "Ringneck", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 32, documentID: "32", nameAr: "كانيور", nameEn: "Conure", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 4, documentID: "4", nameAr: "كوكاتو", nameEn: "Cockatoo", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 5, documentID: "5", nameAr: "بادجي", nameEn: "Budgie", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 7, documentID: "7", nameAr: "طيور الحب", nameEn: "Love bird", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 8, documentID: "8", nameAr: "ماكاو", nameEn: "Macaws", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 9, documentID: "9", nameAr: "الأمازون", nameEn: "Amazon", mainKindID: 1),
            PPAnimalTaxonomySubKind(id: 2, documentID: "2", nameAr: "كناري", nameEn: "canary", mainKindID: 1)
        ]),
        PPAnimalTaxonomyKind(id: 8, documentID: "8", nameAr: "أرانب وحيوانات أليفة صغيرة", nameEn: "Small Pets & Rabbits", subKinds: [
            PPAnimalTaxonomySubKind(id: 401, documentID: "rabbit", nameAr: "أرنب هولندي / قزم", nameEn: "Holland Lop / Dwarf Rabbit", mainKindID: 8),
            PPAnimalTaxonomySubKind(id: 402, documentID: "hamster", nameAr: "هامستر سوري / قزم", nameEn: "Syrian / Dwarf Hamster", mainKindID: 8),
            PPAnimalTaxonomySubKind(id: 403, documentID: "guinea_pig", nameAr: "خنزير غينيا (كابياء)", nameEn: "Guinea Pig", mainKindID: 8),
            PPAnimalTaxonomySubKind(id: 404, documentID: "chinchilla", nameAr: "شنشيلا", nameEn: "Chinchilla", mainKindID: 8)
        ])
    ]

    public func kind(forID id: Int) -> PPAnimalTaxonomyKind? {
        kinds.first(where: { $0.id == id })
    }

    public func kind(forSpecies species: String) -> PPAnimalTaxonomyKind? {
        let trimmed = species.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return kinds.first(where: {
            $0.speciesEquivalent.lowercased() == trimmed
            || $0.documentID.lowercased() == trimmed
            || $0.nameEn.lowercased() == trimmed
            || $0.nameAr == species
            || ($0.id == 6 && (trimmed == "dog" || trimmed == "dogs"))
            || ($0.id == 5 && (trimmed == "cat" || trimmed == "cats"))
            || ($0.id == 1 && (trimmed == "bird" || trimmed == "birds" || trimmed == "parrot"))
            || ($0.id == 8 && (trimmed == "small_pets" || trimmed == "smallpet" || trimmed == "rabbit" || trimmed == "small_pet"))
        })
    }

    public func subKind(forID id: Int, mainKindID: Int) -> PPAnimalTaxonomySubKind? {
        kind(forID: mainKindID)?.subKinds.first(where: { $0.id == id })
    }

    public func subKinds(for mainKindID: Int) -> [PPAnimalTaxonomySubKind] {
        kind(forID: mainKindID)?.subKinds ?? []
    }

    public func subKind(forBreedName name: String, mainKindID: Int? = nil) -> PPAnimalTaxonomySubKind? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let searchKinds: [PPAnimalTaxonomyKind] = {
            if let mainKindID, let specific = kind(forID: mainKindID) {
                return [specific]
            }
            return kinds
        }()

        for k in searchKinds {
            if let match = k.subKinds.first(where: {
                $0.nameAr.lowercased() == trimmed
                || $0.nameEn.lowercased() == trimmed
                || $0.localizedName.lowercased() == trimmed
                || $0.nameAr.contains(name)
                || trimmed.contains($0.nameAr.lowercased())
            }) {
                return match
            }
        }
        return nil
    }
}
