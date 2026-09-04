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
    @Published public var accommodationTypes: [AdminHotelAccommodationType] = []
    @Published public var stays: [AdminHotelStay] = []
    @Published public var reservations: [AdminHotelReservation] = []
    @Published public var isLoading: Bool = false
    @Published public var isSubmitting: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var selectedWing: HotelWing? = nil
    @Published public var searchQuery: String = ""
    @Published public var selectedTab: HotelHubTab = .overview
    @Published public var selectedStayDetail: AdminHotelStay? = nil
    @Published public var selectedReservationDetail: AdminHotelReservation? = nil
    @Published public var newReservationModalOpen: Bool = false
    @Published public var suiteEditorModalAccommodation: AdminHotelAccommodation? = nil
    @Published public var isCreatingNewSuite: Bool = false
    @Published public var typeEditorModalType: AdminHotelAccommodationType? = nil
    @Published public var isCreatingNewType: Bool = false
    @Published public var reservationStatusFilter: String = "all"
    @Published public var roomStatusFilter: String = "all"
    @Published public var roomViewMode: RoomViewMode = .grid
    @Published public var checkInModalReservation: AdminHotelReservation? = nil
    @Published public var checkOutModalStay: AdminHotelStay? = nil
    @Published public var roomStatusModalAccommodation: AdminHotelAccommodation? = nil
    @Published public var commandCenterSnapshot: [String: Any]? = nil
    @Published public private(set) var requiresBranchSelection = false
    @Published public private(set) var canViewHotel = false
    @Published public private(set) var canCheckIn = false
    @Published public private(set) var canCheckOut = false
    @Published public private(set) var canManageAccommodations = false
    @Published public private(set) var canViewCare = false
    @Published public private(set) var canExecuteCareTasks = false
    @Published public private(set) var canViewBilling = false

    public enum RoomViewMode: String, CaseIterable, Identifiable {
        case grid = "grid"
        case list = "list"
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .grid: return Language.get("Hotel_View_Grid", alter: "شبكة الأجنحة")
            case .list: return Language.get("Hotel_View_List", alter: "قائمة تشغيلية")
            }
        }
        public var icon: String {
            switch self {
            case .grid: return "square.grid.2x2.fill"
            case .list: return "list.bullet.rectangle.portrait.fill"
            }
        }
    }

    private nonisolated(unsafe) var accommodationListener: ListenerRegistration?
    private nonisolated(unsafe) var accommodationTypesListener: ListenerRegistration?
    private var cancellables = Set<AnyCancellable>()
    private var loadGeneration = UUID()
    private var dossierRequestID = UUID()
    private var loadedBranchId: String?
    private var loadErrors: [String: String] = [:]
    private var currentBranchId: String? {
        let branchId = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        return (branchId?.isEmpty == false) ? branchId : nil
    }

    public init() {
        startObservingBranchChanges()
        loadHotelOperations()
    }

    deinit {
        accommodationListener?.remove()
        accommodationTypesListener?.remove()
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
        accommodationListener?.remove()
        accommodationListener = nil
        accommodationTypesListener?.remove()
        accommodationTypesListener = nil
        refreshAccess()
        loadGeneration = UUID()
        let generation = loadGeneration
        loadErrors.removeAll()
        isLoading = true
        errorMessage = nil

        guard canViewHotel else {
            clearOperationalState()
            requiresBranchSelection = false
            isLoading = false
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return
        }

        guard let branchId = currentBranchId else {
            clearOperationalState()
            requiresBranchSelection = true
            isLoading = false
            errorMessage = Language.get("Hotel_Err_BranchRequired", alter: "اختر فرعاً لعرض عمليات الفندق.")
            return
        }

        requiresBranchSelection = false
        if loadedBranchId != branchId {
            clearOperationalState()
            loadedBranchId = branchId
        }

        accommodationListener = AdminPetsHotelService.shared.listenAccommodations(branchId: branchId) { [weak self] documents, error in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                if let error {
                    self.setLoadError(error, source: "accommodations")
                    self.isLoading = false
                    return
                }
                self.loadErrors.removeValue(forKey: "accommodations")
                self.accommodations = (documents ?? []).compactMap { self.parseAccommodation(doc: $0, expectedBranchId: branchId) }
                self.reconcileAccommodationMetadata()
                self.refreshLoadErrorMessage()
            }
        }

        accommodationTypesListener = AdminPetsHotelService.shared.listenAccommodationTypes(branchId: branchId) { [weak self] documents, error in
            Task { @MainActor [weak self] in
                guard let self, self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                if error != nil { return }
                self.accommodationTypes = (documents ?? []).compactMap { doc in
                    AdminHotelAccommodationType.fromDictionary(doc.data(), id: doc.documentID)
                }.sorted { $0.sortOrder < $1.sortOrder }
            }
        }

        // Sensitive and aggregate Hotel data is projection-only. Raw stays and
        // reservations remain inaccessible to Admin clients by design.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let serverStays = try await AdminPetsHotelService.shared.fetchOperationalStays(branchId: branchId)
                guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                self.stays = serverStays.compactMap { dict in
                    guard let stayId = self.validIdentifier(dict["stayId"]) else { return nil }
                    return AdminHotelStay.fromDictionary(dict, id: stayId)
                }
                self.loadErrors.removeValue(forKey: "stays")
            } catch {
                guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                self.stays = []
                self.setLoadError(error, source: "stays")
            }

            if self.canViewCare {
                do {
                    let careOperations = try await AdminPetsHotelService.shared.fetchCareOperations(branchId: branchId)
                    guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }

                    let rawTasks = careOperations["tasks"] as? [[String: Any]] ?? []
                    var tasksByStay: [String: [AdminHotelCareTask]] = [:]
                    for task in rawTasks {
                        guard let stayId = self.validIdentifier(task["stayId"]),
                              let taskId = self.validIdentifier(task["taskId"]) else {
                            continue
                        }
                        tasksByStay[stayId, default: []].append(
                            AdminHotelCareTask.fromDictionary(task, id: taskId)
                        )
                    }

                    self.stays = self.stays.map { stay in
                        var hydratedStay = stay
                        hydratedStay.dailyCareTasks = tasksByStay[stay.id] ?? []
                        return hydratedStay
                    }
                    self.loadErrors.removeValue(forKey: "care")
                } catch {
                    guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                    self.setLoadError(error, source: "care")
                }
            } else {
                self.loadErrors.removeValue(forKey: "care")
            }

            do {
                let serverReservations = try await AdminPetsHotelService.shared.fetchReservationOperations(branchId: branchId)
                guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                self.reservations = serverReservations.compactMap { dict in
                    guard let reservationId = self.validIdentifier(dict["reservationId"]) else { return nil }
                    return AdminHotelReservation.fromDictionary(dict, id: reservationId)
                }
                self.loadErrors.removeValue(forKey: "reservations")
            } catch {
                guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                self.reservations = []
                self.setLoadError(error, source: "reservations")
            }

            do {
                let snapshot = try await AdminPetsHotelService.shared.fetchCommandCenter(branchId: branchId)
                guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                self.commandCenterSnapshot = snapshot
                self.loadErrors.removeValue(forKey: "commandCenter")
            } catch {
                guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
                self.commandCenterSnapshot = nil
                self.setLoadError(error, source: "commandCenter")
            }

            guard self.loadGeneration == generation, self.currentBranchId == branchId else { return }
            self.reconcileAccommodationMetadata()
            self.refreshLoadErrorMessage()
            self.isLoading = false
        }
    }

    public var visibleTabs: [HotelHubTab] {
        HotelHubTab.allCases.filter { $0 != .care || canViewCare }
    }

    private func refreshAccess() {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isActive() else {
            canViewHotel = false
            canCheckIn = false
            canCheckOut = false
            canManageAccommodations = false
            canViewCare = false
            canExecuteCareTasks = false
            canViewBilling = false
            if selectedTab == .care {
                selectedTab = .overview
            }
            return
        }
        let branchId = currentBranchId
        let canManageHotel = staff.hasPermission("hotel.manage", inBranch: branchId)
        canViewHotel = staff.hasPermission(kStaffPermHotelView, inBranch: branchId) || canManageHotel
        canCheckIn = staff.hasPermission(kStaffPermHotelCheckIn, inBranch: branchId) || canManageHotel
        canCheckOut = staff.hasPermission(kStaffPermHotelCheckOut, inBranch: branchId) || staff.hasPermission(kStaffPermHotelCheckIn, inBranch: branchId) || canManageHotel
        canManageAccommodations = staff.hasPermission(kStaffPermHotelAccommodationsManage, inBranch: branchId) || canManageHotel
        canViewCare = staff.hasPermission(kStaffPermHotelCareView, inBranch: branchId) || canManageHotel || canViewHotel
        canExecuteCareTasks = staff.hasPermission(kStaffPermHotelTaskExecute, inBranch: branchId) || canManageHotel
        canViewBilling = staff.hasPermission(kStaffPermHotelBillingView, inBranch: branchId) || canManageHotel
        if !canViewCare, selectedTab == .care {
            selectedTab = .overview
        }
    }

    private func clearOperationalState() {
        accommodations = []
        accommodationTypes = []
        stays = []
        reservations = []
        commandCenterSnapshot = nil
        selectedStayDetail = nil
        selectedReservationDetail = nil
        checkInModalReservation = nil
        checkOutModalStay = nil
        roomStatusModalAccommodation = nil
        suiteEditorModalAccommodation = nil
        typeEditorModalType = nil
    }

    private func setLoadError(_ error: Error, source: String) {
        loadErrors[source] = error.localizedDescription
        refreshLoadErrorMessage()
    }

    private func refreshLoadErrorMessage() {
        errorMessage = loadErrors.keys.sorted().compactMap { loadErrors[$0] }.first
    }

    private func validIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            let matchesStatus: Bool = {
                switch roomStatusFilter {
                case "all": return true
                default: return room.status.rawValue == roomStatusFilter
                }
            }()
            let matchesSearch = searchQuery.isEmpty
                || room.name.localizedCaseInsensitiveContains(searchQuery)
                || room.accommodationNumber.localizedCaseInsensitiveContains(searchQuery)
                || (room.currentGuestName?.localizedCaseInsensitiveContains(searchQuery) == true)
            return matchesWing && matchesStatus && matchesSearch
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
            let matchesStatus: Bool = {
                switch reservationStatusFilter {
                case "all": return true
                case "pending": return res.status == .pendingConfirmation || res.status == .draft
                case "confirmed": return res.status == .confirmed || res.status == .preArrival || res.status == .readyForCheckin
                case "in_stay": return res.status == .checkedIn || res.status == .inStay || res.status == .readyForCheckout
                case "completed": return res.status == .completed || res.status == .checkedOut
                case "cancelled": return res.status == .cancelled || res.status == .rejected || res.status == .noShow
                default: return res.status.rawValue == reservationStatusFilter
                }
            }()
            let matchesSearch = searchQuery.isEmpty
                || res.petName.localizedCaseInsensitiveContains(searchQuery)
                || res.customerName.localizedCaseInsensitiveContains(searchQuery)
                || res.customerPhone.localizedCaseInsensitiveContains(searchQuery)
                || res.reservationNumber.localizedCaseInsensitiveContains(searchQuery)
            return matchesWing && matchesStatus && matchesSearch
        }
    }

    public func availableAccommodationIDs(for reservation: AdminHotelReservation) async throws -> Set<String> {
        guard let branchId = currentBranchId else {
            throw AdminPetsHotelError.operationFailed(
                Language.get("Hotel_Err_BranchRequired", alter: "اختر فرعاً لعرض عمليات الفندق.")
            )
        }
        let units = try await AdminPetsHotelService.shared.fetchAvailability(
            branchId: branchId,
            arrivalAt: reservation.checkInDate,
            departureAt: reservation.checkOutDate,
            species: reservation.petSpecies,
            accommodationTypeId: reservation.accommodationTypeId.isEmpty ? nil : reservation.accommodationTypeId
        )
        return Set(units.compactMap { unit in
            guard unit["assignable"] as? Bool == true else { return nil }
            return validIdentifier(unit["accommodationId"])
        })
    }

    // MARK: - Authoritative Operations via Cloud Functions Callables
    public func executeCheckIn(
        reservation: AdminHotelReservation,
        stay: AdminHotelStay,
        assignedRoom: AdminHotelAccommodation,
        belongings: [AdminHotelBelongingItem],
        verification: AdminHotelCheckInVerification = AdminHotelCheckInVerification(),
        notes: String?
    ) async {
        guard canCheckIn else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isSubmitting = true
        errorMessage = nil

        // A multi-pet reservation must submit the exact projected stay shown in
        // the sheet. Never pair independently ordered pet and stay arrays.
        guard !stay.id.isEmpty,
              reservation.stayIds.contains(stay.id),
              stay.reservationId == reservation.id,
              reservation.petId.isEmpty || stay.petId == reservation.petId else {
            isSubmitting = false
            errorMessage = Language.get("Hotel_Err_StayRequired", alter: "لا يوجد سجل إقامة جاهز لهذا الحجز.")
            return
        }
        let belongingsList: [[String: Any]] = belongings.map {
            [
                "description": $0.name,
                "quantity": $0.quantity,
                "itemType": "custom"
            ]
        }
        let contactName = reservation.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let contactPhone = reservation.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact: [String: String]? = {
            guard !contactName.isEmpty, !contactPhone.isEmpty else { return nil }
            return [
                "name": contactName,
                "phone": contactPhone,
                "relationship": "owner"
            ]
        }()

        var submittedVerification = verification
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedNotes.isEmpty {
            submittedVerification.behaviourNotes = trimmedNotes
        }
        nonisolated(unsafe) let safeVerification = submittedVerification.toDictionary()
        nonisolated(unsafe) let safeBelongings = belongingsList

        do {
            _ = try await AdminPetsHotelService.shared.checkInStay(
                stayId: stay.id,
                accommodationId: assignedRoom.id,
                actualArrivalAt: Date(),
                emergencyContact: contact,
                verification: safeVerification,
                belongings: safeBelongings,
                overrideReason: nil
            )

            checkInModalReservation = nil
            isSubmitting = false
            // Server projections are authoritative; never fabricate a local
            // stay number, status, or room occupancy after a command.
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
        earlyReason: String? = nil
    ) async {
        guard canCheckOut else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return
        }
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

            checkOutModalStay = nil
            isSubmitting = false
            // hotelStayCommand atomically checks out the stay, reconciles the
            // ledger, and releases the room to cleaning. No second room write.
            loadHotelOperations()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    public func setRoomStatus(room: AdminHotelAccommodation, newStatus: HotelAccommodationStatus) async -> Bool {
        guard canManageAccommodations else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.setAccommodationStatus(
                accommodationId: room.id,
                status: newStatus.rawValue
            )
            isSubmitting = false
            roomStatusModalAccommodation = nil
            loadHotelOperations()
            return true
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    public func saveAccommodation(
        accommodationId: String?,
        accommodationTypeId: String,
        code: String,
        name: String,
        wing: HotelWing,
        allowedSpecies: [String],
        maxCapacity: Int,
        allowSharedOccupancy: Bool,
        notes: String?,
        active: Bool
    ) async -> Bool {
        guard canManageAccommodations, let branchId = currentBranchId else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.saveAccommodation(
                branchId: branchId,
                accommodationId: accommodationId,
                accommodationTypeId: accommodationTypeId,
                code: code,
                name: name,
                wing: wing.rawValue,
                allowedSpecies: allowedSpecies,
                maxCapacity: maxCapacity,
                allowSharedOccupancy: allowSharedOccupancy,
                notes: notes,
                active: active
            )
            isSubmitting = false
            suiteEditorModalAccommodation = nil
            isCreatingNewSuite = false
            loadHotelOperations()
            return true
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    public func saveAccommodationType(
        typeId: String?,
        code: String,
        nameAr: String,
        nameEn: String,
        wing: HotelWing,
        allowedSpecies: [String],
        defaultCapacity: Int,
        nightlyRateMinor: Int,
        allowSharedOccupancy: Bool,
        description: String?,
        active: Bool
    ) async -> Bool {
        guard canManageAccommodations, let branchId = currentBranchId else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.saveAccommodationType(
                branchId: branchId,
                accommodationTypeId: typeId,
                code: code,
                nameAr: nameAr,
                nameEn: nameEn,
                wing: wing.rawValue,
                allowedSpecies: allowedSpecies,
                defaultCapacity: defaultCapacity,
                nightlyRateMinor: nightlyRateMinor,
                allowSharedOccupancy: allowSharedOccupancy,
                active: active,
                description: description
            )
            isSubmitting = false
            typeEditorModalType = nil
            isCreatingNewType = false
            loadHotelOperations()
            return true
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    public func toggleAccommodationActive(room: AdminHotelAccommodation) async {
        guard canManageAccommodations else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            _ = try await AdminPetsHotelService.shared.setAccommodationActive(
                accommodationId: room.id,
                active: !room.active
            )
            loadHotelOperations()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createReservation(
        customerUid: String,
        customerName: String,
        customerPhone: String,
        customerEmail: String?,
        pets: [AdminHotelPetDraft],
        wing: HotelWing,
        arrivalAt: Date,
        departureAt: Date,
        depositMinor: Int,
        emergencyName: String?,
        emergencyPhone: String?,
        notes: String?,
        confirmImmediately: Bool
    ) async -> Bool {
        guard let branchId = currentBranchId else { return false }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isSubmitting = true
        errorMessage = nil

        let petsPayload: [[String: Any]] = pets.map { draft in
            var petDict: [String: Any] = [
                "petId": draft.id,
                "petSnapshot": [
                    "name": draft.name,
                    "species": draft.categoryName,
                    "breed": draft.breed,
                    "weightKg": draft.weightKg
                ],
                "careRequirements": [
                    "diet": draft.specialDiet,
                    "allergies": draft.allergies.isEmpty ? [] : [draft.allergies],
                    "requiresMedication": draft.requiresMedication
                ]
            ]
            if !draft.accommodationTypeId.isEmpty {
                petDict["accommodationTypeId"] = draft.accommodationTypeId
            }
            return petDict
        }

        var customerSnapshot: [String: Any] = [
            "name": customerName,
            "phone": customerPhone
        ]
        if let email = customerEmail, !email.isEmpty {
            customerSnapshot["email"] = email
        }

        var emergencyContact: [String: String]? = nil
        if let eName = emergencyName, !eName.isEmpty, let ePhone = emergencyPhone, !ePhone.isEmpty {
            emergencyContact = ["name": eName, "phone": ePhone]
        }

        do {
            _ = try await AdminPetsHotelService.shared.createReservation(
                branchId: branchId,
                customerUid: customerUid.isEmpty ? "guest-\(UUID().uuidString.prefix(8))" : customerUid,
                customerSnapshot: customerSnapshot,
                arrivalAt: arrivalAt,
                departureAt: departureAt,
                pets: petsPayload,
                emergencyContact: emergencyContact,
                depositMinor: depositMinor,
                notes: notes,
                initialStatus: confirmImmediately ? "confirmed" : "pending_confirmation"
            )
            isSubmitting = false
            newReservationModalOpen = false
            loadHotelOperations()
            return true
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    public func confirmReservation(reservation: AdminHotelReservation) async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.confirmReservation(reservationId: reservation.id)
            isSubmitting = false
            if selectedReservationDetail?.id == reservation.id {
                selectedReservationDetail?.status = .confirmed
            }
            loadHotelOperations()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    public func extendReservation(reservation: AdminHotelReservation, newDepartureAt: Date, reasonCode: String = "operator_request") async -> Bool {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.extendReservation(
                reservationId: reservation.id,
                newDepartureAt: newDepartureAt,
                reasonCode: reasonCode
            )
            isSubmitting = false
            loadHotelOperations()
            return true
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    public func transitionReservation(reservation: AdminHotelReservation, action: String, reasonCode: String? = nil, note: String? = nil) async -> Bool {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.transitionReservation(
                action: action,
                reservationId: reservation.id,
                reasonCode: reasonCode,
                note: note
            )
            isSubmitting = false
            selectedReservationDetail = nil
            loadHotelOperations()
            return true
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    public func toggleCareTask(stay: AdminHotelStay, task: AdminHotelCareTask) {
        guard canTransitionCareTask(task) else {
            if task.taskType == .medication {
                errorMessage = Language.get("Hotel_Err_MedicationTaskAuthority", alter: "يجب تسجيل مهام الدواء عبر أمر إعطاء الدواء المخصص.")
            } else if !canExecuteCareTasks {
                errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            }
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let action = task.status == "scheduled" ? "start_task" : "complete_task"

        Task {
            do {
                _ = try await AdminPetsHotelService.shared.transitionCareTask(
                    action: action,
                    stayId: stay.id,
                    taskId: task.id,
                    completionNotes: Language.get("Hotel_Task_CompletedByAdmin", alter: "تم التوثيق عبر تطبيق الإدارة")
                )
                if canViewCare {
                    await loadStayDossier(
                        stayId: stay.id,
                        updatePresentedDetail: selectedStayDetail?.id == stay.id
                    )
                } else {
                    loadHotelOperations()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    public func canTransitionCareTask(_ task: AdminHotelCareTask) -> Bool {
        canExecuteCareTasks &&
        task.taskType != .medication &&
        !task.isCompleted &&
        ["scheduled", "due", "overdue", "in_progress"].contains(task.status)
    }

    public func loadStayDossier(stayId: String, updatePresentedDetail: Bool = false) async {
        guard canViewCare else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return
        }
        guard let branchId = currentBranchId else {
            errorMessage = Language.get("Hotel_Err_BranchRequired", alter: "اختر فرعاً لعرض عمليات الفندق.")
            return
        }
        let generation = loadGeneration
        let requestID = UUID()
        dossierRequestID = requestID
        do {
            let summary = try await AdminPetsHotelService.shared.fetchStayOperationalSummary(branchId: branchId, stayId: stayId)
            guard self.loadGeneration == generation,
                  self.currentBranchId == branchId,
                  self.dossierRequestID == requestID,
                  (!updatePresentedDetail || self.selectedStayDetail?.id == stayId) else {
                return
            }
            if let stayDict = summary["stay"] as? [String: Any] {
                // The dossier read model intentionally nests operational counters
                // beneath `stay.counters`, while the operational-stays projection
                // exposes the same values at the top level. Normalize only the
                // documented counter fields so downstream models consume either
                // server projection without inventing client state.
                var normalizedStay = stayDict
                let counters = stayDict["counters"] as? [String: Any] ?? [:]
                for key in [
                    "openTaskCount",
                    "overdueTaskCount",
                    "pendingMedicationCount",
                    "medicationDeclarationCount",
                    "openIncidentCount",
                    "criticalIncidentCount",
                    "monitoringIncidentCount",
                    "belongingCount",
                    "pendingBelongingCount",
                    "belongingIssueCount"
                ] where normalizedStay[key] == nil {
                    normalizedStay[key] = counters[key]
                }

                let summaryStay = AdminHotelStay.fromDictionary(normalizedStay, id: stayId)
                // A dossier is deliberately narrower than operational_stays.
                // Retain the richer, already-authorized staff projection and
                // overlay only fields the dossier owns authoritatively.
                var loadedStay = self.stays.first(where: { $0.id == stayId }) ?? summaryStay
                if self.stays.contains(where: { $0.id == stayId }) {
                    if !summaryStay.reservationId.isEmpty {
                        loadedStay.reservationId = summaryStay.reservationId
                    }
                    if !summaryStay.petId.isEmpty {
                        loadedStay.petId = summaryStay.petId
                    }
                    if let petName = normalizedStay["petName"] as? String, !petName.isEmpty {
                        loadedStay.petName = petName
                    }
                    if normalizedStay["status"] != nil {
                        loadedStay.status = summaryStay.status
                    }
                    if normalizedStay["guestStatus"] != nil {
                        loadedStay.guestStatus = summaryStay.guestStatus
                    }
                    if normalizedStay["accommodationId"] != nil {
                        loadedStay.accommodationId = summaryStay.accommodationId
                    }
                    if normalizedStay["accommodationCode"] != nil {
                        loadedStay.roomNumber = summaryStay.roomNumber
                    }
                    loadedStay.openTaskCount = summaryStay.openTaskCount
                    loadedStay.overdueTaskCount = summaryStay.overdueTaskCount
                    loadedStay.belongingCount = summaryStay.belongingCount
                    loadedStay.pendingMedicationCount = summaryStay.pendingMedicationCount
                    loadedStay.criticalIncidentCount = summaryStay.criticalIncidentCount
                }

                // Populate tasks
                if let rawTasks = summary["tasks"] as? [[String: Any]] {
                    loadedStay.dailyCareTasks = rawTasks.compactMap { taskDict in
                        guard let taskId = validIdentifier(taskDict["taskId"]) else { return nil }
                        return AdminHotelCareTask.fromDictionary(taskDict, id: taskId)
                    }
                }

                // Populate belongings
                if let rawBelongings = summary["belongings"] as? [[String: Any]] {
                    loadedStay.belongings = rawBelongings.compactMap { bDict in
                        guard let bId = validIdentifier(bDict["belongingId"]) else { return nil }
                        return AdminHotelBelongingItem.fromDictionary(bDict, id: bId)
                    }
                }

                loadedStay = reconciledStay(loadedStay)

                if updatePresentedDetail {
                    self.selectedStayDetail = loadedStay
                }

                // Update the shared operational list for the refreshed stay.
                if let idx = self.stays.firstIndex(where: { $0.id == stayId }) {
                    self.stays[idx] = loadedStay
                }
            }
        } catch {
            guard self.loadGeneration == generation,
                  self.currentBranchId == branchId,
                  self.dossierRequestID == requestID,
                  (!updatePresentedDetail || self.selectedStayDetail?.id == stayId) else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parsing Helpers
    private func parseAccommodation(doc: QueryDocumentSnapshot, expectedBranchId: String) -> AdminHotelAccommodation? {
        let d = doc.data()
        guard (d["branchId"] as? String) == expectedBranchId,
              let wingRaw = d["wing"] as? String,
              let wing = HotelWing(rawValue: wingRaw),
              let statusRaw = d["status"] as? String,
              let status = HotelAccommodationStatus(rawValue: statusRaw) else {
            return nil
        }
        let lastCleanTs = d["lastCleanedAt"] as? Timestamp

        return AdminHotelAccommodation(
            id: doc.documentID,
            accommodationNumber: d["accommodationNumber"] as? String ?? d["code"] as? String ?? doc.documentID,
            name: d["name"] as? String ?? d["accommodationNumber"] as? String ?? doc.documentID,
            wing: wing,
            accommodationTypeId: d["accommodationTypeId"] as? String ?? "",
            status: status,
            capacity: d["capacity"] as? Int ?? d["maxCapacity"] as? Int ?? 1,
            currentOccupancy: d["currentOccupancy"] as? Int ?? 0,
            currentStayId: d["currentStayId"] as? String,
            currentGuestName: d["currentGuestName"] as? String,
            currentGuestSpecies: d["currentGuestSpecies"] as? String,
            nightlyRateMinor: d["nightlyRateMinor"] as? Int,
            branchId: expectedBranchId,
            notes: d["notes"] as? String,
            lastCleanedAt: lastCleanTs?.dateValue(),
            active: d["active"] as? Bool ?? true,
            code: d["code"] as? String ?? d["accommodationNumber"] as? String ?? doc.documentID,
            allowedSpecies: d["allowedSpecies"] as? [String] ?? [],
            allowSharedOccupancy: d["allowSharedOccupancy"] as? Bool ?? false
        )
    }

    private func reconcileAccommodationMetadata() {
        let roomsById = Dictionary(uniqueKeysWithValues: accommodations.map { ($0.id, $0) })
        stays = stays.map(reconciledStay)
        reservations = reservations.map { reservation in
            guard let roomId = reservation.assignedAccommodationId,
                  let room = roomsById[roomId] else { return reservation }
            var resolved = reservation
            resolved.wing = room.wing
            if resolved.assignedRoomNumber?.isEmpty != false {
                resolved.assignedRoomNumber = room.accommodationNumber
            }
            return resolved
        }
    }

    private func reconciledStay(_ stay: AdminHotelStay) -> AdminHotelStay {
        guard let room = accommodations.first(where: { $0.id == stay.accommodationId }) else { return stay }
        var resolved = stay
        resolved.wing = room.wing
        if resolved.roomNumber.isEmpty {
            resolved.roomNumber = room.accommodationNumber
        }
        return resolved
    }

}
