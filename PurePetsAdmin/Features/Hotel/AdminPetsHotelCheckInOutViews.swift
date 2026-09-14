//
//  AdminPetsHotelCheckInOutViews.swift
//  PurePetsAdmin
//
//  Category-defining Express Check-in, Check-out, and Room Status Studios
//  for Pets Hotel (فندق ورعاية الحيوانات الأليفة).
//  Directly integrated with authoritative backend callables.
//

import SwiftUI

// MARK: - Category-Defining Sovereign Express Check-In Studio (Full Screen)
@MainActor
public struct AdminPetsHotelCheckInSheet: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedRoom: AdminHotelAccommodation?
    @State private var verification = AdminHotelCheckInVerification()
    @State private var belongings: [AdminHotelBelongingItem] = []
    @State private var availabilitySnapshot: AdminHotelAvailabilitySnapshot?
    @State private var availabilityErrorMessage: String?
    @State private var isLoadingAvailability = false
    @State private var newBelongingName: String = ""
    @State private var internalNotes: String = ""
    @State private var showVerificationDetails: Bool = true

    public init(reservation: AdminHotelReservation, viewModel: AdminPetsHotelViewModel) {
        self.reservation = reservation
        self.viewModel = viewModel
    }

    private var isPad: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    /// The reservation projection intentionally does not expose care declarations.
    /// Resolve its selected, server-projected stay before rendering a clinical
    /// check-in requirement; no pet ID or client-derived field can substitute.
    private var authoritativeCheckInStay: AdminHotelStay? {
        let projectedStayIDs = Set(reservation.stayIds)
        guard !projectedStayIDs.isEmpty else { return nil }

        let candidates = viewModel.stays.filter { stay in
            projectedStayIDs.contains(stay.id) && stay.reservationId == reservation.id
        }
        guard !reservation.petId.isEmpty else {
            return candidates.count == 1 ? candidates.first : nil
        }
        return candidates.first { $0.petId == reservation.petId }
    }

    private var medicationConfirmationRequired: Bool {
        authoritativeCheckInStay?.medicationConfirmationRequired == true
    }

    private var checkInReadiness: AdminHotelCheckInReadiness {
        AdminHotelCheckInReadinessPolicy.evaluate(
            hasAuthoritativeStay: authoritativeCheckInStay != nil,
            petIdentityVerified: verification.petIdentityVerified,
            vaccinationVerified: verification.vaccinationVerified,
            healthInspectionCompleted: verification.healthInspectionCompleted,
            dietConfirmed: verification.dietConfirmed,
            emergencyContactConfirmed: verification.emergencyContactConfirmed,
            agreementAcknowledged: verification.agreementAcknowledged,
            medicationRequired: medicationConfirmationRequired,
            medicationConfirmed: verification.medicationConfirmed,
            depositRequired: (reservation.depositMinor ?? 0) > 0,
            depositSettled: verification.depositSettled
        )
    }

    private var isCheckInVerificationComplete: Bool {
        checkInReadiness.isComplete
    }

    private var completedVerificationCount: Int {
        checkInReadiness.completedCount
    }

    private var totalVerificationCount: Int {
        checkInReadiness.totalCount
    }

    public var body: some View {
        ZStack {
            AdminSurface.background
                .ignoresSafeArea()

            if isPad {
                AdminPetsHotelCheckIn_iPad(
                    reservation: reservation,
                    viewModel: viewModel,
                    selectedRoom: $selectedRoom,
                    verification: $verification,
                    belongings: $belongings,
                    availabilitySnapshot: availabilitySnapshot,
                    availabilityErrorMessage: availabilityErrorMessage,
                    isLoadingAvailability: isLoadingAvailability,
                    newBelongingName: $newBelongingName,
                    internalNotes: $internalNotes,
                    showVerificationDetails: $showVerificationDetails,
                    authoritativeStay: authoritativeCheckInStay,
                    medicationRequired: medicationConfirmationRequired,
                    isVerificationComplete: isCheckInVerificationComplete,
                    completedCount: completedVerificationCount,
                    totalCount: totalVerificationCount,
                    onRefreshAvailability: { loadAvailability() },
                    onConfirmCheckIn: { performCheckIn() },
                    onDismiss: { dismiss() }
                )
            } else {
                AdminPetsHotelCheckIn_iPhone(
                    reservation: reservation,
                    viewModel: viewModel,
                    selectedRoom: $selectedRoom,
                    verification: $verification,
                    belongings: $belongings,
                    availabilitySnapshot: availabilitySnapshot,
                    availabilityErrorMessage: availabilityErrorMessage,
                    isLoadingAvailability: isLoadingAvailability,
                    newBelongingName: $newBelongingName,
                    internalNotes: $internalNotes,
                    showVerificationDetails: $showVerificationDetails,
                    authoritativeStay: authoritativeCheckInStay,
                    medicationRequired: medicationConfirmationRequired,
                    isVerificationComplete: isCheckInVerificationComplete,
                    completedCount: completedVerificationCount,
                    totalCount: totalVerificationCount,
                    onRefreshAvailability: { loadAvailability() },
                    onConfirmCheckIn: { performCheckIn() },
                    onDismiss: { dismiss() }
                )
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            loadAvailability()
        }
    }

    private func loadAvailability() {
        isLoadingAvailability = true
        availabilitySnapshot = nil
        availabilityErrorMessage = nil
        selectedRoom = nil
        Task {
            do {
                availabilitySnapshot = try await viewModel.availabilitySnapshot(for: reservation)
                autoSuggestAvailableRoom()
            } catch {
                availabilityErrorMessage = error.localizedDescription
            }
            isLoadingAvailability = false
        }
    }

    private func autoSuggestAvailableRoom() {
        let assignableIds = availabilitySnapshot?.assignableIds ?? []
        if let assignedId = reservation.assignedAccommodationId,
           assignableIds.contains(assignedId),
           let match = viewModel.accommodations.first(where: { $0.id == assignedId }) {
            selectedRoom = match
        } else if let match = viewModel.accommodations.first(where: {
            assignableIds.contains($0.id)
        }) {
            selectedRoom = match
        }
    }

    private func performCheckIn() {
        guard let room = selectedRoom, let stay = authoritativeCheckInStay else { return }
        Task {
            await viewModel.executeCheckIn(
                reservation: reservation,
                stay: stay,
                assignedRoom: room,
                belongings: belongings,
                verification: verification,
                notes: internalNotes.isEmpty ? nil : internalNotes
            )
            if viewModel.errorMessage == nil {
                dismiss()
            }
        }
    }
}

// MARK: - iPhone Dedicated Architecture (Fluid Vertical Flow & Thumb-Zone Ergonomics)
private struct AdminPetsHotelCheckIn_iPhone: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Binding var selectedRoom: AdminHotelAccommodation?
    @Binding var verification: AdminHotelCheckInVerification
    @Binding var belongings: [AdminHotelBelongingItem]
    let availabilitySnapshot: AdminHotelAvailabilitySnapshot?
    let availabilityErrorMessage: String?
    let isLoadingAvailability: Bool
    @Binding var newBelongingName: String
    @Binding var internalNotes: String
    @Binding var showVerificationDetails: Bool
    let authoritativeStay: AdminHotelStay?
    let medicationRequired: Bool
    let isVerificationComplete: Bool
    let completedCount: Int
    let totalCount: Int
    let onRefreshAvailability: () -> Void
    let onConfirmCheckIn: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let quickChips: [String] = [
        Language.get("Hotel_Chip_CollarLeash", alter: "طوق ومقود"),
        Language.get("Hotel_Chip_BlanketBed", alter: "بطانية / فراش"),
        Language.get("Hotel_Chip_Medication", alter: "دواء مخصص"),
        Language.get("Hotel_Chip_Carrier", alter: "قفص نقل"),
        Language.get("Hotel_Chip_SpecialFood", alter: "طعام خاص"),
        Language.get("Hotel_Chip_Toys", alter: "ألعاب النزيل")
    ]

    private let quickNotePills: [String] = [
        Language.get("Hotel_NoteTag_Calm", alter: "هادئ ومطيع"),
        Language.get("Hotel_NoteTag_Anxious", alter: "متوتر من الغرباء"),
        Language.get("Hotel_NoteTag_SpecialDiet", alter: "نظام غذائي دقيق"),
        Language.get("Hotel_NoteTag_NeedsCare", alter: "عناية طبية خاصة")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Full Screen Status Bar + Navigation Chrome
            iPhoneNavBar

            // Scrollable Operational Canvas
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Critical Error Banner (if any)
                    if let err = viewModel.errorMessage {
                        errorBanner(err)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    // Pet Hero Dossier Card
                    iPhoneGuestHeroCard
                        .padding(.horizontal, 16)
                        .padding(.top, viewModel.errorMessage == nil ? 12 : 8)
                        .padding(.bottom, 10)

                    // Sticky Readiness Telemetry Section
                    Section {
                        VStack(spacing: 16) {
                            // Room Selection Deck
                            iPhoneRoomSelectionDeck

                            // Clinical & Operational Verification Cockpit
                            iPhoneVerificationCockpit

                            // Belongings & Inventory Vault
                            iPhoneBelongingsVault

                            // Arrival & Behavioral Notes
                            iPhoneNotesStudio

                            // Visual spacer to clear the docked bottom bar
                            Spacer(minLength: 92)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    } header: {
                        stickyReadinessHeader
                    }
                }
            }

            // Floating Glass Action Bar (Pinned above safe area)
            iPhoneDockedActionBar
        }
        .edgesIgnoringSafeArea(.top)
    }

    // MARK: - iPhone Top Navigation Bar
    private var iPhoneNavBar: some View {
        let refNo = !reservation.reservationNumber.isEmpty ? reservation.reservationNumber : String(reservation.id.prefix(8)).uppercased()
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // Dismiss circular button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 36, height: 36)
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(Language.get("Close", alter: "إغلاق"))

                // Titles with Live Pulse Beacon
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_CheckIn_Title", alter: "تسجيل وصول النزيل"))
                        .font(Font.custom("Beiruti-Bold", size: 18))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.72, blue: 0.44))
                            .frame(width: 6, height: 6)
                        Text("\(reservation.petName) • \(refNo)")
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Wing Capsule Tag
                HStack(spacing: 5) {
                    Image(systemName: reservation.wing.icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(reservation.wing.title)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(reservation.wing.tint.opacity(0.14), in: Capsule())
                .foregroundStyle(reservation.wing.tint)
                .overlay(
                    Capsule()
                        .strokeBorder(reservation.wing.tint.opacity(0.28), lineWidth: 0.75)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, max(PPStatusBarHelper.statusBarHeight, 44))
            .padding(.bottom, 10)
            .background(AdminSurface.background)

            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.4))
        }
    }

    // MARK: - iPhone Guest Hero Card
    private var iPhoneGuestHeroCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Pet Avatar with Wing Ambient Glow
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    reservation.wing.tint.opacity(0.24),
                                    reservation.wing.tint.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 62, height: 62)
                    Image(systemName: reservation.wing.icon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(reservation.wing.tint)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(reservation.wing.tint.opacity(0.35), lineWidth: 0.75)
                )
                .shadow(color: reservation.wing.tint.opacity(0.14), radius: 8, y: 3)

                // Pet details & species
                VStack(alignment: .leading, spacing: 3) {
                    Text(reservation.petName)
                        .font(Font.custom("Beiruti-Bold", size: 20))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(petSubtitle)
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)

                    // Owner contact trigger
                    if !reservation.customerPhone.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            callPhone(reservation.customerPhone)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 10))
                                Text(reservation.customerName)
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                            }
                            .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }

                Spacer()

                // Price Tag
                VStack(alignment: .trailing, spacing: 2) {
                    Text(displayedPriceText)
                        .font(Font.custom("Beiruti-Bold", size: 18))
                        .foregroundStyle(AdminSurface.primary)
                    Text(String(format: Language.get("Hotel_Nights_Format", alter: "%ld ليالٍ"), reservation.numberOfNights))
                        .font(Font.custom("Beiruti-Medium", size: 11.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            // Quick Stay Timeline Strip
            HStack(spacing: 12) {
                timelineItem(
                    label: Language.get("Hotel_Arrival", alter: "الوصول"),
                    value: formatDate(reservation.checkInDate),
                    icon: "calendar.badge.clock"
                )
                Divider()
                    .frame(height: 24)
                timelineItem(
                    label: Language.get("Hotel_Departure", alter: "المغادرة"),
                    value: formatDate(reservation.checkOutDate),
                    icon: "calendar.badge.checkmark"
                )
                Divider()
                    .frame(height: 24)
                timelineItem(
                    label: Language.get("Hotel_StayPeriod", alter: "المدة"),
                    value: "\(reservation.numberOfNights) " + Language.get("Nights", alter: "ليالٍ"),
                    icon: "moon.stars.fill"
                )
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private var displayedPriceText: String {
        if let total = reservation.totalAmountMinor, total > 0 {
            return reservation.formattedTotal
        }
        let rateMinor = selectedRoom?.nightlyRateMinor
            ?? viewModel.accommodations.first(where: { $0.id == reservation.assignedAccommodationId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.id == reservation.accommodationTypeId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.wing == reservation.wing })?.nightlyRateMinor

        if let rateMinor, rateMinor > 0 {
            let total = Double(rateMinor * max(1, reservation.numberOfNights)) / 100.0
            return String(format: "%.0f %@", total, Language.get("Currency_QAR", alter: "ر.ق"))
        }
        return reservation.formattedTotal
    }

    private var petSubtitle: String {
        let species = localizedPetSpecies(reservation.petSpecies)
        let breed = reservation.petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !species.isEmpty && !breed.isEmpty {
            return "\(species) • \(breed)"
        } else if !species.isEmpty {
            return species
        } else if !breed.isEmpty {
            return breed
        }
        return reservation.wing.title
    }

    private func timelineItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(AdminSurface.secondaryText)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Font.custom("Beiruti-Regular", size: 10.5))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sticky Readiness Telemetry Header
    private var stickyReadinessHeader: some View {
        VStack(spacing: 0) {
            iPhoneReadinessGaugeCard
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(AdminSurface.background)
        .zIndex(10)
    }

    // MARK: - iPhone Readiness Gauge Card
    private var iPhoneReadinessGaugeCard: some View {
        let progress = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
        let isReady = isVerificationComplete && selectedRoom != nil && authoritativeStay != nil

        return VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: isReady ? "checkmark.seal.fill" : "gauge.with.dots.needle.50percent")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isReady ? Color(red: 0.16, green: 0.72, blue: 0.44) : .orange)
                    Text(Language.get("Hotel_Readiness_Title", alter: "جاهزية الاستقبال والتسكين"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                Spacer()
                Text("\(completedCount) / \(totalCount)")
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(isReady ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
            }

            // Animated Smooth Progress Bar
            GeometryReader { p in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .systemGray5))
                        .frame(height: 7)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: isReady
                                    ? [Color(red: 0.16, green: 0.72, blue: 0.44), Color(red: 0.08, green: 0.85, blue: 0.55)]
                                    : [Color.orange, Color.yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(p.size.width * CGFloat(progress), 12), height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: progress)
                }
            }
            .frame(height: 7)

            // Dynamic Checklist Status Pills
            HStack(spacing: 6) {
                statusPill(
                    title: selectedRoom != nil ? selectedRoom!.accommodationNumber : Language.get("Hotel_SelectRoom", alter: "اختيار الغرفة"),
                    isComplete: selectedRoom != nil,
                    icon: "bed.double.fill"
                )
                statusPill(
                    title: Language.get("Hotel_VerifyVaccination", alter: "التطعيمات"),
                    isComplete: verification.vaccinationVerified,
                    icon: "syringe.fill"
                )
                statusPill(
                    title: Language.get("Hotel_VerifyAgreement", alter: "العقد"),
                    isComplete: verification.agreementAcknowledged,
                    icon: "doc.text.fill"
                )
                statusPill(
                    title: Language.get("Hotel_Belongings", alter: "المقتنيات"),
                    isComplete: !belongings.isEmpty,
                    icon: "shippingbox.fill"
                )
            }
        }
        .padding(13)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 8, x: 0, y: 3)
    }

    private func statusPill(title: String, isComplete: Bool, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : icon)
                .font(.system(size: 9.5))
                .foregroundStyle(isComplete ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
            Text(title)
                .font(Font.custom("Beiruti-Medium", size: 11))
                .foregroundStyle(isComplete ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isComplete ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.10) : AdminSurface.surface,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(isComplete ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.25) : Color(uiColor: .ppSurfaceBorder).opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - iPhone Room Selection Deck
    private var iPhoneRoomSelectionDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(Language.get("Hotel_SelectRoom", alter: "اختر الجناح أو الغرفة"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "bed.double.fill")
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRefreshAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            let availableRooms = viewModel.accommodations.filter {
                (availabilitySnapshot?.assignableIds.contains($0.id) ?? false)
            }

            if isLoadingAvailability {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        AdminHotelShimmerRoomCard()
                        AdminHotelShimmerRoomCard()
                        AdminHotelShimmerRoomCard()
                    }
                    .padding(.vertical, 2)
                }
            } else if let availabilityErrorMessage {
                AdminHotelAvailabilityDiagnosticsBanner(
                    snapshot: availabilitySnapshot,
                    errorMessage: availabilityErrorMessage
                )
            } else if availableRooms.isEmpty {
                AdminHotelAvailabilityDiagnosticsBanner(
                    snapshot: availabilitySnapshot,
                    errorMessage: nil
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableRooms) { room in
                            let isSelected = selectedRoom?.id == room.id
                            AdminHotelRoomTile(
                                room: room,
                                isSelected: isSelected
                            ) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedRoom = room
                            }
                            .frame(width: 140)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - iPhone Verification Cockpit
    private var iPhoneVerificationCockpit: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(Language.get("Hotel_VerificationTitle", alter: "متطلبات الدخول والتحقق الإلزامي"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "checklist.checked")
                        .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        showVerificationDetails.toggle()
                    }
                } label: {
                    Image(systemName: showVerificationDetails ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            if showVerificationDetails {
                VStack(spacing: 8) {
                    if authoritativeStay == nil {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(Language.get("Hotel_Err_StayRequired", alter: "لا يوجد سجل إقامة جاهز لتسجيل وصول هذا الحجز."))
                                .font(Font.custom("Beiruti-Medium", size: 12.5))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyIdentity", alter: "التحقق من هوية الحيوان والمالك"),
                        subtitle: Language.get("Hotel_VerifyIdentity_Sub", alter: "مطابقة بيانات المالك والشريحة الإلكترونية"),
                        icon: "person.text.rectangle.fill",
                        isVerified: $verification.petIdentityVerified
                    ) {
                        toggleVerification(&verification.petIdentityVerified)
                    }

                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyVaccination", alter: "شهادة التطعيمات سارية وموثقة"),
                        subtitle: Language.get("Hotel_VerifyVaccination_Sub", alter: "دفتر التطعيمات معتمد وخالي من التحذيرات"),
                        icon: "syringe.fill",
                        isVerified: $verification.vaccinationVerified
                    ) {
                        toggleVerification(&verification.vaccinationVerified)
                    }

                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyInspection", alter: "الفحص السريري الأولي سليم"),
                        subtitle: Language.get("Hotel_VerifyInspection_Sub", alter: "فحص الجلد والعيون والنشاط السريري العام"),
                        icon: "stethoscope",
                        isVerified: $verification.healthInspectionCompleted
                    ) {
                        toggleVerification(&verification.healthInspectionCompleted)
                    }

                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyDiet", alter: "تأكيد النظام الغذائي والحساسيات"),
                        subtitle: Language.get("Hotel_VerifyDiet_Sub", alter: "مراجعة مواعيد الوجبات ومسببات الحساسية"),
                        icon: "fork.knife",
                        isVerified: $verification.dietConfirmed
                    ) {
                        toggleVerification(&verification.dietConfirmed)
                    }

                    if medicationRequired {
                        AdminHotelVerificationCard(
                            title: Language.get("Hotel_VerifyMedication", alter: "تأكيد خطة الأدوية إن وجدت"),
                            subtitle: Language.get("Hotel_VerifyMedication_Sub", alter: "مطابقة الجرعات ومواعيد إعطاء الدواء"),
                            icon: "pill.fill",
                            isVerified: $verification.medicationConfirmed
                        ) {
                            toggleVerification(&verification.medicationConfirmed)
                        }
                    }

                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyEmergency", alter: "تأكيد رقم الطوارئ البديل"),
                        subtitle: Language.get("Hotel_VerifyEmergency_Sub", alter: "رقم فعال للتواصل الفوري في الطوارئ"),
                        icon: "phone.badge.checkmark",
                        isVerified: $verification.emergencyContactConfirmed
                    ) {
                        toggleVerification(&verification.emergencyContactConfirmed)
                    }

                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyAgreement", alter: "الموافقة على شروط الرعاية الفندقية"),
                        subtitle: Language.get("Hotel_VerifyAgreement_Sub", alter: "الموافقة على سياسة الرعاية والطوارئ الفندقية"),
                        icon: "doc.text.fill",
                        isVerified: $verification.agreementAcknowledged
                    ) {
                        toggleVerification(&verification.agreementAcknowledged)
                    }

                    if (reservation.depositMinor ?? 0) > 0 {
                        AdminHotelVerificationCard(
                            title: Language.get("Hotel_VerifyDeposit", alter: "تأكيد حالة العربون المستحق"),
                            subtitle: Language.get("Hotel_VerifyDeposit_Sub", alter: "التحقق من سداد العربون المسبق للحجز"),
                            icon: "creditcard.fill",
                            isVerified: $verification.depositSettled
                        ) {
                            toggleVerification(&verification.depositSettled)
                        }
                    }
                }
            }
        }
    }

    private func toggleVerification(_ binding: inout Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        binding.toggle()
    }

    // MARK: - iPhone Belongings Vault
    private var iPhoneBelongingsVault: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(Language.get("Hotel_RecordBelongings", alter: "تسجيل المقتنيات المستلمة عند الوصول"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(spacing: 10) {
                // Quick Suggestion Chips Cloud
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Hotel_QuickChips_Title", alter: "اقتراحات سريعة للمقتنيات:"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(quickChips, id: \.self) { chip in
                                Button {
                                    addBelongingNamed(chip)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(chip)
                                            .font(Font.custom("Beiruti-Medium", size: 12))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AdminSurface.surface, in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.5)
                                    )
                                    .foregroundStyle(AdminSurface.primaryText)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Existing items list
                if !belongings.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(belongings) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AdminSurface.primary)

                                Text(item.name)
                                    .font(Font.custom("Beiruti-Medium", size: 13.5))
                                    .foregroundStyle(AdminSurface.primaryText)

                                Spacer()

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    belongings.removeAll(where: { $0.id == item.id })
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.red.opacity(0.8))
                                        .padding(6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                // Custom Add Row
                HStack(spacing: 8) {
                    TextField(
                        Language.get("Hotel_AddBelongingPrompt", alter: "أضف غرضاً مثل دواء أو بطانية"),
                        text: $newBelongingName
                    )
                    .font(Font.custom("Beiruti-Medium", size: 13.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        addBelongingNamed(newBelongingName)
                        newBelongingName = ""
                    } label: {
                        Text(Language.get("Add", alter: "إضافة"))
                            .font(Font.custom("Beiruti-Bold", size: 13.5))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(newBelongingName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(newBelongingName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                }
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
    }

    private func addBelongingNamed(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        belongings.append(AdminHotelBelongingItem(name: trimmed))
    }

    // MARK: - iPhone Notes Studio
    private var iPhoneNotesStudio: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(Language.get("Hotel_IntakeNotes", alter: "ملاحظات الوصول"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "note.text")
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Quick Note Pills
                HStack(spacing: 6) {
                    ForEach(quickNotePills, id: \.self) { pill in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if internalNotes.isEmpty {
                                internalNotes = pill
                            } else {
                                internalNotes += " • \(pill)"
                            }
                        } label: {
                            Text(pill)
                                .font(Font.custom("Beiruti-Medium", size: 11.5))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AdminSurface.surface, in: Capsule())
                        }
                    }
                }

                TextField(
                    Language.get("Hotel_IntakeNotesPlaceholder", alter: "تعليمات الطعام أو الحساسية أو السلوك أو غيرها"),
                    text: $internalNotes
                )
                .font(Font.custom("Beiruti-Medium", size: 13.5))
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
    }

    // MARK: - iPhone Docked Floating Action Bar
    private var iPhoneDockedActionBar: some View {
        let isReady = isVerificationComplete && selectedRoom != nil && authoritativeStay != nil && !viewModel.isSubmitting

        return VStack(spacing: 6) {
            // Status warning hint if disabled
            if !isReady && !viewModel.isSubmitting {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                    if selectedRoom == nil {
                        Text(Language.get("Hotel_Readiness_SelectRoomFirst", alter: "يرجى تحديد الغرفة أولاً"))
                    } else if authoritativeStay == nil {
                        Text(Language.get("Hotel_Err_StayRequired", alter: "لا يوجد سجل إقامة جاهز لهذا الحجز."))
                    } else {
                        Text(String(format: Language.get("Hotel_Readiness_MissingRequirements", alter: "متطلبات متبقية: %d"), totalCount - completedCount))
                    }
                }
                .font(Font.custom("Beiruti-Medium", size: 12))
                .foregroundStyle(Color.orange)
            }

            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                onConfirmCheckIn()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(Language.get("Hotel_ConfirmCheckIn", alter: "تأكيد الوصول وتسكين النزيل"))
                        .font(Font.custom("Beiruti-Bold", size: 17))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    isReady
                        ? LinearGradient(
                            colors: [Color(red: 0.16, green: 0.72, blue: 0.44), Color(red: 0.10, green: 0.82, blue: 0.50)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [Color(uiColor: .systemGray4), Color(uiColor: .systemGray4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(
                    color: isReady ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.35) : .clear,
                    radius: 10,
                    y: 4
                )
            }
            .disabled(!isReady)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, max(UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 0, 16))
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(Font.custom("Beiruti-Medium", size: 13))
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    private func callPhone(_ raw: String) {
        let clean = raw.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    private func localizedPetSpecies(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "cat" || s == "قط" || s == "قطة" || s == "cats" {
            return Language.get("Pet_Cat", alter: "قط")
        } else if s == "dog" || s == "كلب" || s == "dogs" {
            return Language.get("Pet_Dog", alter: "كلب")
        } else if s == "bird" || s == "طير" || s == "طائر" || s == "birds" {
            return Language.get("Pet_Bird", alter: "طائر")
        } else if s == "rabbit" || s == "أرنب" || s == "rabbits" {
            return Language.get("Pet_Rabbit", alter: "أرنب")
        } else if s.isEmpty {
            return ""
        }
        return raw
    }
}

// MARK: - iPad Dedicated Architecture (Panoramic Two-Column Command Station)
private struct AdminPetsHotelCheckIn_iPad: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Binding var selectedRoom: AdminHotelAccommodation?
    @Binding var verification: AdminHotelCheckInVerification
    @Binding var belongings: [AdminHotelBelongingItem]
    let availabilitySnapshot: AdminHotelAvailabilitySnapshot?
    let availabilityErrorMessage: String?
    let isLoadingAvailability: Bool
    @Binding var newBelongingName: String
    @Binding var internalNotes: String
    @Binding var showVerificationDetails: Bool
    let authoritativeStay: AdminHotelStay?
    let medicationRequired: Bool
    let isVerificationComplete: Bool
    let completedCount: Int
    let totalCount: Int
    let onRefreshAvailability: () -> Void
    let onConfirmCheckIn: () -> Void
    let onDismiss: () -> Void

    private let quickChips: [String] = [
        Language.get("Hotel_Chip_CollarLeash", alter: "طوق ومقود"),
        Language.get("Hotel_Chip_BlanketBed", alter: "بطانية / فراش"),
        Language.get("Hotel_Chip_Medication", alter: "دواء مخصص"),
        Language.get("Hotel_Chip_Carrier", alter: "قفص نقل"),
        Language.get("Hotel_Chip_SpecialFood", alter: "طعام خاص"),
        Language.get("Hotel_Chip_Toys", alter: "ألعاب النزيل")
    ]

    private let quickNotePills: [String] = [
        Language.get("Hotel_NoteTag_Calm", alter: "هادئ ومطيع"),
        Language.get("Hotel_NoteTag_Anxious", alter: "متوتر من الغرباء"),
        Language.get("Hotel_NoteTag_SpecialDiet", alter: "نظام غذائي دقيق"),
        Language.get("Hotel_NoteTag_NeedsCare", alter: "عناية طبية خاصة")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Widescreen Command Header
            iPadTopHeader

            // Dual Column Panoramic Flight Deck
            HStack(alignment: .top, spacing: 20) {
                // Left Column: Guest & Financial Dossier (38% width)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        iPadPetHeroProfile
                        iPadReadinessDialCard
                        iPadOwnerContactCard
                        iPadScheduleTimelineCard
                        iPadFinancialLedgerCard
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                }
                .frame(width: 360)

                // Right Column: Operational Intake Deck (62% width)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        if let err = viewModel.errorMessage {
                            errorBanner(err)
                        }

                        iPadRoomAllocationMatrix
                        iPadVerificationMatrix
                        iPadBelongingsVault
                        iPadNotesStudio
                        Spacer(minLength: 80)
                    }
                    .padding(.vertical, 16)
                    .padding(.trailing, 16)
                }
            }
            .padding(.horizontal, 20)

            // Pinned Widescreen Tactical Action Bar
            iPadBottomActionBar
        }
        .edgesIgnoringSafeArea(.top)
    }

    // MARK: - iPad Top Header
    private var iPadTopHeader: some View {
        let refNo = !reservation.reservationNumber.isEmpty ? reservation.reservationNumber : String(reservation.id.prefix(8)).uppercased()
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                // Ref Capsule
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.72, blue: 0.44))
                        .frame(width: 7, height: 7)
                    Text(refNo)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())

                // Title
                Text(Language.get("Hotel_CheckIn_Title", alter: "تسجيل وصول النزيل"))
                    .font(Font.custom("Beiruti-Bold", size: 22))
                    .foregroundStyle(AdminSurface.primaryText)

                // Wing Tag
                HStack(spacing: 5) {
                    Image(systemName: reservation.wing.icon)
                        .font(.system(size: 12, weight: .bold))
                    Text(reservation.wing.title)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(reservation.wing.tint.opacity(0.14), in: Capsule())
                .foregroundStyle(reservation.wing.tint)

                Spacer()

                // Close Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 40, height: 40)
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .overlay(
                        Circle()
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.highlight)
            }
            .padding(.horizontal, 24)
            .padding(.top, max(PPStatusBarHelper.statusBarHeight, 44))
            .padding(.bottom, 12)
            .background(AdminSurface.background)

            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.4))
        }
    }

    // MARK: - iPad Left Panel Components
    private var iPadPetHeroProfile: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                reservation.wing.tint.opacity(0.25),
                                reservation.wing.tint.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                Image(systemName: reservation.wing.icon)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(reservation.wing.tint)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(reservation.wing.tint.opacity(0.35), lineWidth: 0.75)
            )

            Text(reservation.petName)
                .font(Font.custom("Beiruti-Bold", size: 22))
                .foregroundStyle(AdminSurface.primaryText)

            Text(petSubtitle)
                .font(Font.custom("Beiruti-Medium", size: 13.5))
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var petSubtitle: String {
        let species = localizedPetSpecies(reservation.petSpecies)
        let breed = reservation.petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !species.isEmpty && !breed.isEmpty {
            return "\(species) • \(breed)"
        } else if !species.isEmpty {
            return species
        } else if !breed.isEmpty {
            return breed
        }
        return reservation.wing.title
    }

    private var iPadReadinessDialCard: some View {
        let progress = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
        let isReady = isVerificationComplete && selectedRoom != nil && authoritativeStay != nil

        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                // Circular Ring Meter
                ZStack {
                    Circle()
                        .stroke(Color(uiColor: .systemGray5), lineWidth: 6)
                        .frame(width: 54, height: 54)

                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            isReady ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color.orange,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 54, height: 54)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: progress)

                    Text("\(Int(progress * 100))%")
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(isReady ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_Readiness_Title", alter: "جاهزية الاستقبال والتسكين"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text("\(completedCount) / \(totalCount) " + Language.get("Completed", alter: "مكتمل"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var iPadOwnerContactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(Language.get("Hotel_PetOwner", alter: "مالك الحيوان"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(AdminSurface.primary)
            }

            Text(reservation.customerName)
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            if !reservation.customerPhone.isEmpty {
                Button {
                    callPhone(reservation.customerPhone)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 14))
                        Text(reservation.customerPhone)
                            .font(Font.custom("Beiruti-Medium", size: 13))
                    }
                    .foregroundStyle(AdminSurface.primary)
                }
                .hoverEffect(.highlight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var iPadScheduleTimelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(Language.get("Hotel_StayPeriod", alter: "فترة الإقامة"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "calendar")
                    .foregroundStyle(AdminSurface.primary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_Arrival", alter: "الوصول"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatDate(reservation.checkInDate))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("Hotel_Departure", alter: "المغادرة"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatDate(reservation.checkOutDate))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var iPadFinancialLedgerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(Language.get("Hotel_Ledger_Total", alter: "إجمالي الحساب:"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "creditcard")
                    .foregroundStyle(AdminSurface.primary)
            }

            HStack {
                Text(displayedPriceText)
                    .font(Font.custom("Beiruti-Bold", size: 22))
                    .foregroundStyle(AdminSurface.primary)
                Spacer()
                if let bal = reservation.balanceDueMinor, bal > 0 {
                    let formattedBal = String(format: "%.0f", Double(bal) / 100.0)
                    let currency = Language.get("Currency_QAR", alter: "ر.ق")
                    let pending = Language.get("Pending", alter: "متبقي")
                    Text("\(formattedBal) \(currency) \(pending)")
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var displayedPriceText: String {
        if let total = reservation.totalAmountMinor, total > 0 {
            return reservation.formattedTotal
        }
        let rateMinor = selectedRoom?.nightlyRateMinor
            ?? viewModel.accommodations.first(where: { $0.id == reservation.assignedAccommodationId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.id == reservation.accommodationTypeId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.wing == reservation.wing })?.nightlyRateMinor

        if let rateMinor, rateMinor > 0 {
            let total = Double(rateMinor * max(1, reservation.numberOfNights)) / 100.0
            return String(format: "%.0f %@", total, Language.get("Currency_QAR", alter: "ر.ق"))
        }
        return reservation.formattedTotal
    }

    // MARK: - iPad Right Panel Components
    private var iPadRoomAllocationMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(Language.get("Hotel_SelectRoom", alter: "اختر الجناح أو الغرفة"))
                        .font(Font.custom("Beiruti-Bold", size: 17))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "bed.double.fill")
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRefreshAvailability()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            let availableRooms = viewModel.accommodations.filter {
                (availabilitySnapshot?.assignableIds.contains($0.id) ?? false)
            }

            if isLoadingAvailability {
                HStack(spacing: 12) {
                    AdminHotelShimmerRoomCard()
                    AdminHotelShimmerRoomCard()
                    AdminHotelShimmerRoomCard()
                }
            } else if let availabilityErrorMessage {
                AdminHotelAvailabilityDiagnosticsBanner(
                    snapshot: availabilitySnapshot,
                    errorMessage: availabilityErrorMessage
                )
            } else if availableRooms.isEmpty {
                AdminHotelAvailabilityDiagnosticsBanner(
                    snapshot: availabilitySnapshot,
                    errorMessage: nil
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 10)], spacing: 10) {
                    ForEach(availableRooms) { room in
                        let isSelected = selectedRoom?.id == room.id
                        AdminHotelRoomTile(
                            room: room,
                            isSelected: isSelected
                        ) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedRoom = room
                        }
                    }
                }
            }
        }
    }

    private var iPadVerificationMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(Language.get("Hotel_VerificationTitle", alter: "متطلبات الدخول والتحقق الإلزامي"))
                    .font(Font.custom("Beiruti-Bold", size: 17))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 8) {
                AdminHotelVerificationCard(
                    title: Language.get("Hotel_VerifyIdentity", alter: "التحقق من هوية الحيوان والمالك"),
                    subtitle: Language.get("Hotel_VerifyIdentity_Sub", alter: "مطابقة بيانات المالك والشريحة الإلكترونية"),
                    icon: "person.text.rectangle.fill",
                    isVerified: $verification.petIdentityVerified
                ) {
                    toggleVerification(&verification.petIdentityVerified)
                }

                AdminHotelVerificationCard(
                    title: Language.get("Hotel_VerifyVaccination", alter: "شهادة التطعيمات سارية وموثقة"),
                    subtitle: Language.get("Hotel_VerifyVaccination_Sub", alter: "دفتر التطعيمات معتمد وخالي من التحذيرات"),
                    icon: "syringe.fill",
                    isVerified: $verification.vaccinationVerified
                ) {
                    toggleVerification(&verification.vaccinationVerified)
                }

                AdminHotelVerificationCard(
                    title: Language.get("Hotel_VerifyInspection", alter: "الفحص السريري الأولي سليم"),
                    subtitle: Language.get("Hotel_VerifyInspection_Sub", alter: "فحص الجلد والعيون والنشاط السريري العام"),
                    icon: "stethoscope",
                    isVerified: $verification.healthInspectionCompleted
                ) {
                    toggleVerification(&verification.healthInspectionCompleted)
                }

                AdminHotelVerificationCard(
                    title: Language.get("Hotel_VerifyDiet", alter: "تأكيد النظام الغذائي والحساسيات"),
                    subtitle: Language.get("Hotel_VerifyDiet_Sub", alter: "مراجعة مواعيد الوجبات ومسببات الحساسية"),
                    icon: "fork.knife",
                    isVerified: $verification.dietConfirmed
                ) {
                    toggleVerification(&verification.dietConfirmed)
                }

                if medicationRequired {
                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyMedication", alter: "تأكيد خطة الأدوية إن وجدت"),
                        subtitle: Language.get("Hotel_VerifyMedication_Sub", alter: "مطابقة الجرعات ومواعيد إعطاء الدواء"),
                        icon: "pill.fill",
                        isVerified: $verification.medicationConfirmed
                    ) {
                        toggleVerification(&verification.medicationConfirmed)
                    }
                }

                AdminHotelVerificationCard(
                    title: Language.get("Hotel_VerifyEmergency", alter: "تأكيد رقم الطوارئ البديل"),
                    subtitle: Language.get("Hotel_VerifyEmergency_Sub", alter: "رقم فعال للتواصل الفوري في الطوارئ"),
                    icon: "phone.badge.checkmark",
                    isVerified: $verification.emergencyContactConfirmed
                ) {
                    toggleVerification(&verification.emergencyContactConfirmed)
                }

                AdminHotelVerificationCard(
                    title: Language.get("Hotel_VerifyAgreement", alter: "الموافقة على شروط الرعاية الفندقية"),
                    subtitle: Language.get("Hotel_VerifyAgreement_Sub", alter: "الموافقة على سياسة الرعاية والطوارئ الفندقية"),
                    icon: "doc.text.fill",
                    isVerified: $verification.agreementAcknowledged
                ) {
                    toggleVerification(&verification.agreementAcknowledged)
                }

                if (reservation.depositMinor ?? 0) > 0 {
                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyDeposit", alter: "تأكيد حالة العربون المستحق"),
                        subtitle: Language.get("Hotel_VerifyDeposit_Sub", alter: "التحقق من سداد العربون المسبق للحجز"),
                        icon: "creditcard.fill",
                        isVerified: $verification.depositSettled
                    ) {
                        toggleVerification(&verification.depositSettled)
                    }
                }
            }
        }
    }

    private func toggleVerification(_ binding: inout Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        binding.toggle()
    }

    private var iPadBelongingsVault: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(Language.get("Hotel_RecordBelongings", alter: "تسجيل المقتنيات المستلمة عند الوصول"))
                    .font(Font.custom("Beiruti-Bold", size: 17))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(spacing: 10) {
                // Quick Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickChips, id: \.self) { chip in
                            Button {
                                addBelongingNamed(chip)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(chip)
                                        .font(Font.custom("Beiruti-Medium", size: 13))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AdminSurface.surface, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.5)
                                )
                                .foregroundStyle(AdminSurface.primaryText)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .hoverEffect(.highlight)
                        }
                    }
                }

                // Belongings List
                if !belongings.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(belongings) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AdminSurface.primary)

                                Text(item.name)
                                    .font(Font.custom("Beiruti-Medium", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)

                                Spacer()

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    belongings.removeAll(where: { $0.id == item.id })
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.red.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                // Input Bar
                HStack(spacing: 10) {
                    TextField(
                        Language.get("Hotel_AddBelongingPrompt", alter: "أضف غرضاً مثل دواء أو بطانية"),
                        text: $newBelongingName
                    )
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        addBelongingNamed(newBelongingName)
                        newBelongingName = ""
                    } label: {
                        Text(Language.get("Add", alter: "إضافة"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(newBelongingName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
    }

    private func addBelongingNamed(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        belongings.append(AdminHotelBelongingItem(name: trimmed))
    }

    private var iPadNotesStudio: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(Language.get("Hotel_IntakeNotes", alter: "ملاحظات الوصول"))
                    .font(Font.custom("Beiruti-Bold", size: 17))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "note.text")
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(quickNotePills, id: \.self) { pill in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if internalNotes.isEmpty {
                                internalNotes = pill
                            } else {
                                internalNotes += " • \(pill)"
                            }
                        } label: {
                            Text(pill)
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AdminSurface.surface, in: Capsule())
                        }
                        .hoverEffect(.highlight)
                    }
                }

                TextField(
                    Language.get("Hotel_IntakeNotesPlaceholder", alter: "تعليمات الطعام أو الحساسية أو السلوك أو غيرها"),
                    text: $internalNotes
                )
                .font(Font.custom("Beiruti-Medium", size: 14))
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
    }

    // MARK: - iPad Bottom Action Bar
    private var iPadBottomActionBar: some View {
        let isReady = isVerificationComplete && selectedRoom != nil && authoritativeStay != nil && !viewModel.isSubmitting

        return VStack(spacing: 0) {
            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.4))

            HStack(spacing: 16) {
                // Dismiss Action
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.highlight)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                // Readiness summary
                if !isReady && !viewModel.isSubmitting {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        if selectedRoom == nil {
                            Text(Language.get("Hotel_Readiness_SelectRoomFirst", alter: "يرجى تحديد الغرفة أولاً"))
                        } else {
                            Text(String(format: Language.get("Hotel_Readiness_MissingRequirements", alter: "متطلبات متبقية: %d"), totalCount - completedCount))
                        }
                    }
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .foregroundStyle(.orange)
                }

                // Primary Check-In Button with ⌘+Return Shortcut
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onConfirmCheckIn()
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(Language.get("Hotel_ConfirmCheckIn", alter: "تأكيد الوصول وتسكين النزيل"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .frame(height: 48)
                    .background(
                        isReady
                            ? LinearGradient(
                                colors: [Color(red: 0.16, green: 0.72, blue: 0.44), Color(red: 0.10, green: 0.82, blue: 0.50)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color(uiColor: .systemGray4), Color(uiColor: .systemGray4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(
                        color: isReady ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.35) : .clear,
                        radius: 8,
                        y: 3
                    )
                }
                .disabled(!isReady)
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.highlight)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(AdminSurface.background)
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(Font.custom("Beiruti-Medium", size: 13))
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    private func callPhone(_ raw: String) {
        let clean = raw.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    private func localizedPetSpecies(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "cat" || s == "قط" || s == "قطة" || s == "cats" {
            return Language.get("Pet_Cat", alter: "قط")
        } else if s == "dog" || s == "كلب" || s == "dogs" {
            return Language.get("Pet_Dog", alter: "كلب")
        } else if s == "bird" || s == "طير" || s == "طائر" || s == "birds" {
            return Language.get("Pet_Bird", alter: "طائر")
        } else if s == "rabbit" || s == "أرنب" || s == "rabbits" {
            return Language.get("Pet_Rabbit", alter: "أرنب")
        } else if s.isEmpty {
            return ""
        }
        return raw
    }
}

// MARK: - Category-Defining Shared Hotel Room & Verification Tiles
private struct AdminHotelRoomTile: View {
    let room: AdminHotelAccommodation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.accommodationNumber)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Text(room.name)
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : AdminSurface.secondaryText)
                    .lineLimit(1)

                Text(room.formattedRate)
                    .font(Font.custom("Beiruti-Bold", size: 12.5))
                    .foregroundStyle(isSelected ? .white : AdminSurface.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.45), lineWidth: isSelected ? 1.5 : 0.75)
            )
            .shadow(color: isSelected ? AdminSurface.primary.opacity(0.24) : Color.clear, radius: 6, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.accommodationNumber), \(room.name), \(room.formattedRate)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

private struct AdminHotelVerificationCard: View {
    let title: String
    let subtitle: String?
    let icon: String
    @Binding var isVerified: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Icon Emblem Container
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isVerified ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.18) : AdminSurface.surface)
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isVerified ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
                }

                // Title & Subtitle Stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Font.custom("Beiruti-Regular", size: 11.5))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Custom Tactile Haptic Switch Capsule
                ZStack {
                    Capsule()
                        .fill(isVerified ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color(uiColor: .systemGray4))
                        .frame(width: 44, height: 26)

                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: Color.black.opacity(0.14), radius: 2, y: 1)
                        .offset(x: isVerified ? 9 : -9)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isVerified)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isVerified ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.06) : AdminSurface.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isVerified ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.35) : Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isVerified ? Language.get("Checked", alter: "تم التحقق") : Language.get("Unchecked", alter: "لم يتم التحقق"))
        .accessibilityHint(Language.get("DoubleTapToToggle", alter: "اضغط مرتين للتبديل"))
    }
}

private struct AdminHotelShimmerRoomCard: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(uiColor: .systemGray4))
                .frame(width: 55, height: 16)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 95, height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(uiColor: .systemGray5))
                .frame(width: 65, height: 13)
        }
        .padding(12)
        .frame(width: 140, height: 84)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.0)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: (phase * 2 - 1) * 140)
        )
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

private struct AdminHotelAvailabilityDiagnosticsBanner: View {
    let snapshot: AdminHotelAvailabilitySnapshot?
    let errorMessage: String?

    private var accent: Color { errorMessage == nil ? .orange : .red }

    private var title: String {
        if errorMessage != nil {
            return Language.get("Hotel_Availability_LoadFailed", alter: "تعذر التحقق من توفر الغرف")
        }
        if snapshot?.units.isEmpty == true {
            return Language.get("Hotel_Availability_NoMatchingType", alter: "لا توجد غرف مطابقة لفئة الحجز")
        }
        return Language.get("Hotel_NoAvailableRoomsInWing", alter: "لا توجد غرف قابلة للتسكين خلال الفترة المحددة")
    }

    private var subtitle: String {
        if let errorMessage, !errorMessage.isEmpty { return errorMessage }
        if snapshot?.units.isEmpty == true {
            return Language.get(
                "Hotel_Availability_NoMatchingType_Help",
                alter: "راجع فئة الجناح المحجوز أو غيّر الفئة من إدارة الحجز قبل التسكين."
            )
        }
        return Language.get(
            "Hotel_Availability_Rejections_Help",
            alter: "الغرف موجودة، لكن قواعد التسكين الحالية تمنع استخدامها لهذا النزيل. الأسباب موضحة أدناه."
        )
    }

    private var rejectedUnits: [AdminHotelAvailabilityUnit] {
        Array((snapshot?.rejectedUnits ?? []).prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: errorMessage == nil ? "exclamationmark.triangle.fill" : "wifi.exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Font.custom("Beiruti-Bold", size: 13.5))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(subtitle)
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if errorMessage == nil {
                ForEach(rejectedUnits) { unit in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(unit.code.isEmpty ? unit.name : unit.code)
                                .font(Font.custom("Beiruti-Bold", size: 12.5))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(unit.rejections.map(reasonText).joined(separator: " • "))
                                .font(Font.custom("Beiruti-Regular", size: 11.5))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.24), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
    }

    private func reasonText(_ code: String) -> String {
        switch code {
        case "unit_inactive":
            return Language.get("Hotel_Availability_Reason_Inactive", alter: "الغرفة غير مفعلة")
        case "unit_out_of_service":
            return Language.get("Hotel_Availability_Reason_OutOfService", alter: "الغرفة خارج الخدمة")
        case "unit_not_assignable":
            return Language.get("Hotel_Availability_Reason_Status", alter: "حالة الغرفة لا تسمح بالتسكين")
        case "species_not_allowed":
            return Language.get("Hotel_Availability_Reason_Species", alter: "نوع الحيوان غير مسموح لهذه الغرفة")
        case "branch_mismatch":
            return Language.get("Hotel_Availability_Reason_Branch", alter: "الغرفة تابعة لفرع آخر")
        case "capacity_exceeded":
            return Language.get("Hotel_Availability_Reason_Capacity", alter: "السعة ممتلئة خلال الفترة")
        case "sharing_not_allowed":
            return Language.get("Hotel_Availability_Reason_Sharing", alter: "المشاركة غير مسموحة")
        case "double_booked":
            return Language.get("Hotel_Availability_Reason_Booking", alter: "يوجد حجز متعارض خلال الفترة")
        case "unit_not_found":
            return Language.get("Hotel_Availability_Reason_Missing", alter: "سجل الغرفة غير موجود")
        default:
            return code.replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - Express Check-Out Sheet
@MainActor
public struct AdminPetsHotelCheckOutSheet: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var verification = AdminHotelCheckOutVerification()
    @State private var earlyReason: String = "early_departure_by_owner"
    @State private var showSettlementSheet: Bool = false

    private var currentStay: AdminHotelStay {
        viewModel.stays.first(where: { $0.id == stay.id })
            ?? (viewModel.checkOutModalStay?.id == stay.id ? (viewModel.checkOutModalStay ?? stay) : stay)
    }

    private var isEarly: Bool {
        Date() < currentStay.expectedCheckOutTime
    }

    public var body: some View {
        VStack(spacing: 0) {
            checkOutNavBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Stay Discharge Hero
                    stayDischargeHero

                    // Outstanding Balance Notice Card
                    if currentStay.outstandingMinor > 0 {
                        outstandingBalanceCard
                    }

                    // Error Alert Banner
                    if let err = viewModel.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.red)
                            Text(err)
                                .font(Font.custom("Beiruti-Medium", size: 13.5))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if currentStay.outstandingMinor > 0 && viewModel.canViewBilling {
                                Button {
                                    showSettlementSheet = true
                                } label: {
                                    Text(Language.get("Hotel_Settle_Action", alter: "تسوية"))
                                        .font(Font.custom("Beiruti-Bold", size: 12.5))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.red, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Verification Checklist
                    verificationChecklist

                    // Early Checkout Notice
                    if isEarly {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.system(size: 18))
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("Hotel_EarlyCheckoutAlert", alter: "مغادرة مبكرة قبل الموعد المقرر"))
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)
                                Text(Language.get("Hotel_EarlyCheckoutSub", alter: "سيتم احتساب الليالي الفعلية وفق السياسة التشغيلية"))
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Execute Departure Button
                    executeDepartureButton
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showSettlementSheet) {
            AdminHotelQuickSettlementSheet(stay: currentStay, viewModel: viewModel)
        }
    }

    private var checkOutNavBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Hotel_Checkout_Title", alter: "تسجيل مغادرة النزيل"),
            subtitle: "\(currentStay.petName) • \(currentStay.roomNumber.isEmpty ? currentStay.wing.title : currentStay.roomNumber)",
            statusDotColor: Color(red: 0.82, green: 0.15, blue: 0.35),
            isModal: true,
            onBack: { dismiss() }
        ) {
            HStack(spacing: 4) {
                Image(systemName: currentStay.wing.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(currentStay.wing.title)
                    .font(Font.custom("Beiruti-Bold", size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(currentStay.wing.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(currentStay.wing.tint)
        }
    }

    private var stayDischargeHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.15))
                    .frame(width: 68, height: 68)
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color(red: 0.82, green: 0.15, blue: 0.35))
            }

            VStack(spacing: 4) {
                Text(currentStay.petName)
                    .font(Font.custom("Beiruti-Bold", size: 24))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(localizedSpeciesAndBreed)
                    .font(Font.custom("Beiruti-Medium", size: 15))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Text(Language.get("Hotel_CheckoutPrompt", alter: "إجراءات مغادرة النزيل وتسليم الأغراض وتفريغ الجناح"))
                .font(Font.custom("Beiruti-Medium", size: 13))
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var outstandingBalanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Hotel_OutstandingBalance_Notice", alter: "رصيد مالي مستحق على الإقامة"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Hotel_OutstandingBalance_ActionHint", alter: "يجب تسوية المبلغ المالي المتبقي قبل تسجيل المغادرة وتسليم النزيل."))
                        .font(Font.custom("Beiruti-Medium", size: 12.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
            }

            Divider()
                .background(Color.orange.opacity(0.25))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_Ledger_Balance", alter: "المتبقي للدفع:"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(String(format: "%.0f %@", Double(currentStay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(Font.custom("Beiruti-Bold", size: 22))
                        .foregroundStyle(Color.orange)
                }

                Spacer()

                if viewModel.canViewBilling {
                    Button {
                        showSettlementSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(Language.get("Hotel_SettleBalance_Button", alter: "تسجيل تسوية الرصيد"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Color.orange.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Text(Language.get("Hotel_SettleBalance_Restricted", alter: "يرجى مراجعة موظف الحسابات لتسوية الرصيد المتبقي."))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private var verificationChecklist: some View {
        VStack(spacing: 10) {
            if currentStay.belongingCount > 0 {
                Toggle(isOn: $verification.belongingsReturned) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_BelongingsHandedBack", alter: "تسليم كافة الأغراض للمالك"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Language.get("Hotel_BelongingsVerifySub", alter: "تم التحقق من تطابق العهدة ومحتوياتها"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

                Divider()
            }

            Toggle(isOn: $verification.healthCheckCompleted) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_DischargeHealthCheck", alter: "فحص المؤشرات الصحية قبل المغادرة"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Language.get("Hotel_DischargeHealthSub", alter: "النزيل بحالة طبيعية ومستقرة"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

            Divider()

            Toggle(isOn: $verification.roomInspectionCompleted) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_RoomInspectionComplete", alter: "اكتمال فحص الغرفة قبل التسليم"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Language.get("Hotel_RoomInspectionDetail", alter: "تم توثيق حالة الغرفة وأي ملاحظات تشغيلية"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

            Divider()

            if currentStay.criticalIncidentCount > 0 {
                Toggle(isOn: $verification.incidentsAcknowledged) {
                    Text(Language.get("Hotel_IncidentsAcknowledged", alter: "مراجعة الحوادث والملاحظات المفتوحة"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

                Divider()
            }

            if currentStay.pendingMedicationCount > 0 {
                Toggle(isOn: $verification.medicationResolved) {
                    Text(Language.get("Hotel_MedicationResolved", alter: "تسوية جميع مهام الأدوية"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

                Divider()
            }

            Toggle(isOn: $verification.handoverVerified) {
                Text(Language.get("Hotel_HandoverVerified", alter: "التحقق من هوية المستلم وتسليم النزيل"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_RoomCleaningAutomatic", alter: "بعد المغادرة ينقل الخادم الغرفة تلقائياً إلى حالة التنظيف."))
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var executeDepartureButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await viewModel.executeCheckOut(
                        stay: currentStay,
                        verification: verification,
                        earlyReason: isEarly ? earlyReason : nil
                    )
                    if viewModel.errorMessage == nil {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: Language.isRTL() ? "arrow.left.to.line" : "arrow.right.to.line")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(Language.get("Hotel_ConfirmCheckoutButton", alter: "إتمام المغادرة وتسليم النزيل"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    viewModel.isSubmitting || !isCheckOutVerificationComplete || !viewModel.canCheckOut
                        ? Color.gray.opacity(0.4)
                        : Color(red: 0.82, green: 0.15, blue: 0.35),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.3), radius: 10, y: 4)
            }
            .disabled(viewModel.isSubmitting || !isCheckOutVerificationComplete || !viewModel.canCheckOut)
            .buttonStyle(PlainButtonStyle())

            if currentStay.outstandingMinor > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                    Text(Language.get("Hotel_OutstandingBalance_ActionHint", alter: "يجب تسوية المبلغ المالي المتبقي قبل تسجيل المغادرة وتسليم النزيل."))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.top, 2)
            }
        }
    }

    private var localizedSpeciesAndBreed: String {
        let breed = currentStay.petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        let species = localizedSpecies(currentStay.petSpecies)
        if !breed.isEmpty && !species.isEmpty {
            return "\(species) • \(breed)"
        } else if !species.isEmpty {
            return species
        } else if !breed.isEmpty {
            return breed
        } else {
            return currentStay.wing.title
        }
    }

    private func localizedSpecies(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "cat" || s == "قط" || s == "قطة" || s == "cats" {
            return Language.get("Pet_Cat", alter: "قط")
        } else if s == "dog" || s == "كلب" || s == "dogs" {
            return Language.get("Pet_Dog", alter: "كلب")
        } else if s == "bird" || s == "طير" || s == "طائر" || s == "birds" {
            return Language.get("Pet_Bird", alter: "طائر")
        } else if s == "rabbit" || s == "أرنب" || s == "rabbits" {
            return Language.get("Pet_Rabbit", alter: "أرنب")
        } else if s.isEmpty {
            return ""
        }
        return raw
    }

    private var isCheckOutVerificationComplete: Bool {
        verification.healthCheckCompleted &&
        verification.roomInspectionCompleted &&
        verification.handoverVerified &&
        (currentStay.belongingCount == 0 || verification.belongingsReturned) &&
        (currentStay.criticalIncidentCount == 0 || verification.incidentsAcknowledged) &&
        (currentStay.pendingMedicationCount == 0 || verification.medicationResolved) &&
        currentStay.outstandingMinor == 0
    }
}

// MARK: - Quick Stay Settlement Sheet
@MainActor
public struct AdminHotelQuickSettlementSheet: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMethod: String = "cash"
    @State private var reference: String = ""
    @State private var notes: String = ""
    @State private var isProcessing: Bool = false

    public var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            AdminSovereignNavigationBar(
                title: Language.get("Hotel_Settlement_Title", alter: "تسجيل تسوية رصيد الإقامة"),
                subtitle: "\(stay.petName) • \(String(format: "%.0f %@", Double(stay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))",
                statusDotColor: Color.orange,
                isModal: true,
                onBack: { dismiss() }
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Hero amount card
                    VStack(spacing: 8) {
                        Text(Language.get("Hotel_Settlement_AmountToPay", alter: "المبلغ المطلوب تسويته:"))
                            .font(Font.custom("Beiruti-Medium", size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(String(format: "%.0f %@", Double(stay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                            .font(Font.custom("Beiruti-Bold", size: 32))
                            .foregroundStyle(Color.orange)

                        Text("\(stay.petName) • \(stay.customerName)")
                            .font(Font.custom("Beiruti-Medium", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
                    )

                    // Error Alert Banner if any
                    if let err = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(Font.custom("Beiruti-Medium", size: 13))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Payment Method Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Language.get("Hotel_Settlement_Method", alter: "طريقة الدفع"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        HStack(spacing: 12) {
                            methodCard(
                                method: "cash",
                                title: Language.get("Hotel_Settlement_Method_Cash", alter: "نقداً (كاش)"),
                                icon: "banknote.fill"
                            )

                            methodCard(
                                method: "card_terminal",
                                title: Language.get("Hotel_Settlement_Method_Card", alter: "بطاقة / جهاز POS"),
                                icon: "creditcard.fill"
                            )
                        }
                    }
                    .padding(16)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
                    )

                    // Reference & Notes Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Language.get("Hotel_Settlement_Reference", alter: "الرقم المرجعي"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        TextField(Language.get("Hotel_Settlement_RefPlaceholder", alter: "رقم إيصال أو عملية السداد (اختياري)"), text: $reference)
                            .font(Font.custom("Beiruti-Medium", size: 14))
                            .padding(12)
                            .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.8)
                            )

                        Text(Language.get("Hotel_Settlement_Notes", alter: "ملاحظات"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .padding(.top, 4)

                        TextField(Language.get("Hotel_Settlement_NotesPlaceholder", alter: "ملاحظات إضافية على السداد (اختياري)"), text: $notes)
                            .font(Font.custom("Beiruti-Medium", size: 14))
                            .padding(12)
                            .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.8)
                            )
                    }
                    .padding(16)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
                    )

                    // Confirm Settlement Button
                    Button {
                        Task {
                            isProcessing = true
                            let ok = await viewModel.recordSettlement(
                                stayId: stay.id,
                                method: selectedMethod,
                                amountMinor: stay.outstandingMinor,
                                reference: reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reference,
                                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                            )
                            isProcessing = false
                            if ok {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isProcessing || viewModel.isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Text(Language.get("Hotel_Settlement_ConfirmButton", alter: "تأكيد تسجيل السداد والتسوية"))
                                .font(Font.custom("Beiruti-Bold", size: 16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            isProcessing || viewModel.isSubmitting
                                ? Color.gray.opacity(0.4)
                                : Color(red: 0.16, green: 0.72, blue: 0.44),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .shadow(color: Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.35), radius: 10, y: 4)
                    }
                    .disabled(isProcessing || viewModel.isSubmitting)
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(18)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func methodCard(method: String, title: String, icon: String) -> some View {
        let isSelected = selectedMethod == method
        return Button {
            selectedMethod = method
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.orange : AdminSurface.secondaryText)
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(
                isSelected ? Color.orange.opacity(0.12) : AdminSurface.background,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.orange : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: isSelected ? 1.5 : 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Room Status Quick Dial Sheet
@MainActor
public struct AdminPetsHotelRoomStatusSheet: View {
    let room: AdminHotelAccommodation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            roomStatusNavBar

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(room.wing.tint.opacity(0.18))
                            .frame(width: 52, height: 52)
                        Image(systemName: room.wing.icon)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(room.wing.tint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.name)
                            .font(Font.custom("Beiruti-Bold", size: 18))
                            .foregroundStyle(AdminSurface.primaryText)
                        Text("\(room.accommodationNumber) • \(room.wing.title)")
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    Spacer()
                }
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(Language.get("Hotel_ChangeStatusPrompt", alter: "تحديث الحالة التشغيلية للجناح:"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.secondaryText)

                // Status Options List
                VStack(spacing: 8) {
                    ForEach([HotelAccommodationStatus.available, .cleaning, .inspection, .maintenance, .blocked, .isolation], id: \.self) { status in
                        let isCurrent = room.status == status
                        Button {
                            Task {
                                if await viewModel.setRoomStatus(room: room, newStatus: status) {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(status.color.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: status.icon)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(status.color)
                                }

                                Text(status.title)
                                    .font(Font.custom("Beiruti-Bold", size: 15))
                                    .foregroundStyle(AdminSurface.primaryText)

                                Spacer()

                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(status.color)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isCurrent ? status.color.opacity(0.1) : AdminSurface.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isCurrent ? status.color.opacity(0.4) : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isCurrent || viewModel.isSubmitting || !viewModel.canManageAccommodations)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var roomStatusNavBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Hotel_RoomStatusTitle", alter: "حالة الجناح"),
            subtitle: "\(room.accommodationNumber) • \(room.wing.title)",
            statusDotColor: room.status.color,
            isModal: true,
            onBack: { dismiss() }
        ) {
            HStack(spacing: 4) {
                Image(systemName: room.status.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(room.status.title)
                    .font(Font.custom("Beiruti-Bold", size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(room.status.color.opacity(0.12), in: Capsule())
            .foregroundStyle(room.status.color)
        }
    }
}
