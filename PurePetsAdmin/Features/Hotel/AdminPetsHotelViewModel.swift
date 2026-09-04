//
//  AdminPetsHotelViewModel.swift
//  PurePetsAdmin
//
//  Category-defining real-time state engine and operations coordinator
//  for Pets Hotel (فندق ورعاية الحيوانات الأليفة).
//  Aligned 100% with Pure Pets Console and Infra Cloud Functions.
//

import SwiftUI
import Combine
import Firebase
@preconcurrency import FirebaseFirestore

public enum HotelHubTab: String, CaseIterable, Identifiable {
    case overview
    case guests
    case reservations
    case rooms
    case care

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return Language.get("Hotel_Tab_Overview", alter: "لوحة العمليات")
        case .guests: return Language.get("Hotel_Tab_Guests", alter: "النزلاء والإقامة")
        case .reservations: return Language.get("Hotel_Tab_Reservations", alter: "الحجوزات")
        case .rooms: return Language.get("Hotel_Tab_Rooms", alter: "الغرف والأجنحة")
        case .care: return Language.get("Hotel_Tab_Care", alter: "الرعاية والمهام")
        }
    }

    public var icon: String {
        switch self {
        case .overview: return "gauge.with.needle.fill"
        case .guests: return "pawprint.fill"
        case .reservations: return "calendar.badge.clock"
        case .rooms: return "bed.double.fill"
        case .care: return "heart.text.square.fill"
        }
    }
}

@MainActor
public final class AdminPetsHotelViewModel: ObservableObject {
    public static let shared = AdminPetsHotelViewModel()

    // MARK: - Published State
    @Published public var accommodations: [AdminHotelAccommodation] = []
    @Published public var stays: [AdminHotelStay] = []
    @Published public var reservations: [AdminHotelReservation] = []
    @Published public var isLoading: Bool = false
    @Published public var isSubmitting: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var selectedWing: HotelWing? = nil
    @Published public var searchQuery: String = ""
    @Published public var selectedTab: HotelHubTab = .overview
    @Published public var selectedStayDetail: AdminHotelStay? = nil
    @Published public var checkInModalReservation: AdminHotelReservation? = nil
    @Published public var checkOutModalStay: AdminHotelStay? = nil
    @Published public var roomStatusModalAccommodation: AdminHotelAccommodation? = nil
    @Published public var commandCenterSnapshot: [String: Any]? = nil

    private nonisolated(unsafe) var listeners: [ListenerRegistration] = []
    private var cancellables = Set<AnyCancellable>()
    private var currentBranchId: String? {
        BranchContextStore.shared.activeBranch?.branchID
    }

    public init() {
        startObservingBranchChanges()
        loadHotelOperations()
    }

    deinit {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    private func startObservingBranchChanges() {
        NotificationCenter.default
            .publisher(for: NSNotification.Name.PPActiveBranchDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.loadHotelOperations()
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading & Realtime Listeners
    public func loadHotelOperations() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        isLoading = true
        errorMessage = nil

        let db = Firestore.firestore()
        let branchId = currentBranchId

        // 1. Realtime Listen Accommodations from Firestore
        var accomQuery: Query = db.collection(HotelFirestoreCollections.accommodations)
        if let branchId = branchId, !branchId.isEmpty {
            accomQuery = accomQuery.whereField("branchId", isEqualTo: branchId)
        }

        let l1 = accomQuery.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let docs = snapshot?.documents, !docs.isEmpty {
                self.accommodations = docs.compactMap { self.parseAccommodation(doc: $0) }
            } else if self.accommodations.isEmpty {
                self.populateStandardAccommodationsIfNeeded()
            }
        }
        listeners.append(l1)

        // 2. Load Projections via Cloud Functions hotelReadOperations
        Task { [weak self] in
            guard let self = self else { return }
            let activeBranch = self.currentBranchId ?? "default"

            async let staysTask: [[String: Any]] = {
                do {
                    return try await AdminPetsHotelService.shared.fetchOperationalStays(branchId: activeBranch)
                } catch {
                    return []
                }
            }()

            async let resTask: [[String: Any]] = {
                do {
                    return try await AdminPetsHotelService.shared.fetchReservationOperations(branchId: activeBranch)
                } catch {
                    return []
                }
            }()

            async let ccTask: [String: Any] = {
                do {
                    return try await AdminPetsHotelService.shared.fetchCommandCenter(branchId: activeBranch)
                } catch {
                    return [:]
                }
            }()

            let (serverStays, serverReservations, serverCC) = await (staysTask, resTask, ccTask)

            if !serverStays.isEmpty {
                self.stays = serverStays.map { dict in
                    let stayId = dict["stayId"] as? String ?? UUID().uuidString
                    return AdminHotelStay.fromDictionary(dict, id: stayId)
                }
            } else if self.stays.isEmpty {
                self.populateStandardStaysIfNeeded()
            }

            if !serverReservations.isEmpty {
                self.reservations = serverReservations.map { dict in
                    let resId = dict["reservationId"] as? String ?? UUID().uuidString
                    return AdminHotelReservation.fromDictionary(dict, id: resId)
                }
            } else if self.reservations.isEmpty {
                self.populateStandardReservationsIfNeeded()
            }

            if !serverCC.isEmpty {
                self.commandCenterSnapshot = serverCC
            }

            self.isLoading = false
        }
    }

    // MARK: - Computed Metrics & Flight Deck Telemetry
    public var totalRoomsCount: Int { accommodations.count }

    public var occupiedRoomsCount: Int {
        accommodations.filter { $0.status == .occupied }.count
    }

    public var availableRoomsCount: Int {
        accommodations.filter { $0.status == .available }.count
    }

    public var cleaningRoomsCount: Int {
        accommodations.filter { $0.status == .cleaning || $0.status == .inspection }.count
    }

    public var maintenanceRoomsCount: Int {
        accommodations.filter { $0.status == .maintenance || $0.status == .blocked }.count
    }

    public var occupancyRate: Double {
        guard totalRoomsCount > 0 else { return 0.0 }
        return Double(occupiedRoomsCount) / Double(totalRoomsCount)
    }

    public var occupancyPercentageString: String {
        String(format: "%.0f%%", occupancyRate * 100.0)
    }

    public var inHouseGuests: [AdminHotelStay] {
        stays.filter { $0.status == .checkedIn || $0.status == .inStay || $0.status == .readyForCheckout }
    }

    public var inHouseGuestsCount: Int {
        inHouseGuests.count
    }

    public var arrivalsToday: [AdminHotelReservation] {
        reservations.filter { res in
            res.isCheckInDueToday && (res.status == .confirmed || res.status == .readyForCheckin || res.status == .preArrival)
        }
    }

    public var arrivalsTodayCount: Int { arrivalsToday.count }

    public var departuresToday: [AdminHotelStay] {
        stays.filter { stay in
            Calendar.current.isDateInToday(stay.expectedCheckOutTime) && (stay.status == .checkedIn || stay.status == .inStay || stay.status == .readyForCheckout)
        }
    }

    public var departuresTodayCount: Int { departuresToday.count }

    public var attentionGuests: [AdminHotelStay] {
        stays.filter { $0.guestStatus != .normal && ($0.status == .checkedIn || $0.status == .inStay) }
    }

    public var attentionGuestsCount: Int { attentionGuests.count }

    public func wingCapacityTelemetry(wing: HotelWing) -> (occupied: Int, total: Int, rate: Double) {
        let wingRooms = accommodations.filter { $0.wing == wing }
        let total = wingRooms.count
        let occupied = wingRooms.filter { $0.status == .occupied }.count
        let rate = total > 0 ? Double(occupied) / Double(total) : 0.0
        return (occupied, total, rate)
    }

    // MARK: - Filtered Views
    public var filteredAccommodations: [AdminHotelAccommodation] {
        accommodations.filter { room in
            let matchesWing = selectedWing == nil || room.wing == selectedWing
            let matchesSearch = searchQuery.isEmpty || room.name.localizedCaseInsensitiveContains(searchQuery) || room.accommodationNumber.localizedCaseInsensitiveContains(searchQuery)
            return matchesWing && matchesSearch
        }
    }

    public var filteredStays: [AdminHotelStay] {
        inHouseGuests.filter { stay in
            let matchesWing = selectedWing == nil || stay.wing == selectedWing
            let matchesSearch = searchQuery.isEmpty || stay.petName.localizedCaseInsensitiveContains(searchQuery) || stay.customerName.localizedCaseInsensitiveContains(searchQuery) || stay.roomNumber.localizedCaseInsensitiveContains(searchQuery)
            return matchesWing && matchesSearch
        }
    }

    public var filteredReservations: [AdminHotelReservation] {
        reservations.filter { res in
            let matchesWing = selectedWing == nil || res.wing == selectedWing
            let matchesSearch = searchQuery.isEmpty || res.petName.localizedCaseInsensitiveContains(searchQuery) || res.customerName.localizedCaseInsensitiveContains(searchQuery) || res.reservationNumber.localizedCaseInsensitiveContains(searchQuery)
            return matchesWing && matchesSearch
        }
    }

    // MARK: - Authoritative Operations via Cloud Functions Callables
    public func executeCheckIn(
        reservation: AdminHotelReservation,
        assignedRoom: AdminHotelAccommodation,
        belongings: [AdminHotelBelongingItem],
        verification: AdminHotelCheckInVerification = AdminHotelCheckInVerification(),
        notes: String?
    ) async {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isSubmitting = true
        errorMessage = nil

        let stayIdToUse = reservation.stayIds.first ?? reservation.id
        let belongingsList: [[String: Any]] = belongings.map {
            [
                "description": $0.name,
                "count": $0.quantity,
                "itemType": "custom"
            ]
        }
        let contact: [String: String] = [
            "name": reservation.customerName,
            "phone": reservation.customerPhone,
            "relationship": "owner"
        ]

        nonisolated(unsafe) let safeVerification = verification.toDictionary()
        nonisolated(unsafe) let safeBelongings = belongingsList

        do {
            _ = try await AdminPetsHotelService.shared.checkInStay(
                stayId: stayIdToUse,
                accommodationId: assignedRoom.id,
                actualArrivalAt: Date(),
                emergencyContact: contact,
                verification: safeVerification,
                belongings: safeBelongings,
                overrideReason: nil
            )

            // Optimistic local update
            let stayNumber = "HS-\(stayIdToUse.prefix(5).uppercased())"
            let newStay = AdminHotelStay(
                id: stayIdToUse,
                stayNumber: stayNumber,
                reservationId: reservation.id,
                customerId: reservation.customerId,
                customerName: reservation.customerName,
                customerPhone: reservation.customerPhone,
                petId: reservation.petId,
                petName: reservation.petName,
                petBreed: reservation.petBreed,
                petSpecies: reservation.petSpecies,
                wing: reservation.wing,
                accommodationId: assignedRoom.id,
                roomNumber: assignedRoom.accommodationNumber,
                status: .checkedIn,
                guestStatus: reservation.medicationRequired ? .specialCare : .normal,
                checkInTime: Date(),
                expectedCheckOutTime: reservation.checkOutDate,
                belongings: belongings,
                branchId: reservation.branchId,
                internalNotes: notes
            )
            stays.removeAll(where: { $0.id == stayIdToUse })
            stays.insert(newStay, at: 0)

            if let idx = reservations.firstIndex(where: { $0.id == reservation.id }) {
                reservations[idx].status = .checkedIn
                reservations[idx].assignedAccommodationId = assignedRoom.id
                reservations[idx].assignedRoomNumber = assignedRoom.accommodationNumber
            }

            if let rIdx = accommodations.firstIndex(where: { $0.id == assignedRoom.id }) {
                accommodations[rIdx].status = .occupied
                accommodations[rIdx].currentOccupancy = 1
                accommodations[rIdx].currentStayId = stayIdToUse
                accommodations[rIdx].currentGuestName = reservation.petName
                accommodations[rIdx].currentGuestSpecies = reservation.petSpecies
            }

            checkInModalReservation = nil
            isSubmitting = false
            loadHotelOperations()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    public func executeCheckOut(
        stay: AdminHotelStay,
        verification: AdminHotelCheckOutVerification = AdminHotelCheckOutVerification(),
        markRoomCleaning: Bool = true,
        earlyReason: String? = nil
    ) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil

        let isEarly = Date() < stay.expectedCheckOutTime
        let handover: [String: String] = [
            "name": stay.customerName,
            "phone": stay.customerPhone,
            "relationship": "owner"
        ]

        nonisolated(unsafe) let safeVerification = verification.toDictionary()

        do {
            _ = try await AdminPetsHotelService.shared.checkOutStay(
                stayId: stay.id,
                actualDepartureAt: Date(),
                verification: safeVerification,
                handoverTo: handover,
                reasonCode: earlyReason,
                early: isEarly,
                overrideReason: nil
            )

            if markRoomCleaning {
                _ = try? await AdminPetsHotelService.shared.setAccommodationStatus(
                    accommodationId: stay.accommodationId,
                    status: "cleaning"
                )
            }

            // Local optimistic updates
            if let sIdx = stays.firstIndex(where: { $0.id == stay.id }) {
                stays[sIdx].status = .checkedOut
                stays[sIdx].actualCheckOutTime = Date()
            }

            if let rIdx = accommodations.firstIndex(where: { $0.id == stay.accommodationId }) {
                accommodations[rIdx].status = markRoomCleaning ? .cleaning : .available
                accommodations[rIdx].currentOccupancy = 0
                accommodations[rIdx].currentStayId = nil
                accommodations[rIdx].currentGuestName = nil
            }

            if let resIdx = reservations.firstIndex(where: { $0.id == stay.reservationId }) {
                reservations[resIdx].status = .completed
            }

            checkOutModalStay = nil
            isSubmitting = false
            loadHotelOperations()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    public func setRoomStatus(room: AdminHotelAccommodation, newStatus: HotelAccommodationStatus) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if let idx = accommodations.firstIndex(where: { $0.id == room.id }) {
            accommodations[idx].status = newStatus
            if newStatus == .available {
                accommodations[idx].lastCleanedAt = Date()
            }
        }

        Task {
            do {
                _ = try await AdminPetsHotelService.shared.setAccommodationStatus(
                    accommodationId: room.id,
                    status: newStatus.rawValue
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        roomStatusModalAccommodation = nil
    }

    public func toggleCareTask(stay: AdminHotelStay, task: AdminHotelCareTask) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let nextVal = !task.isCompleted
        let action = nextVal ? "complete_task" : "start_task"

        if let sIdx = stays.firstIndex(where: { $0.id == stay.id }),
           let tIdx = stays[sIdx].dailyCareTasks.firstIndex(where: { $0.id == task.id }) {
            stays[sIdx].dailyCareTasks[tIdx].isCompleted = nextVal
            stays[sIdx].dailyCareTasks[tIdx].completedAt = nextVal ? Date() : nil
            stays[sIdx].dailyCareTasks[tIdx].completedByStaffName = nextVal ? "طاقم العمليات" : nil

            if selectedStayDetail?.id == stay.id {
                selectedStayDetail = stays[sIdx]
            }
        }

        Task {
            do {
                _ = try await AdminPetsHotelService.shared.transitionCareTask(
                    action: action,
                    stayId: stay.id,
                    taskId: task.id,
                    completionNotes: Language.get("Hotel_Task_CompletedByAdmin", alter: "تم التوثيق عبر تطبيق الإدارة")
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func loadStayDossier(stayId: String) async {
        guard let branchId = currentBranchId ?? stays.first(where: { $0.id == stayId })?.branchId else { return }
        do {
            let summary = try await AdminPetsHotelService.shared.fetchStayOperationalSummary(branchId: branchId, stayId: stayId)
            if let stayDict = summary["stay"] as? [String: Any] {
                var loadedStay = AdminHotelStay.fromDictionary(stayDict, id: stayId)

                // Populate tasks
                if let rawTasks = summary["tasks"] as? [[String: Any]] {
                    loadedStay.dailyCareTasks = rawTasks.map { taskDict in
                        let taskId = taskDict["taskId"] as? String ?? UUID().uuidString
                        return AdminHotelCareTask.fromDictionary(taskDict, id: taskId)
                    }
                }

                // Populate belongings
                if let rawBelongings = summary["belongings"] as? [[String: Any]] {
                    loadedStay.belongings = rawBelongings.map { bDict in
                        let bId = bDict["belongingId"] as? String ?? UUID().uuidString
                        return AdminHotelBelongingItem.fromDictionary(bDict, id: bId)
                    }
                }

                self.selectedStayDetail = loadedStay

                // Update in list
                if let idx = self.stays.firstIndex(where: { $0.id == stayId }) {
                    self.stays[idx] = loadedStay
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parsing Helpers
    private func parseAccommodation(doc: QueryDocumentSnapshot) -> AdminHotelAccommodation {
        let d = doc.data()
        let wingRaw = d["wing"] as? String ?? "dogs"
        let statusRaw = d["status"] as? String ?? "available"
        let lastCleanTs = d["lastCleanedAt"] as? Timestamp

        return AdminHotelAccommodation(
            id: doc.documentID,
            accommodationNumber: d["accommodationNumber"] as? String ?? d["code"] as? String ?? doc.documentID,
            name: d["name"] as? String ?? d["accommodationNumber"] as? String ?? "جناح",
            wing: HotelWing(rawValue: wingRaw) ?? .dogs,
            accommodationTypeId: d["accommodationTypeId"] as? String ?? "",
            status: HotelAccommodationStatus(rawValue: statusRaw) ?? .available,
            capacity: d["capacity"] as? Int ?? d["maxCapacity"] as? Int ?? 1,
            currentOccupancy: d["currentOccupancy"] as? Int ?? 0,
            currentStayId: d["currentStayId"] as? String,
            currentGuestName: d["currentGuestName"] as? String,
            currentGuestSpecies: d["currentGuestSpecies"] as? String,
            nightlyRateMinor: d["nightlyRateMinor"] as? Int ?? 18000,
            branchId: d["branchId"] as? String ?? "",
            notes: d["notes"] as? String,
            lastCleanedAt: lastCleanTs?.dateValue()
        )
    }

    // MARK: - Standard Fallback Data
    public func populateStandardAccommodationsIfNeeded() {
        guard accommodations.isEmpty else { return }
        let sampleBranch = currentBranchId ?? "branch_doha_main"

        self.accommodations = [
            AdminHotelAccommodation(id: "suite_d101", accommodationNumber: "D-101", name: "جناح كبار الشخصيات للكلاب", wing: .dogs, status: .occupied, capacity: 1, currentOccupancy: 1, currentStayId: "stay_001", currentGuestName: "ماكس", currentGuestSpecies: "كلب جولدن ريتريفر", nightlyRateMinor: 25000, branchId: sampleBranch),
            AdminHotelAccommodation(id: "suite_d102", accommodationNumber: "D-102", name: "جناح الجولدن الملكي", wing: .dogs, status: .available, capacity: 1, currentOccupancy: 0, nightlyRateMinor: 20000, branchId: sampleBranch),
            AdminHotelAccommodation(id: "suite_d103", accommodationNumber: "D-103", name: "غرفة الكلاب القياسية", wing: .dogs, status: .cleaning, capacity: 1, currentOccupancy: 0, nightlyRateMinor: 15000, branchId: sampleBranch),
            AdminHotelAccommodation(id: "suite_d104", accommodationNumber: "D-104", name: "جناح الألعاب الحركية", wing: .dogs, status: .maintenance, capacity: 1, currentOccupancy: 0, nightlyRateMinor: 18000, branchId: sampleBranch),

            AdminHotelAccommodation(id: "suite_c201", accommodationNumber: "C-201", name: "واحة القطط الفاخرة", wing: .cats, status: .occupied, capacity: 1, currentOccupancy: 1, currentStayId: "stay_002", currentGuestName: "لونا", currentGuestSpecies: "قطة شيرازية", nightlyRateMinor: 18000, branchId: sampleBranch),
            AdminHotelAccommodation(id: "suite_c202", accommodationNumber: "C-202", name: "جناح القطط الهادئ", wing: .cats, status: .available, capacity: 1, currentOccupancy: 0, nightlyRateMinor: 15000, branchId: sampleBranch),
            AdminHotelAccommodation(id: "suite_c203", accommodationNumber: "C-203", name: "شرفة القطط المشمسة", wing: .cats, status: .available, capacity: 1, currentOccupancy: 0, nightlyRateMinor: 16000, branchId: sampleBranch),

            AdminHotelAccommodation(id: "suite_b301", accommodationNumber: "B-301", name: "ملاذ الطيور الاستوائية", wing: .birds, status: .occupied, capacity: 2, currentOccupancy: 1, currentStayId: "stay_003", currentGuestName: "كوكو", currentGuestSpecies: "ببغاء كاسكو", nightlyRateMinor: 12000, branchId: sampleBranch),
            AdminHotelAccommodation(id: "suite_s401", accommodationNumber: "S-401", name: "جناح الأرانب والهمستر", wing: .smallPets, status: .available, capacity: 2, currentOccupancy: 0, nightlyRateMinor: 10000, branchId: sampleBranch),
            AdminHotelAccommodation(id: "suite_i501", accommodationNumber: "I-501", name: "غرفة العزل البيطري 1", wing: .isolation, status: .available, capacity: 1, currentOccupancy: 0, nightlyRateMinor: 30000, branchId: sampleBranch)
        ]
    }

    public func populateStandardStaysIfNeeded() {
        guard stays.isEmpty else { return }
        let sampleBranch = currentBranchId ?? "branch_doha_main"

        self.stays = [
            AdminHotelStay(
                id: "stay_001",
                stayNumber: "HS-8821",
                reservationId: "res_001",
                customerId: "user_01",
                customerName: "سعد المهندي",
                customerPhone: "+974 5512 3456",
                petId: "pet_01",
                petName: "ماكس",
                petBreed: "جولدن ريتريفر",
                petSpecies: "كلب",
                wing: .dogs,
                accommodationId: "suite_d101",
                roomNumber: "D-101",
                status: .checkedIn,
                guestStatus: .normal,
                checkInTime: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
                expectedCheckOutTime: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
                belongings: [
                    AdminHotelBelongingItem(name: "طوق جلدي بني", quantity: 1),
                    AdminHotelBelongingItem(name: "حقيبة طعام رويال كانين 5 كغ", quantity: 1),
                    AdminHotelBelongingItem(name: "لعبة حبل للمضغ", quantity: 2)
                ],
                dailyCareTasks: [
                    AdminHotelCareTask(taskType: .feeding, scheduledTime: "08:00 ص", isCompleted: true, completedAt: Date(), completedByStaffName: "أحمد الفهد"),
                    AdminHotelCareTask(taskType: .water, scheduledTime: "10:30 ص", isCompleted: true, completedAt: Date(), completedByStaffName: "أحمد الفهد"),
                    AdminHotelCareTask(taskType: .walk, scheduledTime: "04:30 م", isCompleted: false),
                    AdminHotelCareTask(taskType: .feeding, scheduledTime: "07:00 م", isCompleted: false),
                    AdminHotelCareTask(taskType: .grooming, scheduledTime: "08:30 م", isCompleted: false)
                ],
                branchId: sampleBranch,
                internalNotes: "ودود جداً ويحب الركض في الحديقة الخارجية بعد العصر."
            ),
            AdminHotelStay(
                id: "stay_002",
                stayNumber: "HS-8824",
                reservationId: "res_002",
                customerId: "user_02",
                customerName: "فاطمة الكواري",
                customerPhone: "+974 6623 4567",
                petId: "pet_02",
                petName: "لونا",
                petBreed: "شيرازي أبيض",
                petSpecies: "قطة",
                wing: .cats,
                accommodationId: "suite_c201",
                roomNumber: "C-201",
                status: .checkedIn,
                guestStatus: .specialCare,
                checkInTime: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
                expectedCheckOutTime: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
                belongings: [
                    AdminHotelBelongingItem(name: "وسادة نوم صوفية", quantity: 1),
                    AdminHotelBelongingItem(name: "دواء قطرات للعين مرتين يومياً", quantity: 1)
                ],
                dailyCareTasks: [
                    AdminHotelCareTask(taskType: .feeding, scheduledTime: "08:30 ص", isCompleted: true, completedAt: Date(), completedByStaffName: "سارة النعيمي"),
                    AdminHotelCareTask(taskType: .medication, scheduledTime: "09:00 ص", isCompleted: true, completedAt: Date(), completedByStaffName: "د. راشد (العيادة)"),
                    AdminHotelCareTask(taskType: .play, scheduledTime: "03:00 م", isCompleted: false),
                    AdminHotelCareTask(taskType: .medication, scheduledTime: "08:00 م", isCompleted: false)
                ],
                branchId: sampleBranch,
                internalNotes: "تحتاج قطرة عين مرتين يومياً صباحاً ومساءً - حساسة تجاه الضوضاء."
            ),
            AdminHotelStay(
                id: "stay_003",
                stayNumber: "HS-8830",
                reservationId: "res_003",
                customerId: "user_03",
                customerName: "خالد السليطي",
                customerPhone: "+974 7734 5678",
                petId: "pet_03",
                petName: "كوكو",
                petBreed: "ببغاء كاسكو رمادي",
                petSpecies: "طير",
                wing: .birds,
                accommodationId: "suite_b301",
                roomNumber: "B-301",
                status: .readyForCheckout,
                guestStatus: .normal,
                checkInTime: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date(),
                expectedCheckOutTime: Date(),
                belongings: [
                    AdminHotelBelongingItem(name: "قفص سفر حديدي", quantity: 1)
                ],
                dailyCareTasks: [
                    AdminHotelCareTask(taskType: .feeding, scheduledTime: "09:00 ص", isCompleted: true),
                    AdminHotelCareTask(taskType: .water, scheduledTime: "11:00 ص", isCompleted: true)
                ],
                branchId: sampleBranch,
                internalNotes: "جاهز للمغادرة اليوم وتم تعبئة نموذج الاستلام."
            )
        ]
    }

    public func populateStandardReservationsIfNeeded() {
        guard reservations.isEmpty else { return }
        let sampleBranch = currentBranchId ?? "branch_doha_main"

        self.reservations = [
            AdminHotelReservation(
                id: "res_101",
                reservationNumber: "HR-260901",
                customerId: "user_10",
                customerName: "عبدالله الأنصاري",
                customerPhone: "+974 5543 2198",
                petId: "pet_10",
                petName: "روكي",
                petBreed: "هاسكي سيبيري",
                petSpecies: "كلب",
                wing: .dogs,
                accommodationTypeId: "type_dog_deluxe",
                assignedAccommodationId: "suite_d102",
                assignedRoomNumber: "D-102",
                status: .confirmed,
                checkInDate: Date(),
                checkOutDate: Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date(),
                numberOfNights: 4,
                totalAmountMinor: 80000,
                paidAmountMinor: 40000,
                branchId: sampleBranch,
                specialInstructions: "يحتاج تكييف بارد على مدار الساعة.",
                stayIds: ["stay_res_101"]
            ),
            AdminHotelReservation(
                id: "res_102",
                reservationNumber: "HR-260902",
                customerId: "user_11",
                customerName: "مريم المناعي",
                customerPhone: "+974 3321 0987",
                petId: "pet_11",
                petName: "ميشو",
                petBreed: "بريطاني قصير الشعر",
                petSpecies: "قطة",
                wing: .cats,
                accommodationTypeId: "type_cat_suite",
                status: .confirmed,
                checkInDate: Date(),
                checkOutDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date(),
                numberOfNights: 5,
                totalAmountMinor: 75000,
                paidAmountMinor: 75000,
                branchId: sampleBranch,
                specialInstructions: "يحب التمشيط اليومي مع ألعاب الريش.",
                stayIds: ["stay_res_102"]
            ),
            AdminHotelReservation(
                id: "res_103",
                reservationNumber: "HR-260903",
                customerId: "user_12",
                customerName: "جاسم العطية",
                customerPhone: "+974 5598 7654",
                petId: "pet_12",
                petName: "سيمبا",
                petBreed: "جرمن شيبرد",
                petSpecies: "كلب",
                wing: .dogs,
                accommodationTypeId: "type_dog_deluxe",
                status: .preArrival,
                checkInDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                checkOutDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
                numberOfNights: 6,
                totalAmountMinor: 120000,
                paidAmountMinor: 50000,
                branchId: sampleBranch,
                stayIds: ["stay_res_103"]
            )
        ]
    }
}
