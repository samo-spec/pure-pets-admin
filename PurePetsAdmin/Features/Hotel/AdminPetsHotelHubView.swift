//
//  AdminPetsHotelHubView.swift
//  PurePetsAdmin
//
//  SwiftyMax NextGen V6 Flagship Pets Hotel Command Hub.
//  Category-defining, beyond-FAANG mobile operations suite for
//  boarding, guest stays, rooms, front-desk intake, and daily care.
//

import SwiftUI

public struct AdminPetsHotelHubView: View {
    @StateObject private var viewModel = AdminPetsHotelViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Bar
            topNavigationBar

            // Flight Mode Tab Picker
            flightTabPicker

            // Search & Wing Filters (Visible on relevant tabs)
            if viewModel.selectedTab != .overview {
                filterDeck
            }

            // Tab Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    switch viewModel.selectedTab {
                    case .overview:
                        overviewFlightDeck
                    case .guests:
                        guestsListView
                    case .reservations:
                        reservationsListView
                    case .rooms:
                        roomsGridView
                    case .care:
                        careOperationsView
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 48)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .sheet(item: $viewModel.selectedStayDetail) { stay in
            AdminPetsHotelStayDetailSheet(stay: stay, viewModel: viewModel)
        }
        .sheet(item: $viewModel.checkInModalReservation) { res in
            AdminPetsHotelCheckInSheet(reservation: res, viewModel: viewModel)
        }
        .sheet(item: $viewModel.checkOutModalStay) { stay in
            AdminPetsHotelCheckOutSheet(stay: stay, viewModel: viewModel)
        }
        .sheet(item: $viewModel.roomStatusModalAccommodation) { room in
            AdminPetsHotelRoomStatusSheet(room: room, viewModel: viewModel)
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75))

                    Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Language.get("Hotel_Title", alter: "فندق ورعاية الحيوانات"))
                        .font(Font.custom("Beiruti-Bold", size: 20))
                        .foregroundStyle(AdminSurface.primaryText)

                    // Live pulse dot
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                            .frame(width: 6, height: 6)
                        Text(Language.get("LiveSync", alter: "مباشر"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: Capsule())
                }

                if !BranchContextStore.shared.currentBranchDisplayName.isEmpty {
                    Text(BranchContextStore.shared.currentBranchDisplayName)
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            Spacer()

            // Refresh button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.loadHotelOperations()
            } label: {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.75))

                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Flight Mode Tab Picker
    private var flightTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HotelHubTab.allCases) { tab in
                    let isSelected = viewModel.selectedTab == tab
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewModel.selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.title)
                                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 14))
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
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Filter Deck (Search + Wing Pills)
    private var filterDeck: some View {
        VStack(spacing: 8) {
            // Search Input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AdminSurface.secondaryText)

                TextField(Language.get("Search", alter: "البحث بالاسم، الغرفة، أو العميل..."), text: $viewModel.searchQuery)
                    .font(Font.custom("Beiruti-Medium", size: 14))

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
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
            .padding(.horizontal, 18)

            // Wing Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // "All" Pill
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectedWing = nil
                    } label: {
                        Text(Language.get("All", alter: "الكل"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
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
                                    .font(.system(size: 11, weight: .bold))
                                Text(wing.title)
                                    .font(Font.custom("Beiruti-Medium", size: 13))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(isSelected ? wing.tint : AdminSurface.control, in: Capsule())
                            .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Tab 1: Overview Flight Deck
    private var overviewFlightDeck: some View {
        VStack(spacing: 18) {
            // Live Spatial Occupancy Radar Card
            occupancyRadarCard

            // Today's Operational Horizon (Arrivals vs Departures)
            operationalHorizonTwinPillars

            // Clinical & Special Attention Alert Deck
            if viewModel.attentionGuestsCount > 0 {
                attentionSentinelDeck
            }

            // Wing Capacity Multi-Deck
            wingCapacitySection
        }
    }

    private var occupancyRadarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Occupancy_Rate", alter: "نسبة إشغال الفندق"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(viewModel.occupancyPercentageString)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text("\(viewModel.occupiedRoomsCount) من أصل \(viewModel.totalRoomsCount) أجنحة مشغولة")
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Circular Progress Indicator
                ZStack {
                    Circle()
                        .stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 8)
                        .frame(width: 76, height: 76)

                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.occupancyRate))
                        .stroke(
                            LinearGradient(
                                colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
            }

            // Micro telemetry counters
            HStack(spacing: 10) {
                telemetryTag(title: Language.get("Hotel_Available", alter: "متاح"), count: viewModel.availableRoomsCount, color: Color(red: 0.16, green: 0.72, blue: 0.44))
                telemetryTag(title: Language.get("Hotel_Occupied", alter: "مشغول"), count: viewModel.occupiedRoomsCount, color: AdminSurface.primary)
                telemetryTag(title: Language.get("Hotel_Cleaning", alter: "تنظيف"), count: viewModel.cleaningRoomsCount, color: Color(red: 0.95, green: 0.65, blue: 0.15))
                telemetryTag(title: Language.get("Hotel_Maintenance", alter: "صيانة"), count: viewModel.maintenanceRoomsCount, color: Color(red: 0.50, green: 0.50, blue: 0.55))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.04), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private func telemetryTag(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title):")
                .font(Font.custom("Beiruti-Medium", size: 12))
                .foregroundStyle(AdminSurface.secondaryText)
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var operationalHorizonTwinPillars: some View {
        HStack(spacing: 12) {
            // Check-ins Today (Arrivals)
            Button {
                viewModel.selectedTab = .reservations
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.10, green: 0.55, blue: 0.85).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.down.left.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.85))
                        }
                        Spacer()
                        Text("\(viewModel.arrivalsTodayCount)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.85))
                    }

                    Text(Language.get("Hotel_ArrivalsToday", alter: "وصول اليوم (تسجيل دخول)"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Hotel_TapToViewReservations", alter: "اضغط لعرض الحجوزات"))
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
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
                viewModel.selectedTab = .guests
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.up.right.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                        }
                        Spacer()
                        Text("\(viewModel.departuresTodayCount)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                    }

                    Text(Language.get("Hotel_DeparturesToday", alter: "مغادرة اليوم (تسليم)"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Hotel_TapToViewStays", alter: "اضغط لإتمام المغادرة"))
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
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

    private var attentionSentinelDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))

                Text(Language.get("Hotel_Sentinel_AttentionGuests", alter: "نزلاء يتطلبون عناية أو متابعة خاصة"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text("\(viewModel.attentionGuestsCount)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.15), in: Capsule())
                    .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.attentionGuests) { stay in
                        Button {
                            viewModel.selectedStayDetail = stay
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: stay.wing.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(stay.wing.tint)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stay.petName)
                                        .font(Font.custom("Beiruti-Bold", size: 14))
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Text(stay.guestStatus.title)
                                        .font(Font.custom("Beiruti-Medium", size: 12))
                                        .foregroundStyle(stay.guestStatus.color)
                                }

                                Text(stay.roomNumber)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
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

    private var wingCapacitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_WingCapacityBreakdown", alter: "توزيع السعة حسب الأجنحة"), systemImage: "square.grid.2x2.fill")
                .font(Font.custom("Beiruti-Bold", size: 16))
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
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(wing.tint)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(wing.title)
                                        .font(Font.custom("Beiruti-Bold", size: 14))
                                        .foregroundStyle(AdminSurface.primaryText)
                                    Spacer()
                                    Text("\(telemetry.occupied) / \(telemetry.total)")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }

                                ProgressView(value: telemetry.rate)
                                    .tint(wing.tint)
                                    .scaleEffect(y: 1.1)
                            }
                        }
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Guests & In-House Stays
    private var guestsListView: some View {
        VStack(spacing: 12) {
            if viewModel.filteredStays.isEmpty {
                emptyStateCard(
                    title: Language.get("Hotel_NoInHouseGuests", alter: "لا يوجد نزلاء حالياً في هذا الجناح"),
                    symbol: "pawprint"
                )
            } else {
                ForEach(viewModel.filteredStays) { stay in
                    guestCard(stay: stay)
                }
            }
        }
    }

    private func guestCard(stay: AdminHotelStay) -> some View {
        Button {
            viewModel.selectedStayDetail = stay
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(stay.wing.tint.opacity(0.18))
                            .frame(width: 52, height: 52)
                        Image(systemName: stay.wing.icon)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(stay.wing.tint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(stay.petName)
                                .font(Font.custom("Beiruti-Bold", size: 18))
                                .foregroundStyle(AdminSurface.primaryText)

                            if stay.guestStatus != .normal {
                                Image(systemName: stay.guestStatus.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(stay.guestStatus.color)
                            }
                        }

                        Text("\(stay.petBreed) • \(stay.customerName)")
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    // Room Badge
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(stay.roomNumber)
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(stay.wing.tint)
                        Text(stay.wing.title)
                            .font(Font.custom("Beiruti-Medium", size: 11))
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
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.82, green: 0.15, blue: 0.35), in: Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
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

    // MARK: - Tab 3: Reservations
    private var reservationsListView: some View {
        VStack(spacing: 12) {
            if viewModel.filteredReservations.isEmpty {
                emptyStateCard(
                    title: Language.get("Hotel_NoReservations", alter: "لا توجد حجوزات مسجلة"),
                    symbol: "calendar.badge.clock"
                )
            } else {
                ForEach(viewModel.filteredReservations) { res in
                    reservationCard(reservation: res)
                }
            }
        }
    }

    private func reservationCard(reservation: AdminHotelReservation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(reservation.wing.tint.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: reservation.wing.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(reservation.wing.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(reservation.petName)
                            .font(Font.custom("Beiruti-Bold", size: 17))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(reservation.status.title)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(reservation.status.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(reservation.status.color)
                    }

                    Text("\(reservation.petBreed) • \(reservation.customerName)")
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(reservation.formattedTotal)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primary)
                    Text("\(reservation.numberOfNights) ليالي")
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            // Dates horizon & Check-in trigger
            HStack {
                Label("\(formatDate(reservation.checkInDate)) → \(formatDate(reservation.checkOutDate))", systemImage: "calendar")
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)

                Spacer()

                if reservation.status != .checkedIn && reservation.status != .completed && reservation.status != .cancelled {
                    Button {
                        viewModel.checkInModalReservation = reservation
                    } label: {
                        Text(Language.get("Hotel_CheckInNow", alter: "تسجيل الدخول الآن"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.16, green: 0.72, blue: 0.44), in: Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
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

    // MARK: - Tab 4: Rooms & Suites Spatial Grid
    private var roomsGridView: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.filteredAccommodations) { room in
                Button {
                    viewModel.roomStatusModalAccommodation = room
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(room.accommodationNumber)
                                .font(Font.custom("Beiruti-Bold", size: 17))
                                .foregroundStyle(AdminSurface.primaryText)
                            Spacer()
                            Image(systemName: room.wing.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(room.wing.tint)
                        }

                        Text(room.name)
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)

                        if let guest = room.currentGuestName {
                            HStack(spacing: 4) {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 10))
                                Text(guest)
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                            }
                            .foregroundStyle(AdminSurface.primary)
                        } else {
                            Text(room.formattedRate)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        // Status Pill
                        HStack(spacing: 4) {
                            Circle()
                                .fill(room.status.color)
                                .frame(width: 5, height: 5)
                            Text(room.status.title)
                                .font(Font.custom("Beiruti-Bold", size: 11))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(room.status.color.opacity(0.12), in: Capsule())
                        .foregroundStyle(room.status.color)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(room.status == .occupied ? AdminSurface.primary.opacity(0.3) : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Tab 5: Care Operations & Tasks
    private var careOperationsView: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.inHouseGuests) { stay in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(stay.wing.tint.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: stay.wing.icon)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(stay.wing.tint)
                        }

                        Text(stay.petName)
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("(\(stay.roomNumber))")
                            .font(Font.custom("Beiruti-Medium", size: 13))
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
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)

                                    Image(systemName: task.taskType.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AdminSurface.primary)
                                        .frame(width: 20)

                                    Text(task.taskType.title)
                                        .font(Font.custom("Beiruti-Bold", size: 14))
                                        .foregroundStyle(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primaryText)

                                    Spacer()

                                    Text(task.scheduledTime)
                                        .font(Font.custom("Beiruti-Medium", size: 12))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
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

    private func emptyStateCard(title: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(AdminSurface.secondaryText)

            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMM"
        return df.string(from: date)
    }
}
