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
        case .cats: return Language.get("Hotel_Wing_Cats", alter: "واحة القطط")
        case .birds: return Language.get("Hotel_Wing_Birds", alter: "ملاذ الطيور")
        case .smallPets: return Language.get("Hotel_Wing_SmallPets", alter: "الحيوانات الأليفة الصغيرة")
        case .isolation: return Language.get("Hotel_Wing_Isolation", alter: "العزل والرعاية الخاصة")
        case .medicalObservation: return Language.get("Hotel_Wing_MedicalObservation", alter: "الملاحظة الطبية")
        case .daycare: return Language.get("Hotel_Wing_Daycare", alter: "الرعاية النهارية")
        }
    }

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
        case .available: return Language.get("Hotel_Room_Available", alter: "متاح وجاهز")
        case .reserved: return Language.get("Hotel_Room_Reserved", alter: "محجوز")
        case .occupied: return Language.get("Hotel_Room_Occupied", alter: "مشغول")
        case .cleaning: return Language.get("Hotel_Room_Cleaning", alter: "قيد التنظيف والتعقيم")
        case .inspection: return Language.get("Hotel_Room_Inspection", alter: "قيد الفحص الدوري")
        case .maintenance: return Language.get("Hotel_Room_Maintenance", alter: "صيانة وتجهيز")
        case .blocked: return Language.get("Hotel_Room_Blocked", alter: "معطل مؤقتاً")
        case .isolation: return Language.get("Hotel_Room_Isolation", alter: "عزل طبي")
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
        case .draft: return Language.get("Hotel_Res_Draft", alter: "مسودة حجز")
        case .pendingConfirmation: return Language.get("Hotel_Res_Pending", alter: "بانتظار التأكيد")
        case .confirmed: return Language.get("Hotel_Res_Confirmed", alter: "مؤكد")
        case .preArrival: return Language.get("Hotel_Res_PreArrival", alter: "استعداد للوصول")
        case .readyForCheckin: return Language.get("Hotel_Res_ReadyCheckin", alter: "جاهز لتسجيل الدخول")
        case .checkedIn, .inStay: return Language.get("Hotel_Res_InStay", alter: "في الإقامة")
        case .readyForCheckout: return Language.get("Hotel_Res_ReadyCheckout", alter: "جاهز للمغادرة")
        case .checkedOut, .completed: return Language.get("Hotel_Res_Completed", alter: "مكتمل")
        case .cancelled: return Language.get("Hotel_Res_Cancelled", alter: "ملغي")
        case .noShow: return Language.get("Hotel_Res_NoShow", alter: "لم يحضر")
        case .rejected: return Language.get("Hotel_Res_Rejected", alter: "مرفوض")
        case .earlyCheckout: return Language.get("Hotel_Res_EarlyCheckout", alter: "مغادرة مبكرة")
        }
    }

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
        case .normal: return Language.get("Hotel_Guest_Normal", alter: "مستقر وطبيعي")
        case .specialCare: return Language.get("Hotel_Guest_SpecialCare", alter: "عناية ورعاية خاصة")
        case .monitor: return Language.get("Hotel_Guest_Monitor", alter: "تحت الملاحظة الدقيقة")
        case .attention: return Language.get("Hotel_Guest_Attention", alter: "تنبيه صحي/سلوكي")
        case .critical: return Language.get("Hotel_Guest_Critical", alter: "حرج - رعاية بيطرية")
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
        case .feeding: return Language.get("Hotel_Task_Feeding", alter: "وجبة طعام")
        case .water: return Language.get("Hotel_Task_Water", alter: "تجديد مياه الشرب")
        case .walk: return Language.get("Hotel_Task_Walk", alter: "نزهة ومشي خارجي")
        case .play: return Language.get("Hotel_Task_Play", alter: "وقت اللعب والترفيه")
        case .medication: return Language.get("Hotel_Task_Medication", alter: "إعطاء دواء/علاج")
        case .cleaning: return Language.get("Hotel_Task_Cleaning", alter: "تنظيف وتعقيم الجناح")
        case .roomInspection: return Language.get("Hotel_Task_RoomInspection", alter: "فحص الجناح")
        case .grooming: return Language.get("Hotel_Task_Grooming", alter: "تمشيط وعناية بالفرو")
        case .healthCheck: return Language.get("Hotel_Task_HealthCheck", alter: "فحص المؤشرات الحيوية")
        case .photoUpdate: return Language.get("Hotel_Task_PhotoUpdate", alter: "تحديث صورة النزيل")
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
        return String(format: "%.0f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public static func fromDictionary(_ dict: [String: Any], id: String) -> AdminHotelAccommodationType {
        let names = dict["name"] as? [String: String] ?? [:]
        let nameAr = dict["nameAr"] as? String ?? names["ar"] ?? ""
        let nameEn = dict["nameEn"] as? String ?? names["en"] ?? ""
        let wingRaw = dict["wing"] as? String ?? "dogs"

        return AdminHotelAccommodationType(
            id: id,
            code: dict["code"] as? String ?? "",
            nameAr: nameAr,
            nameEn: nameEn,
            wing: HotelWing(rawValue: wingRaw) ?? .dogs,
            allowedSpecies: dict["allowedSpecies"] as? [String] ?? [],
            defaultCapacity: dict["defaultCapacity"] as? Int ?? 1,
            nightlyRateMinor: dict["nightlyRateMinor"] as? Int ?? 0,
            allowSharedOccupancy: dict["allowSharedOccupancy"] as? Bool ?? false,
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

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        categoryName: String = "dog",
        breed: String = "",
        weightKg: Double = 5.0,
        accommodationTypeId: String = "",
        specialDiet: String = "",
        allergies: String = "",
        requiresMedication: Bool = false,
        medicationsText: String = ""
    ) {
        self.id = id
        self.name = name
        self.categoryName = categoryName
        self.breed = breed
        self.weightKg = weightKg
        self.accommodationTypeId = accommodationTypeId
        self.specialDiet = specialDiet
        self.allergies = allergies
        self.requiresMedication = requiresMedication
        self.medicationsText = medicationsText
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
    public var allowSharedOccupancy: Bool

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
        self.allowSharedOccupancy = allowSharedOccupancy
    }

    public var formattedRate: String {
        guard let nightlyRateMinor else {
            return Language.get("Hotel_RateUnavailable", alter: "السعر غير متاح")
        }
        let major = Double(nightlyRateMinor) / 100.0
        return String(format: "%.0f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
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
    public var wing: HotelWing
    public var accommodationTypeId: String
    public var assignedAccommodationId: String?
    public var assignedRoomNumber: String?
    public var status: HotelReservationStatus
    public var checkInDate: Date
    public var checkOutDate: Date
    public var numberOfNights: Int
    public var totalAmountMinor: Int?
    public var paidAmountMinor: Int?
    /// Present only when the billing projection permits it; nil means redacted.
    public var depositMinor: Int?
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
        wing: HotelWing,
        accommodationTypeId: String = "",
        assignedAccommodationId: String? = nil,
        assignedRoomNumber: String? = nil,
        status: HotelReservationStatus,
        checkInDate: Date,
        checkOutDate: Date,
        numberOfNights: Int = 1,
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
        self.wing = wing
        self.accommodationTypeId = accommodationTypeId
        self.assignedAccommodationId = assignedAccommodationId
        self.assignedRoomNumber = assignedRoomNumber
        self.status = status
        self.checkInDate = checkInDate
        self.checkOutDate = checkOutDate
        self.numberOfNights = numberOfNights
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
        return String(format: "%.0f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    public var balanceDueMinor: Int? {
        guard let totalAmountMinor, let paidAmountMinor else { return nil }
        return max(0, totalAmountMinor - paidAmountMinor)
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
        let billing = dict["billingSummary"] as? [String: Any] ?? [:]
        let totalMinor = (billing["grandTotalMinor"] as? Int) ?? (pricing["quotedTotalMinor"] as? Int)
        let settledMinor = (billing["settledMinor"] as? Int) ?? (pricing["depositMinor"] as? Int)
        let depositMinor = pricing["depositMinor"] as? Int

        // A pet identifier is never a valid stay-command identifier. Keep only
        // the server-projected stay IDs and fail closed when none are available.
        let stayIds = ((dict["stayIds"] as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

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
            wing: resolvedHotelWing(rawValue: wingRaw, species: petSnapshot["species"] as? String),
            accommodationTypeId: firstPetLine["accommodationTypeId"] as? String ?? "",
            assignedAccommodationId: firstPetLine["accommodationId"] as? String,
            assignedRoomNumber: firstPetLine["accommodationCode"] as? String,
            status: HotelReservationStatus(rawValue: statusRaw) ?? .draft,
            checkInDate: arrivalAt,
            checkOutDate: departureAt,
            numberOfNights: nights,
            totalAmountMinor: totalMinor,
            paidAmountMinor: settledMinor,
            depositMinor: depositMinor,
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

        return AdminHotelStay(
            id: id,
            stayNumber: dict["stayNumber"] as? String ?? "",
            reservationId: dict["reservationId"] as? String ?? "",
            customerId: dict["customerUid"] as? String ?? dict["customerId"] as? String ?? "",
            customerName: customer["name"] as? String ?? dict["customerName"] as? String ?? "",
            customerPhone: customer["phone"] as? String ?? dict["customerPhone"] as? String ?? "",
            petId: pet["petId"] as? String ?? dict["petId"] as? String ?? "",
            petName: pet["name"] as? String ?? dict["petName"] as? String ?? "",
            petBreed: pet["breed"] as? String ?? dict["petBreed"] as? String ?? "",
            petSpecies: pet["species"] as? String ?? dict["petSpecies"] as? String ?? "",
            petPhotoUrl: pet["imageURL"] as? String ?? dict["petPhotoUrl"] as? String,
            wing: resolvedHotelWing(rawValue: wingRaw, species: pet["species"] as? String ?? dict["petSpecies"] as? String),
            accommodationId: dict["accommodationId"] as? String ?? "",
            roomNumber: dict["accommodationCode"] as? String ?? dict["roomNumber"] as? String ?? "",
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
            outstandingMinor: ledger["outstandingMinor"] as? Int ?? 0,
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
