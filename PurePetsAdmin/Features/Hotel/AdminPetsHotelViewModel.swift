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
    @Published public var hotelDiagnostics: AdminHotelDiagnostics? = nil
    @Published public var isLoadingDiagnostics: Bool = false
    @Published public private(set) var requiresBranchSelection = false
    @Published public private(set) var canViewHotel = false
    @Published public private(set) var canManageReservations = false
    @Published public private(set) var canCheckIn = false
    @Published public private(set) var canCheckOut = false
    @Published public private(set) var canManageAccommodations = false
    @Published public private(set) var canViewCare = false
    @Published public private(set) var canExecuteCareTasks = false
    @Published public private(set) var canViewBilling = false
    @Published public private(set) var canManageBilling = false

    public var needsSetup: Bool {
        if let diagnostics = hotelDiagnostics {
            return diagnostics.needsSetup
        }
        return accommodationTypes.isEmpty || accommodations.isEmpty
    }

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
                self.reconcileAccommodationMetadata()
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
            self.loadDiagnostics()
        }
    }

    public func loadDiagnostics() {
        guard let branchId = currentBranchId else { return }
        isLoadingDiagnostics = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let diag = try await AdminPetsHotelService.shared.fetchDiagnostics(branchId: branchId)
                self.hotelDiagnostics = diag
            } catch {
                print("Failed to load hotel diagnostics: \(error)")
            }
            self.isLoadingDiagnostics = false
        }
    }

    public var visibleTabs: [HotelHubTab] {
        HotelHubTab.allCases.filter { $0 != .care || canViewCare }
    }

    private func refreshAccess() {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isActive() else {
            canViewHotel = false
            canManageReservations = false
            canCheckIn = false
            canCheckOut = false
            canManageAccommodations = false
            canViewCare = false
            canExecuteCareTasks = false
            canViewBilling = false
            canManageBilling = false
            if selectedTab == .care {
                selectedTab = .overview
            }
            return
        }
        let branchId = currentBranchId
        canViewHotel = staff.hasPermission(kStaffPermHotelView, inBranch: branchId)
        canManageReservations = staff.hasPermission(kStaffPermHotelReservationsManage, inBranch: branchId)
        canCheckIn = staff.hasPermission(kStaffPermHotelCheckIn, inBranch: branchId)
        canCheckOut = staff.hasPermission(kStaffPermHotelCheckOut, inBranch: branchId)
        canManageAccommodations = staff.hasPermission(kStaffPermHotelAccommodationsManage, inBranch: branchId)
        canViewCare = staff.hasPermission(kStaffPermHotelCareView, inBranch: branchId)
        canExecuteCareTasks = staff.hasPermission(kStaffPermHotelTaskExecute, inBranch: branchId)
        canViewBilling = staff.hasPermission(kStaffPermHotelBillingView, inBranch: branchId)
            || staff.hasPermission(kStaffPermHotelBillingManage, inBranch: branchId)
            || staff.hasPermission(kStaffPermHotelBillingAdjust, inBranch: branchId)
        canManageBilling = staff.hasPermission(kStaffPermHotelBillingManage, inBranch: branchId)
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

    private func resolvedCapacity(for room: AdminHotelAccommodation) -> Int {
        let typeCapacity = accommodationTypes.first(where: { $0.id == room.accommodationTypeId })?.defaultCapacity ?? 1
        return max(1, room.capacity > 0 ? room.capacity : typeCapacity)
    }

    /// One capacity calculation feeds both the hotel hero and every wing row.
    /// This keeps physical suite count separate from usable pet positions.
    private func capacityTelemetry(for rooms: [AdminHotelAccommodation]) -> (occupied: Int, total: Int, rate: Double) {
        guard !rooms.isEmpty else { return (0, 0, 0.0) }
        let roomIds = Set(rooms.map(\.id))
        let total = rooms.reduce(0) { $0 + resolvedCapacity(for: $1) }
        let assignedInHouse = inHouseGuests.filter { roomIds.contains($0.accommodationId) }.count
        let projectedOccupancy = rooms.reduce(0) { partial, room in
            partial + min(resolvedCapacity(for: room), max(0, room.currentOccupancy))
        }
        // Older room documents may only expose `.occupied`; preserve one consumed
        // position per such room until their occupancy projection is populated.
        let legacyOccupiedFallback = rooms.filter { $0.status == .occupied }.count
        let occupied = min(total, max(assignedInHouse, max(projectedOccupancy, legacyOccupiedFallback)))
        let rate = total > 0 ? min(1.0, Double(occupied) / Double(total)) : 0.0
        return (occupied, total, rate)
    }

    public var totalCapacity: Int { capacityTelemetry(for: accommodations).total }

    /// Capacity telemetry is position-based, not physical-room based.
    /// A shared suite with capacity 10 and 3 pets contributes 3 occupied and 7 free positions.
    public var occupiedCapacityCount: Int { capacityTelemetry(for: accommodations).occupied }

    public var availableCapacityCount: Int {
        max(0, totalCapacity - occupiedCapacityCount)
    }

    public var capacityOccupancyRate: Double { capacityTelemetry(for: accommodations).rate }

    public var capacityOccupancyPercentageString: String {
        String(format: "%.0f%%", capacityOccupancyRate * 100.0)
    }

    public func wingCapacityTelemetry(wing: HotelWing) -> (occupied: Int, total: Int, rate: Double) {
        capacityTelemetry(for: accommodations.filter { $0.wing == wing })
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

    public func availabilitySnapshot(
        for reservation: AdminHotelReservation,
        stay: AdminHotelStay? = nil
    ) async throws -> AdminHotelAvailabilitySnapshot {
        guard let branchId = currentBranchId else {
            throw AdminPetsHotelError.operationFailed(
                Language.get("Hotel_Err_BranchRequired", alter: "اختر فرعاً لعرض عمليات الفندق.")
            )
        }
        let resolvedStayId = stay?.id ?? reservation.stayIds.first
        let resolvedMainKindId = reservation.mainKindId ?? stay?.mainKindId
        return try await AdminPetsHotelService.shared.fetchAvailability(
            branchId: branchId,
            arrivalAt: reservation.checkInDate,
            departureAt: reservation.checkOutDate,
            species: reservation.petSpecies,
            accommodationTypeId: reservation.accommodationTypeId.isEmpty ? nil : reservation.accommodationTypeId,
            stayId: resolvedStayId,
            mainKindId: resolvedMainKindId
        )
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

    public func recordSettlement(
        stayId: String,
        method: String,
        amountMinor: Int,
        reference: String? = nil,
        notes: String? = nil
    ) async -> Bool {
        guard canManageBilling else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.recordStaySettlement(
                stayId: stayId,
                method: method,
                amountMinor: amountMinor,
                reference: reference,
                notes: notes
            )
            // The billing command is authoritative. Never manufacture a paid
            // balance locally; wait for the next server projection so reception
            // cannot release a guest on optimistic settlement state.
            isSubmitting = false
            loadHotelOperations()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
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
        allowedMainKindIds: [Int] = [],
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
                allowedMainKindIds: allowedMainKindIds,
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
        allowedMainKindIds: [Int] = [],
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
                allowedMainKindIds: allowedMainKindIds,
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

    public func reassignStayRoom(
        stayId: String,
        accommodationId: String,
        reasonCode: String = "operator_reassignment",
        note: String? = nil,
        confirmReprice: Bool = false,
        expectedNewRateMinor: Int? = nil
    ) async -> Bool {
        guard canManageAccommodations else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.assignAccommodation(
                stayId: stayId,
                accommodationId: accommodationId,
                reasonCode: reasonCode,
                note: note,
                isReassign: true,
                confirmReprice: confirmReprice,
                expectedNewRateMinor: expectedNewRateMinor
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
        guard canManageReservations else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return false
        }
        let branchId = currentBranchId
            ?? BranchContextStore.shared.activeBranch?.branchID
            ?? PPBranchContextManager.shared().activeBranch?.branchID

        guard let branchId, !branchId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = Language.get("Hotel_Err_NoBranchSelected", alter: "يرجى تحديد فرع أولاً.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        isSubmitting = true
        errorMessage = nil

        let cleanPhone = customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let directUid = AdminHotelCustomerIdentityPolicy.resolvedCustomerUid(
            providedUid: customerUid,
            lookedUpUid: nil
        )
        let lookedUpUid: String?
        if directUid == nil, !cleanPhone.isEmpty {
            lookedUpUid = await lookupCustomerUidByPhone(cleanPhone)
        } else {
            lookedUpUid = nil
        }

        guard let effectiveCustomerUid = AdminHotelCustomerIdentityPolicy.resolvedCustomerUid(
            providedUid: directUid,
            lookedUpUid: lookedUpUid
        ) else {
            isSubmitting = false
            errorMessage = Language.get(
                "Hotel_Err_RegisteredCustomerRequired",
                alter: "يجب اختيار ملف عميل مسجل قبل إنشاء حجز الفندق. لا يمكن ربط الحجز بحساب بديل."
            )
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }

        let petsPayload: [[String: Any]] = pets.map { draft in
            var petSnapshot: [String: Any] = [
                "name": draft.name,
                "species": draft.categoryName,
                "breed": draft.breed,
                "weightKg": draft.weightKg
            ]
            if let mkId = draft.mainKindId {
                petSnapshot["mainKindId"] = mkId
            }
            if let mkDoc = draft.mainKindDocumentId {
                petSnapshot["mainKindDocumentId"] = mkDoc
            }
            if let ar = draft.mainKindNameAr {
                petSnapshot["mainKindNameAr"] = ar
            }
            if let en = draft.mainKindNameEn {
                petSnapshot["mainKindNameEn"] = en
            }
            if let skId = draft.subKindId {
                petSnapshot["subKindId"] = skId
            }
            if let skDoc = draft.subKindDocumentId {
                petSnapshot["subKindDocumentId"] = skDoc
            }
            if let sar = draft.subKindNameAr {
                petSnapshot["subKindNameAr"] = sar
            }
            if let sen = draft.subKindNameEn {
                petSnapshot["subKindNameEn"] = sen
            }

            var petDict: [String: Any] = [
                "petId": draft.id,
                "petSnapshot": petSnapshot,
                "careRequirements": [
                    "diet": draft.specialDiet,
                    "allergies": draft.allergies.isEmpty ? [] : [draft.allergies],
                    "requiresMedication": draft.requiresMedication
                ]
            ]
            if let mkId = draft.mainKindId {
                petDict["mainKindId"] = mkId
            }
            if !draft.accommodationTypeId.isEmpty {
                petDict["accommodationTypeId"] = draft.accommodationTypeId
            }
            if let accId = draft.accommodationId, !accId.isEmpty {
                petDict["accommodationId"] = accId
                if let code = accommodations.first(where: { $0.id == accId })?.accommodationNumber {
                    petDict["accommodationCode"] = code
                }
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
                customerUid: effectiveCustomerUid,
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

    // MARK: - Customer Directory & Pet Search

    private func parseCustomerOption(from doc: DocumentSnapshot) -> AdminHotelCustomerOption {
        let data = doc.data() ?? [:]
        let uid = (data["uid"] as? String) ?? doc.documentID
        let name = (data["UserName"] as? String)
            ?? (data["displayName"] as? String)
            ?? (data["FirstName"] as? String)
            ?? (data["name"] as? String)
            ?? (data["userName"] as? String)
            ?? uid
        let phone = (data["MobileNo"] as? String)
            ?? (data["phone"] as? String)
            ?? (data["phoneNumber"] as? String)
            ?? (data["mobile"] as? String)
            ?? ""
        let email = (data["UserEmail"] as? String)
            ?? (data["email"] as? String)
            ?? ""
        let photo = (data["photoURL"] as? String)
            ?? (data["UserImageUrl"] as? String)
            ?? (data["UserImageName"] as? String)
            ?? (data["imageURL"] as? String)
            ?? ""
        return AdminHotelCustomerOption(uid: uid, name: name, phone: phone, email: email, photoURL: photo)
    }

    @MainActor
    public func fetchCustomerProfile(uid: String) async -> AdminHotelCustomerOption? {
        guard !uid.isEmpty else { return nil }
        let db = Firestore.firestore()
        do {
            let doc = try await db.collection("UsersCol").document(uid).getDocument()
            if doc.exists {
                return parseCustomerOption(from: doc)
            }
            let pubDoc = try await db.collection("PublicUserProfiles").document(uid).getDocument()
            if pubDoc.exists {
                return parseCustomerOption(from: pubDoc)
            }
        } catch {
            print("[AdminPetsHotelViewModel] fetchCustomerProfile error: \(error)")
        }
        return nil
    }

    @MainActor
    public func searchCustomers(query: String) async -> [AdminHotelCustomerOption] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let db = Firestore.firestore()
        let usersCollection = db.collection("UsersCol")
        let publicCollection = db.collection("PublicUserProfiles")

        do {
            var rawDocs: [DocumentSnapshot] = []

            if clean.isEmpty {
                // Return recent active customers from UsersCol
                let snap = try await usersCollection.limit(to: 20).getDocuments()
                rawDocs = snap.documents
                if rawDocs.isEmpty {
                    let pubSnap = try await publicCollection.limit(to: 20).getDocuments()
                    rawDocs = pubSnap.documents
                }
            } else if clean.allSatisfy({ $0.isNumber || $0 == "+" || $0 == "-" || $0 == " " }) && clean.count >= 3 {
                // Phone search
                let digits = clean.filter { $0.isNumber }
                let snap1 = try await usersCollection.whereField("MobileNo", isEqualTo: clean).limit(to: 10).getDocuments()
                rawDocs.append(contentsOf: snap1.documents)

                if rawDocs.isEmpty && !digits.isEmpty && digits != clean {
                    let snapDigits = try await usersCollection.whereField("MobileNo", isEqualTo: digits).limit(to: 10).getDocuments()
                    rawDocs.append(contentsOf: snapDigits.documents)
                }

                if rawDocs.isEmpty {
                    let snap2 = try await usersCollection.whereField("phone", isEqualTo: clean).limit(to: 10).getDocuments()
                    rawDocs.append(contentsOf: snap2.documents)
                }

                if rawDocs.isEmpty {
                    let pubSnap = try await publicCollection.whereField("phone", isEqualTo: clean).limit(to: 10).getDocuments()
                    rawDocs.append(contentsOf: pubSnap.documents)
                }
            } else {
                // Text/Name prefix search in UsersCol
                let snap1 = try await usersCollection
                    .order(by: "UserName")
                    .start(at: [clean])
                    .end(at: [clean + "\u{f8ff}"])
                    .limit(to: 15)
                    .getDocuments()
                rawDocs.append(contentsOf: snap1.documents)

                if rawDocs.isEmpty {
                    let snap2 = try await usersCollection
                        .order(by: "displayName")
                        .start(at: [clean])
                        .end(at: [clean + "\u{f8ff}"])
                        .limit(to: 15)
                        .getDocuments()
                    rawDocs.append(contentsOf: snap2.documents)
                }

                if rawDocs.isEmpty {
                    let pubSnap = try await publicCollection
                        .order(by: "displayName")
                        .start(at: [clean])
                        .end(at: [clean + "\u{f8ff}"])
                        .limit(to: 15)
                        .getDocuments()
                    rawDocs.append(contentsOf: pubSnap.documents)
                }
            }

            var results: [AdminHotelCustomerOption] = []
            var seenUids = Set<String>()

            for doc in rawDocs {
                let parsed = parseCustomerOption(from: doc)
                if !seenUids.contains(parsed.uid) {
                    seenUids.insert(parsed.uid)
                    results.append(parsed)
                }
            }

            // If query is specific and results are empty, perform broad in-memory match over recent records
            if !clean.isEmpty && results.isEmpty {
                let broadUsers = try await usersCollection.limit(to: 60).getDocuments()
                let lowerClean = clean.lowercased()
                for doc in broadUsers.documents {
                    let parsed = parseCustomerOption(from: doc)
                    if !seenUids.contains(parsed.uid) {
                        let nameMatch = parsed.name.lowercased().contains(lowerClean)
                        let phoneMatch = parsed.phone.contains(clean)
                        let emailMatch = parsed.email.lowercased().contains(lowerClean)
                        if nameMatch || phoneMatch || emailMatch {
                            seenUids.insert(parsed.uid)
                            results.append(parsed)
                        }
                    }
                }

                if results.isEmpty {
                    let broadPublic = try await publicCollection.limit(to: 40).getDocuments()
                    for doc in broadPublic.documents {
                        let parsed = parseCustomerOption(from: doc)
                        if !seenUids.contains(parsed.uid) {
                            let nameMatch = parsed.name.lowercased().contains(lowerClean)
                            let phoneMatch = parsed.phone.contains(clean)
                            let emailMatch = parsed.email.lowercased().contains(lowerClean)
                            if nameMatch || phoneMatch || emailMatch {
                                seenUids.insert(parsed.uid)
                                results.append(parsed)
                            }
                        }
                    }
                }
            }

            // For any result lacking phone or email (e.g. from PublicUserProfiles), enrich from UsersCol
            var enrichedResults: [AdminHotelCustomerOption] = []
            for item in results {
                if item.phone.isEmpty || item.email.isEmpty {
                    if let full = try? await usersCollection.document(item.uid).getDocument(), full.exists {
                        let fullOption = parseCustomerOption(from: full)
                        enrichedResults.append(
                            AdminHotelCustomerOption(
                                uid: item.uid,
                                name: !fullOption.name.isEmpty && fullOption.name != item.uid ? fullOption.name : item.name,
                                phone: !fullOption.phone.isEmpty ? fullOption.phone : item.phone,
                                email: !fullOption.email.isEmpty ? fullOption.email : item.email,
                                photoURL: !fullOption.photoURL.isEmpty ? fullOption.photoURL : item.photoURL
                            )
                        )
                        continue
                    }
                }
                enrichedResults.append(item)
            }

            return enrichedResults
        } catch {
            return []
        }
    }

    @MainActor
    public func fetchCustomerPets(customerUid: String) async -> [AdminHotelCustomerPetOption] {
        guard !customerUid.isEmpty else { return [] }
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("UsersCol").document(customerUid).collection("petProfiles").limit(to: 30).getDocuments()
            return snapshot.documents.compactMap { doc -> AdminHotelCustomerPetOption? in
                let data = doc.data()
                let petId = (data["petID"] as? String) ?? (data["petId"] as? String) ?? doc.documentID
                let name = (data["name"] as? String) ?? (data["petName"] as? String) ?? ""
                guard !name.isEmpty else { return nil }
                let breed = (data["breed"] as? String) ?? ""
                let species = (data["categoryName"] as? String) ?? (data["species"] as? String) ?? "dog"
                let age = (data["ageInMonths"] as? Int) ?? 0
                let image = (data["imageURL"] as? String) ?? (data["imageUrl"] as? String) ?? ""
                let isDefault = (data["isDefaultPet"] as? Bool) ?? false

                return AdminHotelCustomerPetOption(
                    petId: petId,
                    name: name,
                    breed: breed,
                    species: species,
                    ageInMonths: age,
                    imageURL: image,
                    isDefaultPet: isDefault
                )
            }
        } catch {
            return []
        }
    }

    private func lookupCustomerUidByPhone(_ phone: String) async -> String? {
        guard !phone.isEmpty else { return nil }
        let clean = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = clean.filter { $0.isNumber }
        let db = Firestore.firestore()
        do {
            for key in ["MobileNo", "phone", "phoneNumber"] {
                let snap = try await db.collection("UsersCol").whereField(key, isEqualTo: clean).limit(to: 1).getDocuments()
                if let first = snap.documents.first {
                    return first.documentID
                }
                if !digits.isEmpty && digits != clean {
                    let snapDigits = try await db.collection("UsersCol").whereField(key, isEqualTo: digits).limit(to: 1).getDocuments()
                    if let firstDigits = snapDigits.documents.first {
                        return firstDigits.documentID
                    }
                }
            }
            let snapPub = try await db.collection("PublicUserProfiles").whereField("phone", isEqualTo: clean).limit(to: 1).getDocuments()
            if let first = snapPub.documents.first {
                return (first.data()["uid"] as? String) ?? first.documentID
            }
        } catch {
            // Ignore
        }
        return nil
    }

    public func confirmReservation(reservation: AdminHotelReservation) async {
        guard canManageReservations else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.confirmReservation(reservationId: reservation.id)
            // Do not fabricate a local lifecycle transition. The reservation
            // operations projection confirms the committed server state.
            isSubmitting = false
            loadHotelOperations()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    public func extendReservation(reservation: AdminHotelReservation, newDepartureAt: Date, reasonCode: String = "operator_request", note: String? = nil) async -> Bool {
        guard canManageReservations else {
            errorMessage = AdminPetsHotelError.permissionDenied.localizedDescription
            return false
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await AdminPetsHotelService.shared.extendReservation(
                reservationId: reservation.id,
                newDepartureAt: newDepartureAt,
                reasonCode: reasonCode,
                note: note
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

    public func updateReservation(
        reservation: AdminHotelReservation,
        customerName: String,
        customerPhone: String,
        customerEmail: String?,
        petName: String,
        petBreed: String,
        specialDiet: String,
        allergies: String,
        requiresMedication: Bool,
        arrivalAt: Date,
        departureAt: Date,
        emergencyName: String?,
        emergencyPhone: String?,
        notes: String?,
        overrideReason: String? = "admin_update",
        petSpecies: String? = nil,
        mainKindId: Int? = nil,
        mainKindDocumentId: String? = nil,
        mainKindNameAr: String? = nil,
        mainKindNameEn: String? = nil,
        subKindId: Int? = nil,
        subKindDocumentId: String? = nil,
        subKindNameAr: String? = nil,
        subKindNameEn: String? = nil,
        accommodationTypeId: String? = nil,
        assignedAccommodationId: String? = nil,
        medicationsText: String? = nil,
        depositMinor: Int? = nil
    ) async -> Bool {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        errorMessage = nil

        let petId = reservation.petId.isEmpty ? "\(reservation.id)_pet" : reservation.petId
        let effectiveSpecies = petSpecies ?? (reservation.petSpecies.isEmpty ? "dog" : reservation.petSpecies)

        var petSnapshot: [String: Any] = [
            "name": petName,
            "species": effectiveSpecies,
            "breed": petBreed,
            "weightKg": 5.0
        ]
        let effectiveMainKindId = mainKindId ?? reservation.mainKindId
        if let mkId = effectiveMainKindId {
            petSnapshot["mainKindId"] = mkId
        }
        let effectiveMainKindDocId = mainKindDocumentId ?? reservation.mainKindDocumentId
        if let mkDoc = effectiveMainKindDocId {
            petSnapshot["mainKindDocumentId"] = mkDoc
        }
        let effectiveMainKindAr = mainKindNameAr ?? reservation.mainKindNameAr
        if let ar = effectiveMainKindAr {
            petSnapshot["mainKindNameAr"] = ar
        }
        let effectiveMainKindEn = mainKindNameEn ?? reservation.mainKindNameEn
        if let en = effectiveMainKindEn {
            petSnapshot["mainKindNameEn"] = en
        }
        let effectiveSubKindId = subKindId ?? reservation.subKindId
        if let skId = effectiveSubKindId {
            petSnapshot["subKindId"] = skId
        }
        let effectiveSubKindDocId = subKindDocumentId ?? reservation.subKindDocumentId
        if let skDoc = effectiveSubKindDocId {
            petSnapshot["subKindDocumentId"] = skDoc
        }
        let effectiveSubKindAr = subKindNameAr ?? reservation.subKindNameAr
        if let sar = effectiveSubKindAr {
            petSnapshot["subKindNameAr"] = sar
        }
        let effectiveSubKindEn = subKindNameEn ?? reservation.subKindNameEn
        if let sen = effectiveSubKindEn {
            petSnapshot["subKindNameEn"] = sen
        }

        var careRequirements: [String: Any] = [
            "diet": specialDiet,
            "allergies": allergies.isEmpty ? [] : [allergies],
            "requiresMedication": requiresMedication
        ]
        if let medNotes = medicationsText, !medNotes.isEmpty {
            careRequirements["medications"] = medNotes
            careRequirements["medicationsText"] = medNotes
        }

        var petDict: [String: Any] = [
            "petId": petId,
            "petSnapshot": petSnapshot,
            "careRequirements": careRequirements
        ]
        if let mkId = effectiveMainKindId {
            petDict["mainKindId"] = mkId
        }
        let effectiveAccommodationTypeId = accommodationTypeId ?? (!reservation.accommodationTypeId.isEmpty ? reservation.accommodationTypeId : nil)
        if let accTypeId = effectiveAccommodationTypeId, !accTypeId.isEmpty {
            petDict["accommodationTypeId"] = accTypeId
        }
        let effectiveAccommodationId = assignedAccommodationId ?? reservation.assignedAccommodationId
        if let accId = effectiveAccommodationId, !accId.isEmpty {
            petDict["accommodationId"] = accId
            if let code = accommodations.first(where: { $0.id == accId })?.accommodationNumber {
                petDict["accommodationCode"] = code
            }
        }
        let petsPayload: [[String: Any]] = [petDict]

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

        let effectiveDepositMinor = depositMinor ?? reservation.depositMinor ?? 0

        do {
            _ = try await AdminPetsHotelService.shared.updateReservation(
                reservationId: reservation.id,
                customerUid: reservation.customerId,
                customerSnapshot: customerSnapshot,
                arrivalAt: arrivalAt,
                departureAt: departureAt,
                pets: petsPayload,
                emergencyContact: emergencyContact,
                depositMinor: effectiveDepositMinor,
                notes: notes,
                overrideReason: overrideReason
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

        let allowedKinds: [Int]
        if let direct = d["allowedMainKindIds"] as? [Int] {
            allowedKinds = direct
        } else if let nsNumbers = d["allowedMainKindIds"] as? [NSNumber] {
            allowedKinds = nsNumbers.map(\.intValue)
        } else {
            allowedKinds = []
        }

        return AdminHotelAccommodation(
            id: doc.documentID,
            accommodationNumber: d["accommodationNumber"] as? String ?? d["code"] as? String ?? doc.documentID,
            name: d["name"] as? String ?? d["accommodationNumber"] as? String ?? doc.documentID,
            wing: wing,
            accommodationTypeId: d["accommodationTypeId"] as? String ?? "",
            status: status,
            capacity: (d["capacity"] as? NSNumber)?.intValue ?? (d["capacity"] as? Int) ?? (d["maxCapacity"] as? NSNumber)?.intValue ?? (d["maxCapacity"] as? Int) ?? 1,
            currentOccupancy: (d["currentOccupancy"] as? NSNumber)?.intValue ?? (d["currentOccupancy"] as? Int) ?? (d["occupiedCount"] as? NSNumber)?.intValue ?? (d["occupiedCount"] as? Int) ?? 0,
            currentStayId: d["currentStayId"] as? String,
            currentGuestName: d["currentGuestName"] as? String,
            currentGuestSpecies: d["currentGuestSpecies"] as? String,
            nightlyRateMinor: (d["nightlyRateMinor"] as? NSNumber)?.intValue ?? (d["nightlyRateMinor"] as? Int),
            branchId: expectedBranchId,
            notes: d["notes"] as? String,
            lastCleanedAt: lastCleanTs?.dateValue(),
            active: d["active"] as? Bool ?? true,
            code: d["code"] as? String ?? d["accommodationNumber"] as? String ?? doc.documentID,
            allowedSpecies: d["allowedSpecies"] as? [String] ?? [],
            allowedMainKindIds: allowedKinds,
            allowSharedOccupancy: d["allowSharedOccupancy"] as? Bool ?? false
        )
    }

    private func reconcileAccommodationMetadata() {
        accommodationTypes = accommodationTypes.map { type in
            var resolved = type
            let canonicalKindId: Int? = {
                switch resolved.wing {
                case .dogs: return 6
                case .cats: return 5
                case .birds: return 1
                case .smallPets: return 8
                default: return nil
                }
            }()
            if let cid = canonicalKindId, !resolved.allowedMainKindIds.contains(cid) {
                resolved.allowedMainKindIds.append(cid)
            }
            if resolved.allowedSpecies.isEmpty {
                resolved.allowedSpecies = AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: resolved.wing.rawValue)
            }
            return resolved
        }

        let typesById = Dictionary(accommodationTypes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        accommodations = accommodations.map { room in
            var resolved = room
            if resolved.capacity <= 1, let matchedType = typesById[resolved.accommodationTypeId], matchedType.defaultCapacity > 1 {
                resolved.capacity = matchedType.defaultCapacity
            }
            if resolved.nightlyRateMinor == nil || resolved.nightlyRateMinor == 0 {
                if let matchedType = typesById[resolved.accommodationTypeId], matchedType.nightlyRateMinor > 0 {
                    resolved.nightlyRateMinor = matchedType.nightlyRateMinor
                } else if let wingMatch = accommodationTypes.first(where: { $0.wing == resolved.wing && $0.nightlyRateMinor > 0 }) {
                    resolved.nightlyRateMinor = wingMatch.nightlyRateMinor
                }
            }
            if resolved.allowedMainKindIds.isEmpty, let matchedType = typesById[resolved.accommodationTypeId] {
                resolved.allowedMainKindIds = matchedType.allowedMainKindIds
            }
            // Reconcile current occupant & occupied status from in-house stays
            if let activeStay = stays.first(where: { $0.accommodationId == room.id && ($0.status == .checkedIn || $0.status == .inStay) }) {
                if resolved.currentGuestName == nil || resolved.currentGuestName?.isEmpty == true {
                    resolved.currentGuestName = activeStay.petName
                }
                if resolved.status == .available {
                    resolved.status = .occupied
                }
            }
            return resolved
        }

        let roomsById = Dictionary(accommodations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        stays = stays.map(reconciledStay)
        reservations = reservations.map { reservation in
            var resolved = reservation

            // Reconcile assigned room from reservation OR its matching stay
            let matchingStay = stays.first {
                $0.reservationId == reservation.id ||
                (!reservation.stayIds.isEmpty && reservation.stayIds.contains($0.id))
            }
            let effectiveRoomId: String? = {
                if let assigned = reservation.assignedAccommodationId, !assigned.isEmpty {
                    return assigned
                }
                if let stayAccId = matchingStay?.accommodationId, !stayAccId.isEmpty {
                    return stayAccId
                }
                return nil
            }()

            if let roomId = effectiveRoomId,
               let room = roomsById[roomId] {
                resolved.assignedAccommodationId = roomId
                resolved.wing = room.wing
                if resolved.assignedRoomNumber?.isEmpty != false {
                    resolved.assignedRoomNumber = room.accommodationNumber
                }
                if (resolved.nightlyRateMinor == nil || resolved.nightlyRateMinor == 0),
                   let rate = room.nightlyRateMinor, rate > 0 {
                    resolved.nightlyRateMinor = rate
                }
                if (resolved.totalAmountMinor == nil || resolved.totalAmountMinor == 0),
                   let rate = room.nightlyRateMinor, rate > 0 {
                    resolved.totalAmountMinor = rate * max(1, resolved.numberOfNights)
                }
            } else if let stayRoom = matchingStay?.roomNumber, !stayRoom.isEmpty {
                if resolved.assignedRoomNumber?.isEmpty != false {
                    resolved.assignedRoomNumber = stayRoom
                }
                if resolved.assignedAccommodationId == nil || resolved.assignedAccommodationId?.isEmpty == true {
                    resolved.assignedAccommodationId = matchingStay?.accommodationId
                }
            } else if resolved.totalAmountMinor == nil || resolved.totalAmountMinor == 0 {
                if let matchedType = typesById[reservation.accommodationTypeId], matchedType.nightlyRateMinor > 0 {
                    resolved.totalAmountMinor = matchedType.nightlyRateMinor * max(1, resolved.numberOfNights)
                } else if let rate = resolved.nightlyRateMinor, rate > 0 {
                    resolved.totalAmountMinor = rate * max(1, resolved.numberOfNights)
                } else if let wingMatch = accommodationTypes.first(where: { $0.wing == resolved.wing && $0.nightlyRateMinor > 0 }) {
                    resolved.totalAmountMinor = wingMatch.nightlyRateMinor * max(1, resolved.numberOfNights)
                }
            }

            if resolved.nightlyRateMinor == nil || resolved.nightlyRateMinor == 0 {
                if let typeRate = typesById[reservation.accommodationTypeId]?.nightlyRateMinor, typeRate > 0 {
                    resolved.nightlyRateMinor = typeRate
                } else if let wingRate = accommodationTypes.first(where: { $0.wing == resolved.wing && $0.nightlyRateMinor > 0 })?.nightlyRateMinor {
                    resolved.nightlyRateMinor = wingRate
                }
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

    public func activeStay(for room: AdminHotelAccommodation) -> AdminHotelStay? {
        stays.first { stay in
            (stay.status == .checkedIn || stay.status == .inStay) &&
            (stay.accommodationId == room.id || (!room.accommodationNumber.isEmpty && stay.roomNumber == room.accommodationNumber))
        }
    }

}
