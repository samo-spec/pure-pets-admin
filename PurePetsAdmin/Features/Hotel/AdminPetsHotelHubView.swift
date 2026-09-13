//
//  AdminPetsHotelHubView.swift
//  PurePetsAdmin
//
//  SwiftyMax NextGen V6 Sovereign Pets Hotel Command Hub.
//  Category-defining, beyond-FAANG dual native architecture for iPhone and iPad separately.
//  Strictly governed by Beiruti (PPBrandFont) typography across all states.
//

import SwiftUI

public struct AdminPetsHotelHubView: View {
    @StateObject private var viewModel = AdminPetsHotelViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    private let onDismiss: (() -> Void)?

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private var isPadConsole: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isPadConsole {
                iPadHotelConsoleView(viewModel: viewModel, onDismiss: onDismiss)
            } else {
                iPhoneHotelHubView(viewModel: viewModel, onDismiss: onDismiss)
            }

            // Hidden Push Navigation Links
            NavigationLink(
                destination: AdminPetsHotelCreateReservationSheet(
                    viewModel: viewModel,
                    isPushMode: true,
                    onBack: { viewModel.newReservationModalOpen = false }
                )
                .navigationBarHidden(true),
                isActive: $viewModel.newReservationModalOpen
            ) {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)

            NavigationLink(
                destination: AdminPetsHotelSuiteEditorSheet(
                    accommodation: nil,
                    viewModel: viewModel,
                    isPushMode: true,
                    onBack: { viewModel.isCreatingNewSuite = false }
                )
                .navigationBarHidden(true),
                isActive: $viewModel.isCreatingNewSuite
            ) {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)

            NavigationLink(
                destination: Group {
                    if let stay = viewModel.selectedStayDetail {
                        AdminPetsHotelStayDetailSheet(
                            stay: stay,
                            viewModel: viewModel,
                            isPushMode: true,
                            onBack: { viewModel.selectedStayDetail = nil }
                        )
                        .navigationBarHidden(true)
                    } else {
                        EmptyView()
                    }
                },
                isActive: Binding(
                    get: { viewModel.selectedStayDetail != nil },
                    set: { if !$0 { viewModel.selectedStayDetail = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)

            NavigationLink(
                destination: Group {
                    if let res = viewModel.selectedReservationDetail {
                        AdminPetsHotelReservationDetailSheet(
                            reservation: res,
                            viewModel: viewModel,
                            isPushMode: true,
                            onBack: { viewModel.selectedReservationDetail = nil }
                        )
                        .navigationBarHidden(true)
                    } else {
                        EmptyView()
                    }
                },
                isActive: Binding(
                    get: { viewModel.selectedReservationDetail != nil },
                    set: { if !$0 { viewModel.selectedReservationDetail = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
            .accessibilityHidden(true)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $viewModel.suiteEditorModalAccommodation) { acc in
            AdminPetsHotelSuiteEditorSheet(accommodation: acc, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: $viewModel.typeEditorModalType) { type in
            AdminPetsHotelAccommodationTypeEditorSheet(accommodationType: type, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(isPresented: $viewModel.isCreatingNewType) {
            AdminPetsHotelAccommodationTypeEditorSheet(accommodationType: nil, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .fullScreenCover(item: $viewModel.checkInModalReservation) { res in
            AdminPetsHotelCheckInSheet(reservation: res, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: $viewModel.checkOutModalStay) { stay in
            AdminPetsHotelCheckOutSheet(stay: stay, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: $viewModel.roomStatusModalAccommodation) { room in
            AdminPetsHotelRoomStatusSheet(room: room, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .onAppear {
            viewModel.loadHotelOperations()
        }
    }
}

// MARK: - iPhone Sovereign Architecture
private struct iPhoneHotelHubView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    let onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Apex Navigation Bar
            AdminSovereignNavigationBar(
                title: Language.get("Hotel_Title", alter: "فندق ورعاية الحيوانات"),
                subtitle: BranchContextStore.shared.currentBranchDisplayName.isEmpty
                    ? Language.get("Hotel_Workspace", alter: "مساحة الفندق • مباشر")
                    : "\(BranchContextStore.shared.currentBranchDisplayName) • مباشر",
                statusDotColor: Color(red: 0.16, green: 0.78, blue: 0.48),
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                AdminSquircleActionButton(
                    systemImage: "arrow.clockwise",
                    isLoading: viewModel.isLoading,
                    accessibilityLabel: Language.get("Refresh", alter: "تحديث")
                ) {
                    viewModel.loadHotelOperations()
                }
            }

            // Diagnostic & Branch Required Banner
            if viewModel.isLoading || viewModel.requiresBranchSelection || viewModel.errorMessage != nil {
                HotelStateBannerView(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Flight Tab Picker
            HotelFlightTabPicker(selectedTab: $viewModel.selectedTab, visibleTabs: viewModel.visibleTabs)

            // Search & Wing Filters (Visible on guests & care)
            if viewModel.selectedTab == .guests || viewModel.selectedTab == .care {
                HotelFilterDeckView(viewModel: viewModel)
            }

            // Scrollable Operational Canvas
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    if viewModel.isLoading && viewModel.inHouseGuests.isEmpty && viewModel.accommodations.isEmpty {
                        HotelOverviewSkeletonView()
                    } else {
                        switch viewModel.selectedTab {
                        case .overview:
                            iPhoneOverviewFlightDeck(viewModel: viewModel)
                        case .guests:
                            HotelGuestsListView(viewModel: viewModel)
                        case .reservations:
                            AdminPetsHotelReservationsManagementView(viewModel: viewModel)
                        case .rooms:
                            AdminPetsHotelSuitesManagementView(viewModel: viewModel)
                        case .care:
                            HotelCareOperationsView(viewModel: viewModel)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - iPhone Overview Flight Deck
private struct iPhoneOverviewFlightDeck: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(spacing: 16) {
            // Live Spatial Occupancy Radar Card
            HotelOccupancyRadarCard(viewModel: viewModel)

            // Today's Operational Horizon (Arrivals vs Departures)
            HotelOperationalHorizonTwinPillars(viewModel: viewModel)

            // Clinical & Special Attention Alert Deck
            if viewModel.attentionGuestsCount > 0 {
                HotelAttentionSentinelDeck(viewModel: viewModel)
            }

            // Quick Operations Horizon
            HotelQuickOperationsDeck(viewModel: viewModel)

            // Wing Capacity Multi-Deck
            HotelWingCapacitySection(viewModel: viewModel)
        }
    }
}

// MARK: - iPad Sovereign Widescreen Architecture
private struct iPadHotelConsoleView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    let onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Apex Panoramic Navigation Bar
            AdminSovereignNavigationBar(
                title: Language.get("Hotel_Title", alter: "فندق ورعاية الحيوانات"),
                subtitle: BranchContextStore.shared.currentBranchDisplayName.isEmpty
                    ? Language.get("Hotel_Workspace", alter: "مساحة الفندق • مباشر")
                    : "\(BranchContextStore.shared.currentBranchDisplayName) • لوحة التحكم الشاملة",
                statusDotColor: Color(red: 0.16, green: 0.78, blue: 0.48),
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                HStack(spacing: 10) {
                    AdminSquircleActionButton(
                        systemImage: "arrow.clockwise",
                        isLoading: viewModel.isLoading,
                        accessibilityLabel: Language.get("Refresh", alter: "تحديث")
                    ) {
                        viewModel.loadHotelOperations()
                    }
                }
            }

            if viewModel.isLoading || viewModel.requiresBranchSelection || viewModel.errorMessage != nil {
                HotelStateBannerView(viewModel: viewModel)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            // Widescreen Cockpit Split: Leading Command Pedestal + Trailing Interactive Matrix
            HStack(alignment: .top, spacing: 20) {
                // Leading Command Column (380pt fixed width)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        HotelOccupancyRadarCard(viewModel: viewModel)

                        HotelOperationalHorizonTwinPillars(viewModel: viewModel)

                        HotelQuickOperationsDeck(viewModel: viewModel)

                        if viewModel.attentionGuestsCount > 0 {
                            HotelAttentionSentinelDeck(viewModel: viewModel)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .frame(width: 380)

                // Trailing Operational Column (Fluid)
                VStack(spacing: 12) {
                    HStack {
                        HotelFlightTabPicker(selectedTab: $viewModel.selectedTab, visibleTabs: viewModel.visibleTabs)
                        Spacer()
                    }

                    if viewModel.selectedTab == .guests || viewModel.selectedTab == .care {
                        HotelFilterDeckView(viewModel: viewModel)
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            if viewModel.isLoading && viewModel.inHouseGuests.isEmpty && viewModel.accommodations.isEmpty {
                                HotelOverviewSkeletonView()
                            } else {
                                switch viewModel.selectedTab {
                                case .overview:
                                    iPadOverviewWorkspace(viewModel: viewModel)
                                case .guests:
                                    iPadGuestsGridWorkspace(viewModel: viewModel)
                                case .reservations:
                                    AdminPetsHotelReservationsManagementView(viewModel: viewModel)
                                case .rooms:
                                    AdminPetsHotelSuitesManagementView(viewModel: viewModel)
                                case .care:
                                    HotelCareOperationsView(viewModel: viewModel)
                                }
                            }
                        }
                        .padding(.trailing, 4)
                        .padding(.bottom, 40)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
        }
    }
}

// MARK: - iPad Overview Workspace
private struct iPadOverviewWorkspace: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(spacing: 18) {
            HotelWingCapacitySection(viewModel: viewModel)

            if !viewModel.inHouseGuests.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(Language.get("Hotel_Tab_Guests", alter: "النزلاء والإقامة الحالية"), systemImage: "pawprint.fill")
                            .font(PPBrandFont.bold(size: 16))
                            .foregroundStyle(AdminSurface.primaryText)
                        Spacer()
                        Button {
                            viewModel.selectedTab = .guests
                        } label: {
                            Text(Language.get("ViewAll", alter: "عرض الكل"))
                                .font(PPBrandFont.bold(size: 13))
                                .foregroundStyle(AdminSurface.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.inHouseGuests.prefix(4)) { stay in
                            HotelGuestCard(stay: stay, viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - iPad Guests Grid Workspace
private struct iPadGuestsGridWorkspace: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(spacing: 14) {
            if viewModel.filteredStays.isEmpty {
                HotelEmptyStateCard(
                    title: Language.get("Hotel_NoInHouseGuests", alter: "لا يوجد نزلاء حالياً في هذا الجناح"),
                    symbol: "pawprint"
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(viewModel.filteredStays) { stay in
                        HotelGuestCard(stay: stay, viewModel: viewModel)
                    }
                }
            }
        }
    }
}

// MARK: - Component: Living Occupancy Sentinel Radar Card
private struct HotelOccupancyRadarCard: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    private var occupancyGradient: LinearGradient {
        let rate = viewModel.occupancyRate
        if rate >= 0.90 {
            return LinearGradient(
                colors: [Color(red: 0.88, green: 0.22, blue: 0.35), Color(red: 0.98, green: 0.40, blue: 0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if rate >= 0.70 {
            return LinearGradient(
                colors: [Color(red: 0.95, green: 0.65, blue: 0.15), Color(red: 1.0, green: 0.78, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                            .frame(width: 7, height: 7)
                            .scaleEffect(isBreathing && !reduceMotion ? 1.25 : 1.0)

                        Text(Language.get("Hotel_Occupancy_Rate", alter: "نسبة إشغال الفندق"))
                            .font(PPBrandFont.bold(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Text(viewModel.occupancyPercentageString)
                        .font(PPBrandFont.bold(size: 38))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(String.localizedStringWithFormat(
                        Language.get("Hotel_OccupancySummary_Format", alter: "%ld من أصل %ld أجنحة مشغولة"),
                        viewModel.occupiedRoomsCount,
                        viewModel.totalRoomsCount
                    ))
                    .font(PPBrandFont.medium(size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Circular Progress Beacon with Breathing Glow
                ZStack {
                    Circle()
                        .stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.01, min(1.0, viewModel.occupancyRate))))
                        .stroke(
                            occupancyGradient,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "bed.double.fill")
                        .font(PPBrandFont.bold(size: 22))
                        .foregroundStyle(AdminSurface.primary)
                }
                .padding(.top, 2)
            }

            // Micro-telemetry status deck
            HStack(spacing: 8) {
                HotelTelemetryTag(
                    title: Language.get("Hotel_Available", alter: "متاح"),
                    count: viewModel.availableRoomsCount,
                    color: Color(red: 0.16, green: 0.72, blue: 0.44)
                )
                HotelTelemetryTag(
                    title: Language.get("Hotel_Occupied", alter: "مشغول"),
                    count: viewModel.occupiedRoomsCount,
                    color: AdminSurface.primary
                )
                HotelTelemetryTag(
                    title: Language.get("Hotel_Cleaning", alter: "تنظيف"),
                    count: viewModel.cleaningRoomsCount,
                    color: Color(red: 0.95, green: 0.65, blue: 0.15)
                )
                HotelTelemetryTag(
                    title: Language.get("Hotel_Maintenance", alter: "صيانة"),
                    count: viewModel.maintenanceRoomsCount,
                    color: Color(red: 0.50, green: 0.50, blue: 0.55)
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.04), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
    }
}

// MARK: - Component: Micro-Telemetry Status Tag
private struct HotelTelemetryTag: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5.5, height: 5.5)
            Text(title)
                .font(PPBrandFont.medium(size: 11.5))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
            Text("\(count)")
                .font(PPBrandFont.bold(size: 12.5))
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4.5)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Component: Operational Horizon Twin Pillars
private struct HotelOperationalHorizonTwinPillars: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Check-ins Today (Arrivals)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.selectedTab = .reservations
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.10, green: 0.55, blue: 0.85).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.down.left.circle.fill")
                                .font(PPBrandFont.bold(size: 16))
                                .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.85))
                        }
                        Spacer()
                        Text("\(viewModel.arrivalsTodayCount)")
                            .font(PPBrandFont.bold(size: 26))
                            .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.85))
                    }

                    Text(Language.get("Hotel_ArrivalsToday", alter: "وصول اليوم (تسجيل دخول)"))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(Language.get("Hotel_TapToViewReservations", alter: "اضغط لعرض الحجوزات"))
                        .font(PPBrandFont.medium(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(red: 0.10, green: 0.55, blue: 0.85).opacity(0.25), lineWidth: 0.75)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Check-outs Today (Departures)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.selectedTab = .guests
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(PPBrandFont.bold(size: 16))
                                .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                        }
                        Spacer()
                        Text("\(viewModel.departuresTodayCount)")
                            .font(PPBrandFont.bold(size: 26))
                            .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                    }

                    Text(Language.get("Hotel_DeparturesToday", alter: "مغادرة اليوم (تسليم)"))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(Language.get("Hotel_TapToViewStays", alter: "اضغط لإتمام المغادرة"))
                        .font(PPBrandFont.medium(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.25), lineWidth: 0.75)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Component: Clinical Attention Sentinel Deck
private struct HotelAttentionSentinelDeck: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(PPBrandFont.bold(size: 15))
                    .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))

                Text(Language.get("Hotel_Sentinel_AttentionGuests", alter: "نزلاء يتطلبون عناية أو متابعة خاصة"))
                    .font(PPBrandFont.bold(size: 14.5))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text("\(viewModel.attentionGuestsCount)")
                    .font(PPBrandFont.bold(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.15), in: Capsule())
                    .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.attentionGuests) { stay in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.selectedStayDetail = stay
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: stay.wing.icon)
                                    .font(PPBrandFont.bold(size: 16))
                                    .foregroundStyle(stay.wing.tint)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stay.petName)
                                        .font(PPBrandFont.bold(size: 13.5))
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Text(stay.guestStatus.title)
                                        .font(PPBrandFont.medium(size: 11.5))
                                        .foregroundStyle(stay.guestStatus.color)
                                }

                                Text(stay.roomNumber)
                                    .font(PPBrandFont.bold(size: 12))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .padding(10)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(stay.guestStatus.color.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.25), lineWidth: 0.75)
        )
    }
}

// MARK: - Component: Quick Operations Horizon Deck
private struct HotelQuickOperationsDeck: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        HStack(spacing: 10) {
            // New Reservation Action
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.newReservationModalOpen = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus")
                        .font(PPBrandFont.bold(size: 14))
                    Text(Language.get("Hotel_QuickAction_NewReservation", alter: "حجز جديد"))
                        .font(PPBrandFont.bold(size: 13.5))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())

            // Add Suite Action
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.isCreatingNewSuite = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.square.fill")
                        .font(PPBrandFont.bold(size: 14))
                    Text(Language.get("Hotel_QuickAction_AddSuite", alter: "إضافة جناح"))
                        .font(PPBrandFont.bold(size: 13.5))
                }
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!viewModel.canManageAccommodations)
            .opacity(viewModel.canManageAccommodations ? 1.0 : 0.4)

            // Add Accommodation Type Action
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.isCreatingNewType = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(PPBrandFont.bold(size: 14))
                    Text(Language.get("Hotel_QuickAction_ManageTypes", alter: "الأنواع"))
                        .font(PPBrandFont.bold(size: 13.5))
                }
                .foregroundStyle(AdminSurface.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!viewModel.canManageAccommodations)
            .opacity(viewModel.canManageAccommodations ? 1.0 : 0.4)
        }
    }
}

// MARK: - Component: Wing Capacity Multi-Deck
private struct HotelWingCapacitySection: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Hotel_WingCapacityBreakdown", alter: "توزيع السعة حسب الأجنحة"), systemImage: "square.grid.2x2.fill")
                .font(PPBrandFont.bold(size: 16))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 8) {
                ForEach(HotelWing.allCases) { wing in
                    let telemetry = viewModel.wingCapacityTelemetry(wing: wing)
                    if telemetry.total > 0 {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(wing.tint.opacity(0.15))
                                    .frame(width: 34, height: 34)
                                Image(systemName: wing.icon)
                                    .font(PPBrandFont.bold(size: 14))
                                    .foregroundStyle(wing.tint)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(wing.title)
                                        .font(PPBrandFont.bold(size: 14))
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Spacer()
                                    Text("\(telemetry.occupied) / \(telemetry.total)")
                                        .font(PPBrandFont.bold(size: 12))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }

                                ProgressView(value: telemetry.rate)
                                    .tint(wing.tint)
                                    .scaleEffect(y: 1.1)
                            }
                        }
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Component: Flight Mode Tab Picker
private struct HotelFlightTabPicker: View {
    @Binding var selectedTab: HotelHubTab
    let visibleTabs: [HotelHubTab]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabs) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(PPBrandFont.bold(size: 13))
                            Text(tab.title)
                                .font(isSelected ? PPBrandFont.bold(size: 13.5) : PPBrandFont.medium(size: 13.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                        )
                        .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Component: Search & Wing Filter Deck
private struct HotelFilterDeckView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Search Input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(PPBrandFont.medium(size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)

                TextField(Language.get("Search", alter: "البحث بالاسم، الغرفة، أو العميل..."), text: $viewModel.searchQuery)
                    .font(PPBrandFont.medium(size: 14))

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(PPBrandFont.bold(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75)
            )
            .padding(.horizontal, 16)

            // Wing Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectedWing = nil
                    } label: {
                        Text(Language.get("All", alter: "الكل"))
                            .font(PPBrandFont.bold(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(viewModel.selectedWing == nil ? AdminSurface.primaryText : AdminSurface.control, in: Capsule())
                            .foregroundStyle(viewModel.selectedWing == nil ? AdminSurface.surface : AdminSurface.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())

                    ForEach(HotelWing.allCases) { wing in
                        let isSelected = viewModel.selectedWing == wing
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.selectedWing = isSelected ? nil : wing
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: wing.icon)
                                    .font(PPBrandFont.bold(size: 11))
                                Text(wing.title)
                                    .font(PPBrandFont.medium(size: 13))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(isSelected ? wing.tint : AdminSurface.control, in: Capsule())
                            .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Component: In-House Guests List
private struct HotelGuestsListView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.filteredStays.isEmpty {
                HotelEmptyStateCard(
                    title: Language.get("Hotel_NoInHouseGuests", alter: "لا يوجد نزلاء حالياً في هذا الجناح"),
                    symbol: "pawprint"
                )
            } else {
                ForEach(viewModel.filteredStays) { stay in
                    HotelGuestCard(stay: stay, viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Component: Guest Card
private struct HotelGuestCard: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        Button {
            viewModel.selectedStayDetail = stay
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(stay.wing.tint.opacity(0.18))
                            .frame(width: 50, height: 50)
                        Image(systemName: stay.wing.icon)
                            .font(PPBrandFont.bold(size: 22))
                            .foregroundStyle(stay.wing.tint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(stay.petName)
                                .font(PPBrandFont.bold(size: 17))
                                .foregroundStyle(AdminSurface.primaryText)

                            if stay.guestStatus != .normal {
                                Image(systemName: stay.guestStatus.icon)
                                    .font(PPBrandFont.bold(size: 12))
                                    .foregroundStyle(stay.guestStatus.color)
                            }
                        }

                        Text("\(stay.petBreed) • \(stay.customerName)")
                            .font(PPBrandFont.medium(size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Room Badge
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(stay.roomNumber)
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundStyle(stay.wing.tint)
                        Text(stay.wing.title)
                            .font(PPBrandFont.medium(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Divider()

                // Stay Progress & Quick Actions
                HStack {
                    ProgressView(value: stay.stayProgress)
                        .tint(stay.stayProgress >= 0.9 ? Color.orange : AdminSurface.primary)
                        .scaleEffect(y: 1.1)

                    Spacer(minLength: 14)

                    Button {
                        viewModel.checkOutModalStay = stay
                    } label: {
                        Text(Language.get("Hotel_CheckOutButton", alter: "مغادرة"))
                            .font(PPBrandFont.bold(size: 13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.82, green: 0.15, blue: 0.35), in: Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!viewModel.canCheckOut)
                    .opacity(viewModel.canCheckOut ? 1 : 0.45)
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Component: Care Operations & Tasks
private struct HotelCareOperationsView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.inHouseGuests.isEmpty {
                HotelEmptyStateCard(
                    title: Language.get("Hotel_NoInHouseGuests", alter: "لا يوجد نزلاء حالياً لمتابعة مهام الرعاية"),
                    symbol: "heart.text.square.fill"
                )
            } else {
                ForEach(viewModel.inHouseGuests) { stay in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(stay.wing.tint.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: stay.wing.icon)
                                    .font(PPBrandFont.bold(size: 14))
                                    .foregroundStyle(stay.wing.tint)
                            }

                            Text(stay.petName)
                                .font(PPBrandFont.bold(size: 16))
                                .foregroundStyle(AdminSurface.primaryText)

                            Text("(\(stay.roomNumber))")
                                .font(PPBrandFont.medium(size: 13))
                                .foregroundStyle(AdminSurface.secondaryText)

                            Spacer()
                        }

                        // Tasks for this pet
                        VStack(spacing: 6) {
                            ForEach(stay.dailyCareTasks) { task in
                                Button {
                                    viewModel.toggleCareTask(stay: stay, task: task)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .font(PPBrandFont.bold(size: 18))
                                            .foregroundStyle(task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)

                                        Image(systemName: task.taskType.icon)
                                            .font(PPBrandFont.bold(size: 13))
                                            .foregroundStyle(AdminSurface.primary)
                                            .frame(width: 20)

                                        Text(task.taskType.title)
                                            .font(PPBrandFont.bold(size: 14))
                                            .foregroundStyle(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primaryText)

                                        Spacer()

                                        Text(task.scheduledTime)
                                            .font(PPBrandFont.medium(size: 12))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(!viewModel.canTransitionCareTask(task))
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
            }
        }
    }
}

// MARK: - Component: Hotel State Diagnostic Banner
private struct HotelStateBannerView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if viewModel.isLoading && viewModel.errorMessage == nil {
                ProgressView()
                    .tint(AdminSurface.primary)
            } else {
                Image(systemName: viewModel.requiresBranchSelection ? "building.2.crop.circle" : "exclamationmark.triangle.fill")
                    .font(PPBrandFont.bold(size: 16))
                    .foregroundStyle(viewModel.requiresBranchSelection ? AdminSurface.primary : Color.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.requiresBranchSelection
                     ? Language.get("Hotel_BranchRequired_Title", alter: "اختر فرع الفندق")
                     : viewModel.isLoading
                        ? Language.get("Hotel_Loading_Title", alter: "جاري مزامنة عمليات الفندق")
                        : Language.get("Hotel_LoadError_Title", alter: "تعذر تحديث بعض بيانات الفندق"))
                    .font(PPBrandFont.bold(size: 14))
                    .foregroundStyle(AdminSurface.primaryText)

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(PPBrandFont.medium(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if !viewModel.requiresBranchSelection && !viewModel.isLoading {
                Button(Language.get("Retry", alter: "إعادة المحاولة")) {
                    viewModel.loadHotelOperations()
                }
                .font(PPBrandFont.bold(size: 13))
                .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }
}

// MARK: - Component: Empty State Card
private struct HotelEmptyStateCard: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 60, height: 60)
                Image(systemName: symbol)
                    .font(PPBrandFont.bold(size: 26))
                    .foregroundStyle(AdminSurface.primary)
            }

            Text(title)
                .font(PPBrandFont.bold(size: 15))
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75)
        )
    }
}

// MARK: - Component: Shimmer Skeleton View
private struct HotelOverviewSkeletonView: View {
    @State private var shimmerPhase: CGFloat = -1.0

    var body: some View {
        VStack(spacing: 16) {
            // Radar Skeleton
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .frame(height: 160)
                .overlay(
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 120, height: 16)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 80, height: 36)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.gray.opacity(0.18))
                                .frame(width: 140, height: 14)
                        }
                        Spacer()
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            .frame(width: 76, height: 76)
                    }
                    .padding(20)
                )

            // Twin Pillars Skeleton
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AdminSurface.control)
                    .frame(height: 105)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AdminSurface.control)
                    .frame(height: 105)
            }

            // Wing Bars Skeleton
            VStack(spacing: 10) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(height: 58)
                }
            }
        }
        .opacity(0.85)
    }
}
