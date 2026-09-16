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
        var initialVerification = AdminHotelCheckInVerification()
        if (reservation.depositMinor ?? 0) > 0 &&
           (reservation.paymentStatus == "deposit_held" || (reservation.paidAmountMinor ?? 0) >= (reservation.depositMinor ?? 0)) {
            initialVerification.depositSettled = true
        }
        _verification = State(initialValue: initialVerification)
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
            if (reservation.depositMinor ?? 0) > 0 &&
               (reservation.paymentStatus == "deposit_held" || (reservation.paidAmountMinor ?? 0) >= (reservation.depositMinor ?? 0)) {
                verification.depositSettled = true
            }
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
                availabilitySnapshot = try await viewModel.availabilitySnapshot(for: reservation, stay: authoritativeCheckInStay)
                autoSuggestAvailableRoom()
            } catch {
                availabilityErrorMessage = error.localizedDescription
            }
            isLoadingAvailability = false
        }
    }

    private func autoSuggestAvailableRoom() {
        let assignableIds = availabilitySnapshot?.assignableIds ?? []
        if let heldUnit = availabilitySnapshot?.units.first(where: { $0.isReservedForThisStay }),
           let match = viewModel.accommodations.first(where: { $0.id == heldUnit.accommodationId }) {
            selectedRoom = match
        } else if let assignedId = reservation.assignedAccommodationId,
           assignableIds.contains(assignedId),
           let match = viewModel.accommodations.first(where: { $0.id == assignedId }) {
            selectedRoom = match
        } else if let firstAssignableId = assignableIds.first,
                  let match = viewModel.accommodations.first(where: { $0.id == firstAssignableId }) {
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
        Language.get("Hotel_Chip_Toys", alter: "ألعاب")
    ]

    private let quickNotePills: [String] = [
        Language.get("Hotel_NoteTag_Calm", alter: "هادئ / ودود"),
        Language.get("Hotel_NoteTag_Anxious", alter: "خجول / متوتر"),
        Language.get("Hotel_NoteTag_SpecialDiet", alter: "نظام غذائي خاص"),
        Language.get("Hotel_NoteTag_NeedsCare", alter: "يحتاج دواء")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Full Screen Status Bar + Navigation Chrome
            iPhoneNavBar

            // Scrollable Operational Canvas
            // Keep this stack non-lazy: the check-in form contains dynamic-height
            // verification and inventory sections. Lazy pinned headers can remeasure
            // off-screen content and correct the scroll offset while the operator is
            // reviewing actions near the bottom of the form.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
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

                    // Readiness telemetry stays in normal document flow so reaching
                    // the lower actions never changes the ScrollView's anchor.
                    iPhoneReadinessHeader

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
                    Text(displayedPriceSubtext)
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

            // Dedicated Financial Breakdown Strip when deposit exists
            if let depositStr = reservation.formattedDeposit, (reservation.depositMinor ?? 0) > 0 {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        Text(Language.get("Hotel_DepositPaid_Label", alter: "عربون مسدد:"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(depositStr)
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    }

                    Spacer()

                    if let balanceStr = reservation.formattedBalanceDue {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.orange)
                            Text(Language.get("Hotel_BalanceRemaining_Label", alter: "المتبقي عند المغادرة:"))
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(balanceStr)
                                .font(Font.custom("Beiruti-Bold", size: 12))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AdminSurface.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75)
                )
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private var displayedPriceText: String {
        if let bal = reservation.balanceDueMinor, (reservation.depositMinor ?? 0) > 0, bal < (reservation.totalAmountMinor ?? 0) {
            let major = Double(bal) / 100.0
            return String(format: "%.0f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
        }
        if let total = reservation.totalAmountMinor, total > 0 {
            return reservation.formattedTotal
        }
        let rateMinor = selectedRoom?.nightlyRateMinor
            ?? reservation.nightlyRateMinor
            ?? viewModel.accommodations.first(where: { $0.id == reservation.assignedAccommodationId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.id == reservation.accommodationTypeId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.wing == reservation.wing })?.nightlyRateMinor

        if let rateMinor, rateMinor > 0 {
            let total = Double(rateMinor * max(1, reservation.numberOfNights)) / 100.0
            return String(format: "%.0f %@", total, Language.get("Currency_QAR", alter: "ر.ق"))
        }
        return reservation.formattedTotal
    }

    private var displayedPriceSubtext: String {
        let nightsFormat = String(format: Language.get("Hotel_Nights_Format", alter: "%ld ليالٍ"), reservation.numberOfNights)
        if let bal = reservation.balanceDueMinor, (reservation.depositMinor ?? 0) > 0, bal < (reservation.totalAmountMinor ?? 0) {
            return Language.get("Hotel_BalanceRemaining_Short", alter: "المتبقي للتحصيل") + " • " + reservation.formattedTotal
        }
        let rateMinor = selectedRoom?.nightlyRateMinor
            ?? reservation.nightlyRateMinor
            ?? viewModel.accommodations.first(where: { $0.id == reservation.assignedAccommodationId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.id == reservation.accommodationTypeId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.wing == reservation.wing })?.nightlyRateMinor

        if let rateMinor, rateMinor > 0 {
            let perNight = Double(rateMinor) / 100.0
            let rateStr = String(format: "%.0f %@", perNight, Language.get("Currency_QAR", alter: "ر.ق"))
            let perNightLabel = Language.get("Hotel_PerNight", alter: "/ ليلة")
            return "\(nightsFormat) • \(rateStr) \(perNightLabel)"
        }
        return nightsFormat
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

    // MARK: - iPhone Readiness Telemetry Header
    private var iPhoneReadinessHeader: some View {
        VStack(spacing: 0) {
            iPhoneReadinessGaugeCard
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(AdminSurface.background)
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
        AdminHotelCheckInRoomSelectionSection(
            reservation: reservation,
            authoritativeStay: authoritativeStay,
            viewModel: viewModel,
            selectedRoom: $selectedRoom,
            availabilitySnapshot: availabilitySnapshot,
            availabilityErrorMessage: availabilityErrorMessage,
            isLoadingAvailability: isLoadingAvailability,
            onRefreshAvailability: onRefreshAvailability,
            isIPad: false
        )
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
                        let isPrepaid = reservation.paymentStatus == "deposit_held" || (reservation.paidAmountMinor ?? 0) >= (reservation.depositMinor ?? 0)
                        let depositSubtitle: String = {
                            if let formattedDep = reservation.formattedDeposit, isPrepaid {
                                return String(format: Language.get("Hotel_DepositVerified_Sub", alter: "تم استلام العربون مسبقاً بقيمة %@"), formattedDep)
                            }
                            return Language.get("Hotel_VerifyDeposit_Sub", alter: "التحقق من سداد العربون المسبق للحجز")
                        }()

                        AdminHotelVerificationCard(
                            title: Language.get("Hotel_VerifyDeposit", alter: "تأكيد حالة العربون المستحق"),
                            subtitle: depositSubtitle,
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
                        Language.get("Hotel_AddBelongingPrompt", alter: "أضف غرضاً (مثل: حقيبة النقل، بطانية، طوق)..."),
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
                Text(Language.get("Hotel_IntakeNotes", alter: "ملاحظات تسجيل الوصول"))
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
                    Language.get("Hotel_IntakeNotesPlaceholder", alter: "أدخل ملاحظات الاستقبال أو تعليمات التعامل..."),
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
        Language.get("Hotel_Chip_Toys", alter: "ألعاب")
    ]

    private let quickNotePills: [String] = [
        Language.get("Hotel_NoteTag_Calm", alter: "هادئ / ودود"),
        Language.get("Hotel_NoteTag_Anxious", alter: "خجول / متوتر"),
        Language.get("Hotel_NoteTag_SpecialDiet", alter: "نظام غذائي خاص"),
        Language.get("Hotel_NoteTag_NeedsCare", alter: "يحتاج دواء")
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
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(Language.get("Hotel_Ledger_Total", alter: "إجمالي الحساب:"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
            } icon: {
                Image(systemName: "creditcard")
                    .foregroundStyle(AdminSurface.primary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reservation.formattedTotal)
                        .font(Font.custom("Beiruti-Bold", size: 22))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(displayedPriceSubtext)
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
                if let bal = reservation.balanceDueMinor, (reservation.depositMinor ?? 0) > 0, bal > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        let formattedBal = String(format: "%.0f", Double(bal) / 100.0)
                        let currency = Language.get("Currency_QAR", alter: "ر.ق")
                        Text("\(formattedBal) \(currency)")
                            .font(Font.custom("Beiruti-Bold", size: 18))
                            .foregroundStyle(.orange)
                        Text(Language.get("Hotel_BalanceRemaining_Label", alter: "المتبقي عند المغادرة"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            if let depositStr = reservation.formattedDeposit, (reservation.depositMinor ?? 0) > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    Text(Language.get("Hotel_DepositPaid_Label", alter: "عربون مسدد:"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(depositStr)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            ?? reservation.nightlyRateMinor
            ?? viewModel.accommodations.first(where: { $0.id == reservation.assignedAccommodationId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.id == reservation.accommodationTypeId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.wing == reservation.wing })?.nightlyRateMinor

        if let rateMinor, rateMinor > 0 {
            let total = Double(rateMinor * max(1, reservation.numberOfNights)) / 100.0
            return String(format: "%.0f %@", total, Language.get("Currency_QAR", alter: "ر.ق"))
        }
        return reservation.formattedTotal
    }

    private var displayedPriceSubtext: String {
        let nightsFormat = String(format: Language.get("Hotel_Nights_Format", alter: "%ld ليالٍ"), reservation.numberOfNights)
        if let bal = reservation.balanceDueMinor, (reservation.depositMinor ?? 0) > 0, bal < (reservation.totalAmountMinor ?? 0) {
            return Language.get("Hotel_BalanceRemaining_Short", alter: "المتبقي للتحصيل") + " • " + reservation.formattedTotal
        }
        let rateMinor = selectedRoom?.nightlyRateMinor
            ?? reservation.nightlyRateMinor
            ?? viewModel.accommodations.first(where: { $0.id == reservation.assignedAccommodationId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.id == reservation.accommodationTypeId })?.nightlyRateMinor
            ?? viewModel.accommodationTypes.first(where: { $0.wing == reservation.wing })?.nightlyRateMinor

        if let rateMinor, rateMinor > 0 {
            let perNight = Double(rateMinor) / 100.0
            let rateStr = String(format: "%.0f %@", perNight, Language.get("Currency_QAR", alter: "ر.ق"))
            let perNightLabel = Language.get("Hotel_PerNight", alter: "/ ليلة")
            return "\(rateStr) \(perNightLabel) • \(nightsFormat)"
        }
        return nightsFormat
    }

    // MARK: - iPad Right Panel Components
    private var iPadRoomAllocationMatrix: some View {
        AdminHotelCheckInRoomSelectionSection(
            reservation: reservation,
            authoritativeStay: authoritativeStay,
            viewModel: viewModel,
            selectedRoom: $selectedRoom,
            availabilitySnapshot: availabilitySnapshot,
            availabilityErrorMessage: availabilityErrorMessage,
            isLoadingAvailability: isLoadingAvailability,
            onRefreshAvailability: onRefreshAvailability,
            isIPad: true
        )
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
                    let isPrepaid = reservation.paymentStatus == "deposit_held" || (reservation.paidAmountMinor ?? 0) >= (reservation.depositMinor ?? 0)
                    let depositSubtitle: String = {
                        if let formattedDep = reservation.formattedDeposit, isPrepaid {
                            return String(format: Language.get("Hotel_DepositVerified_Sub", alter: "تم استلام العربون مسبقاً بقيمة %@"), formattedDep)
                        }
                        return Language.get("Hotel_VerifyDeposit_Sub", alter: "التحقق من سداد العربون المسبق للحجز")
                    }()

                    AdminHotelVerificationCard(
                        title: Language.get("Hotel_VerifyDeposit", alter: "تأكيد حالة العربون المستحق"),
                        subtitle: depositSubtitle,
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
                        Language.get("Hotel_AddBelongingPrompt", alter: "أضف غرضاً (مثل: حقيبة النقل، بطانية، طوق)..."),
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
                Text(Language.get("Hotel_IntakeNotes", alter: "ملاحظات تسجيل الوصول"))
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
                    Language.get("Hotel_IntakeNotesPlaceholder", alter: "أدخل ملاحظات الاستقبال أو تعليمات التعامل..."),
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
    var effectiveRateMinor: Int? = nil
    var isReservedForThisStay: Bool = false
    let isSelected: Bool
    let onSelect: () -> Void

    private var displayRateText: String {
        if let rate = effectiveRateMinor ?? room.nightlyRateMinor, rate > 0 {
            let qar = Double(rate) / 100.0
            return String(format: "%.0f %@", qar, Language.get("Currency_QAR", alter: "ر.ق"))
        }
        return room.formattedRate
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                if isReservedForThisStay {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(Language.get("Hotel_ReservedForThisGuest", alter: "محجوز لهذا الضيف"))
                            .font(Font.custom("Beiruti-Bold", size: 9))
                    }
                    .foregroundStyle(isSelected ? Color.white : Color(uiColor: .systemGreen))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((isSelected ? Color.white.opacity(0.2) : Color(uiColor: .systemGreen).opacity(0.15)), in: Capsule())
                }

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

                Text(displayRateText)
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
                    .strokeBorder(isSelected ? AdminSurface.primary : (isReservedForThisStay ? Color(uiColor: .systemGreen).opacity(0.6) : Color(uiColor: .ppSurfaceBorder).opacity(0.45)), lineWidth: isSelected ? 1.5 : (isReservedForThisStay ? 1.2 : 0.75))
            )
            .shadow(color: isSelected ? AdminSurface.primary.opacity(0.24) : Color.clear, radius: 6, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(room.accommodationNumber), \(room.name), \(displayRateText)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

private struct AdminHotelUnavailableRoomTile: View {
    let room: AdminHotelAccommodation
    let dominantRejectionCode: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(room.accommodationNumber)
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                Spacer()
                Image(systemName: "slash.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red.opacity(0.6))
            }

            Text(room.name)
                .font(Font.custom("Beiruti-Medium", size: 11))
                .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                .lineLimit(1)

            if let code = dominantRejectionCode {
                Text(AdminHotelDominantReasonPolicy.localizedReason(for: code))
                    .font(Font.custom("Beiruti-Medium", size: 10))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.control.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.75)
        )
    }
}

private struct PendingRepriceAssignment: Identifiable {
    let id = UUID()
    let type: AdminHotelCompatibleAlternativeType
    let unit: AdminHotelAvailabilityUnit
}

private struct AdminHotelCheckInRoomSelectionSection: View {
    let reservation: AdminHotelReservation
    let authoritativeStay: AdminHotelStay?
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Binding var selectedRoom: AdminHotelAccommodation?
    let availabilitySnapshot: AdminHotelAvailabilitySnapshot?
    let availabilityErrorMessage: String?
    let isLoadingAvailability: Bool
    let onRefreshAvailability: () -> Void
    let isIPad: Bool

    @State private var isUnavailableExpanded: Bool = false
    @State private var pendingReprice: PendingRepriceAssignment? = nil
    @State private var isReassigning: Bool = false

    private var heldUnitId: String? {
        availabilitySnapshot?.units.first(where: { $0.isReservedForThisStay })?.accommodationId
    }

    private var assignableRooms: [AdminHotelAccommodation] {
        let assignableIds = availabilitySnapshot?.assignableIds ?? []
        return viewModel.accommodations
            .filter { assignableIds.contains($0.id) }
            .sorted { r1, r2 in
                if r1.id == heldUnitId { return true }
                if r2.id == heldUnitId { return false }
                return r1.accommodationNumber < r2.accommodationNumber
            }
    }

    private var rejectedUnits: [AdminHotelAvailabilityUnit] {
        availabilitySnapshot?.rejectedUnits ?? []
    }

    private var compatibleAlternatives: [AdminHotelCompatibleAlternativeType] {
        availabilitySnapshot?.compatibleAlternativeTypes ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack {
                Label {
                    Text(Language.get("Hotel_SelectRoom", alter: "اختر الجناح أو الغرفة"))
                        .font(Font.custom("Beiruti-Bold", size: isIPad ? 17 : 16))
                        .foregroundStyle(AdminSurface.primaryText)
                } icon: {
                    Image(systemName: "bed.double.fill")
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                if isReassigning {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onRefreshAvailability()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
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
            } else {
                // Dominant Rejection Banner if 0 assignable rooms in exact type
                if assignableRooms.isEmpty {
                    let dominantCode = AdminHotelDominantReasonPolicy.dominantReason(from: rejectedUnits.flatMap(\.rejections))
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Hotel_NoExactRoomsAssignableTitle", alter: "لا توجد أجنحة شاغرة بالفئة الأصلية"))
                                .font(Font.custom("Beiruti-Bold", size: 13.5))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(AdminHotelDominantReasonPolicy.localizedReason(for: dominantCode ?? ""))
                                .font(Font.custom("Beiruti-Regular", size: 11.5))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
                }

                // TIER 1: Recommended / Assignable Rooms
                if !assignableRooms.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(uiColor: .systemGreen))
                                .frame(width: 6, height: 6)
                            Text(Language.get("Hotel_Tier1_MatchingSuites", alter: "الأجنحة المطابقة والمتاحة للتسكين"))
                                .font(Font.custom("Beiruti-Bold", size: 13))
                                .foregroundStyle(AdminSurface.primaryText)
                            Spacer()
                            Text("\(assignableRooms.count)")
                                .font(Font.custom("Beiruti-Bold", size: 11))
                                .foregroundStyle(Color(uiColor: .systemGreen))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color(uiColor: .systemGreen).opacity(0.12), in: Capsule())
                        }

                        if isIPad {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 10)], spacing: 10) {
                                ForEach(assignableRooms) { room in
                                    roomTile(for: room)
                                }
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(assignableRooms) { room in
                                        roomTile(for: room)
                                            .frame(width: 145)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                // TIER 2: Compatible Alternative Tiers & Upgrades
                if !compatibleAlternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.and.arrow.down.left.rectangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AdminSurface.primary)
                            Text(Language.get("Hotel_Tier2_AlternativeTiers", alter: "فئات وترقيات بديلة متوافقة"))
                                .font(Font.custom("Beiruti-Bold", size: 13))
                                .foregroundStyle(AdminSurface.primaryText)
                        }

                        ForEach(compatibleAlternatives) { alt in
                            alternativeTypeCard(alt)
                        }
                    }
                }

                // TIER 3: Unavailable Rooms with Exact Dominant Reasons
                if !rejectedUnits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isUnavailableExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isUnavailableExpanded ? "chevron.down" : (Language.isRTL() ? "chevron.left" : "chevron.right"))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                Text(String(format: Language.get("Hotel_Tier3_UnavailableSuites", alter: "الأجنحة غير المتاحة مع أسباب الاستبعاد (%d)"), rejectedUnits.count))
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if isUnavailableExpanded {
                            let rejectedAccommodations: [(room: AdminHotelAccommodation, rejection: String?)] = rejectedUnits.compactMap { unit in
                                guard let match = viewModel.accommodations.first(where: { $0.id == unit.accommodationId }) else { return nil }
                                let dominantCode = AdminHotelDominantReasonPolicy.dominantReason(from: unit.rejections)
                                return (match, dominantCode)
                            }

                            if isIPad {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 8)], spacing: 8) {
                                    ForEach(rejectedAccommodations, id: \.room.id) { pair in
                                        AdminHotelUnavailableRoomTile(room: pair.room, dominantRejectionCode: pair.rejection)
                                    }
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(rejectedAccommodations, id: \.room.id) { pair in
                                            AdminHotelUnavailableRoomTile(room: pair.room, dominantRejectionCode: pair.rejection)
                                                .frame(width: 140)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .alert(item: $pendingReprice) { pending in
            let deltaText = AdminHotelRepricePolicy.formattedDelta(rateDeltaMinor: pending.type.rateDeltaMinor)
            return Alert(
                title: Text(Language.get("Hotel_RepriceConfirmTitle", alter: "تأكيد تغيير الفئة وإعادة التسعير")),
                message: Text(String(format: Language.get("Hotel_RepriceConfirmMessage", alter: "سيتم تسكين النزيل في الجناح (%@) التابع للفئة (%@) مع تعديل السعر بمقدار (%@). هل تريد المتابعة؟"), pending.unit.code, pending.type.displayName, deltaText)),
                primaryButton: .default(Text(Language.get("Confirm", alter: "تأكيد")), action: {
                    guard let stayId = authoritativeStay?.id else { return }
                    Task {
                        isReassigning = true
                        let success = await viewModel.reassignStayRoom(
                            stayId: stayId,
                            accommodationId: pending.unit.accommodationId,
                            reasonCode: "tier_upgrade_at_checkin",
                            confirmReprice: true,
                            expectedNewRateMinor: pending.type.nightlyRateMinor
                        )
                        isReassigning = false
                        if success {
                            if let newAcc = viewModel.accommodations.first(where: { $0.id == pending.unit.accommodationId }) {
                                selectedRoom = newAcc
                            }
                            onRefreshAvailability()
                        }
                    }
                }),
                secondaryButton: .cancel(Text(Language.get("Cancel", alter: "إلغاء")))
            )
        }
    }

    private func effectiveRateForRoom(_ room: AdminHotelAccommodation) -> Int? {
        if let rate = room.nightlyRateMinor {
            return rate
        }
        if !room.accommodationTypeId.isEmpty,
           let typeRate = viewModel.accommodationTypes.first(where: { $0.id == room.accommodationTypeId })?.nightlyRateMinor {
            return typeRate
        }
        if room.id == reservation.assignedAccommodationId, let resRate = reservation.nightlyRateMinor {
            return resRate
        }
        if let wingRate = viewModel.accommodationTypes.first(where: { $0.wing == reservation.wing })?.nightlyRateMinor {
            return wingRate
        }
        return reservation.nightlyRateMinor
    }

    private func roomTile(for room: AdminHotelAccommodation) -> some View {
        let isSelected = selectedRoom?.id == room.id
        let isHeld = (room.id == heldUnitId)
        let effectiveRate = effectiveRateForRoom(room)
        return AdminHotelRoomTile(
            room: room,
            effectiveRateMinor: effectiveRate,
            isReservedForThisStay: isHeld,
            isSelected: isSelected
        ) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedRoom = room
        }
    }

    private func alternativeTypeCard(_ alt: AdminHotelCompatibleAlternativeType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alt.displayName)
                        .font(Font.custom("Beiruti-Bold", size: 13.5))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(String(format: Language.get("Hotel_Suite_AvailableUnits", alter: "%d أجنحة شاغرة"), alt.assignableUnits.count))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Rate Delta Badge
                Text(AdminHotelRepricePolicy.formattedDelta(rateDeltaMinor: alt.rateDeltaMinor))
                    .font(Font.custom("Beiruti-Bold", size: 11))
                    .foregroundStyle(alt.rateDeltaMinor > 0 ? AdminSurface.primary : (alt.rateDeltaMinor < 0 ? Color(uiColor: .systemGreen) : AdminSurface.secondaryText))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (alt.rateDeltaMinor > 0 ? AdminSurface.primary : (alt.rateDeltaMinor < 0 ? Color(uiColor: .systemGreen) : AdminSurface.secondaryText)).opacity(0.12),
                        in: Capsule()
                    )
            }

            // Units under this alternative type
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(alt.assignableUnits) { unit in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            pendingReprice = PendingRepriceAssignment(type: alt, unit: unit)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text(unit.code)
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                                Text("(\(Language.get("Hotel_ChangeAndAssign", alter: "تغيير وتسكين")))")
                                    .font(Font.custom("Beiruti-Regular", size: 10))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.8)
        )
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

// MARK: - Express Check-Out Sheet (Category-Defining Discharge Architecture)
@MainActor
public struct AdminPetsHotelCheckOutSheet: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var verification = AdminHotelCheckOutVerification()
    @State private var earlyReason: String = "early_departure_by_owner"
    @State private var showSettlementSheet: Bool = false
    @State private var checkoutSuccess: Bool = false
    @State private var auraBreathing: Bool = false

    public init(stay: AdminHotelStay, viewModel: AdminPetsHotelViewModel) {
        self.stay = stay
        self.viewModel = viewModel
    }

    private var currentStay: AdminHotelStay {
        viewModel.stays.first(where: { $0.id == stay.id })
            ?? (viewModel.checkOutModalStay?.id == stay.id ? (viewModel.checkOutModalStay ?? stay) : stay)
    }

    private var isEarly: Bool {
        Date() < currentStay.expectedCheckOutTime
    }

    private var isPad: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
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

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                checkOutNavBar

                if isPad {
                    AdminPetsHotelCheckOut_iPad(
                        stay: currentStay,
                        viewModel: viewModel,
                        verification: $verification,
                        earlyReason: $earlyReason,
                        showSettlementSheet: $showSettlementSheet,
                        isCheckOutVerificationComplete: isCheckOutVerificationComplete,
                        isEarly: isEarly,
                        onExecuteCheckOut: { performCheckOut() }
                    )
                } else {
                    AdminPetsHotelCheckOut_iPhone(
                        stay: currentStay,
                        viewModel: viewModel,
                        verification: $verification,
                        earlyReason: $earlyReason,
                        showSettlementSheet: $showSettlementSheet,
                        isCheckOutVerificationComplete: isCheckOutVerificationComplete,
                        isEarly: isEarly,
                        onExecuteCheckOut: { performCheckOut() }
                    )
                }
            }

            if checkoutSuccess {
                AdminPetsHotelCelebrationOverlay(
                    petName: currentStay.petName,
                    wing: currentStay.wing,
                    onDismiss: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .zIndex(100)
            }
        }
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $showSettlementSheet) {
            AdminHotelQuickSettlementSheet(stay: currentStay, viewModel: viewModel)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                auraBreathing = true
            }
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
            HStack(spacing: 5) {
                Image(systemName: currentStay.wing.icon)
                    .font(PPBrandFont.bold(size: 11))
                Text(currentStay.wing.title)
                    .font(PPBrandFont.bold(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(currentStay.wing.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(currentStay.wing.tint)
        }
    }

    private func performCheckOut() {
        Task {
            await viewModel.executeCheckOut(
                stay: currentStay,
                verification: verification,
                earlyReason: isEarly ? earlyReason : nil
            )
            if viewModel.errorMessage == nil {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    checkoutSuccess = true
                }
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                dismiss()
            }
        }
    }
}

// MARK: - iPhone Dedicated Architecture
private struct AdminPetsHotelCheckOut_iPhone: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Binding var verification: AdminHotelCheckOutVerification
    @Binding var earlyReason: String
    @Binding var showSettlementSheet: Bool
    let isCheckOutVerificationComplete: Bool
    let isEarly: Bool
    let onExecuteCheckOut: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Living Reunion Hero
                    AdminPetsHotelDischargeHero(stay: stay)

                    // Outstanding Balance or Settled Ledger Card
                    if stay.outstandingMinor > 0 {
                        AdminPetsHotelOutstandingCard(
                            stay: stay,
                            canViewBilling: viewModel.canViewBilling,
                            onSettle: { showSettlementSheet = true }
                        )
                    }

                    // Backend Error Notice Banner
                    if let err = viewModel.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(PPBrandFont.bold(size: 16))
                                .foregroundStyle(AdminSurface.crimson)
                            Text(err)
                                .font(PPBrandFont.medium(size: 13))
                                .foregroundStyle(AdminSurface.crimson)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(AdminSurface.crimson.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // Early Departure Telemetry
                    if isEarly {
                        AdminPetsHotelEarlyDepartureCard(stay: stay)
                    }

                    // 4 Category-Defining Tactile Discharge Protocol Pods
                    AdminPetsHotelProtocolPodsStack(
                        stay: stay,
                        verification: $verification
                    )

                    // Stay Horizon Telemetry
                    AdminPetsHotelStayHorizonCard(stay: stay)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }

            // Fixed Liquid Floating Deck (Slide-to-Discharge)
            VStack(spacing: 0) {
                Divider()
                    .background(AdminSurface.hairline.opacity(0.6))

                AdminPetsHotelSlideToDischargeBar(
                    isComplete: isCheckOutVerificationComplete,
                    isSubmitting: viewModel.isSubmitting,
                    canCheckOut: viewModel.canCheckOut,
                    outstandingMinor: stay.outstandingMinor,
                    onSlideComplete: onExecuteCheckOut
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .background(
                AdminSurface.background
                    .opacity(0.96)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

// MARK: - iPad Dedicated Architecture (Command Station Panoramic Layout)
private struct AdminPetsHotelCheckOut_iPad: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Binding var verification: AdminHotelCheckOutVerification
    @Binding var earlyReason: String
    @Binding var showSettlementSheet: Bool
    let isCheckOutVerificationComplete: Bool
    let isEarly: Bool
    let onExecuteCheckOut: () -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 20) {
                // Left Column: Guest Dossier & Horizon Telemetry
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        AdminPetsHotelDischargeHero(stay: stay)

                        if stay.outstandingMinor > 0 {
                            AdminPetsHotelOutstandingCard(
                                stay: stay,
                                canViewBilling: viewModel.canViewBilling,
                                onSettle: { showSettlementSheet = true }
                            )
                        }

                        AdminPetsHotelStayHorizonCard(stay: stay)

                        if isEarly {
                            AdminPetsHotelEarlyDepartureCard(stay: stay)
                        }

                        // Guardian Direct Communications Quick-Card
                        AdminPetsHotelGuardianContactCard(stay: stay)
                    }
                    .padding(20)
                }
                .frame(width: min(420, proxy.size.width * 0.42))
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )

                // Right Column: Tactile Discharge Protocols & Slide Station
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 18) {
                            // Section Eyebrow
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(Language.get("Hotel_CheckoutPrompt", alter: "إجراءات مغادرة النزيل وتسليم الأغراض وتفريغ الجناح"))
                                        .font(PPBrandFont.bold(size: 18))
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Text(Language.get("Hotel_Readiness_ProtocolPill", alter: "بروتوكول التسليم الرباعي المعتمد"))
                                        .font(PPBrandFont.medium(size: 13))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }
                                Spacer()

                                // Completion Ratio Pill
                                protocolProgressPill
                            }
                            .padding(.top, 4)

                            if let err = viewModel.errorMessage {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(PPBrandFont.bold(size: 16))
                                        .foregroundStyle(AdminSurface.crimson)
                                    Text(err)
                                        .font(PPBrandFont.medium(size: 13))
                                        .foregroundStyle(AdminSurface.crimson)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(14)
                                .background(AdminSurface.crimson.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }

                            AdminPetsHotelProtocolPodsStack(
                                stay: stay,
                                verification: $verification
                            )
                        }
                        .padding(20)
                    }

                    // Discharge Slide Station
                    VStack(spacing: 0) {
                        Divider()
                            .background(AdminSurface.hairline)

                        AdminPetsHotelSlideToDischargeBar(
                            isComplete: isCheckOutVerificationComplete,
                            isSubmitting: viewModel.isSubmitting,
                            canCheckOut: viewModel.canCheckOut,
                            outstandingMinor: stay.outstandingMinor,
                            onSlideComplete: onExecuteCheckOut
                        )
                        .padding(20)
                    }
                    .background(AdminSurface.card)
                }
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
            }
            .padding(18)
        }
    }

    private var completedProtocolCount: Int {
        var count = 0
        if verification.handoverVerified { count += 1 }
        if stay.belongingCount == 0 || verification.belongingsReturned { count += 1 }
        if verification.healthCheckCompleted { count += 1 }
        if verification.roomInspectionCompleted { count += 1 }
        return count
    }

    private var protocolProgressPill: some View {
        HStack(spacing: 6) {
            Image(systemName: completedProtocolCount == 4 ? "checkmark.circle.fill" : "circle.dashed")
                .font(PPBrandFont.bold(size: 13))
            Text("\(completedProtocolCount) / 4")
                .font(PPBrandFont.bold(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            completedProtocolCount == 4
                ? AdminSurface.emerald.opacity(0.16)
                : AdminSurface.amber.opacity(0.14),
            in: Capsule()
        )
        .foregroundStyle(completedProtocolCount == 4 ? AdminSurface.emerald : AdminSurface.amber)
    }
}

// MARK: - Living Reunion Hero Section
private struct AdminPetsHotelDischargeHero: View {
    let stay: AdminHotelStay
    @State private var isPulsing: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Outer Ambient Aura Ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                stay.wing.tint.opacity(isPulsing ? 0.28 : 0.12),
                                stay.wing.tint.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 28,
                            endRadius: 64
                        )
                    )
                    .frame(width: 128, height: 128)
                    .scaleEffect(isPulsing ? 1.08 : 0.95)

                // Mid Halo Ring
                Circle()
                    .strokeBorder(stay.wing.tint.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 86, height: 86)

                // Avatar Container
                ZStack {
                    Circle()
                        .fill(stay.wing.tint.opacity(0.18))
                        .frame(width: 76, height: 76)

                    if let photoUrl = stay.petPhotoUrl, let url = URL(string: photoUrl) {
                        AdminRemoteImage(url: url) {
                            Image(systemName: stay.wing.icon)
                                .font(PPBrandFont.bold(size: 32))
                                .foregroundStyle(stay.wing.tint)
                        }
                        .frame(width: 76, height: 76)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: stay.wing.icon)
                            .font(PPBrandFont.bold(size: 32))
                            .foregroundStyle(stay.wing.tint)
                    }
                }
                .shadow(color: stay.wing.tint.opacity(0.25), radius: 10, y: 4)

                // Status Badge Overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(AdminSurface.emerald)
                                .frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(PPBrandFont.bold(size: 12))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 2, y: 2)
                    }
                }
                .frame(width: 76, height: 76)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }

            VStack(spacing: 5) {
                Text(stay.petName)
                    .font(PPBrandFont.bold(size: 26))
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 8) {
                    Text(localizedSpeciesAndBreed)
                        .font(PPBrandFont.medium(size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text("•")
                        .font(PPBrandFont.regular(size: 12))
                        .foregroundStyle(AdminSurface.hairline)

                    HStack(spacing: 4) {
                        Image(systemName: "bed.double.fill")
                            .font(PPBrandFont.bold(size: 11))
                        Text(stay.roomNumber.isEmpty ? stay.wing.title : stay.roomNumber)
                            .font(PPBrandFont.bold(size: 12.5))
                    }
                    .foregroundStyle(stay.wing.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stay.wing.tint.opacity(0.12), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var localizedSpeciesAndBreed: String {
        let breed = stay.petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        let species = localizedSpecies(stay.petSpecies)
        if !breed.isEmpty && !species.isEmpty {
            return "\(species) • \(breed)"
        } else if !species.isEmpty {
            return species
        } else if !breed.isEmpty {
            return breed
        } else {
            return stay.wing.title
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
}

// MARK: - Stay Horizon Telemetry Card
private struct AdminPetsHotelStayHorizonCard: View {
    let stay: AdminHotelStay

    private var nightsCount: Int {
        let diff = Calendar.current.dateComponents([.day], from: stay.checkInTime, to: stay.expectedCheckOutTime).day ?? 1
        return max(1, diff)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(PPBrandFont.bold(size: 13))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_StayHorizon_Title", alter: "أفق الإقامة والفترة الفندقية"))
                        .font(PPBrandFont.bold(size: 13.5))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                Spacer()

                Text("\(nightsCount) \(Language.get("Nights", alter: "ليالي"))")
                    .font(PPBrandFont.bold(size: 12))
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
            }

            Divider()
                .background(AdminSurface.hairline)

            HStack(spacing: 0) {
                // Check-in Horizon
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Hotel_CheckIn_Date", alter: "تاريخ الدخول"))
                        .font(PPBrandFont.medium(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatDate(stay.checkInTime))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(formatTime(stay.checkInTime))
                        .font(PPBrandFont.regular(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Directional Horizon Arrow
                Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                    .font(PPBrandFont.bold(size: 14))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.5))
                    .padding(.horizontal, 10)

                // Departure Horizon
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Language.get("Hotel_ExpectedCheckOut", alter: "المغادرة المجدولة"))
                        .font(PPBrandFont.medium(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatDate(stay.expectedCheckOutTime))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(formatTime(stay.expectedCheckOutTime))
                        .font(PPBrandFont.regular(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Outstanding Financial Settlement Card
private struct AdminPetsHotelOutstandingCard: View {
    let stay: AdminHotelStay
    let canViewBilling: Bool
    let onSettle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.amber.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(PPBrandFont.bold(size: 20))
                        .foregroundStyle(AdminSurface.amber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_OutstandingBalance_Notice", alter: "رصيد مالي مستحق على الإقامة"))
                        .font(PPBrandFont.bold(size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Hotel_OutstandingBalance_ActionHint", alter: "يجب تسوية المبلغ المتبقي قبل تسليم النزيل وإخلاء الجناح."))
                        .font(PPBrandFont.medium(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
            }

            Divider()
                .background(AdminSurface.amber.opacity(0.3))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_Ledger_Balance", alter: "المتبقي للدفع:"))
                        .font(PPBrandFont.medium(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(String(format: "%.0f %@", Double(stay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(PPBrandFont.bold(size: 22))
                        .foregroundStyle(AdminSurface.amber)
                }

                Spacer()

                if canViewBilling {
                    Button(action: onSettle) {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard.fill")
                                .font(PPBrandFont.bold(size: 13))
                            Text(Language.get("Hotel_SettleBalance_Button", alter: "تسجيل تسوية الرصيد"))
                                .font(PPBrandFont.bold(size: 13.5))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AdminSurface.amber, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: AdminSurface.amber.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Text(Language.get("Hotel_SettleBalance_Restricted", alter: "يرجى مراجعة موظف الحسابات."))
                        .font(PPBrandFont.medium(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
        .padding(14)
        .background(AdminSurface.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.amber.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Early Departure Card
private struct AdminPetsHotelEarlyDepartureCard: View {
    let stay: AdminHotelStay

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.amber.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock.badge.exclamationmark")
                    .font(PPBrandFont.bold(size: 18))
                    .foregroundStyle(AdminSurface.amber)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Hotel_Checkout_Early_Title", alter: "مغادرة مبكرة قبل الموعد المقرر"))
                    .font(PPBrandFont.bold(size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(String(
                    format: Language.get("Hotel_Checkout_Early_Detail", alter: "الموعد الأصلي: %@ • الفعلي: %@ • تُعدل الليالي وفق سياسة الفندق"),
                    formatTime(stay.expectedCheckOutTime),
                    formatTime(Date())
                ))
                .font(PPBrandFont.medium(size: 11.5))
                .foregroundStyle(AdminSurface.secondaryText)
            }
            Spacer()
        }
        .padding(12)
        .background(AdminSurface.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.amber.opacity(0.28), lineWidth: 0.75)
        )
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        f.dateFormat = "d MMM, h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Guardian Direct Communications Quick-Card (iPad)
private struct AdminPetsHotelGuardianContactCard: View {
    let stay: AdminHotelStay

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("Hotel_Guardian_DirectContact", alter: "بيانات التواصل المباشر مع المالك"))
                .font(PPBrandFont.bold(size: 13))
                .foregroundStyle(AdminSurface.secondaryText)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "person.crop.circle.fill")
                        .font(PPBrandFont.bold(size: 22))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stay.customerName)
                        .font(PPBrandFont.bold(size: 14.5))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(stay.customerPhone)
                        .font(PPBrandFont.regular(size: 12.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        callPhone(stay.customerPhone)
                    } label: {
                        Image(systemName: "phone.circle.fill")
                            .font(PPBrandFont.bold(size: 28))
                            .foregroundStyle(AdminSurface.emerald)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        openWhatsApp(stay.customerPhone)
                    } label: {
                        Image(systemName: "message.circle.fill")
                            .font(PPBrandFont.bold(size: 28))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func callPhone(_ raw: String) {
        let clean = raw.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    private func openWhatsApp(_ raw: String) {
        let clean = raw.filter { "0123456789".contains($0) }
        guard let url = URL(string: "https://wa.me/\(clean)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - 4 Category-Defining Tactile Discharge Protocol Pods Stack
private struct AdminPetsHotelProtocolPodsStack: View {
    let stay: AdminHotelStay
    @Binding var verification: AdminHotelCheckOutVerification

    var body: some View {
        VStack(spacing: 12) {
            // Pod 1: Guardian Identity & Handover Clearance
            AdminPetsHotelProtocolPod(
                icon: "person.crop.circle.badge.checkmark",
                title: Language.get("Hotel_Checkout_Pod_Guardian_Title", alter: "إثبات هوية المستلم وتسليم النزيل"),
                subtitle: String(
                    format: Language.get("Hotel_Checkout_Pod_Guardian_Sub", alter: "المالك المعتمد المسجل: %@ • %@"),
                    stay.customerName,
                    stay.customerPhone
                ),
                isVerified: verification.handoverVerified,
                verifiedNotice: Language.get("Hotel_Checkout_Pod_Guardian_Verified", alter: "تم التحقق من هوية المستلم الحاضر"),
                pendingNotice: Language.get("Hotel_Checkout_Pod_Guardian_Pending", alter: "اضغط للتحقق من هوية المستلم الحاضر"),
                accentColor: Color(red: 0.20, green: 0.55, blue: 0.95),
                onToggle: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    verification.handoverVerified.toggle()
                }
            ) {
                HStack(spacing: 10) {
                    Button {
                        callPhone(stay.customerPhone)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "phone.fill")
                                .font(PPBrandFont.bold(size: 11))
                            Text(Language.get("Call", alter: "اتصال"))
                                .font(PPBrandFont.bold(size: 11.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.emerald.opacity(0.14), in: Capsule())
                        .foregroundStyle(AdminSurface.emerald)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button {
                        openWhatsApp(stay.customerPhone)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "message.fill")
                                .font(PPBrandFont.bold(size: 11))
                            Text("واتساب")
                                .font(PPBrandFont.bold(size: 11.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.primary.opacity(0.14), in: Capsule())
                        .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 2)
            }

            // Pod 2: Belongings & Custody Return
            AdminPetsHotelProtocolPod(
                icon: "shippingbox.fill",
                title: Language.get("Hotel_Checkout_Pod_Belongings_Title", alter: "تسليم الأمانات والمتعلقات الخاصة"),
                subtitle: stay.belongingCount > 0
                    ? String(format: Language.get("Hotel_Belongings_Count_Format", alter: "إجمالي العهد المسجلة: %d أغراض ومحتويات"), stay.belongingCount)
                    : Language.get("Hotel_NoBelongingsRegistered", alter: "لا توجد أمانات شخصية مسجلة في هذا الحجز"),
                isVerified: stay.belongingCount == 0 || verification.belongingsReturned,
                verifiedNotice: Language.get("Hotel_Checkout_Pod_Belongings_Verified", alter: "تم تسليم كافة الأغراض والعهد للمستلم"),
                pendingNotice: Language.get("Hotel_Checkout_Pod_Belongings_Pending", alter: "اضغط لتأكيد تسليم الأمانات للمستلم"),
                accentColor: Color(red: 0.90, green: 0.50, blue: 0.15),
                onToggle: {
                    guard stay.belongingCount > 0 else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    verification.belongingsReturned.toggle()
                }
            ) {
                if stay.belongingCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(PPBrandFont.bold(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(Language.get("Hotel_BelongingsHandedBack", alter: "تأكد من تطابق كافة الأغراض قبل تسليم النزيل"))
                            .font(PPBrandFont.medium(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            // Pod 3: Clinical Assessment & Vitals Sign-off
            AdminPetsHotelProtocolPod(
                icon: "heart.text.square.fill",
                title: Language.get("Hotel_Checkout_Pod_Health_Title", alter: "الفحص الطبي والمؤشرات الحيوية"),
                subtitle: Language.get("Hotel_Checkout_Pod_Health_Sub", alter: "تأكيد سلامة النزيل البدنية واستقرار مؤشراته الحيوية"),
                isVerified: verification.healthCheckCompleted,
                verifiedNotice: Language.get("Hotel_Checkout_Pod_Health_Verified", alter: "تم الفحص السريري: النزيل بحالة ممتازة"),
                pendingNotice: Language.get("Hotel_Checkout_Pod_Health_Pending", alter: "اضغط لتأكيد السلامة والفحص السريري"),
                accentColor: Color(red: 0.16, green: 0.72, blue: 0.44),
                onToggle: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    verification.healthCheckCompleted.toggle()
                }
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    if stay.criticalIncidentCount > 0 {
                        HStack(spacing: 8) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                verification.incidentsAcknowledged.toggle()
                            } label: {
                                Image(systemName: verification.incidentsAcknowledged ? "checkmark.square.fill" : "square")
                                    .font(PPBrandFont.bold(size: 14))
                                    .foregroundStyle(verification.incidentsAcknowledged ? AdminSurface.emerald : AdminSurface.amber)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Text(Language.get("Hotel_IncidentsAcknowledged", alter: "مراجعة واعتماد الحوادث والملاحظات المفتوحة"))
                                .font(PPBrandFont.bold(size: 11.5))
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        .padding(8)
                        .background(AdminSurface.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if stay.pendingMedicationCount > 0 {
                        HStack(spacing: 8) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                verification.medicationResolved.toggle()
                            } label: {
                                Image(systemName: verification.medicationResolved ? "checkmark.square.fill" : "square")
                                    .font(PPBrandFont.bold(size: 14))
                                    .foregroundStyle(verification.medicationResolved ? AdminSurface.emerald : AdminSurface.amber)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Text(Language.get("Hotel_MedicationResolved", alter: "تسوية وإغلاق جميع الجرعات الدوائية"))
                                .font(PPBrandFont.bold(size: 11.5))
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        .padding(8)
                        .background(AdminSurface.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            // Pod 4: Suite Release & Sanitization Dispatch
            AdminPetsHotelProtocolPod(
                icon: "sparkles.rectangle.stack.fill",
                title: Language.get("Hotel_Checkout_Pod_Suite_Title", alter: "تحرير الجناح وتوجيه التعقيم الفوري"),
                subtitle: Language.get("Hotel_Checkout_Pod_Suite_Sub", alter: "ينتقل الجناح تلقائياً إلى مسار التنظيف والتعقيم"),
                isVerified: verification.roomInspectionCompleted,
                verifiedNotice: Language.get("Hotel_Checkout_Pod_Suite_Verified", alter: "تم إخلاء الجناح وتوجيهه للتعقيم المباشر"),
                pendingNotice: Language.get("Hotel_Checkout_Pod_Suite_Pending", alter: "اضغط لتأكيد إخلاء الجناح للتعقيم"),
                accentColor: Color(red: 0.62, green: 0.32, blue: 0.88),
                onToggle: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    verification.roomInspectionCompleted.toggle()
                }
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(PPBrandFont.bold(size: 11))
                        .foregroundStyle(Color(red: 0.62, green: 0.32, blue: 0.88))
                    Text(Language.get("Hotel_RoomCleaningAutomatic", alter: "بعد المغادرة ينقل الخادم الجناح تلقائياً إلى مسار التنظيف."))
                        .font(PPBrandFont.medium(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
    }

    private func callPhone(_ raw: String) {
        let clean = raw.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    private func openWhatsApp(_ raw: String) {
        let clean = raw.filter { "0123456789".contains($0) }
        guard let url = URL(string: "https://wa.me/\(clean)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Generic Tactile Interactive Protocol Pod Component
private struct AdminPetsHotelProtocolPod<ExtraContent: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let isVerified: Bool
    let verifiedNotice: String
    let pendingNotice: String
    let accentColor: Color
    let onToggle: () -> Void
    @ViewBuilder let extraContent: () -> ExtraContent

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    // Pod Category Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isVerified ? AdminSurface.emerald.opacity(0.14) : accentColor.opacity(0.14))
                            .frame(width: 42, height: 42)
                        Image(systemName: icon)
                            .font(PPBrandFont.bold(size: 18))
                            .foregroundStyle(isVerified ? AdminSurface.emerald : accentColor)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)

                        Text(subtitle)
                            .font(PPBrandFont.medium(size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    // Tactile Verification Seal Button
                    ZStack {
                        Circle()
                            .fill(isVerified ? AdminSurface.emerald : AdminSurface.hairline.opacity(0.35))
                            .frame(width: 28, height: 28)
                        Image(systemName: isVerified ? "checkmark" : "circle")
                            .font(PPBrandFont.bold(size: 13))
                            .foregroundStyle(isVerified ? .white : AdminSurface.secondaryText)
                    }
                    .scaleEffect(isVerified ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVerified)
                }

                extraContent()

                // Bottom Status Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(isVerified ? AdminSurface.emerald : AdminSurface.amber)
                        .frame(width: 6, height: 6)
                    Text(isVerified ? verifiedNotice : pendingNotice)
                        .font(PPBrandFont.bold(size: 11))
                        .foregroundStyle(isVerified ? AdminSurface.emerald : AdminSurface.amber)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isVerified ? AdminSurface.emerald.opacity(0.08) : AdminSurface.amber.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
            .padding(14)
            .background(
                isVerified ? AdminSurface.control : AdminSurface.control.opacity(0.9),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isVerified ? AdminSurface.emerald.opacity(0.4) : AdminSurface.hairline,
                        lineWidth: isVerified ? 1.25 : 0.75
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Category-Defining Slide-to-Discharge Handover Rail
private struct AdminPetsHotelSlideToDischargeBar: View {
    let isComplete: Bool
    let isSubmitting: Bool
    let canCheckOut: Bool
    let outstandingMinor: Int
    let onSlideComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var shakeHint: Bool = false

    private let knobSize: CGFloat = 52
    private let barHeight: CGFloat = 60

    private var isLocked: Bool {
        !isComplete || !canCheckOut || isSubmitting
    }

    var body: some View {
        GeometryReader { geo in
            let maxDistance = max(10, geo.size.width - knobSize - 8)
            let isRTL = Language.isRTL()

            ZStack(alignment: isRTL ? .trailing : .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        isLocked
                            ? Color.gray.opacity(0.16)
                            : Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.15)
                    )
                    .frame(height: barHeight)

                // Track Progress Fill
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.82, green: 0.15, blue: 0.35),
                                Color(red: 0.95, green: 0.25, blue: 0.45)
                            ],
                            startPoint: isRTL ? .trailing : .leading,
                            endPoint: isRTL ? .leading : .trailing
                        )
                    )
                    .frame(width: max(knobSize + 8, dragOffset + knobSize + 4), height: barHeight)
                    .opacity(isLocked ? 0.0 : 1.0)
                    .animation(isDragging ? .none : .spring(response: 0.35, dampingFraction: 0.75), value: dragOffset)

                // Track Centered Label
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                        Text(Language.get("Hotel_Checkout_Slide_Processing", alter: "جاري إتمام المغادرة وتحرير الجناح..."))
                            .font(PPBrandFont.bold(size: 14))
                            .foregroundStyle(.white)
                    } else if outstandingMinor > 0 {
                        Image(systemName: "creditcard.fill")
                            .font(PPBrandFont.bold(size: 13))
                            .foregroundStyle(AdminSurface.amber)
                        Text(Language.get("Hotel_OutstandingBalance_Notice", alter: "يرجى تسوية الرصيد المالي أولاً"))
                            .font(PPBrandFont.bold(size: 13.5))
                            .foregroundStyle(AdminSurface.amber)
                    } else if !isComplete {
                        Image(systemName: "checklist")
                            .font(PPBrandFont.bold(size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(Language.get("Hotel_Checkout_IncompleteHint", alter: "يرجى استكمال متطلبات التحقق"))
                            .font(PPBrandFont.bold(size: 13.5))
                            .foregroundStyle(AdminSurface.secondaryText)
                    } else {
                        Text(Language.get("Hotel_Checkout_Slide_Title", alter: "مرر لإتمام المغادرة وتسليم النزيل"))
                            .font(PPBrandFont.bold(size: 14.5))
                            .foregroundStyle(dragOffset > maxDistance * 0.4 ? .white : AdminSurface.primaryText)
                    }
                }
                .frame(maxWidth: .infinity)

                // Draggable Tactile Thumb Knob
                ZStack {
                    Circle()
                        .fill(
                            isLocked
                                ? Color.gray.opacity(0.4)
                                : Color(red: 0.82, green: 0.15, blue: 0.35)
                        )
                        .frame(width: knobSize, height: knobSize)
                        .shadow(
                            color: isLocked ? Color.clear : Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.45),
                            radius: 8,
                            y: 3
                        )

                    Image(systemName: isRTL ? "arrow.left" : "arrow.right")
                        .font(PPBrandFont.bold(size: 18))
                        .foregroundStyle(.white)
                        .scaleEffect(isDragging ? 1.15 : 1.0)
                }
                .padding(4)
                .offset(x: isRTL ? -dragOffset : dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isLocked else {
                                if !shakeHint {
                                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                                    shakeHint = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        shakeHint = false
                                    }
                                }
                                return
                            }
                            isDragging = true
                            let translation = isRTL ? -value.translation.width : value.translation.width
                            dragOffset = min(max(0, translation), maxDistance)
                            if dragOffset == maxDistance {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                        .onEnded { _ in
                            guard !isLocked else { return }
                            isDragging = false
                            if dragOffset >= maxDistance * 0.86 {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    dragOffset = maxDistance
                                }
                                onSlideComplete()
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .animation(isDragging ? .none : .spring(response: 0.35, dampingFraction: 0.75), value: dragOffset)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        isLocked
                            ? AdminSurface.hairline
                            : Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .frame(height: barHeight)
    }
}

// MARK: - Celebratory Completion Modal Overlay
private struct AdminPetsHotelCelebrationOverlay: View {
    let petName: String
    let wing: HotelWing
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.emerald.opacity(0.18))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.seal.fill")
                        .font(PPBrandFont.bold(size: 44))
                        .foregroundStyle(AdminSurface.emerald)
                }

                VStack(spacing: 6) {
                    Text(Language.get("Hotel_Checkout_Celebration_Title", alter: "تم تسليم النزيل بنجاح!"))
                        .font(PPBrandFont.bold(size: 22))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(petName)
                        .font(PPBrandFont.bold(size: 18))
                        .foregroundStyle(wing.tint)

                    Text(Language.get("Hotel_Checkout_Celebration_Sub", alter: "رافقتكم السلامة • تم تحرير الجناح للتعقيم وتحديث السجلات"))
                        .font(PPBrandFont.medium(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Button(action: onDismiss) {
                    Text(Language.get("Hotel_Checkout_Close_Action", alter: "إغلاق نافذة المغادرة"))
                        .font(PPBrandFont.bold(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(AdminSurface.emerald, in: Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 6)
            }
            .padding(26)
            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(AdminSurface.emerald.opacity(0.4), lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 24, y: 12)
            .padding(.horizontal, 32)
        }
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
                        Text(Language.get("Hotel_Settlement_Reference", alter: "رقم إيصال تسوية الإقامة الفندقية"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        TextField(Language.get("Hotel_Settlement_RefPlaceholder", alter: "رقم إيصال أو عملية تسوية الإقامة الفندقية السعيدة..."), text: $reference)
                            .font(Font.custom("Beiruti-Medium", size: 14))
                            .padding(12)
                            .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.8)
                            )

                        Text(Language.get("Hotel_Settlement_Notes", alter: "ملاحظات تسوية الإجازة الفندقية"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .padding(.top, 4)

                        TextField(Language.get("Hotel_Settlement_NotesPlaceholder", alter: "ملاحظات إضافية على تسوية الإجازة السعيدة (اختياري)..."), text: $notes)
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
