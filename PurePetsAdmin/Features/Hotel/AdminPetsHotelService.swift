//
//  AdminPetsHotelService.swift
//  PurePetsAdmin
//
//  Authoritative data-access and operations bridge for Pets Hotel (فندق ورعاية الحيوانات الأليفة).
//  Mirrors Pure Pets Console petsHotelService.ts and invokes backend callables
//  defined in Pure Pets Infra/functions/hotel/.
//
//  Invariants:
//   - Reads: Aggregate operational telemetry and redacted dossiers are fetched
//     via hotelReadOperations. Accommodations are listened to in Firestore.
//   - Writes: Strictly callable-only (hotelStayCommand, hotelAccommodationCommand,
//     hotelReservationCommand, hotelCareCommand, hotelBillingCommand).
//   - Idempotency: Every mutation carries a unique, durable commandId.
//   - Audit & Security: Preserves branch scope and backend validation chains.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

public enum AdminPetsHotelError: LocalizedError {
    case invalidResponse
    case operationFailed(String)
    case unauthenticated
    case permissionDenied
    case stayNotFound
    case blockers([String])
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return Language.get("Hotel_Err_InvalidResponse", alter: "استجابة غير صالحة من خادم فندق الحيوانات.")
        case .operationFailed(let reason):
            return reason
        case .unauthenticated:
            return Language.get("Hotel_Err_Unauthenticated", alter: "الجلسة غير مسجلة أو انتهت صلاحيتها.")
        case .permissionDenied:
            return Language.get("Hotel_Err_PermissionDenied", alter: "ليس لديك صلاحية لتنفيذ هذه العملية الفندقية.")
        case .stayNotFound:
            return Language.get("Hotel_Err_StayNotFound", alter: "سجل الإقامة المطلوب غير موجود.")
        case .blockers(let list):
            return list.joined(separator: "\n")
        case .transport(let reason):
            return reason
        }
    }
}

public final class AdminPetsHotelService: @unchecked Sendable {
    public static let shared = AdminPetsHotelService()

    private let functions: Functions
    private let timeoutInterval: TimeInterval = 30.0
    private let commandStore = UserDefaults.standard

    private init() {
        self.functions = Functions.functions()
    }

    // MARK: - Idempotency Key Generator
    public static func generateCommandId(scope: String) -> String {
        let cleanScope = scope.replacingOccurrences(of: "[^A-Za-z0-9:_-]", with: "-", options: .regularExpression)
        let uuid = UUID().uuidString.lowercased()
        let raw = "hotel-\(cleanScope)-\(uuid)"
        return String(raw.prefix(128))
    }

    private func commandFingerprint(name: String, action: String, payload: [String: Any]) -> String {
        var canonicalPayload = payload
        // These instants are generated when a button is pressed. They must not
        // turn a retry of the same logical check-in/out into a new command.
        canonicalPayload.removeValue(forKey: "actualArrivalAt")
        canonicalPayload.removeValue(forKey: "actualDepartureAt")

        let envelope: [String: Any] = [
            "uid": Auth.auth().currentUser?.uid ?? "",
            "name": name,
            "action": action,
            "payload": canonicalPayload
        ]
        let data = (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func commandStoreKey(fingerprint: String) -> String {
        "pp.hotel.command.\(fingerprint)"
    }

    private func shouldRetainCommandId(after error: Error) -> Bool {
        guard let hotelError = error as? AdminPetsHotelError else { return false }
        switch hotelError {
        case .transport, .invalidResponse:
            return true
        default:
            return false
        }
    }

    // MARK: - Core Callable Execution
    private struct HotelSendablePayload: @unchecked Sendable {
        let dict: [String: Any]
    }

    @MainActor
    private func executeCallable(name: String, payload: [String: Any]) async throws -> [String: Any] {
        let boxed = HotelSendablePayload(dict: payload)
        let callable = functions.httpsCallable(name)
        callable.timeoutInterval = timeoutInterval

        do {
            let result = try await callable.call(boxed.dict)
            guard let dict = result.data as? [String: Any] else {
                throw AdminPetsHotelError.invalidResponse
            }
            if let ok = dict["ok"] as? Bool, !ok {
                let msg = dict["message"] as? String
                    ?? dict["error"] as? String
                    ?? Language.get("Hotel_Err_CommandFailed", alter: "تعذر تنفيذ أمر الفندق.")
                throw AdminPetsHotelError.operationFailed(msg)
            }
            return dict
        } catch let error as AdminPetsHotelError {
            throw error
        } catch let err as NSError {
            // Parse Cloud Function details
            if err.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: err.code)
                switch code {
                case .permissionDenied:
                    throw AdminPetsHotelError.permissionDenied
                case .unauthenticated:
                    throw AdminPetsHotelError.unauthenticated
                case .notFound:
                    throw AdminPetsHotelError.stayNotFound
                case .cancelled, .unknown, .deadlineExceeded, .internal, .unavailable, .dataLoss:
                    throw AdminPetsHotelError.transport(err.localizedDescription)
                default:
                    break
                }
            }
            if let details = err.userInfo[FunctionsErrorDetailsKey] as? [String: Any] {
                if let blockers = details["blockers"] as? [String], !blockers.isEmpty {
                    throw AdminPetsHotelError.blockers(blockers)
                }
                if let domainCode = details["domainCode"] as? String {
                    throw AdminPetsHotelError.operationFailed(domainCode)
                }
            }
            throw AdminPetsHotelError.transport(err.localizedDescription)
        }
    }

    @MainActor
    private func callHotelCommand(name: String, action: String, payload: [String: Any]) async throws -> [String: Any] {
        var body = payload
        body["action"] = action
        let suppliedCommandId = body["commandId"] as? String
        let fingerprint = commandFingerprint(name: name, action: action, payload: payload)
        let storeKey = commandStoreKey(fingerprint: fingerprint)
        if suppliedCommandId == nil {
            let durableCommandId = commandStore.string(forKey: storeKey) ?? Self.generateCommandId(scope: action)
            body["commandId"] = durableCommandId
            commandStore.set(durableCommandId, forKey: storeKey)
        }

        do {
            let result = try await executeCallable(name: name, payload: body)
            if suppliedCommandId == nil {
                commandStore.removeObject(forKey: storeKey)
            }
            return result
        } catch {
            if suppliedCommandId == nil && !shouldRetainCommandId(after: error) {
                commandStore.removeObject(forKey: storeKey)
            }
            throw error
        }
    }

    @MainActor
    private func callHotelRead(view: String, payload: [String: Any]) async throws -> [String: Any] {
        var body = payload
        body["view"] = view
        return try await executeCallable(name: "hotelReadOperations", payload: body)
    }

    // MARK: - Safe direct reads
    public func listenAccommodations(
        branchId: String,
        onChange: @escaping ([QueryDocumentSnapshot]?, Error?) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore()
            .collection(HotelFirestoreCollections.accommodations)
            .whereField("branchId", isEqualTo: branchId)
            .limit(to: 200)
            .addSnapshotListener { snapshot, error in
                onChange(snapshot?.documents, error)
            }
    }

    public func listenAccommodationTypes(
        branchId: String,
        onChange: @escaping ([QueryDocumentSnapshot]?, Error?) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore()
            .collection(HotelFirestoreCollections.accommodationTypes)
            .whereField("branchId", isEqualTo: branchId)
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                onChange(snapshot?.documents, error)
            }
    }

    // MARK: - Stay Commands (hotelStayCommand)
    @MainActor
    public func checkInStay(
        stayId: String,
        accommodationId: String? = nil,
        actualArrivalAt: Date = Date(),
        emergencyContact: [String: String]? = nil,
        verification: [String: Any],
        belongings: [[String: Any]]? = nil,
        overrideReason: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "actualArrivalAt": ISO8601DateFormatter().string(from: actualArrivalAt),
            "verification": verification
        ]
        if let accId = accommodationId, !accId.isEmpty {
            payload["accommodationId"] = accId
        }
        if let contact = emergencyContact {
            payload["emergencyContact"] = contact
        }
        if let items = belongings, !items.isEmpty {
            payload["belongings"] = items
        }
        if let reason = overrideReason, !reason.isEmpty {
            payload["overrideReason"] = reason
        }

        return try await callHotelCommand(name: "hotelStayCommand", action: "check_in", payload: payload)
    }

    @MainActor
    public func checkOutStay(
        stayId: String,
        actualDepartureAt: Date = Date(),
        verification: [String: Any],
        handoverTo: [String: String]? = nil,
        reasonCode: String? = nil,
        early: Bool = false,
        overrideReason: String? = nil
    ) async throws -> [String: Any] {
        let action = early ? "early_checkout" : "check_out"
        var payload: [String: Any] = [
            "stayId": stayId,
            "actualDepartureAt": ISO8601DateFormatter().string(from: actualDepartureAt),
            "verification": verification
        ]
        if let handover = handoverTo {
            payload["handoverTo"] = handover
        }
        if let reason = reasonCode, !reason.isEmpty {
            payload["reasonCode"] = reason
        }
        if let overrideReason = overrideReason, !overrideReason.isEmpty {
            payload["overrideReason"] = overrideReason
        }

        return try await callHotelCommand(name: "hotelStayCommand", action: action, payload: payload)
    }

    @MainActor
    public func assignAccommodation(
        stayId: String,
        accommodationId: String,
        reasonCode: String? = "reception_assignment",
        note: String? = nil,
        overrideReason: String? = nil,
        isReassign: Bool = false
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "accommodationId": accommodationId
        ]
        if let code = reasonCode, !code.isEmpty {
            payload["reasonCode"] = code
        }
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        if let reason = overrideReason, !reason.isEmpty {
            payload["overrideReason"] = reason
        }

        let action = isReassign ? "reassign_accommodation" : "assign_accommodation"
        return try await callHotelCommand(name: "hotelStayCommand", action: action, payload: payload)
    }

    @MainActor
    public func markReadyForCheckout(stayId: String, note: String? = nil) async throws -> [String: Any] {
        var payload: [String: Any] = ["stayId": stayId]
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        return try await callHotelCommand(name: "hotelStayCommand", action: "mark_ready_for_checkout", payload: payload)
    }

    @MainActor
    public func extendStay(
        stayId: String,
        newDepartureAt: Date,
        reasonCode: String = "operator_request",
        note: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "newDepartureAt": ISO8601DateFormatter().string(from: newDepartureAt),
            "reasonCode": reasonCode
        ]
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        return try await callHotelCommand(name: "hotelStayCommand", action: "extend_stay", payload: payload)
    }

    @MainActor
    public func cancelStay(
        stayId: String,
        reasonCode: String = "customer_request",
        note: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "reasonCode": reasonCode
        ]
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        return try await callHotelCommand(name: "hotelStayCommand", action: "cancel_stay", payload: payload)
    }

    @MainActor
    public func recordBelongings(
        stayId: String,
        belongings: [[String: Any]],
        note: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "belongings": belongings
        ]
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        return try await callHotelCommand(name: "hotelStayCommand", action: "record_belongings", payload: payload)
    }

    @MainActor
    public func returnBelongings(
        stayId: String,
        verifications: [[String: Any]],
        note: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "verifications": verifications
        ]
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        return try await callHotelCommand(name: "hotelStayCommand", action: "return_belongings", payload: payload)
    }

    // MARK: - Accommodation Commands (hotelAccommodationCommand)
    @MainActor
    public func saveAccommodation(
        branchId: String,
        accommodationId: String? = nil,
        accommodationTypeId: String,
        code: String,
        name: String,
        wing: String,
        allowedSpecies: [String],
        maxCapacity: Int = 1,
        allowSharedOccupancy: Bool = false,
        status: String? = nil,
        notes: String? = nil,
        active: Bool = true
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "branchId": branchId,
            "accommodationTypeId": accommodationTypeId,
            "code": code.uppercased(),
            "name": name,
            "wing": wing,
            "allowedSpecies": allowedSpecies,
            "maxCapacity": maxCapacity,
            "allowSharedOccupancy": allowSharedOccupancy,
            "active": active
        ]
        if let id = accommodationId, !id.isEmpty {
            payload["accommodationId"] = id
        }
        if let status, !status.isEmpty {
            payload["status"] = status
        }
        if let notes, !notes.isEmpty {
            payload["notes"] = notes
        }
        return try await callHotelCommand(name: "hotelAccommodationCommand", action: "save_accommodation", payload: payload)
    }

    @MainActor
    public func saveAccommodationType(
        branchId: String,
        accommodationTypeId: String? = nil,
        code: String,
        nameAr: String,
        nameEn: String,
        wing: String,
        allowedSpecies: [String],
        defaultCapacity: Int = 1,
        nightlyRateMinor: Int,
        allowSharedOccupancy: Bool = false,
        sortOrder: Int = 0,
        active: Bool = true,
        description: String? = nil,
        currency: String = "QAR"
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "branchId": branchId,
            "code": code.uppercased(),
            "nameAr": nameAr,
            "nameEn": nameEn,
            "wing": wing,
            "allowedSpecies": allowedSpecies,
            "defaultCapacity": defaultCapacity,
            "nightlyRateMinor": nightlyRateMinor,
            "allowSharedOccupancy": allowSharedOccupancy,
            "sortOrder": sortOrder,
            "active": active,
            "currency": currency
        ]
        if let id = accommodationTypeId, !id.isEmpty {
            payload["accommodationTypeId"] = id
        }
        if let description, !description.isEmpty {
            payload["description"] = description
        }
        return try await callHotelCommand(name: "hotelAccommodationCommand", action: "save_accommodation_type", payload: payload)
    }

    @MainActor
    public func setAccommodationStatus(
        accommodationId: String,
        status: String,
        notes: String? = nil,
        overrideReason: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "accommodationId": accommodationId,
            "status": status
        ]
        if let notes = notes, !notes.isEmpty {
            payload["notes"] = notes
        }
        if let reason = overrideReason, !reason.isEmpty {
            payload["overrideReason"] = reason
        }
        return try await callHotelCommand(name: "hotelAccommodationCommand", action: "set_accommodation_status", payload: payload)
    }

    @MainActor
    public func setAccommodationActive(
        accommodationId: String,
        active: Bool,
        overrideReason: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "accommodationId": accommodationId,
            "active": active
        ]
        if let reason = overrideReason, !reason.isEmpty {
            payload["overrideReason"] = reason
        }
        return try await callHotelCommand(name: "hotelAccommodationCommand", action: "set_accommodation_active", payload: payload)
    }

    // MARK: - Reservation Commands (hotelReservationCommand)
    @MainActor
    public func createReservation(
        branchId: String,
        customerUid: String,
        customerSnapshot: [String: Any],
        arrivalAt: Date,
        departureAt: Date,
        pets: [[String: Any]],
        emergencyContact: [String: String]? = nil,
        arrivalTransport: String = "customer_dropoff",
        departureTransport: String = "customer_pickup",
        depositMinor: Int = 0,
        notes: String? = nil,
        initialStatus: String = "confirmed"
    ) async throws -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "branchId": branchId,
            "customerUid": customerUid,
            "customerSnapshot": customerSnapshot,
            "arrivalAt": formatter.string(from: arrivalAt),
            "departureAt": formatter.string(from: departureAt),
            "pets": pets,
            "arrivalTransport": arrivalTransport,
            "departureTransport": departureTransport,
            "depositMinor": depositMinor,
            "initialStatus": initialStatus
        ]
        if let contact = emergencyContact {
            payload["emergencyContact"] = contact
        }
        if let notes, !notes.isEmpty {
            payload["notes"] = notes
        }
        return try await callHotelCommand(name: "hotelReservationCommand", action: "create_reservation", payload: payload)
    }

    @MainActor
    public func extendReservation(
        reservationId: String,
        newDepartureAt: Date,
        reasonCode: String = "operator_request",
        note: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "reservationId": reservationId,
            "newDepartureAt": ISO8601DateFormatter().string(from: newDepartureAt),
            "reasonCode": reasonCode
        ]
        if let note, !note.isEmpty {
            payload["note"] = note
        }
        return try await callHotelCommand(name: "hotelReservationCommand", action: "extend_reservation", payload: payload)
    }

    @MainActor
    public func transitionReservation(
        action: String,
        reservationId: String,
        reasonCode: String? = nil,
        note: String? = nil,
        overrideReason: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = ["reservationId": reservationId]
        if let reasonCode, !reasonCode.isEmpty {
            payload["reasonCode"] = reasonCode
        }
        if let note, !note.isEmpty {
            payload["note"] = note
        }
        if let overrideReason, !overrideReason.isEmpty {
            payload["overrideReason"] = overrideReason
        }
        return try await callHotelCommand(name: "hotelReservationCommand", action: action, payload: payload)
    }

    @MainActor
    public func createCustomerPetProfile(
        customerUid: String,
        name: String,
        categoryId: Int,
        categoryName: String,
        breed: String? = nil,
        ageInMonths: Int = 0
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "customerUid": customerUid,
            "name": name,
            "categoryId": categoryId,
            "categoryName": categoryName,
            "ageInMonths": ageInMonths
        ]
        if let breed, !breed.isEmpty {
            payload["breed"] = breed
        }
        return try await callHotelCommand(name: "hotelReservationCommand", action: "create_customer_pet", payload: payload)
    }

    @MainActor
    public func confirmReservation(reservationId: String, overrideReason: String? = nil) async throws -> [String: Any] {
        var payload: [String: Any] = ["reservationId": reservationId]
        if let reason = overrideReason, !reason.isEmpty {
            payload["overrideReason"] = reason
        }
        return try await callHotelCommand(name: "hotelReservationCommand", action: "confirm_reservation", payload: payload)
    }

    @MainActor
    public func cancelReservation(
        reservationId: String,
        reasonCode: String = "customer_request",
        note: String? = nil,
        overrideReason: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "reservationId": reservationId,
            "reasonCode": reasonCode
        ]
        if let note = note, !note.isEmpty {
            payload["note"] = note
        }
        if let reason = overrideReason, !reason.isEmpty {
            payload["overrideReason"] = reason
        }
        return try await callHotelCommand(name: "hotelReservationCommand", action: "cancel_reservation", payload: payload)
    }

    @MainActor
    public func markReadyForCheckin(reservationId: String) async throws -> [String: Any] {
        return try await callHotelCommand(name: "hotelReservationCommand", action: "mark_ready_for_checkin", payload: ["reservationId": reservationId])
    }

    @MainActor
    public func markPreArrival(reservationId: String) async throws -> [String: Any] {
        return try await callHotelCommand(name: "hotelReservationCommand", action: "mark_pre_arrival", payload: ["reservationId": reservationId])
    }

    @MainActor
    public func completeReservation(reservationId: String, overrideReason: String? = nil) async throws -> [String: Any] {
        var payload: [String: Any] = ["reservationId": reservationId]
        if let reason = overrideReason, !reason.isEmpty {
            payload["overrideReason"] = reason
        }
        return try await callHotelCommand(name: "hotelReservationCommand", action: "complete_reservation", payload: payload)
    }

    // MARK: - Care Commands (hotelCareCommand)
    @MainActor
    public func transitionCareTask(
        action: String, // "start_task" | "complete_task" | "skip_task" | "fail_task"
        stayId: String,
        taskId: String,
        completionNotes: String? = nil,
        reason: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "taskId": taskId
        ]
        if let notes = completionNotes, !notes.isEmpty {
            payload["completionNotes"] = notes
        }
        if let reason = reason, !reason.isEmpty {
            payload["reason"] = reason
        }
        return try await callHotelCommand(name: "hotelCareCommand", action: action, payload: payload)
    }

    @MainActor
    public func recordHealthObservation(
        stayId: String,
        observation: [String: Any]
    ) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "stayId": stayId,
            "observation": observation
        ]
        return try await callHotelCommand(name: "hotelCareCommand", action: "record_health_observation", payload: payload)
    }

    // MARK: - Billing Commands (hotelBillingCommand)
    @MainActor
    public func addStayCharge(
        stayId: String,
        chargeType: String,
        description: String,
        amountMinor: Int,
        quantity: Int = 1,
        unitAmountMinor: Int? = nil,
        notes: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "chargeType": chargeType,
            "description": description,
            "amountMinor": amountMinor,
            "quantity": quantity
        ]
        if let unit = unitAmountMinor {
            payload["unitAmountMinor"] = unit
        }
        if let note = notes, !note.isEmpty {
            payload["notes"] = note
        }
        return try await callHotelCommand(name: "hotelBillingCommand", action: "add_charge", payload: payload)
    }

    @MainActor
    public func recordStaySettlement(
        stayId: String,
        method: String,
        amountMinor: Int,
        reference: String? = nil,
        notes: String? = nil
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "stayId": stayId,
            "method": method,
            "amountMinor": amountMinor
        ]
        if let ref = reference, !ref.isEmpty {
            payload["reference"] = ref
        }
        if let note = notes, !note.isEmpty {
            payload["notes"] = note
        }
        return try await callHotelCommand(name: "hotelBillingCommand", action: "record_payment", payload: payload)
    }

    // MARK: - Operational Read Projections (hotelReadOperations)
    @MainActor
    public func fetchCommandCenter(branchId: String, now: Date = Date()) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "branchId": branchId,
            "now": ISO8601DateFormatter().string(from: now)
        ]
        return try await callHotelRead(view: "command_center", payload: payload)
    }

    @MainActor
    public func fetchAvailability(
        branchId: String,
        arrivalAt: Date,
        departureAt: Date,
        species: String,
        accommodationTypeId: String? = nil
    ) async throws -> [[String: Any]] {
        var payload: [String: Any] = [
            "branchId": branchId,
            "arrivalAt": ISO8601DateFormatter().string(from: arrivalAt),
            "departureAt": ISO8601DateFormatter().string(from: departureAt),
            "species": species
        ]
        if let accommodationTypeId, !accommodationTypeId.isEmpty {
            payload["accommodationTypeId"] = accommodationTypeId
        }
        let result = try await callHotelRead(view: "availability", payload: payload)
        return result["units"] as? [[String: Any]] ?? []
    }

    @MainActor
    public func fetchOperationalStays(branchId: String, inHouseOnly: Bool = false, limit: Int = 200) async throws -> [[String: Any]] {
        let payload: [String: Any] = [
            "branchId": branchId,
            "inHouseOnly": inHouseOnly,
            "limit": limit
        ]
        let result = try await callHotelRead(view: "operational_stays", payload: payload)
        return (result["stays"] as? [[String: Any]]) ?? []
    }

    @MainActor
    public func fetchReservationOperations(branchId: String, limit: Int = 100) async throws -> [[String: Any]] {
        let payload: [String: Any] = [
            "branchId": branchId,
            "limit": limit
        ]
        let result = try await callHotelRead(view: "reservation_operations", payload: payload)
        return (result["reservations"] as? [[String: Any]]) ?? []
    }

    @MainActor
    public func fetchStayOperationalSummary(branchId: String, stayId: String, limit: Int = 80) async throws -> [String: Any] {
        let payload: [String: Any] = [
            "branchId": branchId,
            "stayId": stayId,
            "limit": limit
        ]
        return try await callHotelRead(view: "stay_operational_summary", payload: payload)
    }

    @MainActor
    public func fetchCareOperations(branchId: String, rangeStart: Date? = nil, rangeEnd: Date? = nil) async throws -> [String: Any] {
        var payload: [String: Any] = ["branchId": branchId]
        let formatter = ISO8601DateFormatter()
        if let start = rangeStart {
            payload["rangeStart"] = formatter.string(from: start)
        }
        if let end = rangeEnd {
            payload["rangeEnd"] = formatter.string(from: end)
        }
        return try await callHotelRead(view: "care_operations", payload: payload)
    }
}
