//
//  AdminPetsHotelReservationsManagementViews.swift
//  PurePetsAdmin
//
//  Category-defining, beyond-FAANG mobile operations suite for
//  hotel reservations management (إدارة الحجوزات الفندقية).
//  Mirrors Pure Pets Console and Infra Cloud Functions.
//

import SwiftUI

// MARK: - Main Reservations Management View
public struct AdminPetsHotelReservationsManagementView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AdminPetsHotelViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Pipeline Telemetry Sentinel Deck
            pipelineTelemetryDeck

            // Lifecycle Horizon Filter Tabs
            lifecycleTabs

            // Tactical Action Bar (Search + Wing Pills + New Booking CTA)
            tacticalActionBar

            // Reservations List Content
            if viewModel.filteredReservations.isEmpty {
                emptyReservationsCard
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredReservations) { res in
                        AdminPetsHotelReservationCard(reservation: res, viewModel: viewModel)
                    }
                }
            }
        }
    }

    // MARK: - Pipeline Telemetry Sentinel Deck
    private var pipelineTelemetryDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("Hotel_Res_PipelineTitle", alter: "مؤشرات تدفق الحجوزات والنزلاء"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text(String.localizedStringWithFormat(
                    Language.get("Hotel_Res_TotalCountFormat", alter: "%ld حجز مسجل"),
                    viewModel.reservations.count
                ))
                .font(Font.custom("Beiruti-Medium", size: 12))
                .foregroundStyle(AdminSurface.secondaryText)
            }

            HStack(spacing: 8) {
                telemetryTile(
                    title: Language.get("Hotel_Res_PendingTab", alter: "بانتظار التأكيد"),
                    count: viewModel.reservations.filter { $0.status == .pendingConfirmation || $0.status == .draft }.count,
                    color: Color(red: 0.95, green: 0.55, blue: 0.15),
                    icon: "clock.badge.exclamationmark"
                )

                telemetryTile(
                    title: Language.get("Hotel_Res_ConfirmedTab", alter: "مؤكد وجاهز"),
                    count: viewModel.reservations.filter { $0.status == .confirmed || $0.status == .readyForCheckin }.count,
                    color: Color(red: 0.10, green: 0.55, blue: 0.85),
                    icon: "calendar.badge.checkmark"
                )

                telemetryTile(
                    title: Language.get("Hotel_Res_ArrivalsToday", alter: "وصول اليوم"),
                    count: viewModel.arrivalsTodayCount,
                    color: Color(red: 0.16, green: 0.72, blue: 0.44),
                    icon: "arrow.down.left.circle.fill"
                )

                telemetryTile(
                    title: Language.get("Hotel_Res_InStayTab", alter: "في الإقامة"),
                    count: viewModel.inHouseGuestsCount,
                    color: AdminSurface.primary,
                    icon: "pawprint.fill"
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

    private func telemetryTile(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            Text(title)
                .font(Font.custom("Beiruti-Medium", size: 11))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Lifecycle Horizon Filter Tabs
    private var lifecycleTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterPill(id: "all", title: Language.get("All", alter: "الكل"))
                filterPill(id: "pending", title: Language.get("Hotel_Res_PendingTab", alter: "بانتظار التأكيد"))
                filterPill(id: "confirmed", title: Language.get("Hotel_Res_ConfirmedTab", alter: "المؤكدة"))
                filterPill(id: "in_stay", title: Language.get("Hotel_Res_InStayTab", alter: "قيد الإقامة"))
                filterPill(id: "completed", title: Language.get("Hotel_Res_CompletedTab", alter: "المكتملة"))
                filterPill(id: "cancelled", title: Language.get("Hotel_Res_CancelledTab", alter: "الملغاة والمرفوضة"))
            }
        }
    }

    private func filterPill(id: String, title: String) -> some View {
        let isSelected = viewModel.reservationStatusFilter == id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.reservationStatusFilter = id
            }
        } label: {
            Text(title)
                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: Capsule())
                .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                .overlay(Capsule().strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Tactical Action Bar (Search + New Booking CTA)
    private var tacticalActionBar: some View {
        HStack(spacing: 10) {
            // Summary count
            Text(String.localizedStringWithFormat(
                Language.get("Hotel_Res_ShowingFormat", alter: "عرض %ld حجز"),
                viewModel.filteredReservations.count
            ))
            .font(Font.custom("Beiruti-Bold", size: 13))
            .foregroundStyle(AdminSurface.secondaryText)

            Spacer()

            // New Reservation CTA
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.newReservationModalOpen = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("Hotel_Res_NewReservationCTA", alter: "حجز فندقي جديد"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var emptyReservationsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundStyle(AdminSurface.secondaryText)

            Text(Language.get("Hotel_Res_NoReservationsMatch", alter: "لا توجد حجوزات مسجلة تطابق التصفية الحالية"))
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.secondaryText)

            Button {
                viewModel.newReservationModalOpen = true
            } label: {
                Text(Language.get("Hotel_Res_CreateFirst", alter: "تسجيل حجز فندقي جديد"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Category-Defining Flagship Reservation Card
public struct AdminPetsHotelReservationCard: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Wing Icon + Pet & Customer + Status Pill
            HStack(spacing: 12) {
                // Pet Avatar & Wing Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(reservation.wing.tint.opacity(0.18))
                        .frame(width: 50, height: 50)
                    Image(systemName: reservation.wing.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(reservation.wing.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(reservation.petName.isEmpty ? Language.get("Pet", alter: "حيوان أليف") : reservation.petName)
                            .font(PPBrandFont.bold(17))
                            .foregroundStyle(AdminSurface.primaryText)

                        if reservation.medicationRequired {
                            Image(systemName: "pill.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        }
                    }

                    HStack(spacing: 4) {
                        Text(reservation.customerName)
                            .font(PPBrandFont.medium(13))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(reservation.customerPhone)
                            .font(PPBrandFont.medium(12))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                // Status Capsule
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(reservation.status.color)
                            .frame(width: 6, height: 6)
                        Text(reservation.status.title)
                            .font(PPBrandFont.bold(11))
                            .foregroundStyle(reservation.status.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(reservation.status.color.opacity(0.12), in: Capsule())

                    if !reservation.reservationNumber.isEmpty {
                        Text(reservation.reservationNumber)
                            .font(PPBrandFont.bold(10))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            Divider()
                .opacity(0.6)

            // Horizon Stay Window & Room Assignment
            HStack(spacing: 12) {
                // Dates Horizon
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text("\(formatDate(reservation.checkInDate)) → \(formatDate(reservation.checkOutDate))")
                        .font(PPBrandFont.medium(12))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text("(\(reservation.numberOfNights) \(Language.get("Hotel_Nights_Short", alter: "ليالي")))")
                        .font(PPBrandFont.bold(11))
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                // Room Assignment Badge
                if let roomNumber = reservation.assignedRoomNumber, !roomNumber.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 10))
                        Text(roomNumber)
                            .font(PPBrandFont.bold(11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(reservation.wing.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(reservation.wing.tint)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                        Text(Language.get("Hotel_Room_Unassigned", alter: "غير مخصص"))
                            .font(PPBrandFont.bold(11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Color.orange)
                }
            }

            // Financial Balance & Action Strip
            HStack {
                // Financial Quoted / Balance
                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Hotel_Res_TotalQuoted", alter: "إجمالي الحساب:"))
                        .font(PPBrandFont.medium(10))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(reservation.formattedTotal)
                        .font(PPBrandFont.bold(14))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Action Buttons based on status
                HStack(spacing: 8) {
                    // Confirm action if pending
                    if reservation.status == .pendingConfirmation || reservation.status == .draft {
                        Button {
                            Task {
                                await viewModel.confirmReservation(reservation: reservation)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                Text(Language.get("Hotel_Res_ConfirmAction", alter: "تأكيد الحجز"))
                                    .font(PPBrandFont.bold(12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.10, green: 0.55, blue: 0.85), in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Check-in trigger if ready or confirmed
                    if reservation.status == .confirmed || reservation.status == .readyForCheckin || reservation.status == .preArrival {
                        Button {
                            viewModel.checkInModalReservation = reservation
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.left.circle.fill")
                                    .font(.system(size: 11))
                                Text(Language.get("Hotel_CheckInNow", alter: "تسجيل دخول"))
                                    .font(PPBrandFont.bold(12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.16, green: 0.72, blue: 0.44), in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!viewModel.canCheckIn)
                        .opacity(viewModel.canCheckIn ? 1 : 0.5)
                    }

                    // Dossier Inspector trigger
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectedReservationDetail = reservation
                    } label: {
                        HStack(spacing: 4) {
                            Text(Language.get("Details", alter: "التفاصيل"))
                                .font(PPBrandFont.bold(12))
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdminSurface.surface, in: Capsule())
                        .foregroundStyle(AdminSurface.primary)
                        .overlay(Capsule().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.04), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.85)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.selectedReservationDetail = reservation
        }
        .hoverEffect(.highlight)
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMM"
        return df.string(from: date)
    }
}

// MARK: - Sovereign Reservation Detail Sheet (ملف الحجز والنزيل المتكامل)
// First-Principles Dual-Architecture: iPadOS Spatial Observatory Cockpit & iPhone Tactile Boarding Deck.
// Strict Beiruti Typography Mandate: Every glyph strictly rendered via Beiruti font family.

private struct HotelBeiruti {
    static func bold(_ size: CGFloat) -> Font {
        Font.custom("Beiruti-Bold", size: size)
    }
    static func medium(_ size: CGFloat) -> Font {
        Font.custom("Beiruti-Medium", size: size)
    }
    static func regular(_ size: CGFloat) -> Font {
        Font.custom("Beiruti-Regular", size: size)
    }
}

public struct AdminPetsHotelReservationDetailSheet: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    public var isPushMode: Bool = true
    public var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        reservation: AdminHotelReservation,
        viewModel: AdminPetsHotelViewModel,
        isPushMode: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.reservation = reservation
        self.viewModel = viewModel
        self.isPushMode = isPushMode
        self.onBack = onBack
    }

    @State private var isExtending: Bool = false
    @State private var isShowingReasonSheet: Bool = false
    @State private var pendingAction: String = ""
    @State private var showCopiedToast: Bool = false

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isIPad {
                iPadObservatoryCockpit
            } else {
                iPhoneTactileBoardingDeck
            }

            // Top-anchored confirmation toast
            if showCopiedToast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        Text(Language.get("Hotel_ReservationNumber_Copied", alter: "تم نسخ رقم الحجز بنجاح"))
                            .font(HotelBeiruti.bold(13))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.88), in: Capsule())
                    .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .padding(.top, 16)
                    Spacer()
                }
                .zIndex(100)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .fullScreenCover(isPresented: $isExtending) {
            AdminPetsHotelExtendStayDialog(reservation: reservation, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $isShowingReasonSheet) {
            AdminPetsHotelReasonSheet(reservation: reservation, action: pendingAction, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - iPhone Tactile Handheld Deck Layout

    private var iPhoneTactileBoardingDeck: some View {
        VStack(spacing: 0) {
            // Sovereign Navigation Header
            AdminSovereignNavigationBar(
                title: reservation.reservationNumber.isEmpty ? Language.get("Hotel_Res_DetailTitle", alter: "تفاصيل الحجز") : reservation.reservationNumber,
                subtitle: "\(reservation.petName) • \(reservation.wing.title)",
                statusDotColor: reservation.status.color,
                isModal: !isPushMode,
                customTopSpacing: 0,
                onBack: {
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                }
            ) {
                // Status Capsule Header Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(reservation.status.color)
                        .frame(width: 7, height: 7)
                    Text(reservation.status.title)
                        .font(HotelBeiruti.bold(12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(reservation.status.color.opacity(0.12), in: Capsule())
                .foregroundStyle(reservation.status.color)
            }

            // Scrollable Operational Feed
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // VIP Boarding Pass Hero Deck
                    boardingPassHeroCard(compact: true)

                    // Stay Horizon Runway Timeline
                    stayHorizonRunwayCard

                    // Room & Suite Allocation Station
                    roomAllocationStationCard

                    // Clinical Care & Feeding Protocol
                    careProtocolCard

                    // Customer Dossier & Contact
                    customerDossierCard

                    // Financial Folio & Invoicing Ledger
                    financialFolioCard

                    // Emergency Contact (If present)
                    if let eName = reservation.emergencyContactName, !eName.isEmpty {
                        emergencyContactCard(name: eName, phone: reservation.emergencyContactPhone ?? "")
                    }

                    // Audit Metadata & System Provenance
                    auditStampCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 120) // Clearance for the floating action dock
            }
        }
        .safeAreaInset(edge: .bottom) {
            iPhoneFloatingActionDock
        }
    }

    // MARK: - iPad Spatial Multi-Column Cockpit Layout

    private var iPadObservatoryCockpit: some View {
        VStack(spacing: 0) {
            // iPad Top Command Bar
            iPadTopCommandBar

            // Spatial Two-Column Command Grid
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    // Left Column (40% width): Guest & Clinical Dossier
                    VStack(spacing: 18) {
                        boardingPassHeroCard(compact: false)
                        careProtocolCard
                        customerDossierCard
                        if let eName = reservation.emergencyContactName, !eName.isEmpty {
                            emergencyContactCard(name: eName, phone: reservation.emergencyContactPhone ?? "")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column (60% width): Stay Horizon & Financial Folio
                    VStack(spacing: 18) {
                        stayHorizonRunwayCard
                        roomAllocationStationCard
                        financialFolioCard
                        auditStampCard
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - iPad Native Navigation & Action Bar

    private var iPadTopCommandBar: some View {
        HStack(spacing: 14) {
            Button {
                if let onBack = onBack {
                    onBack()
                } else {
                    dismiss()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                    Text(Language.get("Back", alter: "رجوع"))
                        .font(HotelBeiruti.bold(14))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AdminSurface.control, in: Capsule())
                .foregroundStyle(AdminSurface.primaryText)
            }
            .buttonStyle(PlainButtonStyle())
            .hoverEffect(.lift)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(reservation.reservationNumber.isEmpty ? Language.get("Hotel_Res_DetailTitle", alter: "تفاصيل الحجز") : reservation.reservationNumber)
                        .font(HotelBeiruti.bold(18))
                        .foregroundStyle(AdminSurface.primaryText)

                    Button {
                        copyReservationNumber()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(.highlight)

                    // Status Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(reservation.status.color)
                            .frame(width: 7, height: 7)
                        Text(reservation.status.title)
                            .font(HotelBeiruti.bold(12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(reservation.status.color.opacity(0.12), in: Capsule())
                    .foregroundStyle(reservation.status.color)
                }

                Text("\(reservation.petName) • \(reservation.wing.title)")
                    .font(HotelBeiruti.medium(12))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            // iPad Hardware Toolbar Action Cluster
            HStack(spacing: 10) {
                // Call Customer Shortcut
                let phone = reservation.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                if !phone.isEmpty {
                    Button {
                        callPhone(phone)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 13))
                            Text(Language.get("Hotel_Keyboard_Call", alter: "اتصال (⌘+P)"))
                                .font(HotelBeiruti.bold(13))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(.lift)
                    .keyboardShortcut("p", modifiers: .command)
                }

                // Check-in Button
                if reservation.status == .confirmed || reservation.status == .readyForCheckin || reservation.status == .preArrival {
                    Button {
                        if let onBack = onBack {
                            onBack()
                        } else {
                            dismiss()
                        }
                        viewModel.checkInModalReservation = reservation
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.left.circle.fill")
                                .font(.system(size: 14))
                            Text(Language.get("Hotel_Keyboard_CheckIn", alter: "تسجيل الوصول (⌘+C)"))
                                .font(HotelBeiruti.bold(14))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.16, green: 0.72, blue: 0.44), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(.lift)
                    .disabled(!viewModel.canCheckIn)
                    .keyboardShortcut("c", modifiers: .command)
                }

                // Confirm Button (If pending)
                if reservation.status == .pendingConfirmation || reservation.status == .draft {
                    Button {
                        Task {
                            await viewModel.confirmReservation(reservation: reservation)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.isSubmitting {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            }
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                            Text(Language.get("Hotel_Res_ConfirmAction", alter: "تأكيد الحجز"))
                                .font(HotelBeiruti.bold(14))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.10, green: 0.55, blue: 0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(.lift)
                    .disabled(viewModel.isSubmitting)
                }

                // Extend Stay Button
                if reservation.status != .completed && reservation.status != .cancelled {
                    Button {
                        isExtending = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 13))
                            Text(Language.get("Hotel_Keyboard_Extend", alter: "تمديد (⌘+E)"))
                                .font(HotelBeiruti.bold(13))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(AdminSurface.primary)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.primary.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(.lift)
                    .keyboardShortcut("e", modifiers: .command)
                }

                // Cancel Reservation Button
                if reservation.status != .completed && reservation.status != .cancelled && reservation.status != .checkedIn && reservation.status != .inStay {
                    Button {
                        pendingAction = "cancel_reservation"
                        isShowingReasonSheet = true
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.25))
                            .padding(8)
                            .background(Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.12), in: Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .hoverEffect(.highlight)
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Subcomponent 1: VIP Boarding Pass Hero Deck

    private func boardingPassHeroCard(compact: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Species High-Fidelity Medallion
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    reservation.wing.tint.opacity(0.24),
                                    reservation.wing.tint.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: compact ? 68 : 78, height: compact ? 68 : 78)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(reservation.wing.tint.opacity(0.3), lineWidth: 1)
                        )

                    Image(systemName: reservation.wing.icon)
                        .font(.system(size: compact ? 30 : 36, weight: .bold))
                        .foregroundStyle(reservation.wing.tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(reservation.petName)
                            .font(HotelBeiruti.bold(compact ? 22 : 26))
                            .foregroundStyle(AdminSurface.primaryText)

                        // Status Tag
                        HStack(spacing: 4) {
                            Circle()
                                .fill(reservation.status.color)
                                .frame(width: 6, height: 6)
                            Text(reservation.status.title)
                                .font(HotelBeiruti.bold(11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(reservation.status.color.opacity(0.14), in: Capsule())
                        .foregroundStyle(reservation.status.color)
                    }

                    Text(reservation.petBreed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reservation.wing.title : "\(reservation.petBreed) • \(reservation.wing.title)")
                        .font(HotelBeiruti.medium(13))
                        .foregroundStyle(AdminSurface.secondaryText)

                    // Booking Ref Badge
                    Button {
                        copyReservationNumber()
                    } label: {
                        HStack(spacing: 5) {
                            Text(reservation.reservationNumber)
                                .font(HotelBeiruti.bold(12))
                                .foregroundStyle(AdminSurface.primary)
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(AdminSurface.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()
            }

            Divider()
                .padding(.vertical, 2)

            // Direct Communication Suite (Call, WhatsApp, Copy)
            HStack(spacing: 8) {
                // Call Phone CTA
                Button {
                    callPhone(reservation.customerPhone)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 12))
                        Text(Language.get("Call", alter: "اتصال"))
                            .font(HotelBeiruti.bold(13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                }
                .buttonStyle(PlainButtonStyle())

                // WhatsApp Chat CTA
                Button {
                    openWhatsApp(phone: reservation.customerPhone)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 12))
                        Text(Language.get("Hotel_WhatsApp_Chat", alter: "واتساب"))
                            .font(HotelBeiruti.bold(13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(red: 0.10, green: 0.65, blue: 0.40).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Color(red: 0.10, green: 0.65, blue: 0.40))
                }
                .buttonStyle(PlainButtonStyle())

                // Copy Number CTA
                Button {
                    copyReservationNumber()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11))
                        Text(Language.get("Hotel_Copy_ReservationNumber", alter: "نسخ"))
                            .font(HotelBeiruti.bold(12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(AdminSurface.primaryText)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.85)
        )
    }

    // MARK: - Subcomponent 2: Stay Horizon Runway Timeline

    private var stayHorizonRunwayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(Language.get("Hotel_Res_StayHorizon", alter: "فترة الإقامة وتخصيص الجناح"), systemImage: "calendar.badge.clock")
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                // Dynamic Horizon State Pill
                let badge = horizonCountdownBadge(for: reservation)
                HStack(spacing: 4) {
                    Circle()
                        .fill(badge.color)
                        .frame(width: 6, height: 6)
                    Text(badge.text)
                        .font(HotelBeiruti.bold(11))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(badge.color.opacity(0.12), in: Capsule())
                .foregroundStyle(badge.color)
            }

            // Visual Flight Runway
            HStack(alignment: .center, spacing: 12) {
                // Check-in Milestone (Left Node)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        Text(Language.get("Hotel_Arrival", alter: "الوصول"))
                            .font(HotelBeiruti.bold(11))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    }
                    Text(formatHotelDayName(reservation.checkInDate))
                        .font(HotelBeiruti.medium(12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatHotelDate(reservation.checkInDate))
                        .font(HotelBeiruti.bold(14))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(formatHotelTime(reservation.checkInDate))
                        .font(HotelBeiruti.medium(12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Flight Runway Connector (Center)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.5))
                            .frame(width: 4, height: 4)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.5),
                                        AdminSurface.primary.opacity(0.5),
                                        Color(red: 0.90, green: 0.35, blue: 0.25).opacity(0.5)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                        Circle()
                            .fill(Color(red: 0.90, green: 0.35, blue: 0.25).opacity(0.5))
                            .frame(width: 4, height: 4)
                    }

                    // Night Badge
                    HStack(spacing: 4) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 9))
                        Text(String.localizedStringWithFormat(
                            Language.get("Hotel_Nights_Format", alter: "%ld ليلة إقامة"),
                            reservation.numberOfNights
                        ))
                        .font(HotelBeiruti.bold(12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 100)

                // Check-out Milestone (Right Node)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(Language.get("Hotel_Departure", alter: "المغادرة"))
                            .font(HotelBeiruti.bold(11))
                            .foregroundStyle(Color(red: 0.90, green: 0.35, blue: 0.25))
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.90, green: 0.35, blue: 0.25))
                    }
                    Text(formatHotelDayName(reservation.checkOutDate))
                        .font(HotelBeiruti.medium(12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatHotelDate(reservation.checkOutDate))
                        .font(HotelBeiruti.bold(14))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(formatHotelTime(reservation.checkOutDate))
                        .font(HotelBeiruti.medium(12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.85)
        )
    }

    // MARK: - Subcomponent 3: Room & Suite Allocation Station

    private var roomAllocationStationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Hotel_WingAndTier", alter: "تخصيص الجناح الفندقي"), systemImage: "bed.double.fill")
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                if reservation.assignedRoomNumber != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                        Text(Language.get("Hotel_Room_Status_Assigned", alter: "تم التخصيص"))
                            .font(HotelBeiruti.bold(11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.12), in: Capsule())
                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                        Text(Language.get("Hotel_Room_Status_Pending", alter: "بانتظار التسكين"))
                            .font(HotelBeiruti.bold(11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.orange)
                }
            }

            if let room = reservation.assignedRoomNumber, !room.isEmpty {
                // Room Allocated State
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(reservation.wing.tint.opacity(0.16))
                            .frame(width: 44, height: 44)
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(reservation.wing.tint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String.localizedStringWithFormat(Language.get("Hotel_AssignedRoom_Format", alter: "جناح رقم: %@"), room))
                            .font(HotelBeiruti.bold(16))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(reservation.wing.title)
                            .font(HotelBeiruti.medium(12))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()
                }
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                // Room Unassigned State with Direct CTA
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "bed.double")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Room_Unassigned", alter: "غير مخصص بعد"))
                            .font(HotelBeiruti.bold(14))
                            .foregroundStyle(Color.orange)

                        Text(Language.get("Hotel_Room_Status_Pending", alter: "يتم تسكين النزيل واختيار الجناح المناسب عند تسجيل الدخول"))
                            .font(HotelBeiruti.medium(12))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    if (reservation.status == .confirmed || reservation.status == .readyForCheckin) && viewModel.canCheckIn {
                        Button {
                            if let onBack = onBack {
                                onBack()
                            } else {
                                dismiss()
                            }
                            viewModel.checkInModalReservation = reservation
                        } label: {
                            Text(Language.get("Hotel_Room_AllocateNow", alter: "تخصيص الآن"))
                                .font(HotelBeiruti.bold(12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.85)
        )
    }

    // MARK: - Subcomponent 4: Clinical Care & Feeding Protocol Card

    private var careProtocolCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Pet_Details", alter: "بيانات النزيل والرعاية"), systemImage: "pawprint.fill")
                .font(HotelBeiruti.bold(15))
                .foregroundStyle(AdminSurface.primaryText)

            // Pet Basic Grid
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Pet_Name", alter: "الاسم"))
                        .font(HotelBeiruti.medium(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(reservation.petName)
                        .font(HotelBeiruti.bold(14))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Breed", alter: "السلالة"))
                        .font(HotelBeiruti.medium(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(reservation.petBreed.isEmpty ? "—" : reservation.petBreed)
                        .font(HotelBeiruti.bold(14))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Category", alter: "الجناح"))
                        .font(HotelBeiruti.medium(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(reservation.wing.title)
                        .font(HotelBeiruti.bold(14))
                        .foregroundStyle(reservation.wing.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Medication Status
            if reservation.medicationRequired {
                HStack(spacing: 8) {
                    Image(systemName: "cross.vial.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(Language.get("Hotel_MedicationRequiredBadge", alter: "يتطلب خطة أدوية مسجلة"))
                            .font(HotelBeiruti.bold(13))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))

                        Text(Language.get("Hotel_MedicationInstructions", alter: "يجب على طاقم الرعاية مراجعة وتوثيق جدول الأدوية الخاصة بالنزيل"))
                            .font(HotelBeiruti.medium(11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))

                    Text(Language.get("Hotel_Care_NoMedication", alter: "لا توجد أدوية مقررة لهذا النزيل"))
                        .font(HotelBeiruti.medium(12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()
                }
                .padding(10)
                .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Feeding Routine
            if let feedNotes = reservation.feedingNotes, !feedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("Hotel_SpecialDietAndAllergies", alter: "النظام الغذائي وتوجيهات الإطعام"))
                            .font(HotelBeiruti.bold(12))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    Text(feedNotes)
                        .font(HotelBeiruti.medium(13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Special Instructions
            if let instructions = reservation.specialInstructions ?? reservation.notes, !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("Hotel_Special_Instructions_Title", alter: "تعليمات وتوجيهات خاصة"))
                            .font(HotelBeiruti.bold(12))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    Text(instructions)
                        .font(HotelBeiruti.medium(13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.85)
        )
    }

    // MARK: - Subcomponent 5: Customer Dossier Card

    private var customerDossierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Customer", alter: "العميل والاتصال"), systemImage: "person.crop.circle.fill")
                .font(HotelBeiruti.bold(15))
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reservation.customerName.isEmpty ? Language.get("Guest", alter: "عميل الحجز") : reservation.customerName)
                        .font(HotelBeiruti.bold(16))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(reservation.customerPhone)
                        .font(HotelBeiruti.bold(13))
                        .foregroundStyle(AdminSurface.secondaryText)

                    if let email = reservation.customerEmail, !email.isEmpty {
                        Text(email)
                            .font(HotelBeiruti.regular(12))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                let phone = reservation.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                if !phone.isEmpty {
                    HStack(spacing: 10) {
                        // WhatsApp Chat Button
                        Button {
                            openWhatsApp(phone: phone)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 37 / 255.0, green: 211 / 255.0, blue: 102 / 255.0).opacity(0.15))
                                    .frame(width: 44, height: 44)

                                if UIImage(named: "whatsapp") != nil {
                                    Image("whatsapp")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 22, height: 22)
                                        .foregroundStyle(Color(red: 37 / 255.0, green: 211 / 255.0, blue: 102 / 255.0))
                                } else {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Color(red: 37 / 255.0, green: 211 / 255.0, blue: 102 / 255.0))
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Language.get("Hotel_WhatsApp_Chat", alter: "واتساب"))

                        // Direct Call Button
                        Button {
                            callPhone(phone)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(Language.get("Call", alter: "اتصال"))
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.85)
        )
    }

    // MARK: - Subcomponent 6: Financial Folio & Invoicing Ledger

    private var financialFolioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(Language.get("Hotel_Billing", alter: "الحساب المالي والفواتير"), systemImage: "creditcard.fill")
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                // Payment Status Badge
                let balance = reservation.balanceDueMinor ?? 0
                if balance <= 0 && (reservation.totalAmountMinor ?? 0) > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text(Language.get("Hotel_Folio_PaidFull", alter: "مدفوع بالكامل"))
                            .font(HotelBeiruti.bold(11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.12), in: Capsule())
                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                } else if let deposit = reservation.depositMinor, deposit > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 10))
                        Text(Language.get("Hotel_Folio_DepositPaid", alter: "تم دفع العربون"))
                            .font(HotelBeiruti.bold(11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.blue)
                }
            }

            VStack(spacing: 10) {
                // Estimated Total
                HStack {
                    Text(Language.get("Hotel_QuotedTotal", alter: "إجمالي الإقامة التقديري:"))
                        .font(HotelBeiruti.medium(13))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(reservation.formattedTotal)
                        .font(HotelBeiruti.bold(17))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                // Deposit Collected
                if let deposit = reservation.depositMinor, deposit > 0 {
                    HStack {
                        Text(Language.get("Hotel_DepositPaid", alter: "العربون المحصل:"))
                            .font(HotelBeiruti.medium(13))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        Text("\(deposit / 100) \(Language.get("Currency_QAR", alter: "ر.ق"))")
                            .font(HotelBeiruti.bold(14))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    }
                }

                // Balance Due
                if let balance = reservation.balanceDueMinor, balance > 0 {
                    Divider()

                    HStack {
                        Text(Language.get("Hotel_BalanceDue", alter: "المتبقي للدفع:"))
                            .font(HotelBeiruti.bold(14))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        Spacer()
                        Text("\(balance / 100) \(Language.get("Currency_QAR", alter: "ر.ق"))")
                            .font(HotelBeiruti.bold(18))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.85)
        )
    }

    // MARK: - Subcomponent 7: Emergency Contact Card

    private func emergencyContactCard(name: String, phone: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("EmergencyContact", alter: "جهة الاتصال في حالات الطوارئ"), systemImage: "cross.fill")
                .font(HotelBeiruti.bold(14))
                .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(HotelBeiruti.bold(15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(phone)
                        .font(HotelBeiruti.medium(12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                Button {
                    callPhone(phone)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 14))
                        Text(Language.get("Hotel_Emergency_Call", alter: "طوارئ"))
                            .font(HotelBeiruti.bold(12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.15), in: Capsule())
                    .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(12)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.2), lineWidth: 0.85)
        )
    }

    // MARK: - Subcomponent 8: Audit Stamp Card

    private var auditStampCard: some View {
        VStack(spacing: 6) {
            HStack {
                Text(Language.get("Hotel_Audit_BookingID", alter: "معرف الحجز:"))
                    .font(HotelBeiruti.medium(11))
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer()
                Text(reservation.id)
                    .font(HotelBeiruti.bold(11))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            HStack {
                Text(Language.get("Hotel_Audit_Created", alter: "تاريخ الإنشاء:"))
                    .font(HotelBeiruti.medium(11))
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer()
                Text(formatHotelDate(reservation.createdAt) + " " + formatHotelTime(reservation.createdAt))
                    .font(HotelBeiruti.medium(11))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            if !reservation.branchId.isEmpty {
                HStack {
                    Text(Language.get("Hotel_Audit_Branch", alter: "الفرع المعتمد:"))
                        .font(HotelBeiruti.medium(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(reservation.branchId)
                        .font(HotelBeiruti.medium(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
        .padding(14)
        .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Subcomponent 9: iPhone Floating Action Dock (Thumb Zone)

    private var iPhoneFloatingActionDock: some View {
        VStack(spacing: 8) {
            // Confirm button (If pending)
            if reservation.status == .pendingConfirmation || reservation.status == .draft {
                Button {
                    Task {
                        await viewModel.confirmReservation(reservation: reservation)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Image(systemName: "checkmark.circle.fill")
                        Text(Language.get("Hotel_Res_ConfirmAction", alter: "تأكيد الحجز الفندقي"))
                            .font(HotelBeiruti.bold(16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.10, green: 0.55, blue: 0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(viewModel.isSubmitting)
            }

            // Check-in CTA Button (If confirmed or ready)
            if reservation.status == .confirmed || reservation.status == .readyForCheckin || reservation.status == .preArrival {
                Button {
                    if let onBack = onBack {
                        onBack()
                    } else {
                        dismiss()
                    }
                    viewModel.checkInModalReservation = reservation
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.left.circle.fill")
                            .font(.system(size: 17))
                        Text(Language.get("Hotel_CheckInNow", alter: "إتمام تسجيل الدخول الآن"))
                            .font(HotelBeiruti.bold(16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.16, green: 0.72, blue: 0.44), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.canCheckIn)
                .opacity(viewModel.canCheckIn ? 1 : 0.6)
            }

            // Secondary Row: Extend Stay & Cancel Actions
            HStack(spacing: 10) {
                // Extend Stay button
                if reservation.status != .completed && reservation.status != .cancelled {
                    Button {
                        isExtending = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 14))
                            Text(Language.get("Hotel_Res_ExtendStay", alter: "تمديد الإقامة"))
                                .font(HotelBeiruti.bold(14))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(AdminSurface.primary)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.primary.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Cancel Reservation button
                if reservation.status != .completed && reservation.status != .cancelled && reservation.status != .checkedIn && reservation.status != .inStay {
                    Button {
                        pendingAction = "cancel_reservation"
                        isShowingReasonSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 13))
                            Text(Language.get("Hotel_Res_CancelReservation", alter: "إلغاء الحجز"))
                                .font(HotelBeiruti.bold(13))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.25))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(red: 0.85, green: 0.25, blue: 0.25).opacity(0.2), lineWidth: 0.85))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Action Helpers

    private func callPhone(_ phone: String) {
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "tel://\(cleaned)") {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    private func openWhatsApp(phone: String) {
        var cleaned = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
        if cleaned.count == 8 {
            cleaned = "974" + cleaned
        }
        let message = String.localizedStringWithFormat(
            Language.isRTL()
                ? "مرحباً بك، نتواصل معك من فندق بيور بيتس بخصوص حجز أليفك (%@) رقم (%@)."
                : "Hello, reaching out from Pure Pets Hotel regarding your pet (%@) reservation (%@).",
            reservation.petName,
            reservation.reservationNumber
        )
        if let encoded = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://wa.me/\(cleaned)?text=\(encoded)") {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    private func copyReservationNumber() {
        UIPasteboard.general.string = reservation.reservationNumber
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }

    private func formatHotelDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMMM yyyy"
        return df.string(from: date)
    }

    private func formatHotelTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "hh:mm a"
        return df.string(from: date)
    }

    private func formatHotelDayName(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "EEEE"
        return df.string(from: date)
    }

    private func horizonCountdownBadge(for reservation: AdminHotelReservation) -> (text: String, color: Color) {
        let cal = Calendar.current
        if reservation.status == .inStay {
            return (Language.get("Hotel_Stay_InHouse", alter: "النزيل مقيم حالياً بالفندق"), Color(red: 0.55, green: 0.25, blue: 0.85))
        }
        if reservation.status == .completed || reservation.status == .earlyCheckout {
            return (Language.get("Hotel_Stay_Departed", alter: "اكتملت الإقامة وغادر النزيل"), Color(red: 0.16, green: 0.72, blue: 0.44))
        }
        if cal.isDateInToday(reservation.checkInDate) {
            return (Language.get("Hotel_Stay_Countdown_Today", alter: "الوصول اليوم"), Color(red: 0.10, green: 0.65, blue: 0.55))
        }
        if cal.isDateInTomorrow(reservation.checkInDate) {
            return (Language.get("Hotel_Stay_Countdown_Tomorrow", alter: "الوصول غداً"), Color(red: 0.15, green: 0.55, blue: 0.90))
        }
        let now = Date()
        if reservation.checkInDate > now {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: reservation.checkInDate)).day ?? 1
            return (String.localizedStringWithFormat(Language.get("Hotel_Stay_Countdown_Days", alter: "متبقي %d أيام"), days), Color(red: 0.88, green: 0.50, blue: 0.15))
        }
        return (reservation.status.title, reservation.status.color)
    }
}


// MARK: - Sovereign Create Reservation Sheet (حجز فندقي جديد)
// Category-defining, beyond-FAANG dual-architecture reservation studio.
// First-principles dedicated iPadOS Observatory Console & iPhone Tactile Deck.

public struct AdminPetsHotelCreateReservationSheet: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var isPushMode: Bool = false
    public var onBack: (() -> Void)? = nil

    public init(viewModel: AdminPetsHotelViewModel, isPushMode: Bool = false, onBack: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.isPushMode = isPushMode
        self.onBack = onBack
    }

    // Customer state
    @State private var customerName: String = ""
    @State private var customerPhone: String = ""
    @State private var customerEmail: String = ""
    @State private var customerSearchQuery: String = ""
    @State private var customerSearchResults: [AdminHotelCustomerOption] = []
    @State private var selectedCustomer: AdminHotelCustomerOption? = nil
    @State private var customerPets: [AdminHotelCustomerPetOption] = []
    @State private var isSearchingCustomers: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    // Pet guest state
    @State private var petName: String = ""
    @State private var petSpecies: String = "dog"
    @State private var petBreed: String = ""
    @State private var petWeight: Double = 5.0
    @State private var specialDiet: String = ""
    @State private var allergies: String = ""
    @State private var requiresMedication: Bool = false
    @State private var medicationsText: String = ""

    // Stay & Tier state
    @State private var selectedWing: HotelWing = .dogs
    @State private var selectedTypeId: String = ""
    @State private var arrivalDate: Date = Date()
    @State private var departureDate: Date = Date().addingTimeInterval(86400 * 3)

    // Financial state
    @State private var depositPaidQAR: String = "0"
    @State private var depositPreset: DepositPreset = .zero
    @State private var emergencyName: String = ""
    @State private var emergencyPhone: String = ""
    @State private var notes: String = ""
    @State private var confirmImmediately: Bool = true

    // UX & Interaction states
    @State private var isSubmitting: Bool = false
    @State private var validationError: String? = nil
    @State private var shakeError: Bool = false
    @State private var morphicPulse: Bool = false

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var numberOfNights: Int {
        let cal = Calendar.current
        let d1 = cal.startOfDay(for: arrivalDate)
        let d2 = cal.startOfDay(for: departureDate)
        let diff = cal.dateComponents([.day], from: d1, to: d2).day ?? 1
        return max(1, diff)
    }

    private var selectedType: AdminHotelAccommodationType? {
        viewModel.accommodationTypes.first(where: { $0.id == selectedTypeId })
            ?? viewModel.accommodationTypes.first(where: { $0.wing == selectedWing })
            ?? viewModel.accommodationTypes.first
    }

    private var nightlyRateMajor: Double {
        if let type = selectedType {
            return Double(type.nightlyRateMinor) / 100.0
        }
        return 35.0
    }

    private var calculatedEstimatedTotal: Double {
        nightlyRateMajor * Double(numberOfNights)
    }

    private var depositPaidValue: Double {
        Double(depositPaidQAR.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
    }

    private var balanceDueAtCheckout: Double {
        max(0.0, calculatedEstimatedTotal - depositPaidValue)
    }

    private var availableSuitesCount: Int {
        guard let type = selectedType else { return 0 }
        let count = viewModel.accommodations.filter { $0.accommodationTypeId == type.id && $0.status == .available }.count
        return max(0, count)
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isIPad {
                iPadObservatoryLayout
            } else {
                iPhoneTactileDeckLayout
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            if selectedTypeId.isEmpty {
                selectedTypeId = viewModel.accommodationTypes.first?.id ?? ""
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                morphicPulse = true
            }
        }
    }

    // MARK: - iPadOS Dedicated Architecture: Dual-Deck Command Observatory

    private var iPadObservatoryLayout: some View {
        VStack(spacing: 0) {
            iPadTopCommandBar

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 28) {
                    // Left Column: Primary Intake Stream (58% width)
                    VStack(spacing: 20) {
                        if let error = validationError {
                            errorBanner(error)
                        }

                        customerProfileCard
                        petIdentityCard
                        suiteTierCard
                        stayChronoHorizonCard
                        careAndEmergencyCard
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column: Live Boarding Pass & Folio Inspector (42% width)
                    VStack(spacing: 20) {
                        liveBoardingPassCard
                        iPadActionFooterCard
                    }
                    .frame(width: 390)
                }
                .padding(28)
            }
        }
    }

    private var iPadTopCommandBar: some View {
        HStack(spacing: 16) {
            AdminSquircleBackButton {
                handleDismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Language.get("Hotel_Res_NewReservationTitle", alter: "تسجيل حجز فندقي جديد"))
                        .font(Font.custom("Beiruti-Bold", size: 20))
                        .foregroundStyle(AdminSurface.primaryText)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(uiColor: .systemGreen))
                            .frame(width: 7, height: 7)
                            .scaleEffect(morphicPulse ? 1.2 : 0.8)
                        Text(Language.get("Hotel_Res_NewReservationSub", alter: "فندق بيور بيتس • حجز إقامة"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(Color(uiColor: .systemGreen))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .systemGreen).opacity(0.12), in: Capsule())
                }

                Text(Language.get("Hotel_Keyboard_SubmitHint", alter: "⌘↵ للتأكيد • Esc للإلغاء"))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            // Quick live telemetry chips
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text("\(numberOfNights) \(Language.get("Hotel_NightsPluralUnit", alter: "ليالٍ"))")
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AdminSurface.primary.opacity(0.1), in: Capsule())

                HStack(spacing: 6) {
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemGreen))
                    Text(String(format: "%.0f %@", calculatedEstimatedTotal, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .systemGreen).opacity(0.1), in: Capsule())
            }

            AdminSquircleCloseButton {
                handleDismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(
            AdminSurface.card
                .ignoresSafeArea(edges: .top)
                .overlay(Divider(), alignment: .bottom)
        )
    }

    // MARK: - iPhone Dedicated Architecture: Tactile Horizon Deck

    private var iPhoneTactileDeckLayout: some View {
        VStack(spacing: 0) {
            iPhoneNavBar

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let error = validationError {
                            errorBanner(error)
                        }

                        customerProfileCard
                        petIdentityCard
                        suiteTierCard
                        stayChronoHorizonCard
                        financialDepositCard
                        careAndEmergencyCard
                        confirmImmediatelyToggleCard

                        // Bottom spacer for pinned dock clearance
                        Spacer()
                            .frame(height: 96)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }

                iPhonePinnedBottomDock
            }
        }
    }

    private var iPhoneNavBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Hotel_Res_NewReservationTitle", alter: "تسجيل حجز فندقي جديد"),
            subtitle: Language.get("Hotel_Res_NewReservationSub", alter: "فندق بيور بيتس • حجز إقامة"),
            statusDotColor: Color(uiColor: .systemGreen),
            isModal: !isPushMode,
            customTopSpacing: 0,
            onBack: { handleDismiss() }
        )
        .background(
            AdminSurface.card
                .ignoresSafeArea(edges: .top)
                .overlay(Divider(), alignment: .bottom)
        )
    }

    private var iPhonePinnedBottomDock: some View {
        HStack(spacing: 12) {
            // Live night count & total summary
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("\(numberOfNights) \(Language.get("Hotel_NightsPluralUnit", alter: "ليالٍ"))")
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primary)
                    Text("•")
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(String(format: "%.0f %@", nightlyRateMajor, Language.get("Hotel_Suite_PerNight", alter: "ر.ق / ليلة")))
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Text(String(format: "%.0f %@", calculatedEstimatedTotal, Language.get("Currency_QAR", alter: "ر.ق")))
                    .font(Font.custom("Beiruti-Bold", size: 19))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            Spacer()

            Button {
                validateAndCreate()
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(Language.get("Hotel_CreateReservationSubmit", alter: "تأكيد وتسجيل الحجز"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Section 1: Customer Profile Card

    private var customerProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                Text(Language.get("Customer_Details", alter: "بيانات العميل"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                if selectedCustomer != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                        Text(Language.get("Hotel_Customer_VerifiedProfile", alter: "ملف مسجل"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundStyle(Color(uiColor: .systemGreen))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .systemGreen).opacity(0.12), in: Capsule())
                } else if !customerName.isEmpty && !customerPhone.isEmpty {
                    Text(Language.get("Hotel_Customer_WalkInBadge", alter: "نزيل مباشر (ضيف)"))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
            }

            // Quick Customer Search / Autocomplete Bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("Hotel_SearchCustomerPlaceholder", alter: "بحث سريع في العملاء المسجلين (بالاسم أو الهاتف)..."), text: $customerSearchQuery)
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .multilineTextAlignment(.leading)
                        .onChange(of: customerSearchQuery) { query in
                            performCustomerSearch(query)
                        }

                    if isSearchingCustomers {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if !customerSearchQuery.isEmpty {
                        Button {
                            customerSearchQuery = ""
                            customerSearchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                )

                // Search Results Dropdown List
                if !customerSearchResults.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(customerSearchResults) { option in
                            Button {
                                selectCustomer(option)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(AdminSurface.primary.opacity(0.12))
                                            .frame(width: 32, height: 32)
                                        Text(String(option.name.prefix(1)).uppercased())
                                            .font(Font.custom("Beiruti-Bold", size: 13))
                                            .foregroundStyle(AdminSurface.primary)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(option.name)
                                            .font(Font.custom("Beiruti-Bold", size: 13))
                                            .foregroundStyle(AdminSurface.primaryText)
                                        if !option.phone.isEmpty {
                                            Text(option.phone)
                                                .font(Font.custom("Beiruti-Medium", size: 11))
                                                .foregroundStyle(AdminSurface.secondaryText)
                                                .monospacedDigit()
                                        }
                                    }

                                    Spacer()

                                    Text(Language.get("Hotel_Select_Action", alter: "اختيار"))
                                        .font(Font.custom("Beiruti-Bold", size: 11))
                                        .foregroundStyle(AdminSurface.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                                }
                                .padding(8)
                                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // If customer is selected: Selected Profile Banner
                if let selected = selectedCustomer {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(uiColor: .systemGreen))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(selected.name)
                                .font(Font.custom("Beiruti-Bold", size: 13))
                                .foregroundStyle(AdminSurface.primaryText)
                            if !selected.phone.isEmpty {
                                Text(selected.phone)
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation {
                                selectedCustomer = nil
                                customerPets = []
                            }
                        } label: {
                            Text(Language.get("Hotel_ChangeCustomer", alter: "تغيير"))
                                .font(Font.custom("Beiruti-Bold", size: 11))
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(uiColor: .systemGreen).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .systemGreen).opacity(0.3), lineWidth: 0.8)
                    )
                }
            }

            // Customer Contact Fields
            VStack(spacing: 10) {
                // Name Field
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("Customer_Name_Placeholder", alter: "اسم العميل بالكامل *"), text: $customerName)
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(customerName.isEmpty && validationError != nil ? Color.red.opacity(0.6) : AdminSurface.hairline.opacity(0.6), lineWidth: 0.8)
                )

                // Phone Field
                HStack(spacing: 10) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("Customer_Phone_Placeholder", alter: "رقم هاتف العميل للتواصل *"), text: $customerPhone)
                        .keyboardType(.phonePad)
                        .font(Font.custom("Beiruti-SemiBold", size: 14))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(customerPhone.isEmpty && validationError != nil ? Color.red.opacity(0.6) : AdminSurface.hairline.opacity(0.6), lineWidth: 0.8)
                )

                // Email Field (Optional)
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("Email_Optional", alter: "البريد الإلكتروني (اختياري)"), text: $customerEmail)
                        .keyboardType(.emailAddress)
                        .font(Font.custom("Beiruti-Regular", size: 14))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.8)
                )
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Section 2: Pet Identity & Care Card

    private var petIdentityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                Text(Language.get("Pet_Details", alter: "بيانات الحيوان الأليف والنزيل"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                if !petName.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(uiColor: .systemGreen))
                }
            }

            // Tactile Species Selector
            HStack(spacing: 8) {
                speciesPill(id: "dog", wing: .dogs, title: Language.get("Dog", alter: "كلب"), icon: "dog.fill", tint: Color(red: 0.88, green: 0.38, blue: 0.20))
                speciesPill(id: "cat", wing: .cats, title: Language.get("Cat", alter: "قط"), icon: "cat.fill", tint: Color(red: 0.65, green: 0.25, blue: 0.85))
                speciesPill(id: "bird", wing: .birds, title: Language.get("Bird", alter: "طائر"), icon: "bird.fill", tint: Color(red: 0.15, green: 0.65, blue: 0.85))
                speciesPill(id: "small_pets", wing: .smallPets, title: Language.get("SmallPet", alter: "أليف صغير"), icon: "hare.fill", tint: Color(red: 0.20, green: 0.75, blue: 0.45))
            }

            // Customer Saved Pets Picker (if available)
            if !customerPets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Hotel_CustomerSavedPets", alter: "حيوانات العميل المسجلة:"))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(customerPets) { pet in
                                let isPicked = (petName == pet.name)
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        petName = pet.name
                                        petBreed = pet.breed
                                        petSpecies = pet.species
                                        if let wing = HotelWing.allCases.first(where: { $0.rawValue == pet.species || (pet.species == "dog" && $0 == .dogs) || (pet.species == "cat" && $0 == .cats) || (pet.species == "bird" && $0 == .birds) || (pet.species == "small_pets" && $0 == .smallPets) }) {
                                            selectedWing = wing
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: pet.species == "cat" ? "cat.fill" : pet.species == "bird" ? "bird.fill" : "dog.fill")
                                            .font(.system(size: 11))
                                        Text(pet.name)
                                            .font(Font.custom("Beiruti-Bold", size: 12))
                                        if !pet.breed.isEmpty {
                                            Text("(\(pet.breed))")
                                                .font(Font.custom("Beiruti-Regular", size: 10))
                                                .foregroundStyle(isPicked ? Color.white.opacity(0.8) : AdminSurface.secondaryText)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isPicked ? AdminSurface.primary : Color(uiColor: .ppForeground), in: Capsule())
                                    .foregroundStyle(isPicked ? Color.white : AdminSurface.primaryText)
                                    .overlay(Capsule().strokeBorder(isPicked ? Color.clear : AdminSurface.hairline, lineWidth: 0.6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Pet Name & Breed Fields
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("Pet_Name_Placeholder", alter: "اسم الحيوان الأليف *"), text: $petName)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(petName.isEmpty && validationError != nil ? Color.red.opacity(0.6) : AdminSurface.hairline.opacity(0.6), lineWidth: 0.8)
                )

                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("Breed_Optional", alter: "السلالة / النوع"), text: $petBreed)
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.8)
                )
            }

            // Medical & Medication Toggle with Expandable Safety Drawer
            VStack(spacing: 8) {
                Toggle(isOn: $requiresMedication.animation(.spring(response: 0.35, dampingFraction: 0.8))) {
                    HStack(spacing: 8) {
                        Image(systemName: "cross.vial.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(requiresMedication ? Color.orange : AdminSurface.secondaryText)
                        Text(Language.get("Hotel_MedicationPlanToggle", alter: "يتطلب جدول أو خطة أدوية أثناء الإقامة"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
                .tint(Color.orange)

                if requiresMedication {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(Language.get("Hotel_MedicationInstructions", alter: "تعليمات الأدوية والجرعات بالتفصيل..."), text: $medicationsText)
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.4), lineWidth: 0.8))

                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.orange)
                            Text(Language.get("Hotel_MedicationRequiredBadge", alter: "سيتم إدراج النزيل ضمن مهام الرعاية الطبية اليومية"))
                                .font(Font.custom("Beiruti-Regular", size: 11))
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func speciesPill(id: String, wing: HotelWing, title: String, icon: String, tint: Color) -> some View {
        let isSelected = petSpecies == id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
                petSpecies = id
                selectedWing = wing
                // Auto-pick first matching type
                if let matching = viewModel.accommodationTypes.first(where: { $0.wing == wing }) {
                    selectedTypeId = matching.id
                }
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected ? tint : tint.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : tint)
                }

                Text(title)
                    .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 12))
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? tint.opacity(0.12) : Color(uiColor: .ppForeground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? tint : AdminSurface.hairline.opacity(0.6), lineWidth: isSelected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 3: Suite Tier & Accommodation Sanctuary

    private var suiteTierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                Text(Language.get("Hotel_WingAndTier", alter: "الجناح والفئة الفندقية"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                if availableSuitesCount > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(uiColor: .systemGreen))
                            .frame(width: 6, height: 6)
                        Text(String(format: Language.get("Hotel_Suite_AvailableUnits", alter: "%d أجنحة متاحة"), availableSuitesCount))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(Color(uiColor: .systemGreen))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .systemGreen).opacity(0.12), in: Capsule())
                }
            }

            if viewModel.accommodationTypes.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "bed.double")
                        .font(.system(size: 24))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                    Text(Language.get("Hotel_NoAccommodationTypesWarning", alter: "لم يتم إنشاء فئات بعد. سيتم استخدام السعر القياسي."))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(Color.orange)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                // Tier Cards Grid
                let filtered = viewModel.accommodationTypes.filter { $0.wing == selectedWing }
                let typesToShow = filtered.isEmpty ? viewModel.accommodationTypes : filtered

                VStack(spacing: 8) {
                    ForEach(typesToShow) { type in
                        let isSelected = (selectedTypeId == type.id)
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTypeId = type.id
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? AdminSurface.primary : AdminSurface.primary.opacity(0.12))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: type.wing.icon)
                                        .font(.system(size: 15))
                                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.displayName)
                                        .font(Font.custom("Beiruti-Bold", size: 14))
                                        .foregroundStyle(AdminSurface.primaryText)

                                    HStack(spacing: 6) {
                                        Text(type.wing.title)
                                            .font(Font.custom("Beiruti-Regular", size: 11))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                        Text("•")
                                            .font(Font.custom("Beiruti-Regular", size: 10))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                        Text(String(format: Language.get("Hotel_SuiteCapacity_Format", alter: "سعة: %d نزيل"), type.defaultCapacity))
                                            .font(Font.custom("Beiruti-Regular", size: 11))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(type.formattedRate)
                                        .font(Font.custom("Beiruti-Bold", size: 15))
                                        .foregroundStyle(AdminSurface.primary)

                                    Text(Language.get("Hotel_Suite_PerNight", alter: "ر.ق / ليلة"))
                                        .font(Font.custom("Beiruti-Regular", size: 10))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
                            }
                            .padding(12)
                            .background(
                                isSelected ? AdminSurface.primary.opacity(0.08) : Color(uiColor: .ppForeground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline.opacity(0.6), lineWidth: isSelected ? 1.5 : 0.75)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Section 4: Stay Chrono Horizon Card (Custom Date Range Picker)

    private var stayChronoHorizonCard: some View {
        AdminHotelDateRangePicker(
            arrivalDate: $arrivalDate,
            departureDate: $departureDate
        )
    }

    // MARK: - Section 5: Financial & Deposit Card

    private var financialDepositCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                Text(Language.get("Hotel_FinancialEstimation", alter: "الحساب التقديري والعربون"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text(String(format: "%.0f %@", calculatedEstimatedTotal, Language.get("Currency_QAR", alter: "ر.ق")))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            // Deposit Presets
            HStack(spacing: 6) {
                depositPresetButton(.zero)
                depositPresetButton(.quarter)
                depositPresetButton(.half)
                depositPresetButton(.full)
            }

            // Custom Deposit Field
            HStack {
                Text(Language.get("Hotel_DepositPaidNow", alter: "العربون المدفوع مقدماً:"))
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer()

                HStack(spacing: 4) {
                    TextField("0", text: $depositPaidQAR)
                        .keyboardType(.numberPad)
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .multilineTextAlignment(.leading)
                        .frame(width: 70)
                    Text(Language.get("Currency_QAR", alter: "ر.ق"))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.75))
            }

            Divider()

            // Remaining Balance Live Telemetry
            HStack {
                Text(Language.get("Hotel_RemainingBalance", alter: "المتبقي عند تسجيل المغادرة:"))
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer()

                Text(String(format: "%.0f %@", balanceDueAtCheckout, Language.get("Currency_QAR", alter: "ر.ق")))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(balanceDueAtCheckout > 0 ? Color(red: 0.88, green: 0.38, blue: 0.20) : Color(uiColor: .systemGreen))
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func depositPresetButton(_ preset: DepositPreset) -> some View {
        let isSelected = (depositPreset == preset)
        return Button {
            applyDepositPreset(preset)
        } label: {
            Text(preset.localizedTitle)
                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 11))
                .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color(uiColor: .systemGreen) : Color(uiColor: .ppForeground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline.opacity(0.6), lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
    }

    private func applyDepositPreset(_ preset: DepositPreset) {
        depositPreset = preset
        let calculated = calculatedEstimatedTotal * preset.percentage
        depositPaidQAR = String(format: "%.0f", calculated)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Section 6: Care & Emergency Card

    private var careAndEmergencyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                Text(Language.get("EmergencyContact", alter: "جهة اتصال الطوارئ والملاحظات"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("Emergency_Name", alter: "اسم شخص للطوارئ (اختياري)"), text: $emergencyName)
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.75))

                HStack(spacing: 10) {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("Emergency_Phone", alter: "هاتف الطوارئ (اختياري)"), text: $emergencyPhone)
                        .keyboardType(.phonePad)
                        .font(Font.custom("Beiruti-SemiBold", size: 13))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.75))

                HStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 20)
                    TextField(Language.get("SpecialInstructions", alter: "أي تعليمات أو متطلبات خاصة بالنزيل..."), text: $notes)
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.75))
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Section 7: Confirmation Toggle Card (iPhone)

    private var confirmImmediatelyToggleCard: some View {
        Toggle(isOn: $confirmImmediately) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Hotel_ConfirmImmediately", alter: "تأكيد فوري للحجز"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("Hotel_ConfirmImmediatelyHint", alter: "ينشئ ملف إقامة جاهز لتسجيل الدخول مباشرة"))
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        }
        .tint(Color(uiColor: .systemGreen))
        .padding(14)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - iPad Live Digital Boarding Pass Inspector

    private var liveBoardingPassCard: some View {
        VStack(spacing: 0) {
            // Ticket Header
            VStack(spacing: 6) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "pawprint.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("Hotel_BoardingPass_Title", alter: "بطاقة الإقامة الفندقية"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                    }

                    Spacer()

                    Text(confirmImmediately ? Language.get("Hotel_Res_Confirmed", alter: "تأكيد فوري") : Language.get("Hotel_Res_Pending", alter: "بانتظار التأكيد"))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(confirmImmediately ? Color(uiColor: .systemGreen) : Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((confirmImmediately ? Color(uiColor: .systemGreen) : Color.orange).opacity(0.12), in: Capsule())
                }

                Text(Language.get("Hotel_BoardingPass_Subtitle", alter: "معاينة مباشرة ومزامنة لحظية للبيانات"))
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(AdminSurface.cardElevated)

            Divider()

            // Pet & Guest Identity Band
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: petSpeciesIcon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(petName.isEmpty ? Language.get("Pet_Name_Placeholder", alter: "اسم الحيوان الأليف") : petName)
                        .font(Font.custom("Beiruti-Bold", size: 18))
                        .foregroundStyle(petName.isEmpty ? AdminSurface.secondaryText.opacity(0.5) : AdminSurface.primaryText)

                    HStack(spacing: 6) {
                        Text(petBreed.isEmpty ? Language.get("Dog", alter: "النزيل") : petBreed)
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)

                        if requiresMedication {
                            Text("•")
                                .font(Font.custom("Beiruti-Regular", size: 10))
                                .foregroundStyle(Color.orange)
                            HStack(spacing: 3) {
                                Image(systemName: "cross.vial.fill")
                                    .font(.system(size: 9))
                                Text(Language.get("Hotel_MedicationRequiredBadge", alter: "خطة أدوية"))
                                    .font(Font.custom("Beiruti-Bold", size: 10))
                            }
                            .foregroundStyle(Color.orange)
                        }
                    }
                }

                Spacer()
            }
            .padding(18)

            // Client Badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(customerName.isEmpty ? Language.get("Customer_Details", alter: "اسم العميل") : customerName)
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                if !customerPhone.isEmpty {
                    Text(customerPhone)
                        .font(Font.custom("Beiruti-SemiBold", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(AdminSurface.control)

            // Stay Horizon Corridor
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_ArrivalDate", alter: "الوصول"))
                        .font(Font.custom("Beiruti-Regular", size: 10))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(arrivalDate.formatted(date: .numeric, time: .omitted))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                VStack(spacing: 2) {
                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text("\(numberOfNights) \(Language.get("Hotel_NightsPluralUnit", alter: "ليالٍ"))")
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(AdminSurface.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AdminSurface.primary.opacity(0.1), in: Capsule())

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("Hotel_DepartureDate", alter: "المغادرة"))
                        .font(Font.custom("Beiruti-Regular", size: 10))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(departureDate.formatted(date: .numeric, time: .omitted))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .padding(18)

            Divider()

            // Financial Breakdown Ledger
            VStack(spacing: 8) {
                HStack {
                    Text("\(numberOfNights) \(Language.get("Hotel_NightsPluralUnit", alter: "ليالٍ")) × \(String(format: "%.0f", nightlyRateMajor)) \(Language.get("Currency_QAR", alter: "ر.ق"))")
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(String(format: "%.0f %@", calculatedEstimatedTotal, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                if depositPaidValue > 0 {
                    HStack {
                        Text(Language.get("Hotel_DepositPaidNow", alter: "العربون المدفوع:"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(Color(uiColor: .systemGreen))
                        Spacer()
                        Text(String(format: "-%.0f %@", depositPaidValue, Language.get("Currency_QAR", alter: "ر.ق")))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(Color(uiColor: .systemGreen))
                    }
                }

                HStack {
                    Text(Language.get("Hotel_RemainingBalance", alter: "المتبقي عند تسجيل المغادرة:"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                    Spacer()
                    Text(String(format: "%.0f %@", balanceDueAtCheckout, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(Font.custom("Beiruti-Bold", size: 17))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
            .padding(18)
            .background(AdminSurface.cardElevated)
        }
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private var iPadActionFooterCard: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $confirmImmediately) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_ConfirmImmediately", alter: "تأكيد فوري للحجز"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Hotel_ConfirmImmediatelyHint", alter: "ينشئ ملف إقامة جاهز لتسجيل الدخول فوراً"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .tint(Color(uiColor: .systemGreen))
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                validateAndCreate()
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .bold))
                    }
                    Text(Language.get("Hotel_CreateReservationSubmit", alter: "تأكيد وتسجيل الحجز الآن"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Helpers & Actions

    private var petSpeciesIcon: String {
        switch petSpecies {
        case "cat": return "cat.fill"
        case "bird": return "bird.fill"
        case "small_pets": return "hare.fill"
        default: return "dog.fill"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.red)
            Text(message)
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundStyle(Color.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.red.opacity(0.3), lineWidth: 1))
    }

    private func triggerValidationError(_ msg: String) {
        validationError = msg
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.3)) {
            shakeError = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            shakeError = false
        }
    }

    private func handleDismiss() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func performCustomerSearch(_ query: String) {
        searchTask?.cancel()
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            customerSearchResults = []
            isSearchingCustomers = false
            return
        }
        isSearchingCustomers = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let results = await viewModel.searchCustomers(query: clean)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.customerSearchResults = results
                self.isSearchingCustomers = false
            }
        }
    }

    private func selectCustomer(_ customer: AdminHotelCustomerOption) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            self.selectedCustomer = customer
            self.customerName = customer.name
            self.customerPhone = customer.phone
            if !customer.email.isEmpty {
                self.customerEmail = customer.email
            }
            self.customerSearchResults = []
            self.customerSearchQuery = ""
        }
        Task {
            let pets = await viewModel.fetchCustomerPets(customerUid: customer.uid)
            await MainActor.run {
                self.customerPets = pets
                if let defaultPet = pets.first(where: { $0.isDefaultPet }) ?? pets.first {
                    self.petName = defaultPet.name
                    self.petBreed = defaultPet.breed
                    self.petSpecies = defaultPet.species
                    if let wing = HotelWing.allCases.first(where: { $0.rawValue == defaultPet.species || (defaultPet.species == "dog" && $0 == .dogs) || (defaultPet.species == "cat" && $0 == .cats) || (defaultPet.species == "bird" && $0 == .birds) || (defaultPet.species == "small_pets" && $0 == .smallPets) }) {
                        self.selectedWing = wing
                        if let matchingType = viewModel.accommodationTypes.first(where: { $0.wing == wing }) {
                            self.selectedTypeId = matchingType.id
                        }
                    }
                }
            }
        }
    }

    private func validateAndCreate() {
        let cleanCustomer = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPhone = customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPet = petName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanCustomer.isEmpty else {
            triggerValidationError(Language.get("Hotel_Err_CustomerNameRequired", alter: "يرجى إدخال اسم العميل."))
            return
        }

        guard !cleanPhone.isEmpty else {
            triggerValidationError(Language.get("Hotel_Err_CustomerPhoneRequired", alter: "يرجى إدخال رقم هاتف العميل."))
            return
        }

        guard !cleanPet.isEmpty else {
            triggerValidationError(Language.get("Hotel_Err_PetNameRequired", alter: "يرجى إدخال اسم الحيوان الأليف."))
            return
        }

        guard departureDate > arrivalDate else {
            triggerValidationError(Language.get("Hotel_Err_InvalidStayRange", alter: "تاريخ المغادرة يجب أن يكون بعد تاريخ الوصول."))
            return
        }

        let depositMinor = Int((depositPaidValue * 100).rounded())

        let draft = AdminHotelPetDraft(
            name: cleanPet,
            categoryName: petSpecies,
            breed: petBreed,
            weightKg: petWeight,
            accommodationTypeId: selectedTypeId,
            specialDiet: specialDiet,
            allergies: allergies,
            requiresMedication: requiresMedication,
            medicationsText: medicationsText
        )

        validationError = nil
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        let customerUidToPass = selectedCustomer?.uid ?? ""

        Task {
            let success = await viewModel.createReservation(
                customerUid: customerUidToPass,
                customerName: cleanCustomer,
                customerPhone: cleanPhone,
                customerEmail: customerEmail.isEmpty ? nil : customerEmail,
                pets: [draft],
                wing: selectedWing,
                arrivalAt: arrivalDate,
                departureAt: departureDate,
                depositMinor: depositMinor,
                emergencyName: emergencyName.isEmpty ? nil : emergencyName,
                emergencyPhone: emergencyPhone.isEmpty ? nil : emergencyPhone,
                notes: notes.isEmpty ? nil : notes,
                confirmImmediately: confirmImmediately
            )
            await MainActor.run {
                self.isSubmitting = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.handleDismiss()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    let errorMsg = viewModel.errorMessage ?? Language.get("Hotel_Err_CreateReservationFailed", alter: "تعذر تأكيد الحجز، يرجى المحاولة مرة أخرى.")
                    self.triggerValidationError(errorMsg)
                }
            }
        }
    }
}

// MARK: - Stay Duration & Deposit Presets

private enum DepositPreset: String, CaseIterable, Identifiable {
    case zero = "0"
    case quarter = "25"
    case half = "50"
    case full = "100"

    var id: String { rawValue }

    var percentage: Double {
        switch self {
        case .zero: return 0.0
        case .quarter: return 0.25
        case .half: return 0.50
        case .full: return 1.00
        }
    }

    var localizedTitle: String {
        switch self {
        case .zero: return Language.get("Hotel_DepositPreset_None", alter: "بدون عربون")
        case .quarter: return "25%"
        case .half: return "50%"
        case .full: return Language.get("Hotel_DepositPreset_100", alter: "سداد كامل")
        }
    }
}


// MARK: - Sovereign Extend Stay Sovereign Dialog
// First-Principles Dual-Architecture: iPadOS Spatial Panoramic Pavilion & iPhone Tactile Boarding Deck.
// 100% Strict Beiruti Typography Mandate: Every single glyph rendered exclusively via Beiruti font family.

public struct AdminPetsHotelExtendStayDialog: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // State
    @State private var newDepartureDate: Date
    @State private var selectedPreset: ExtendDurationPreset? = .oneDay
    @State private var selectedReasonCode: String = "customer_request"
    @State private var operationalNotes: String = ""
    @State private var isSubmitting: Bool = false
    @State private var localErrorMessage: String? = nil
    @State private var showSuccessBanner: Bool = false

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    public init(reservation: AdminHotelReservation, viewModel: AdminPetsHotelViewModel) {
        self.reservation = reservation
        self.viewModel = viewModel
        let baseDate = max(reservation.checkOutDate, Date())
        let defaultNewDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate.addingTimeInterval(86400)
        _newDepartureDate = State(initialValue: defaultNewDate)
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isPad {
                iPadExtendPavilion
            } else {
                iPhoneExtendDeck
            }

            // Top Success Toast Banner
            if showSuccessBanner {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(HotelBeiruti.bold(18))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Text(Language.get("Hotel_Extend_Success_Toast", alter: "تم تمديد فترة الإقامة بنجاح"))
                            .font(HotelBeiruti.bold(15))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.12, green: 0.16, blue: 0.22), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(uiColor: .ppSuccess).opacity(0.4), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .padding(.top, 24)

                    Spacer()
                }
                .zIndex(100)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - iPhone Tactile Handheld Deck

    private var iPhoneExtendDeck: some View {
        VStack(spacing: 0) {
            // Sovereign Navigation Header
            AdminSovereignNavigationBar(
                title: Language.get("Hotel_Res_ExtendStay", alter: "تمديد الإقامة"),
                subtitle: "\(reservation.petName) • \(reservation.reservationNumber)",
                statusDotColor: Color(uiColor: .ppSuccess),
                isModal: true,
                onBack: { dismiss() }
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // 1. Guest & Current Stay Dossier Hero Card
                    heroGuestDossierCard

                    // 2. Quick Duration Presets Matrix
                    quickPresetsSection

                    // 3. Precision Date & Time Controller
                    precisionDepartureController

                    // 4. Live Telemetry & Financial Impact Grid
                    telemetryMetricsGrid

                    // 5. Operational Reason Selector
                    reasonSelectorSection

                    // 6. Reception & Shift Handover Notes
                    handoverNotesSection

                    // 7. Suite Guaranteed Notice
                    suiteAllocationNotice

                    // 8. Error Banner if any
                    if let error = localErrorMessage {
                        errorBannerCard(error)
                    }

                    // Bottom Padding for Sticky Bar
                    Spacer()
                        .frame(height: 100)
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 14)
            }

            // Pinned Floating Bottom Action Bar
            stickyBottomActionBar
        }
    }

    // MARK: - iPad Spatial Panoramic Pavilion

    private var iPadExtendPavilion: some View {
        VStack(spacing: 0) {
            // iPad Sovereign Cockpit Header
            iPadTopCockpitBar

            // Main Dual-Column Observatory
            HStack(alignment: .top, spacing: 24) {
                // Left Column (42%): Guest Dossier & Financial Ledger
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        heroGuestDossierCard
                        stayHorizonComparisonCard
                        financialLedgerProjectionCard
                        suiteAllocationNotice

                        if let error = localErrorMessage {
                            errorBannerCard(error)
                        }
                    }
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)

                // Right Column (58%): Tactical Extension Control Station
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        quickPresetsSection
                        precisionDepartureController
                        reasonSelectorSection
                        handoverNotesSection
                        iPadActionConsoleBar
                    }
                    .padding(.bottom, 30)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
        }
    }

    // MARK: - iPad Top Cockpit Bar

    private var iPadTopCockpitBar: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(HotelBeiruti.bold(14))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Language.get("Hotel_ExtendStay_Title", alter: "تمديد فترة الإقامة الفندقية"))
                        .font(HotelBeiruti.bold(20))
                        .foregroundStyle(AdminSurface.primaryText)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 7, height: 7)
                        Text(reservation.status.localizedTitle)
                            .font(HotelBeiruti.bold(11))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                }

                Text("\(reservation.petName) • \(reservation.petBreed) • \(reservation.reservationNumber)")
                    .font(HotelBeiruti.medium(13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            // Room Badge Pill
            HStack(spacing: 6) {
                Image(systemName: "door.left.hand.closed")
                    .font(HotelBeiruti.bold(12))
                    .foregroundStyle(AdminSurface.primary)
                Text(reservation.assignedRoomNumber != nil ? String(format: Language.get("Hotel_AssignedRoom_Format", alter: "جناح رقم: %@"), reservation.assignedRoomNumber!) : Language.get("Hotel_Room_Unassigned", alter: "جناح غير محدد"))
                    .font(HotelBeiruti.bold(13))
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AdminSurface.control, in: Capsule())
            .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))

            // Keyboard Shortcut Hint
            HStack(spacing: 4) {
                Text(Language.get("Hotel_Extend_Keyboard_ConfirmHint", alter: "⌘⏎ تأكيد"))
                    .font(HotelBeiruti.bold(11))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(AdminSurface.surface)
        .overlay(Divider().foregroundStyle(AdminSurface.hairline), alignment: .bottom)
    }

    // MARK: - Guest Dossier Hero Card

    private var heroGuestDossierCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                // Pet Avatar with Species Glyph
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary.opacity(0.18), AdminSurface.primary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isPad ? 60 : 54, height: isPad ? 60 : 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(0.3), lineWidth: 1)
                        )

                    Image(systemName: petSpeciesIcon)
                        .font(HotelBeiruti.bold(isPad ? 26 : 22))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(reservation.petName)
                            .font(HotelBeiruti.bold(isPad ? 20 : 17))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("•")
                            .font(HotelBeiruti.bold(12))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(reservation.petBreed)
                            .font(HotelBeiruti.medium(13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    HStack(spacing: 8) {
                        // Customer Name
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(HotelBeiruti.bold(10))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(reservation.customerName)
                                .font(HotelBeiruti.medium(12))
                                .foregroundStyle(AdminSurface.primaryText)
                        }

                        // Phone
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(HotelBeiruti.bold(10))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(reservation.customerPhone)
                                .font(HotelBeiruti.medium(12))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }

                Spacer()

                // Wing & Room Pill
                VStack(alignment: .trailing, spacing: 4) {
                    Text(reservation.wing.localizedTitle)
                        .font(HotelBeiruti.bold(11))
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())

                    if let room = reservation.assignedRoomNumber {
                        Text(String(format: Language.get("Hotel_Extend_Room_Badge", alter: "جناح %@"), room))
                            .font(HotelBeiruti.bold(12))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
            }

            Divider()
                .foregroundStyle(AdminSurface.hairline.opacity(0.7))

            // Current Stay Baseline Horizon
            HStack(spacing: 12) {
                // Check-In
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_Arrival", alter: "تاريخ الوصول"))
                        .font(HotelBeiruti.medium(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formattedDateOnly(reservation.checkInDate))
                        .font(HotelBeiruti.bold(13))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(formattedTimeOnly(reservation.checkInDate))
                        .font(HotelBeiruti.regular(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Nights Indicator Pill
                VStack(spacing: 2) {
                    Image(systemName: "arrow.forward")
                        .font(HotelBeiruti.bold(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(String(format: Language.get("Hotel_Extend_OriginalNights", alter: "%d ليالٍ"), reservation.numberOfNights))
                        .font(HotelBeiruti.bold(11))
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                }

                Spacer()

                // Current Checkout
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("Hotel_Extend_CurrentDeparture", alter: "المغادرة المجدولة"))
                        .font(HotelBeiruti.medium(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formattedDateOnly(reservation.checkOutDate))
                        .font(HotelBeiruti.bold(13))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(formattedTimeOnly(reservation.checkOutDate))
                        .font(HotelBeiruti.regular(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .padding(12)
            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    // MARK: - Stay Horizon Comparison Card (iPad Focus)

    private var stayHorizonComparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(HotelBeiruti.bold(14))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_Res_StayHorizon", alter: "أفق الإقامة وتحديث المغادرة"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            VStack(spacing: 10) {
                // Scheduled Current Horizon
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Extend_Timeline_Initial", alter: "الحجز الأساسي"))
                            .font(HotelBeiruti.medium(11))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text("\(formattedDateOnly(reservation.checkInDate)) → \(formattedDateOnly(reservation.checkOutDate))")
                            .font(HotelBeiruti.bold(13))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    Spacer()
                    Text(String(format: Language.get("Hotel_Extend_OriginalNights", alter: "%d ليالٍ"), reservation.numberOfNights))
                        .font(HotelBeiruti.bold(12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(AdminSurface.control, in: Capsule())
                }
                .padding(12)
                .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Extended Target Horizon
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Language.get("Hotel_Extend_Timeline_Extended", alter: "الأفق بعد التمديد"))
                                .font(HotelBeiruti.bold(11))
                                .foregroundStyle(Color(uiColor: .ppSuccess))
                            Circle()
                                .fill(Color(uiColor: .ppSuccess))
                                .frame(width: 6, height: 6)
                        }
                        Text("\(formattedDateOnly(reservation.checkInDate)) → \(formattedDateOnly(newDepartureDate))")
                            .font(HotelBeiruti.bold(14))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: Language.get("Hotel_Extend_TotalNightsFormat", alter: "إجمالي %d ليالٍ"), newTotalNights))
                            .font(HotelBeiruti.bold(12))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Text(String(format: Language.get("Hotel_Extend_PlusNightsFormat", alter: "+%d ليالٍ"), additionalNights))
                            .font(HotelBeiruti.bold(10))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(12)
                .background(Color(uiColor: .ppSuccess).opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(uiColor: .ppSuccess).opacity(0.3), lineWidth: 1))
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    // MARK: - Financial Ledger Projection Card (iPad Focus)

    private var financialLedgerProjectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "banknote.fill")
                    .font(HotelBeiruti.bold(14))
                    .foregroundStyle(Color(uiColor: .ppSuccess))
                Text(Language.get("Hotel_Billing", alter: "الحساب المالي والفواتير"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            VStack(spacing: 8) {
                ledgerRow(
                    title: Language.get("Hotel_Extend_NightlyRate", alter: "السعر التقديري لليلة:"),
                    value: "\(formatQAR(nightlyRateMinor)) \(Language.get("Hotel_Extend_PerNight", alter: "/ ليلة"))",
                    isHighlight: false
                )

                ledgerRow(
                    title: Language.get("Hotel_Extend_AdditionalNights", alter: "الليالي الإضافية:"),
                    value: String(format: Language.get("Hotel_Extend_PlusNightsFormat", alter: "+%d ليالٍ"), additionalNights),
                    isHighlight: false
                )

                ledgerRow(
                    title: Language.get("Hotel_Extend_ProjectedAddAmount", alter: "المبلغ الإضافي التقديري:"),
                    value: "+\(formatQAR(projectedAdditionalMinor))",
                    isHighlight: true,
                    highlightColor: AdminSurface.primary
                )

                Divider()
                    .foregroundStyle(AdminSurface.hairline)

                ledgerRow(
                    title: Language.get("Hotel_DepositPaid", alter: "العربون أو المحصل:"),
                    value: formatQAR(reservation.paidAmountMinor ?? 0),
                    isHighlight: false
                )

                ledgerRow(
                    title: Language.get("Hotel_Extend_ProjectedTotal", alter: "الإجمالي التقديري الجديد:"),
                    value: formatQAR(projectedTotalMinor),
                    isHighlight: true,
                    highlightColor: Color(uiColor: .ppSuccess),
                    isBig: true
                )
            }
            .padding(14)
            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    private func ledgerRow(title: String, value: String, isHighlight: Bool, highlightColor: Color = AdminSurface.primary, isBig: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(isBig ? HotelBeiruti.bold(14) : HotelBeiruti.medium(13))
                .foregroundStyle(AdminSurface.secondaryText)
            Spacer()
            Text(value)
                .font(isBig ? HotelBeiruti.bold(17) : (isHighlight ? HotelBeiruti.bold(14) : HotelBeiruti.medium(13)))
                .foregroundStyle(isHighlight ? highlightColor : AdminSurface.primaryText)
        }
    }

    // MARK: - Quick Presets Section

    private var quickPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(HotelBeiruti.bold(13))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_Extend_QuickPresets", alter: "المدد السريعة للإقامة"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            if isPad {
                // 5-Grid Matrix for iPad
                HStack(spacing: 12) {
                    ForEach(ExtendDurationPreset.allCases) { preset in
                        presetButton(preset: preset)
                    }
                }
            } else {
                // Horizontal Scrollable Pills for iPhone
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ExtendDurationPreset.allCases) { preset in
                            presetButton(preset: preset)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func presetButton(preset: ExtendDurationPreset) -> some View {
        let isSelected = selectedPreset == preset
        return Button {
            selectPreset(preset)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(HotelBeiruti.bold(13))
                    .foregroundStyle(isSelected ? .white : AdminSurface.primary)

                Text(preset.localizedTitle)
                    .font(HotelBeiruti.bold(14))
                    .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isSelected ? AdminSurface.primary : AdminSurface.card,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.8)
            )
            .shadow(color: isSelected ? AdminSurface.primary.opacity(0.25) : Color.clear, radius: 8, y: 3)
            .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }

    // MARK: - Precision Date & Time Controller

    private var precisionDepartureController: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(HotelBeiruti.bold(13))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_Extend_NewDeparture", alter: "موعد المغادرة الجديد المستهدف"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()

                // Live Active Tag
                Text(formattedDayName(newDepartureDate))
                    .font(HotelBeiruti.bold(12))
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
            }

            // Big Date Display Box
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(formattedDateOnly(newDepartureDate))
                        .font(HotelBeiruti.bold(18))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(formattedTimeOnly(newDepartureDate))
                        .font(HotelBeiruti.medium(14))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Nights Delta Badge
                VStack(spacing: 2) {
                    Text(String(format: Language.get("Hotel_Extend_PlusNightsFormat", alter: "+%d ليالٍ"), additionalNights))
                        .font(HotelBeiruti.bold(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .ppSuccess), in: Capsule())
                        .shadow(color: Color(uiColor: .ppSuccess).opacity(0.3), radius: 6, y: 2)
                }
            }
            .padding(14)
            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Embedded Native DatePicker
            DatePicker(
                Language.get("Hotel_NewDepartureDate", alter: "موعد المغادرة الجديد"),
                selection: $newDepartureDate,
                in: minSelectableDate...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .font(HotelBeiruti.bold(14))
            .datePickerStyle(.compact)
            .padding(14)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
            .onChange(of: newDepartureDate) { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // If user picked custom date via picker, check if matches any preset
                syncPresetWithDate()
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    // MARK: - Telemetry Metrics Grid (iPhone Focus)

    private var telemetryMetricsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(HotelBeiruti.bold(13))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_Extend_TotalNightsAfter", alter: "التوقعات التشغيلية والمالية"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                metricTelemetryCard(
                    icon: "moon.stars.fill",
                    title: Language.get("Hotel_Extend_AdditionalNights", alter: "الليالي الإضافية"),
                    value: String(format: Language.get("Hotel_Extend_PlusNightsFormat", alter: "+%d ليالٍ"), additionalNights),
                    accentColor: Color(uiColor: .ppSuccess)
                )

                metricTelemetryCard(
                    icon: "calendar.day.timeline.leading",
                    title: Language.get("Hotel_Extend_TotalNightsAfter", alter: "إجمالي المدة"),
                    value: String(format: Language.get("Hotel_Extend_TotalNightsFormat", alter: "%d ليالٍ"), newTotalNights),
                    accentColor: AdminSurface.primary
                )

                metricTelemetryCard(
                    icon: "tag.fill",
                    title: Language.get("Hotel_Extend_NightlyRate", alter: "سعر الليلة"),
                    value: formatQAR(nightlyRateMinor),
                    accentColor: Color(uiColor: .systemPurple)
                )

                metricTelemetryCard(
                    icon: "plus.circle.fill",
                    title: Language.get("Hotel_Extend_ProjectedAddAmount", alter: "المبلغ الإضافي"),
                    value: "+\(formatQAR(projectedAdditionalMinor))",
                    accentColor: Color(uiColor: .ppWarning)
                )
            }
        }
    }

    private func metricTelemetryCard(icon: String, title: String, value: String, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(HotelBeiruti.bold(12))
                    .foregroundStyle(accentColor)
                Spacer()
            }

            Text(value)
                .font(HotelBeiruti.bold(16))
                .foregroundStyle(AdminSurface.primaryText)

            Text(title)
                .font(HotelBeiruti.medium(11))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .padding(12)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    // MARK: - Operational Reason Selector

    private var reasonSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.clipboard.fill")
                    .font(HotelBeiruti.bold(13))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_Extend_Reason_Title", alter: "سبب التمديد التشغيلي"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(reasonItems) { item in
                    reasonRowItem(item: item)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    private func reasonRowItem(item: ExtendReasonItem) -> some View {
        let isSelected = selectedReasonCode == item.code
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.8)) {
                selectedReasonCode = item.code
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? item.accentColor.opacity(0.18) : AdminSurface.control)
                        .frame(width: 34, height: 34)

                    Image(systemName: item.icon)
                        .font(HotelBeiruti.bold(13))
                        .foregroundStyle(isSelected ? item.accentColor : AdminSurface.secondaryText)
                }

                Text(item.title)
                    .font(isSelected ? HotelBeiruti.bold(14) : HotelBeiruti.medium(13))
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(HotelBeiruti.bold(16))
                        .foregroundStyle(item.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                isSelected ? item.accentColor.opacity(0.06) : AdminSurface.control.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? item.accentColor.opacity(0.5) : AdminSurface.hairline.opacity(0.5), lineWidth: isSelected ? 1.2 : 0.6)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }

    // MARK: - Reception & Shift Handover Notes

    private var handoverNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(HotelBeiruti.bold(13))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_Extend_Notes_Title", alter: "ملاحظات الاستقبال وتسليم الوردية"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            // Quick Tap Tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickNoteTags, id: \.key) { tag in
                        let localized = Language.get(tag.key, alter: tag.alter)
                        let isContained = operationalNotes.contains(localized)
                        Button {
                            toggleQuickTag(localized)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isContained ? "checkmark" : "plus")
                                    .font(HotelBeiruti.bold(10))
                                Text(localized)
                                    .font(HotelBeiruti.medium(12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isContained ? AdminSurface.primary.opacity(0.15) : AdminSurface.control, in: Capsule())
                            .overlay(Capsule().strokeBorder(isContained ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 0.8))
                            .foregroundStyle(isContained ? AdminSurface.primary : AdminSurface.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                }
                .padding(.vertical, 2)
            }

            // Notes Text Input
            ZStack(alignment: .topLeading) {
                if operationalNotes.isEmpty {
                    Text(Language.get("Hotel_Extend_Notes_Placeholder", alter: "أضف أي ملاحظات خاصة بالتغذية أو الرعاية أو الاتفاق المالي..."))
                        .font(HotelBeiruti.regular(13))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }

                TextEditor(text: $operationalNotes)
                    .font(HotelBeiruti.regular(13))
                    .foregroundStyle(AdminSurface.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 70, maxHeight: 110)
                    .padding(10)
            }
            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
    }

    // MARK: - Suite Guaranteed Notice

    private var suiteAllocationNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(HotelBeiruti.bold(16))
                .foregroundStyle(Color(uiColor: .ppSuccess))

            Text(Language.get("Hotel_Extend_Notice_SuiteLocked", alter: "تأمين الجناح: سيظل الجناح الفندقي محجوزاً للأليف طوال فترة التمديد."))
                .font(HotelBeiruti.medium(12))
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 0.8))
    }

    // MARK: - Error Banner Card

    private func errorBannerCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(HotelBeiruti.bold(15))
                .foregroundStyle(Color(uiColor: .ppError))

            Text(message)
                .font(HotelBeiruti.medium(13))
                .foregroundStyle(Color(uiColor: .ppError))

            Spacer()

            Button {
                localErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(HotelBeiruti.bold(11))
                    .foregroundStyle(Color(uiColor: .ppError))
            }
        }
        .padding(14)
        .background(Color(uiColor: .ppError).opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppError).opacity(0.3), lineWidth: 0.8))
    }

    // MARK: - Sticky Bottom Action Bar (iPhone)

    private var stickyBottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
                .foregroundStyle(AdminSurface.hairline)

            HStack(spacing: 12) {
                // Confirm Extension Button
                Button {
                    executeExtension()
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                            Text(Language.get("Hotel_Extend_CTA_Submitting", alter: "جاري تمديد الإقامة..."))
                                .font(HotelBeiruti.bold(15))
                        } else {
                            Image(systemName: "calendar.badge.plus")
                                .font(HotelBeiruti.bold(15))

                            Text("\(Language.get("Hotel_Extend_CTA_Confirm", alter: "تأكيد تمديد الإقامة")) (\(String(format: Language.get("Hotel_Extend_PlusNightsFormat", alter: "+%d ليالٍ"), additionalNights)))")
                                .font(HotelBeiruti.bold(15))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        isSubmitting || additionalNights <= 0 ? AdminSurface.primary.opacity(0.6) : AdminSurface.primary,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 10, y: 4)
                }
                .disabled(isSubmitting || additionalNights <= 0)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(
            AdminSurface.surface.opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - iPad Action Console Bar

    private var iPadActionConsoleBar: some View {
        HStack(spacing: 14) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text(Language.get("Common_Cancel", alter: "إلغاء"))
                    .font(HotelBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .hoverEffect()

            Button {
                executeExtension()
            } label: {
                HStack(spacing: 10) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                        Text(Language.get("Hotel_Extend_CTA_Submitting", alter: "جاري تمديد الإقامة وتحديث السجلات..."))
                            .font(HotelBeiruti.bold(15))
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(HotelBeiruti.bold(16))
                        Text("\(Language.get("Hotel_Extend_CTA_Confirm", alter: "تأكيد تمديد الإقامة")) (\(String(format: Language.get("Hotel_Extend_PlusNightsFormat", alter: "+%d ليالٍ"), additionalNights)) • +\(formatQAR(projectedAdditionalMinor)))")
                            .font(HotelBeiruti.bold(15))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isSubmitting || additionalNights <= 0 ? AdminSurface.primary.opacity(0.6) : AdminSurface.primary,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(.white)
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 10, y: 4)
            }
            .disabled(isSubmitting || additionalNights <= 0)
            .buttonStyle(.plain)
            .hoverEffect()
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 6)
    }

    // MARK: - State Logic & Actions

    private var minSelectableDate: Date {
        max(reservation.checkOutDate, Date())
    }

    private var additionalNights: Int {
        let interval = newDepartureDate.timeIntervalSince(reservation.checkOutDate)
        guard interval > 0 else { return 0 }
        let days = Int(ceil(interval / 86400.0))
        return max(1, days)
    }

    private var newTotalNights: Int {
        reservation.numberOfNights + additionalNights
    }

    private var nightlyRateMinor: Int {
        if let total = reservation.totalAmountMinor, reservation.numberOfNights > 0 {
            return max(0, total / reservation.numberOfNights)
        }
        return 150_00
    }

    private var projectedAdditionalMinor: Int {
        nightlyRateMinor * additionalNights
    }

    private var projectedTotalMinor: Int {
        (reservation.totalAmountMinor ?? 0) + projectedAdditionalMinor
    }

    private func selectPreset(_ preset: ExtendDurationPreset) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.8)) {
            selectedPreset = preset
            if preset.days > 0 {
                let base = max(reservation.checkOutDate, Date())
                newDepartureDate = Calendar.current.date(byAdding: .day, value: preset.days, to: base) ?? base.addingTimeInterval(Double(preset.days) * 86400)
            }
        }
    }

    private func syncPresetWithDate() {
        let calendar = Calendar.current
        let base = max(reservation.checkOutDate, Date())
        let components = calendar.dateComponents([.day], from: base, to: newDepartureDate)
        let days = components.day ?? 0
        if days == 1 {
            selectedPreset = .oneDay
        } else if days == 2 {
            selectedPreset = .twoDays
        } else if days == 3 {
            selectedPreset = .threeDays
        } else if days == 7 {
            selectedPreset = .oneWeek
        } else {
            selectedPreset = .custom
        }
    }

    private func toggleQuickTag(_ tagText: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if operationalNotes.contains(tagText) {
            operationalNotes = operationalNotes.replacingOccurrences(of: tagText, with: "")
                .replacingOccurrences(of: " •  • ", with: " • ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            if operationalNotes.isEmpty {
                operationalNotes = tagText
            } else {
                operationalNotes += " • " + tagText
            }
        }
    }

    private func executeExtension() {
        guard additionalNights > 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSubmitting = true
        localErrorMessage = nil
        Task {
            let trimmedNote = operationalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let success = await viewModel.extendReservation(
                reservation: reservation,
                newDepartureAt: newDepartureDate,
                reasonCode: selectedReasonCode,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            await MainActor.run {
                isSubmitting = false
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                        showSuccessBanner = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        dismiss()
                    }
                } else {
                    localErrorMessage = viewModel.errorMessage ?? Language.get("Hotel_Extend_Error_Title", alter: "تعذر تمديد الإقامة")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    // MARK: - Enums & Supporting Types

    private enum ExtendDurationPreset: String, CaseIterable, Identifiable {
        case oneDay = "1d"
        case twoDays = "2d"
        case threeDays = "3d"
        case oneWeek = "7d"
        case custom = "custom"

        var id: String { rawValue }

        var days: Int {
            switch self {
            case .oneDay: return 1
            case .twoDays: return 2
            case .threeDays: return 3
            case .oneWeek: return 7
            case .custom: return 0
            }
        }

        var localizedTitle: String {
            switch self {
            case .oneDay: return Language.get("Hotel_Extend_Preset_1D", alter: "+يوم واحد")
            case .twoDays: return Language.get("Hotel_Extend_Preset_2D", alter: "+يومان")
            case .threeDays: return Language.get("Hotel_Extend_Preset_3D", alter: "+3 أيام")
            case .oneWeek: return Language.get("Hotel_Extend_Preset_7D", alter: "+أسبوع كامل")
            case .custom: return Language.get("Hotel_Extend_Preset_Custom", alter: "موعد مخصص")
            }
        }

        var icon: String {
            switch self {
            case .oneDay: return "sun.max.fill"
            case .twoDays: return "moon.stars.fill"
            case .threeDays: return "calendar.badge.plus"
            case .oneWeek: return "calendar.day.timeline.leading"
            case .custom: return "slider.horizontal.3"
            }
        }
    }

    private struct ExtendReasonItem: Identifiable {
        var id: String { code }
        let code: String
        let title: String
        let icon: String
        let accentColor: Color
    }

    private var reasonItems: [ExtendReasonItem] {
        [
            ExtendReasonItem(
                code: "customer_request",
                title: Language.get("Hotel_Extend_Reason_ClientRequest", alter: "طلب مالك الأليف"),
                icon: "person.crop.circle.badge.plus",
                accentColor: AdminSurface.primary
            ),
            ExtendReasonItem(
                code: "travel_delay",
                title: Language.get("Hotel_Extend_Reason_TravelDelay", alter: "تأخر سفر أو رحلة طيران"),
                icon: "airplane.departure",
                accentColor: Color(uiColor: .systemIndigo)
            ),
            ExtendReasonItem(
                code: "pet_health",
                title: Language.get("Hotel_Extend_Reason_PetHealth", alter: "ملاحظة بيطرية ورعاية صحية"),
                icon: "cross.case.fill",
                accentColor: Color(uiColor: .ppSuccess)
            ),
            ExtendReasonItem(
                code: "emergency",
                title: Language.get("Hotel_Extend_Reason_Emergency", alter: "ظرف طارئ أو تعذر الاستلام"),
                icon: "exclamationmark.shield.fill",
                accentColor: Color(uiColor: .ppWarning)
            ),
            ExtendReasonItem(
                code: "operator_override",
                title: Language.get("Hotel_Extend_Reason_Admin", alter: "قرار إداري / تشغيلي استثنائي"),
                icon: "crown.fill",
                accentColor: Color(uiColor: .systemPurple)
            )
        ]
    }

    private let quickNoteTags: [(key: String, alter: String)] = [
        ("Hotel_Extend_QuickTag_CashPaid", "دفع نقداً بالاستقبال"),
        ("Hotel_Extend_QuickTag_CheckoutCharge", "تضاف عند الخروج"),
        ("Hotel_Extend_QuickTag_WhatsAppNotified", "تم إشعار المالك واتساب")
    ]

    private var petSpeciesIcon: String {
        switch reservation.petSpecies.lowercased() {
        case "cat": return "cat.fill"
        case "bird": return "bird.fill"
        case "small_pets", "rabbit", "hare": return "hare.fill"
        default: return "dog.fill"
        }
    }

    private func formatQAR(_ minor: Int) -> String {
        let major = Double(minor) / 100.0
        return String(format: "%.0f %@", major, Language.get("Currency_QAR", alter: "ر.ق"))
    }

    private func formattedDateOnly(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        df.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        return df.string(from: date)
    }

    private func formattedTimeOnly(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        df.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        return df.string(from: date)
    }

    private func formattedDayName(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE"
        df.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        return df.string(from: date)
    }
}

// MARK: - Sovereign Reason Dialog Sheet (لإلغاء أو رفض الحجز مع السبب)
public struct AdminPetsHotelReasonSheet: View {
    let reservation: AdminHotelReservation
    let action: String
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReasonCode: String = "customer_request"
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false

    private let reasonOptions: [(id: String, title: String)] = [
        ("customer_request", Language.get("Hotel_Reason_CustomerRequest", alter: "طلب العميل إلغاء الحجز")),
        ("no_show", Language.get("Hotel_Reason_NoShow", alter: "العميل لم يحضر بالموعد")),
        ("health_issue", Language.get("Hotel_Reason_HealthIssue", alter: "عائق صحي أو عدم اكتمال التطعيمات")),
        ("capacity_conflict", Language.get("Hotel_Reason_CapacityConflict", alter: "عدم توفر جناح مناسب")),
        ("operator_override", Language.get("Hotel_Reason_OperatorOverride", alter: "قرار إداري استثنائي"))
    ]

    public init(reservation: AdminHotelReservation, action: String, viewModel: AdminPetsHotelViewModel) {
        self.reservation = reservation
        self.action = action
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("Hotel_Res_CancelReservation", alter: "إلغاء الحجز"),
                subtitle: "\(reservation.petName) • \(reservation.reservationNumber)",
                statusDotColor: Color(uiColor: .ppError),
                isModal: true,
                onBack: { dismiss() }
            )

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Reason_SheetTitle", alter: "سبب إلغاء أو تعديل حالة الحجز"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Hotel_Reason_SheetHint", alter: "يتطلب النظام تسجيل رمز سبب موثق في سجل الرقابة."))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Reason Selection Matrix
                VStack(spacing: 8) {
                    ForEach(reasonOptions, id: \.id) { option in
                        let isSelected = selectedReasonCode == option.id
                        Button {
                            selectedReasonCode = option.id
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(isSelected ? Color.red : AdminSurface.secondaryText)

                                Text(option.title)
                                    .font(Font.custom("Beiruti-Medium", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)

                                Spacer()
                            }
                            .padding(12)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                TextField(Language.get("Notes_Optional", alter: "ملاحظات إضافية توضيحية..."), text: $note)
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        let success = await viewModel.transitionReservation(
                            reservation: reservation,
                            action: action,
                            reasonCode: selectedReasonCode,
                            note: note.isEmpty ? nil : note
                        )
                        isSubmitting = false
                        if success {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text(Language.get("Hotel_ConfirmCancellationCTA", alter: "تأكيد إلغاء الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(isSubmitting)
            }
            .padding(18)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}
