//
//  AdminPetsHotelSuitesManagementViews.swift
//  PurePetsAdmin
//
//  Category-defining, beyond-FAANG spatial operations suite for
//  Suites, Rooms & Accommodations management (إدارة الغرف والأجنحة الفندقية).
//  Mirrors Pure Pets Console and Infra Cloud Functions.
//

import SwiftUI

// MARK: - Main Suites Management View
public struct AdminPetsHotelSuitesManagementView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AdminPetsHotelViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Top Spatial Occupancy & Housekeeping Telemetry HUD
            spatialTelemetryHud

            // Accommodation Types Strip & Actions
            accommodationTypesCarousel

            // Tactical Filter Matrix (Status & Wing Pills + View Toggle)
            controlBar

            // Content Deck (Grid vs List)
            if viewModel.filteredAccommodations.isEmpty {
                emptyAccommodationsCard
            } else {
                switch viewModel.roomViewMode {
                case .grid:
                    spatialArchitectureGrid
                case .list:
                    tacticalOperationsList
                }
            }
        }
    }

    // MARK: - Spatial Telemetry HUD
    private var spatialTelemetryHud: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_Suites_SpatialHUD_Title", alter: "حالة الإشغال والتجهيز الفندقي"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(String.localizedStringWithFormat(
                        Language.get("Hotel_Suites_SummaryFormat", alter: "%ld جناح إجمالي • %ld متاح للاستقبال الآن"),
                        viewModel.totalRoomsCount,
                        viewModel.availableRoomsCount
                    ))
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Live Occupancy Rate Capsule
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.occupancyRate > 0.85 ? Color(red: 0.90, green: 0.25, blue: 0.25) : AdminSurface.primary)
                        .frame(width: 7, height: 7)

                    Text(viewModel.occupancyPercentageString)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Hotel_Occupancy", alter: "إشغال"))
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.75))
            }

            // Segmented Distribution Bar
            GeometryReader { geo in
                let total = max(1, viewModel.totalRoomsCount)
                let availW = geo.size.width * CGFloat(viewModel.availableRoomsCount) / CGFloat(total)
                let occW = geo.size.width * CGFloat(viewModel.occupiedRoomsCount) / CGFloat(total)
                let cleanW = geo.size.width * CGFloat(viewModel.cleaningRoomsCount) / CGFloat(total)
                let maintW = geo.size.width * CGFloat(viewModel.maintenanceRoomsCount) / CGFloat(total)

                HStack(spacing: 3) {
                    if availW > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(red: 0.16, green: 0.72, blue: 0.44))
                            .frame(width: max(4, availW))
                    }
                    if occW > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(red: 0.82, green: 0.15, blue: 0.35))
                            .frame(width: max(4, occW))
                    }
                    if cleanW > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(red: 0.95, green: 0.65, blue: 0.15))
                            .frame(width: max(4, cleanW))
                    }
                    if maintW > 0 {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(red: 0.50, green: 0.50, blue: 0.55))
                            .frame(width: max(4, maintW))
                    }
                }
            }
            .frame(height: 8)

            // Status Counters Micro-Deck
            HStack(spacing: 8) {
                hudPill(title: Language.get("Hotel_Room_Available", alter: "متاح"), count: viewModel.availableRoomsCount, color: Color(red: 0.16, green: 0.72, blue: 0.44), filterKey: "available")
                hudPill(title: Language.get("Hotel_Room_Occupied", alter: "مشغول"), count: viewModel.occupiedRoomsCount, color: Color(red: 0.82, green: 0.15, blue: 0.35), filterKey: "occupied")
                hudPill(title: Language.get("Hotel_Room_Cleaning", alter: "تنظيف"), count: viewModel.cleaningRoomsCount, color: Color(red: 0.95, green: 0.65, blue: 0.15), filterKey: "cleaning")
                hudPill(title: Language.get("Hotel_Room_Maintenance", alter: "صيانة/حظر"), count: viewModel.maintenanceRoomsCount, color: Color(red: 0.50, green: 0.50, blue: 0.55), filterKey: "maintenance")
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private func hudPill(title: String, count: Int, color: Color, filterKey: String) -> some View {
        let isSelected = viewModel.roomStatusFilter == filterKey
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.roomStatusFilter = isSelected ? "all" : filterKey
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(Font.custom("Beiruti-Medium", size: 11))
                    .foregroundStyle(isSelected ? .white : AdminSurface.secondaryText)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? color : color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Accommodation Types Carousel
    private var accommodationTypesCarousel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(Language.get("Hotel_Suites_Types_Title", alter: "فئات وأسعار الأجنحة"), systemImage: "sparkles.rectangle.stack.fill")
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                if viewModel.canManageAccommodations {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.typeEditorModalType = nil
                        viewModel.isCreatingNewType = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                            Text(Language.get("Hotel_Suites_NewType", alter: "إضافة فئة"))
                                .font(Font.custom("Beiruti-Bold", size: 12))
                        }
                        .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if viewModel.accommodationTypes.isEmpty {
                        Text(Language.get("Hotel_Suites_NoTypesYet", alter: "لم يتم تكوين فئات أجنحة بعد لهذا الفرع"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(viewModel.accommodationTypes) { type in
                            Button {
                                if viewModel.canManageAccommodations {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    viewModel.typeEditorModalType = type
                                    viewModel.isCreatingNewType = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(type.wing.tint.opacity(0.18))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: type.wing.icon)
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(type.wing.tint)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(type.displayName)
                                            .font(Font.custom("Beiruti-Bold", size: 13))
                                            .foregroundStyle(AdminSurface.primaryText)
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            Text(type.formattedRate)
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundStyle(AdminSurface.primary)
                                            Text("•")
                                                .font(.system(size: 8))
                                                .foregroundStyle(AdminSurface.secondaryText)
                                            Text(type.code)
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(AdminSurface.secondaryText)
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tactical Control Bar (Status Filter + View Mode Switcher + Add Button)
    private var controlBar: some View {
        HStack(spacing: 10) {
            // Status Menu Filter
            Menu {
                Button(Language.get("All", alter: "الكل")) {
                    viewModel.roomStatusFilter = "all"
                }
                ForEach(HotelAccommodationStatus.allCases) { status in
                    Button {
                        viewModel.roomStatusFilter = status.rawValue
                    } label: {
                        Label(status.title, systemImage: status.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13, weight: .bold))
                    Text(currentStatusFilterTitle)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75))
                .foregroundStyle(viewModel.roomStatusFilter == "all" ? AdminSurface.primaryText : AdminSurface.primary)
            }

            Spacer()

            // View Mode Toggle (Grid vs List)
            HStack(spacing: 2) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.roomViewMode = .grid
                } label: {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(6)
                        .background(viewModel.roomViewMode == .grid ? AdminSurface.primary : Color.clear, in: Circle())
                        .foregroundStyle(viewModel.roomViewMode == .grid ? .white : AdminSurface.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.roomViewMode = .list
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(6)
                        .background(viewModel.roomViewMode == .list ? AdminSurface.primary : Color.clear, in: Circle())
                        .foregroundStyle(viewModel.roomViewMode == .list ? .white : AdminSurface.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(2)
            .background(AdminSurface.control, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75))

            // Add Suite CTA
            if viewModel.canManageAccommodations {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.suiteEditorModalAccommodation = nil
                    viewModel.isCreatingNewSuite = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Hotel_Suites_AddSuite", alter: "إضافة جناح"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AdminSurface.primary, in: Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var currentStatusFilterTitle: String {
        if viewModel.roomStatusFilter == "all" {
            return Language.get("Hotel_Filter_AllRooms", alter: "كل الأجنحة")
        }
        if let status = HotelAccommodationStatus(rawValue: viewModel.roomStatusFilter) {
            return status.title
        }
        return viewModel.roomStatusFilter
    }

    // MARK: - View 1: Spatial Architecture Grid (2 Columns)
    private var spatialArchitectureGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.filteredAccommodations) { room in
                AdminPetsHotelSuiteCard(room: room, viewModel: viewModel)
            }
        }
    }

    // MARK: - View 2: Tactical Operations List
    private var tacticalOperationsList: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.filteredAccommodations) { room in
                tacticalRow(room: room)
            }
        }
    }

    private func tacticalRow(room: AdminHotelAccommodation) -> some View {
        HStack(spacing: 12) {
            // Wing & Code Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(room.wing.tint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: room.wing.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(room.wing.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(room.accommodationNumber)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)

                    if let guest = room.currentGuestName {
                        HStack(spacing: 3) {
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 9))
                            Text(guest)
                                .font(Font.custom("Beiruti-Bold", size: 12))
                        }
                        .foregroundStyle(AdminSurface.primary)
                    }
                }

                Text("\(room.name) • \(room.wing.title)")
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            // Status Pill Button
            Menu {
                Text(Language.get("Hotel_Room_SetStatus", alter: "تحديث حالة الجناح"))
                ForEach(HotelAccommodationStatus.allCases) { status in
                    Button {
                        Task {
                            _ = await viewModel.setRoomStatus(room: room, newStatus: status)
                        }
                    } label: {
                        Label(status.title, systemImage: status.icon)
                    }
                }
                Divider()
                Button(Language.get("Edit", alter: "تعديل بيانات الجناح")) {
                    viewModel.suiteEditorModalAccommodation = room
                    viewModel.isCreatingNewSuite = false
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(room.status.color)
                        .frame(width: 6, height: 6)
                    Text(room.status.title)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(room.status.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(room.status.color.opacity(0.12), in: Capsule())
            }
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var emptyAccommodationsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "bed.double.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(AdminSurface.secondaryText)

            Text(Language.get("Hotel_Suites_NoRoomsMatch", alter: "لا توجد أجنحة تطابق معايير التصفية الحالية"))
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.secondaryText)

            if viewModel.canManageAccommodations {
                Button {
                    viewModel.suiteEditorModalAccommodation = nil
                    viewModel.isCreatingNewSuite = true
                } label: {
                    Text(Language.get("Hotel_Suites_CreateFirst", alter: "إضافة جناح جديد"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Category-Defining Flagship Suite Card
public struct AdminPetsHotelSuiteCard: View {
    let room: AdminHotelAccommodation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Code & Wing Accent
            HStack {
                Text(room.accommodationNumber)
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                // Wing Icon Badge
                ZStack {
                    Circle()
                        .fill(room.wing.tint.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: room.wing.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(room.wing.tint)
                }
            }

            // Suite Name & Capacity
            VStack(alignment: .leading, spacing: 1) {
                Text(room.name)
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(room.wing.title)
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text("•")
                        .font(.system(size: 7))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text("\(room.capacity) \(Language.get("Hotel_Suites_PetsLimit", alter: "حيوانات"))")
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            // Occupant or Rate Snapshot
            if let guest = room.currentGuestName {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.15))
                            .frame(width: 22, height: 22)
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AdminSurface.primary)
                    }

                    Text(guest)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                HStack {
                    Text(room.formattedRate)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primary)
                    Spacer()
                    if !room.active {
                        Text(Language.get("Inactive", alter: "معطل"))
                            .font(Font.custom("Beiruti-Bold", size: 10))
                            .foregroundStyle(Color.orange)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }

            Divider()
                .opacity(0.6)

            // Footer: Glowing Pulsing Status Capsule + Quick Menu
            HStack {
                Menu {
                    Text(Language.get("Hotel_Room_SetStatus", alter: "تحديث حالة الجناح"))
                    ForEach(HotelAccommodationStatus.allCases) { status in
                        Button {
                            Task {
                                _ = await viewModel.setRoomStatus(room: room, newStatus: status)
                            }
                        } label: {
                            Label(status.title, systemImage: status.icon)
                        }
                    }

                    if viewModel.canManageAccommodations {
                        Divider()
                        Button(Language.get("Edit", alter: "تعديل بيانات الجناح")) {
                            viewModel.suiteEditorModalAccommodation = room
                            viewModel.isCreatingNewSuite = false
                        }
                        Button(room.active ? Language.get("Deactivate", alter: "تعطيل الجناح") : Language.get("Activate", alter: "تفعيل الجناح")) {
                            Task {
                                await viewModel.toggleAccommodationActive(room: room)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(room.status.color)
                            .frame(width: 6, height: 6)
                        Text(room.status.title)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(room.status.color.opacity(0.12), in: Capsule())
                    .foregroundStyle(room.status.color)
                }

                Spacer()

                // Edit Button Trigger
                if viewModel.canManageAccommodations {
                    Button {
                        viewModel.suiteEditorModalAccommodation = room
                        viewModel.isCreatingNewSuite = false
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.04), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    room.status == .occupied
                        ? Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.35)
                        : Color(uiColor: .ppSurfaceBorder).opacity(0.55),
                    lineWidth: 0.85
                )
        )
    }
}

// MARK: - Sovereign Suite Editor Sheet (إضافة / تعديل جناح أو غرفة)
public struct AdminPetsHotelSuiteEditorSheet: View {
    let accommodation: AdminHotelAccommodation?
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var name: String = ""
    @State private var selectedWing: HotelWing = .dogs
    @State private var selectedTypeId: String = ""
    @State private var capacity: Int = 1
    @State private var allowSharedOccupancy: Bool = false
    @State private var active: Bool = true
    @State private var notes: String = ""
    @State private var selectedSpecies: Set<String> = ["dog"]
    @State private var isSubmitting: Bool = false
    @State private var validationError: String? = nil

    private var isEditMode: Bool { accommodation != nil }

    public init(accommodation: AdminHotelAccommodation?, viewModel: AdminPetsHotelViewModel) {
        self.accommodation = accommodation
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AdminSovereignNavigationBar(
                    title: isEditMode ? Language.get("Hotel_Suites_EditTitle", alter: "تعديل بيانات الجناح") : Language.get("Hotel_Suites_NewTitle", alter: "إضافة جناح جديد"),
                    subtitle: Language.get("Hotel_Workspace", alter: "مساحة الفندق • مباشر"),
                    statusDotColor: Color(red: 0.16, green: 0.78, blue: 0.48),
                    isModal: true,
                    onBack: { dismiss() }
                )

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        if let error = validationError {
                            Text(error)
                                .font(Font.custom("Beiruti-Bold", size: 13))
                                .foregroundStyle(Color.red)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // Section 1: Identification
                        identitySection

                        // Section 2: Wing & Tier Assignment
                        wingAndTierSection

                        // Section 3: Capacity & Shared Occupancy
                        capacitySection

                        // Section 4: Allowed Species Chips
                        speciesSection

                        // Section 5: Status & Operational Notes
                        notesSection

                        // Save CTA Button
                        saveButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                populateFields()
            }
        }
    }

    private func populateFields() {
        if let room = accommodation {
            code = room.accommodationNumber
            name = room.name
            selectedWing = room.wing
            selectedTypeId = room.accommodationTypeId
            capacity = room.capacity
            allowSharedOccupancy = room.allowSharedOccupancy
            active = room.active
            notes = room.notes ?? ""
            selectedSpecies = Set(room.allowedSpecies.isEmpty ? [room.wing == .cats ? "cat" : "dog"] : room.allowedSpecies)
        } else {
            selectedWing = .dogs
            selectedTypeId = viewModel.accommodationTypes.first?.id ?? ""
            capacity = 1
            allowSharedOccupancy = false
            active = true
            selectedSpecies = ["dog"]
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_BasicInfo", alter: "المعلومات الأساسية"), systemImage: "number.circle.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                // Suite Number / Code
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Suites_CodeLabel", alter: "رقم أو كود الجناح (مثال: D-101)"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField(Language.get("Hotel_Suites_CodePlaceholder", alter: "مثال: D-101"), text: $code)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .padding(10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Suite Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Suites_NameLabel", alter: "اسم الجناح أو الوصف"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField(Language.get("Hotel_Suites_NamePlaceholder", alter: "مثال: الجناح الملكي للكلاب الكبيرة"), text: $name)
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .padding(10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var wingAndTierSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Wing", alter: "الجناح والفئة الفندقية"), systemImage: "building.2.crop.circle.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                // Wing Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Wing_Select", alter: "الجناح التابع له:"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(HotelWing.allCases) { wing in
                                let isSelected = selectedWing == wing
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedWing = wing
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: wing.icon)
                                            .font(.system(size: 12, weight: .bold))
                                        Text(wing.title)
                                            .font(Font.custom("Beiruti-Medium", size: 13))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? wing.tint : AdminSurface.surface, in: Capsule())
                                    .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }

                // Accommodation Type Picker
                if !viewModel.accommodationTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Hotel_Type_Select", alter: "الفئة الفندقية ومعدل السعر:"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Menu {
                            ForEach(viewModel.accommodationTypes) { type in
                                Button {
                                    selectedTypeId = type.id
                                } label: {
                                    Text("\(type.displayName) (\(type.formattedRate))")
                                }
                            }
                        } label: {
                            HStack {
                                if let selected = viewModel.accommodationTypes.first(where: { $0.id == selectedTypeId }) {
                                    Text("\(selected.displayName) — \(selected.formattedRate)")
                                        .font(Font.custom("Beiruti-Bold", size: 14))
                                        .foregroundStyle(AdminSurface.primaryText)
                                } else {
                                    Text(Language.get("Hotel_ChooseType", alter: "اختر فئة الجناح..."))
                                        .font(Font.custom("Beiruti-Medium", size: 13))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            .padding(12)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_CapacitySettings", alter: "السعة والإشغال المشترك"), systemImage: "person.2.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                // Capacity Stepper
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Suites_MaxCapacity", alter: "الحد الأقصى للحيوانات"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Hotel_Suites_CapacityHint", alter: "عدد النزلاء المسموح بتسكينهم"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button {
                            if capacity > 1 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                capacity -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(capacity > 1 ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
                        }
                        .disabled(capacity <= 1)

                        Text("\(capacity)")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(minWidth: 24)

                        Button {
                            if capacity < 10 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                capacity += 1
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }

                Divider()

                // Shared Occupancy Toggle
                Toggle(isOn: $allowSharedOccupancy) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Suites_AllowShared", alter: "السماح بالإشغال المشترك"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Hotel_Suites_AllowSharedHint", alter: "لحيوانات نفس العميل فقط"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .tint(AdminSurface.primary)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_AllowedSpecies", alter: "الأنواع المسموح باستضافتها"), systemImage: "pawprint.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 8) {
                speciesChip(id: "dog", title: Language.get("Dogs", alter: "كلاب"), icon: "dog.fill")
                speciesChip(id: "cat", title: Language.get("Cats", alter: "قطط"), icon: "cat.fill")
                speciesChip(id: "bird", title: Language.get("Birds", alter: "طيور"), icon: "bird.fill")
                speciesChip(id: "small_pets", title: Language.get("SmallPets", alter: "حيوانات صغيرة"), icon: "hare.fill")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func speciesChip(id: String, title: String, icon: String) -> some View {
        let isSelected = selectedSpecies.contains(id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if isSelected {
                if selectedSpecies.count > 1 { selectedSpecies.remove(id) }
            } else {
                selectedSpecies.insert(id)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
            .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_NotesTitle", alter: "ملاحظات وتفعيل الجناح"), systemImage: "note.text")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                Toggle(isOn: $active) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Suites_ActiveStatus", alter: "الجناح مفعل وجاهز للخدمة"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Hotel_Suites_ActiveStatusHint", alter: "الأجنحة المعطلة لا تظهر في الحجوزات"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .tint(Color(red: 0.16, green: 0.72, blue: 0.44))

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Notes", alter: "ملاحظات تشغيلية أو توجيهات الصيانة:"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField(Language.get("Optional", alter: "اختياري..."), text: $notes)
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .padding(10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var saveButton: some View {
        Button {
            validateAndSave()
        } label: {
            HStack(spacing: 6) {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                }
                Text(isEditMode ? Language.get("Save_Changes", alter: "حفظ التغييرات") : Language.get("Hotel_Suites_SubmitNew", alter: "إضافة الجناح الفندقي"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(isSubmitting)
    }

    private func validateAndSave() {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanCode.isEmpty else {
            validationError = Language.get("Hotel_Err_CodeRequired", alter: "يرجى إدخال رقم أو كود الجناح.")
            return
        }

        guard !cleanName.isEmpty else {
            validationError = Language.get("Hotel_Err_NameRequired", alter: "يرجى إدخال اسم أو وصف الجناح.")
            return
        }

        let typeId = selectedTypeId.isEmpty ? (viewModel.accommodationTypes.first?.id ?? "") : selectedTypeId
        guard !typeId.isEmpty else {
            validationError = Language.get("Hotel_Err_TypeRequired", alter: "يرجى اختيار أو إنشاء فئة فندقية للجناح أولاً.")
            return
        }

        validationError = nil
        isSubmitting = true

        Task {
            let success = await viewModel.saveAccommodation(
                accommodationId: accommodation?.id,
                accommodationTypeId: typeId,
                code: cleanCode,
                name: cleanName,
                wing: selectedWing,
                allowedSpecies: Array(selectedSpecies),
                maxCapacity: capacity,
                allowSharedOccupancy: allowSharedOccupancy,
                notes: notes.isEmpty ? nil : notes,
                active: active
            )
            isSubmitting = false
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Sovereign Accommodation Type Editor Sheet (إضافة / تعديل فئة فندقية)
public struct AdminPetsHotelAccommodationTypeEditorSheet: View {
    let accommodationType: AdminHotelAccommodationType?
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var selectedWing: HotelWing = .dogs
    @State private var defaultCapacity: Int = 1
    @State private var nightlyRateMajor: String = "150"
    @State private var allowSharedOccupancy: Bool = false
    @State private var active: Bool = true
    @State private var description: String = ""
    @State private var isSubmitting: Bool = false
    @State private var validationError: String? = nil

    private var isEditMode: Bool { accommodationType != nil }

    public init(accommodationType: AdminHotelAccommodationType?, viewModel: AdminPetsHotelViewModel) {
        self.accommodationType = accommodationType
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                AdminSovereignNavigationBar(
                    title: isEditMode ? Language.get("Hotel_Suites_EditTypeTitle", alter: "تعديل الفئة الفندقية") : Language.get("Hotel_Suites_NewTypeTitle", alter: "فئة فندقية جديدة"),
                    subtitle: Language.get("Hotel_Workspace", alter: "مساحة الفندق • مباشر"),
                    statusDotColor: Color(red: 0.16, green: 0.78, blue: 0.48),
                    isModal: true,
                    onBack: { dismiss() }
                )

                ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if let error = validationError {
                        Text(error)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(Color.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Section: Tier Identification
                    VStack(alignment: .leading, spacing: 10) {
                        Label(Language.get("Hotel_Suites_TierDetails", alter: "تفاصيل الفئة الفندقية"), systemImage: "sparkles")
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        VStack(spacing: 12) {
                            // Code
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("Hotel_Suites_TypeCode", alter: "كود الفئة (مثال: VIP / STD)"))
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                TextField("VIP", text: $code)
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .padding(10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // Arabic Name
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("Hotel_Suites_NameAr", alter: "الاسم بالعربية"))
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                TextField(Language.get("Hotel_Suites_NameArPlaceholder", alter: "مثال: جناح كبار الشخصيات VIP"), text: $nameAr)
                                    .font(Font.custom("Beiruti-Medium", size: 14))
                                    .padding(10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // English Name
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("Hotel_Suites_NameEn", alter: "الاسم بالإنجليزية"))
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                TextField("e.g. VIP Presidential Suite", text: $nameEn)
                                    .font(.system(size: 14))
                                    .padding(10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .padding(14)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    // Section: Pricing & Capacity
                    VStack(alignment: .leading, spacing: 10) {
                        Label(Language.get("Hotel_Suites_PriceAndCapacity", alter: "السعر والسعة الافتراضية"), systemImage: "banknote.fill")
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        VStack(spacing: 12) {
                            // Nightly Rate in QAR
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("Hotel_Suites_NightlyRateQAR", alter: "سعر الليلة الواحدة (ر.ق)"))
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                HStack {
                                    TextField("150", text: $nightlyRateMajor)
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                    Text(Language.get("Currency_QAR", alter: "ر.ق"))
                                        .font(Font.custom("Beiruti-Bold", size: 14))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }
                                .padding(10)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // Wing Selection
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("Hotel_Wing", alter: "الجناح"))
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                                    .foregroundStyle(AdminSurface.secondaryText)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(HotelWing.allCases) { wing in
                                            let isSelected = selectedWing == wing
                                            Button {
                                                selectedWing = wing
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: wing.icon)
                                                        .font(.system(size: 11))
                                                    Text(wing.title)
                                                        .font(Font.custom("Beiruti-Medium", size: 12))
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(isSelected ? wing.tint : AdminSurface.surface, in: Capsule())
                                                .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                        // Save Button
                        Button {
                            validateAndSave()
                        } label: {
                            HStack(spacing: 6) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isEditMode ? Language.get("Save_Changes", alter: "حفظ الفئة") : Language.get("Hotel_Suites_CreateTypeCTA", alter: "إنشاء الفئة الفندقية"))
                                    .font(Font.custom("Beiruti-Bold", size: 16))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .disabled(isSubmitting)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                if let t = accommodationType {
                    code = t.code
                    nameAr = t.nameAr
                    nameEn = t.nameEn
                    selectedWing = t.wing
                    defaultCapacity = t.defaultCapacity
                    nightlyRateMajor = "\(t.nightlyRateMinor / 100)"
                    allowSharedOccupancy = t.allowSharedOccupancy
                    active = t.active
                    description = t.description ?? ""
                }
            }
        }
    }

    private func validateAndSave() {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNameAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let rateDouble = Double(nightlyRateMajor.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let rateMinor = Int(rateDouble * 100)

        guard !cleanCode.isEmpty else {
            validationError = Language.get("Hotel_Err_TypeCodeRequired", alter: "يرجى إدخال كود الفئة.")
            return
        }

        guard !cleanNameAr.isEmpty || !cleanNameEn.isEmpty else {
            validationError = Language.get("Hotel_Err_TypeNameRequired", alter: "يرجى إدخال اسم الفئة بالعربية أو الإنجليزية.")
            return
        }

        validationError = nil
        isSubmitting = true

        Task {
            let success = await viewModel.saveAccommodationType(
                typeId: accommodationType?.id,
                code: cleanCode,
                nameAr: cleanNameAr.isEmpty ? cleanNameEn : cleanNameAr,
                nameEn: cleanNameEn.isEmpty ? cleanNameAr : cleanNameEn,
                wing: selectedWing,
                allowedSpecies: [selectedWing == .cats ? "cat" : "dog"],
                defaultCapacity: defaultCapacity,
                nightlyRateMinor: rateMinor,
                allowSharedOccupancy: allowSharedOccupancy,
                description: description.isEmpty ? nil : description,
                active: active
            )
            isSubmitting = false
            if success {
                dismiss()
            }
        }
    }
}
