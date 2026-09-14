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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    public var isPushMode: Bool = false
    public var onBack: (() -> Void)? = nil

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
    @State private var showNewTypeSheet: Bool = false
    @State private var morphicPulse: Bool = false

    private var isEditMode: Bool { accommodation != nil }

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    public init(
        accommodation: AdminHotelAccommodation?,
        viewModel: AdminPetsHotelViewModel,
        isPushMode: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        self.accommodation = accommodation
        self.viewModel = viewModel
        self.isPushMode = isPushMode
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isIPad {
                iPadStudioFlightDeck
            } else {
                iPhoneTactileDeck
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            populateFields()
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                morphicPulse = true
            }
        }
        .fullScreenCover(isPresented: $showNewTypeSheet) {
            AdminPetsHotelAccommodationTypeEditorSheet(accommodationType: nil, viewModel: viewModel)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - Dismiss & Initialization
    private func handleDismiss() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func populateFields() {
        if let room = accommodation {
            code = room.accommodationNumber
            name = room.name
            selectedWing = room.wing
            selectedTypeId = room.accommodationTypeId
            capacity = max(1, room.capacity)
            allowSharedOccupancy = room.allowSharedOccupancy
            active = room.active
            notes = room.notes ?? ""
            selectedSpecies = Set(room.allowedSpecies.isEmpty ? AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: room.wing.rawValue) : room.allowedSpecies)
        } else {
            selectedWing = .dogs
            selectedTypeId = viewModel.accommodationTypes.first(where: { $0.wing == .dogs })?.id ?? viewModel.accommodationTypes.first?.id ?? ""
            capacity = 1
            allowSharedOccupancy = false
            active = true
            selectedSpecies = ["dog"]
            code = suggestedNextCode
        }
    }

    // MARK: - Smart Helpers & Presets
    private var selectedType: AdminHotelAccommodationType? {
        if let found = viewModel.accommodationTypes.first(where: { $0.id == selectedTypeId }) {
            return found
        }
        return viewModel.accommodationTypes.first(where: { $0.wing == selectedWing }) ?? viewModel.accommodationTypes.first
    }

    private var wingPrefix: String {
        switch selectedWing {
        case .dogs: return "D-"
        case .cats: return "C-"
        case .birds: return "B-"
        case .smallPets: return "S-"
        case .isolation: return "ISO-"
        case .medicalObservation: return "MED-"
        case .daycare: return "DAY-"
        }
    }

    private var suggestedNextCode: String {
        let wingRooms = viewModel.accommodations.filter { $0.wing == selectedWing }
        let nextNumber = 101 + wingRooms.count
        return String(format: "%@%02d", wingPrefix, nextNumber)
    }

    private var codePresets: [String] {
        let prefix = wingPrefix
        return [
            suggestedNextCode,
            "\(prefix)101",
            "\(prefix)102",
            "\(prefix)103",
            "\(prefix)201",
            "\(prefix)VIP"
        ]
    }

    private var nameSuggestions: [String] {
        switch selectedWing {
        case .dogs:
            return [
                Language.get("Hotel_Name_Dog1", alter: "الجناح الملكي للكلاب"),
                Language.get("Hotel_Name_Dog2", alter: "غرفة كلاسيك مريحة"),
                Language.get("Hotel_Name_Dog3", alter: "استوديو ديلوكس فندقي"),
                Language.get("Hotel_Name_Dog4", alter: "جناح الكلاب العائلي")
            ]
        case .cats:
            return [
                Language.get("Hotel_Name_Cat1", alter: "واحة القطط الملكية"),
                Language.get("Hotel_Name_Cat2", alter: "جناح الهدوء والاسترخاء"),
                Language.get("Hotel_Name_Cat3", alter: "استوديو القطط الفاخر"),
                Language.get("Hotel_Name_Cat4", alter: "جناح بانورامي للقطط")
            ]
        case .birds:
            return [
                Language.get("Hotel_Name_Bird1", alter: "ملاذ الطيور الاستوائي"),
                Language.get("Hotel_Name_Bird2", alter: "قفص ملكي بانورامي"),
                Language.get("Hotel_Name_Bird3", alter: "جناح التغريد الطبيعي")
            ]
        case .smallPets:
            return [
                Language.get("Hotel_Name_Small1", alter: "جناح الأرانب والحيوانات الصغيرة"),
                Language.get("Hotel_Name_Small2", alter: "مساحة النشاط والمرح"),
                Language.get("Hotel_Name_Small3", alter: "استوديو مريح مخصص")
            ]
        case .daycare:
            return [
                Language.get("Hotel_Name_Day1", alter: "صالة اللعب والتفاعل النهارية"),
                Language.get("Hotel_Name_Day2", alter: "منطقة الراحة والاسترخاء")
            ]
        case .isolation:
            return [
                Language.get("Hotel_Name_Iso1", alter: "جناح العزل الوقائي المجهز"),
                Language.get("Hotel_Name_Iso2", alter: "غرفة النقاهة الطبية")
            ]
        case .medicalObservation:
            return [
                Language.get("Hotel_Name_Med1", alter: "جناح الملاحظة البيطرية المركزة"),
                Language.get("Hotel_Name_Med2", alter: "غرفة الرعاية الخاصة")
            ]
        }
    }

    private var maintenancePresets: [String] {
        [
            Language.get("Hotel_Maint_AC", alter: "فحص التكييف"),
            Language.get("Hotel_Maint_Sanitize", alter: "تعقيم شامل"),
            Language.get("Hotel_Maint_Camera", alter: "فحص الكاميرا الذكية"),
            Language.get("Hotel_Maint_Bedding", alter: "تجهيز السرير الإسفنجي"),
            Language.get("Hotel_Maint_Door", alter: "فحص قفل الباب"),
            Language.get("Hotel_Maint_Water", alter: "فحص حوض المياه الذكي")
        ]
    }

    private func handleWingSelection(_ wing: HotelWing) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedWing = wing
        if code.isEmpty || code.hasPrefix("D-") || code.hasPrefix("C-") || code.hasPrefix("B-") || code.hasPrefix("S-") || code.hasPrefix("ISO-") || code.hasPrefix("MED-") || code.hasPrefix("DAY-") {
            code = suggestedNextCode
        }
        // Auto-align default species if not yet customized
        switch wing {
        case .dogs:
            if !selectedSpecies.contains("dog") { selectedSpecies = ["dog"] }
        case .cats:
            if !selectedSpecies.contains("cat") { selectedSpecies = ["cat"] }
        case .birds:
            if !selectedSpecies.contains("bird") { selectedSpecies = ["bird"] }
        case .smallPets:
            if !selectedSpecies.contains("small_pets") { selectedSpecies = ["small_pets"] }
        default:
            break
        }
        // Auto-select type for this wing if available
        if let match = viewModel.accommodationTypes.first(where: { $0.wing == wing }) {
            selectedTypeId = match.id
        }
    }

    // MARK: - Validation & Persistence
    private func validateAndSave() {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanCode.isEmpty else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            validationError = Language.get("Hotel_Err_CodeRequired", alter: "يرجى إدخال رقم أو كود الجناح.")
            return
        }

        guard !cleanName.isEmpty else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            validationError = Language.get("Hotel_Err_NameRequired", alter: "يرجى إدخال اسم أو وصف الجناح.")
            return
        }

        let typeId = selectedTypeId.isEmpty ? (viewModel.accommodationTypes.first?.id ?? "") : selectedTypeId
        guard !typeId.isEmpty else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            validationError = Language.get("Hotel_Err_TypeRequired", alter: "يرجى اختيار أو إنشاء فئة فندقية للجناح أولاً.")
            return
        }

        guard !selectedSpecies.isEmpty else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            validationError = Language.get("Hotel_Err_SpeciesRequired", alter: "يرجى تحديد نوع حيوان واحد على الأقل مسموح باستضافته.")
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
                handleDismiss()
            }
        }
    }

    // MARK: - Dynamic Twin / Suite Blueprint View
    private func suiteDigitalTwinCard(isCompact: Bool) -> some View {
        VStack(spacing: 12) {
            // Top Row: Wing Badge + Active Beacon
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: selectedWing.icon)
                        .font(.system(size: 13, weight: .bold))
                    Text(selectedWing.title)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selectedWing.tint.opacity(0.18), in: Capsule())
                .foregroundStyle(selectedWing.tint)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(active ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color(red: 0.95, green: 0.65, blue: 0.15))
                        .frame(width: 7, height: 7)
                        .scaleEffect(morphicPulse ? 1.25 : 0.85)

                    Text(active ? Language.get("Hotel_Suites_StatusReady", alter: "جاهز ومتاح للحجز") : Language.get("Hotel_Suites_StatusMaint", alter: "قيد الصيانة / معطل"))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(active ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color(red: 0.95, green: 0.65, blue: 0.15))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (active ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color(red: 0.95, green: 0.65, blue: 0.15)).opacity(0.12),
                    in: Capsule()
                )
            }

            // Middle Row: Suite Code & Descriptive Name
            HStack(spacing: 14) {
                // Large Room Code Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selectedWing.tint.opacity(0.4), lineWidth: 1.2)
                        )
                    Text(code.isEmpty ? "—" : code)
                        .font(Font.custom("Beiruti-Bold", size: isCompact ? 22 : 28))
                        .foregroundStyle(AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                }
                .frame(minWidth: isCompact ? 80 : 100)
                .frame(height: isCompact ? 52 : 62)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? Language.get("Hotel_Suite_Untitled", alter: "جناح بدون اسم محدد") : name)
                        .font(Font.custom("Beiruti-Bold", size: isCompact ? 16 : 19))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let type = selectedType {
                            Text(type.displayName)
                                .font(Font.custom("Beiruti-Bold", size: 12))
                                .foregroundStyle(selectedWing.tint)
                            Text("•")
                                .font(Font.custom("Beiruti-Bold", size: 10))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(type.formattedRate + " " + Language.get("Hotel_PerNight", alter: "/ ليلة"))
                                .font(Font.custom("Beiruti-Bold", size: 12))
                                .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        } else {
                            Text(Language.get("Hotel_NoTypeSelected", alter: "لم يتم اختيار فئة"))
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }

                Spacer()
            }

            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.4))

            // Bottom Telemetry & Visual Bed Slots
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(String.localizedStringWithFormat(Language.get("Hotel_Suites_PetsCountFormat", alter: "السعة: %ld نزلاء"), capacity))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(AdminSurface.primaryText)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Image(systemName: allowSharedOccupancy ? "checkmark.shield.fill" : "lock.shield.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(allowSharedOccupancy ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
                        Text(allowSharedOccupancy ? Language.get("Hotel_Shared_Active", alter: "إشغال مشترك معتمد") : Language.get("Hotel_Shared_Solo", alter: "إشغال فردي حصري"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(allowSharedOccupancy ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
                    }
                }

                // Interactive Bed Slots Diagram
                HStack(spacing: 5) {
                    ForEach(1...10, id: \.self) { slot in
                        let isOccupiedSlot = slot <= capacity
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                capacity = slot
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isOccupiedSlot ? selectedWing.tint.opacity(0.85) : AdminSurface.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(
                                                isOccupiedSlot ? selectedWing.tint : Color(uiColor: .ppSurfaceBorder).opacity(0.6),
                                                lineWidth: 1
                                            )
                                    )
                                Image(systemName: isOccupiedSlot ? "pawprint.fill" : "bed.double")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isOccupiedSlot ? Color.white : AdminSurface.secondaryText.opacity(0.4))
                            }
                            .frame(height: 22)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Allowed Species silhouettes
                HStack(spacing: 6) {
                    Text(Language.get("Hotel_Allowed_Label", alter: "النزلاء المسموحين:"))
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)

                    ForEach(Array(selectedSpecies), id: \.self) { sp in
                        HStack(spacing: 3) {
                            Image(systemName: speciesIcon(for: sp))
                                .font(.system(size: 9, weight: .bold))
                            Text(speciesTitle(for: sp))
                                .font(Font.custom("Beiruti-Bold", size: 10))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.surface, in: Capsule())
                        .foregroundStyle(AdminSurface.primaryText)
                    }

                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .overlay(
                    LinearGradient(
                        colors: [selectedWing.tint.opacity(0.12), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selectedWing.tint.opacity(0.35), lineWidth: 1.2)
        )
        .shadow(color: selectedWing.tint.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 12, y: 4)
    }

    private func speciesIcon(for id: String) -> String {
        switch id {
        case "dog": return "dog.fill"
        case "cat": return "cat.fill"
        case "bird": return "bird.fill"
        case "small_pets": return "hare.fill"
        default: return "pawprint.fill"
        }
    }

    private func speciesTitle(for id: String) -> String {
        switch id {
        case "dog": return Language.get("Dogs", alter: "كلاب")
        case "cat": return Language.get("Cats", alter: "قطط")
        case "bird": return Language.get("Birds", alter: "طيور")
        case "small_pets": return Language.get("SmallPets", alter: "حيوانات صغيرة")
        default: return id
        }
    }

    // MARK: - Form Sections
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_BasicInfo", alter: "المعلومات الأساسية والكود الفندقي"), systemImage: "number.circle.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 14) {
                // Room Code with Quick Presets
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Language.get("Hotel_Suites_CodeLabel", alter: "رقم أو كود الجناح (مثال: D-101)"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            code = suggestedNextCode
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text(Language.get("Hotel_SuggestCode", alter: "كود مقترح"))
                                    .font(Font.custom("Beiruti-Bold", size: 11))
                            }
                            .foregroundStyle(AdminSurface.primary)
                        }
                    }

                    TextField(Language.get("Hotel_Suites_CodePlaceholder", alter: "مثال: D-101"), text: $code)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )

                    // Quick Code Preset Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(codePresets, id: \.self) { preset in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    code = preset
                                } label: {
                                    Text(preset)
                                        .font(Font.custom("Beiruti-Bold", size: 12))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(code == preset ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                                        .foregroundStyle(code == preset ? Color.white : AdminSurface.primaryText)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: code == preset ? 0 : 0.8)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }

                Divider()
                    .background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))

                // Suite Name with Quick Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Hotel_Suites_NameLabel", alter: "اسم الجناح أو التوصيف الفندقي"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("Hotel_Suites_NamePlaceholder", alter: "مثال: الجناح الملكي للكلاب الكبيرة"), text: $name)
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )

                    // Quick Name Suggestions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(nameSuggestions, id: \.self) { sug in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    name = sug
                                } label: {
                                    Text(sug)
                                        .font(Font.custom("Beiruti-Medium", size: 12))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(name == sug ? selectedWing.tint : AdminSurface.surface, in: Capsule())
                                        .foregroundStyle(name == sug ? Color.white : AdminSurface.primaryText)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: name == sug ? 0 : 0.8)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private var wingSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Wing", alter: "الجناح التابع له والقسم الفندقي"), systemImage: "building.2.crop.circle.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            if isIPad {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(HotelWing.allCases) { wing in
                        wingCard(wing: wing)
                            .hoverEffect(.lift)
                    }
                }
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(HotelWing.allCases) { wing in
                            wingCard(wing: wing)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )
            }
        }
    }

    private func wingCard(wing: HotelWing) -> some View {
        let isSelected = selectedWing == wing
        return Button {
            handleWingSelection(wing)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? wing.tint : AdminSurface.surface)
                        .frame(width: 38, height: 38)
                    Image(systemName: wing.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : wing.tint)
                }

                Text(wing.title)
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundStyle(isSelected ? wing.tint : AdminSurface.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: isIPad ? .infinity : nil)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? wing.tint.opacity(0.12) : AdminSurface.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? wing.tint : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: isSelected ? 1.5 : 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var tierSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(Language.get("Hotel_Type_Select", alter: "الفئة الفندقية ومعدل السعر"), systemImage: "crown.fill")
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNewTypeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("Hotel_Suites_NewType", alter: "فئة جديدة"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundStyle(AdminSurface.primary)
                }
            }

            if viewModel.accommodationTypes.isEmpty {
                VStack(spacing: 8) {
                    Text(Language.get("Hotel_Suites_NoTypesYet", alter: "لم يتم تكوين فئات أجنحة بعد لهذا الفرع"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Button {
                        showNewTypeSheet = true
                    } label: {
                        Text(Language.get("Hotel_Suites_CreateTypeCTA", alter: "إنشاء الفئة الفندقية الأولى"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Group {
                    if isIPad {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(viewModel.accommodationTypes) { type in
                                tierCard(type: type)
                                    .hoverEffect(.lift)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            ForEach(viewModel.accommodationTypes) { type in
                                tierCard(type: type)
                            }
                        }
                    }
                }
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )
            }
        }
    }

    private func tierCard(type: AdminHotelAccommodationType) -> some View {
        let isSelected = selectedTypeId == type.id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTypeId = type.id
            if capacity == 1 && type.defaultCapacity > 1 {
                capacity = type.defaultCapacity
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AdminSurface.primary : AdminSurface.surface)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder), lineWidth: 1.5)
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(type.displayName)
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(type.code)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.surface, in: Capsule())
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    if let desc = type.description, !desc.isEmpty {
                        Text(desc)
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(type.formattedRate)
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    Text(Language.get("Hotel_PerNight", alter: "لكل ليلة"))
                        .font(Font.custom("Beiruti-Medium", size: 10))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: isSelected ? 1.2 : 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_CapacitySettings", alter: "السعة الفندقية والإشغال المشترك"), systemImage: "person.2.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 14) {
                // Stepper Row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Suites_MaxCapacity", alter: "الحد الأقصى للنزلاء"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Hotel_Suites_CapacityHint", alter: "عدد الحيوانات المسموح بتسكينهم في الجناح"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 14) {
                        Button {
                            if capacity > 1 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    capacity -= 1
                                }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(capacity > 1 ? AdminSurface.surface : AdminSurface.surface.opacity(0.4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 0.8)
                                    )
                                Image(systemName: "minus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(capacity > 1 ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.3))
                            }
                            .frame(width: 38, height: 38)
                        }
                        .disabled(capacity <= 1)

                        Text("\(capacity)")
                            .font(Font.custom("Beiruti-Bold", size: 24))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(minWidth: 32)

                        Button {
                            if capacity < 10 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    capacity += 1
                                }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(capacity < 10 ? AdminSurface.primary : AdminSurface.surface.opacity(0.4))
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(capacity < 10 ? Color.white : AdminSurface.secondaryText.opacity(0.3))
                            }
                            .frame(width: 38, height: 38)
                        }
                        .disabled(capacity >= 10)
                    }
                }

                Divider()
                    .background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))

                // Shared Occupancy Shield Card
                Toggle(isOn: $allowSharedOccupancy) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(allowSharedOccupancy ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.15) : AdminSurface.surface)
                                .frame(width: 34, height: 34)
                            Image(systemName: allowSharedOccupancy ? "checkmark.shield.fill" : "shield.slash")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(allowSharedOccupancy ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Hotel_Suites_AllowShared", alter: "السماح بالإشغال المشترك"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(Language.get("Hotel_Suites_AllowSharedHint", alter: "لحيوانات نفس العميل فقط لضمان الأمان وراحة النزلاء"))
                                .font(Font.custom("Beiruti-Medium", size: 11))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }
                .tint(Color(red: 0.16, green: 0.72, blue: 0.44))
            }
            .padding(16)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private var speciesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_AllowedSpecies", alter: "الأنواع المسموح باستضافتها"), systemImage: "pawprint.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 10) {
                speciesCard(id: "dog", title: Language.get("Dogs", alter: "كلاب"), icon: "dog.fill")
                speciesCard(id: "cat", title: Language.get("Cats", alter: "قطط"), icon: "cat.fill")
                speciesCard(id: "bird", title: Language.get("Birds", alter: "طيور"), icon: "bird.fill")
                speciesCard(id: "small_pets", title: Language.get("SmallPets", alter: "حيوانات صغيرة"), icon: "hare.fill")
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private func speciesCard(id: String, title: String, icon: String) -> some View {
        let isSelected = selectedSpecies.contains(id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                if isSelected {
                    if selectedSpecies.count > 1 { selectedSpecies.remove(id) }
                } else {
                    selectedSpecies.insert(id)
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? AdminSurface.primary : AdminSurface.surface)
                        .frame(width: 36, height: 36)
                    Image(systemName: isSelected ? "checkmark" : icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                }

                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 12))
                    .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AdminSurface.primary.opacity(0.1) : AdminSurface.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: isSelected ? 1.5 : 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_NotesTitle", alter: "حالة الجاهزية والتوجيهات التشغيلية"), systemImage: "note.text")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 14) {
                // Active State Toggle
                Toggle(isOn: $active) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(active ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.15) : Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: active ? "bolt.circle.fill" : "wrench.and.screwdriver.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(active ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color(red: 0.95, green: 0.65, blue: 0.15))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Hotel_Suites_ActiveStatus", alter: "الجناح مفعل وجاهز للخدمة"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(active ? Language.get("Hotel_Suites_ActiveHint", alter: "متاح فوراً للاستقبال وظاهر في شاشة الحجوزات") : Language.get("Hotel_Suites_ActiveStatusHint", alter: "الأجنحة المعطلة لا تظهر في الحجوزات وتعتبر تحت الصيانة"))
                                .font(Font.custom("Beiruti-Medium", size: 11))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }
                .tint(Color(red: 0.16, green: 0.72, blue: 0.44))

                Divider()
                    .background(Color(uiColor: .ppSurfaceBorder).opacity(0.5))

                // Operational Notes & Maintenance Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Notes", alter: "ملاحظات تشغيلية أو توجيهات الصيانة:"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("Optional", alter: "اختياري: إرشادات خاصة، حالة التكييف، متطلبات التسكين..."), text: $notes)
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )

                    // Quick Maintenance Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(maintenancePresets, id: \.self) { chip in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if notes.isEmpty {
                                        notes = chip
                                    } else if !notes.contains(chip) {
                                        notes += " • \(chip)"
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(chip)
                                            .font(Font.custom("Beiruti-Medium", size: 11))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(AdminSurface.surface, in: Capsule())
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.red)
            Text(error)
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundStyle(Color.red)
            Spacer()
            Button {
                validationError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.red.opacity(0.7))
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - iPhone Dedicated Architecture
    private var iPhoneTactileDeck: some View {
        VStack(spacing: 0) {
            iPhoneTopBar

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let error = validationError {
                            errorBanner(error)
                        }

                        // Live Specimen Twin
                        suiteDigitalTwinCard(isCompact: true)

                        // Config Deck
                        identitySection
                        wingSelectorSection
                        tierSelectorSection
                        capacitySection
                        speciesSection
                        notesSection

                        Spacer().frame(height: 90)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }

                iPhoneFloatingActionBar
            }
        }
    }

    private var iPhoneTopBar: some View {
        HStack(spacing: 12) {
            AdminSquircleBackButton {
                handleDismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isEditMode ? Language.get("Hotel_Suites_EditTitle", alter: "تعديل بيانات الجناح") : Language.get("Hotel_Suites_NewTitle", alter: "إضافة جناح جديد"))
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                        .frame(width: 6, height: 6)
                        .scaleEffect(morphicPulse ? 1.2 : 0.8)
                    Text(Language.get("Hotel_Workspace", alter: "مساحة الفندق • مباشر"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                }
            }

            Spacer()

            if !code.isEmpty {
                Button {
                    validateAndSave()
                } label: {
                    HStack(spacing: 4) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(isEditMode ? Language.get("Save", alter: "حفظ") : Language.get("Add", alter: "إضافة"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AdminSurface.primary, in: Capsule())
                    .foregroundStyle(Color.white)
                }
                .disabled(isSubmitting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            AdminSurface.surface
                .ignoresSafeArea(edges: .top)
                .overlay(Divider(), alignment: .bottom)
        )
    }

    private var iPhoneFloatingActionBar: some View {
        VStack(spacing: 0) {
            Button {
                validateAndSave()
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: isEditMode ? "pencil.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(isEditMode ? Language.get("Save_Changes", alter: "حفظ التغييرات الفندقية") : Language.get("Hotel_Suites_SubmitNew", alter: "إضافة الجناح الفندقي"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
                .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, y: 4)
            }
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - iPad Dedicated Architecture (Dual-Deck Flight Deck)
    private var iPadStudioFlightDeck: some View {
        VStack(spacing: 0) {
            iPadTopCommandBar

            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 28) {
                    // Leading Column: Parametric Studio (55% width)
                    VStack(spacing: 20) {
                        if let error = validationError {
                            errorBanner(error)
                        }

                        identitySection
                        wingSelectorSection
                        tierSelectorSection
                        capacitySection
                        speciesSection
                        notesSection
                    }
                    .frame(maxWidth: .infinity)

                    // Trailing Column: Digital Twin & Spatial Inspector (45% width, ~400pt)
                    VStack(spacing: 20) {
                        suiteDigitalTwinCard(isCompact: false)
                        iPadSuiteSpecsInspectorCard
                        iPadHousekeepingSimulatorCard
                        iPadActionFooterCard
                    }
                    .frame(width: 400)
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
                    Text(isEditMode ? Language.get("Hotel_Suites_EditTitle", alter: "تعديل بيانات الجناح") : Language.get("Hotel_Suites_NewTitle", alter: "إضافة جناح فندقي جديد"))
                        .font(Font.custom("Beiruti-Bold", size: 20))
                        .foregroundStyle(AdminSurface.primaryText)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                            .frame(width: 7, height: 7)
                            .scaleEffect(morphicPulse ? 1.2 : 0.8)
                        Text(Language.get("Hotel_Workspace", alter: "مساحة الفندق • مباشر"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: Capsule())
                }

                Text(Language.get("Hotel_Keyboard_SaveHint", alter: "⌘S للحفظ • Esc للإلغاء"))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            // Quick live telemetry chips
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: selectedWing.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(selectedWing.tint)
                    Text(selectedWing.title)
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedWing.tint.opacity(0.1), in: Capsule())

                if let type = selectedType {
                    HStack(spacing: 6) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        Text(type.formattedRate)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.1), in: Capsule())
                }
            }

            Button {
                validateAndSave()
            } label: {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(isEditMode ? Language.get("Save_Changes", alter: "حفظ التغييرات") : Language.get("Hotel_Suites_SubmitNew", alter: "إضافة الجناح"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSubmitting)

            AdminSquircleCloseButton {
                handleDismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(
            AdminSurface.surface
                .ignoresSafeArea(edges: .top)
                .overlay(Divider(), alignment: .bottom)
        )
    }

    private var iPadSuiteSpecsInspectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Hotel_Suite_SpecsTitle", alter: "المواصفات الفندقية والتشغيلية"), systemImage: "slider.horizontal.3")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 8) {
                specRow(title: Language.get("Hotel_Wing", alter: "الجناح"), value: selectedWing.title, icon: selectedWing.icon, tint: selectedWing.tint)
                specRow(title: Language.get("Hotel_Category", alter: "الفئة"), value: selectedType?.displayName ?? "—", icon: "crown.fill", tint: AdminSurface.primary)
                specRow(title: Language.get("Hotel_Rate", alter: "سعر الليلة"), value: selectedType?.formattedRate ?? "—", icon: "tag.fill", tint: Color(red: 0.16, green: 0.72, blue: 0.44))
                specRow(title: Language.get("Hotel_Capacity", alter: "أقصى سعة"), value: "\(capacity) " + Language.get("Hotel_Suites_PetsLimit", alter: "نزلاء"), icon: "pawprint.fill", tint: AdminSurface.primary)
                specRow(title: Language.get("Hotel_SharedOccupancy", alter: "الإشغال المشترك"), value: allowSharedOccupancy ? Language.get("Yes", alter: "نعم (نفس العميل)") : Language.get("No", alter: "لا (فردي)"), icon: "person.2.fill", tint: allowSharedOccupancy ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
                specRow(title: Language.get("Status", alter: "حالة الجاهزية"), value: active ? Language.get("Active", alter: "مفعل وجاهز") : Language.get("Inactive", alter: "معطل / صيانة"), icon: active ? "checkmark.circle.fill" : "wrench.fill", tint: active ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color(red: 0.95, green: 0.65, blue: 0.15))
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private func specRow(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            Spacer()
            Text(value)
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(.vertical, 2)
    }

    private var iPadHousekeepingSimulatorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Housekeeping_Protocol", alter: "بروتوكول النظافة والتعقيم"), systemImage: "sparkles")
                .font(Font.custom("Beiruti-Bold", size: 14))
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_ReadyForGuests", alter: "جاهز فوراً للتسكين والاستقبال"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Hotel_SanitizeCycleActive", alter: "دورة التعقيم والتجهيز الدوري معتمدة"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )
        }
    }

    private var iPadActionFooterCard: some View {
        VStack(spacing: 10) {
            Button {
                validateAndSave()
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: isEditMode ? "pencil.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(isEditMode ? Language.get("Save_Changes", alter: "حفظ التغييرات الفندقية") : Language.get("Hotel_Suites_SubmitNew", alter: "إضافة الجناح الفندقي"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 3)
            }
            .disabled(isSubmitting)

            Button {
                handleDismiss()
            } label: {
                Text(Language.get("Cancel", alter: "إلغاء التعديل"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
        )
    }
}

// MARK: - Sovereign Accommodation Type Editor Sheet (إضافة / تعديل فئة فندقية)
public struct AdminPetsHotelAccommodationTypeEditorSheet: View {
    let accommodationType: AdminHotelAccommodationType?
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var code: String = ""
    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var selectedWing: HotelWing = .dogs
    @State private var selectedSpecies: Set<String> = ["dog"]
    @State private var defaultCapacity: Int = 1
    @State private var nightlyRateMajor: String = "150"
    @State private var allowSharedOccupancy: Bool = false
    @State private var active: Bool = true
    @State private var descriptionText: String = ""
    @State private var isSubmitting: Bool = false
    @State private var validationError: String? = nil
    @State private var validationAttempted: Bool = false

    private var isEditMode: Bool { accommodationType != nil }
    private var isPad: Bool { horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad }

    public init(accommodationType: AdminHotelAccommodationType?, viewModel: AdminPetsHotelViewModel) {
        self.accommodationType = accommodationType
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if isPad {
                AdminHotelAccommodationTypePadView(
                    isEditMode: isEditMode,
                    code: $code,
                    nameAr: $nameAr,
                    nameEn: $nameEn,
                    selectedWing: $selectedWing,
                    selectedSpecies: $selectedSpecies,
                    defaultCapacity: $defaultCapacity,
                    nightlyRateMajor: $nightlyRateMajor,
                    allowSharedOccupancy: $allowSharedOccupancy,
                    active: $active,
                    descriptionText: $descriptionText,
                    isSubmitting: isSubmitting,
                    validationError: validationError,
                    onSave: { validateAndSave() },
                    onDismiss: { dismiss() }
                )
            } else {
                AdminHotelAccommodationTypePhoneView(
                    isEditMode: isEditMode,
                    code: $code,
                    nameAr: $nameAr,
                    nameEn: $nameEn,
                    selectedWing: $selectedWing,
                    selectedSpecies: $selectedSpecies,
                    defaultCapacity: $defaultCapacity,
                    nightlyRateMajor: $nightlyRateMajor,
                    allowSharedOccupancy: $allowSharedOccupancy,
                    active: $active,
                    descriptionText: $descriptionText,
                    isSubmitting: isSubmitting,
                    validationError: validationError,
                    onSave: { validateAndSave() },
                    onDismiss: { dismiss() }
                )
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            populateFields()
        }
    }

    private func populateFields() {
        if let t = accommodationType {
            code = t.code
            nameAr = t.nameAr
            nameEn = t.nameEn
            selectedWing = t.wing
            selectedSpecies = Set(t.allowedSpecies.isEmpty ? AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: t.wing.rawValue) : t.allowedSpecies)
            defaultCapacity = max(1, t.defaultCapacity)
            nightlyRateMajor = "\(t.nightlyRateMinor / 100)"
            allowSharedOccupancy = t.allowSharedOccupancy
            active = t.active
            descriptionText = t.description ?? ""
        } else {
            code = "VIP"
            nameAr = ""
            nameEn = ""
            selectedWing = .dogs
            selectedSpecies = ["dog"]
            defaultCapacity = 1
            nightlyRateMajor = "150"
            allowSharedOccupancy = false
            active = true
            descriptionText = ""
        }
    }

    private func validateAndSave() {
        validationAttempted = true
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanNameAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let rateDouble = Double(nightlyRateMajor.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let rateMinor = Int(rateDouble * 100)

        guard !cleanCode.isEmpty else {
            validationError = Language.get("Hotel_Err_TypeCodeRequired", alter: "يرجى إدخال كود الفئة.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        guard !cleanNameAr.isEmpty || !cleanNameEn.isEmpty else {
            validationError = Language.get("Hotel_Err_TypeNameRequired", alter: "يرجى إدخال اسم الفئة بالعربية أو الإنجليزية.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        validationError = nil
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            let finalSpecies = Array(selectedSpecies.isEmpty ? [selectedWing == .cats ? "cat" : "dog"] : selectedSpecies)
            let success = await viewModel.saveAccommodationType(
                typeId: accommodationType?.id,
                code: cleanCode,
                nameAr: cleanNameAr.isEmpty ? cleanNameEn : cleanNameAr,
                nameEn: cleanNameEn.isEmpty ? cleanNameAr : cleanNameEn,
                wing: selectedWing,
                allowedSpecies: finalSpecies,
                defaultCapacity: defaultCapacity,
                nightlyRateMinor: rateMinor,
                allowSharedOccupancy: allowSharedOccupancy,
                description: descriptionText.isEmpty ? nil : descriptionText,
                active: active
            )
            isSubmitting = false
            if success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                validationError = viewModel.errorMessage ?? "Failed to save category"
            }
        }
    }
}

// MARK: - iPhone Dedicated Native Architecture (Ergonomic Thumb-Zone Layout)
private struct AdminHotelAccommodationTypePhoneView: View {
    let isEditMode: Bool
    @Binding var code: String
    @Binding var nameAr: String
    @Binding var nameEn: String
    @Binding var selectedWing: HotelWing
    @Binding var selectedSpecies: Set<String>
    @Binding var defaultCapacity: Int
    @Binding var nightlyRateMajor: String
    @Binding var allowSharedOccupancy: Bool
    @Binding var active: Bool
    @Binding var descriptionText: String
    let isSubmitting: Bool
    let validationError: String?
    let onSave: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: isEditMode ? Language.get("Hotel_Suites_EditTypeTitle", alter: "تعديل الفئة الفندقية") : Language.get("Hotel_Suites_NewTypeTitle", alter: "فئة فندقية جديدة"),
                subtitle: Language.get("Hotel_Workspace", alter: "مساحة الفندق • مباشر"),
                statusDotColor: Color(red: 0.16, green: 0.78, blue: 0.48),
                isModal: true,
                customTopSpacing: 0,
                onBack: onDismiss
            )
            .background(
                AdminSurface.card
                    .ignoresSafeArea(edges: .top)
                    .overlay(Divider(), alignment: .bottom)
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. The Living Tier Vitrine (Hero Preview)
                    AdminHotelTierLivingVitrine(
                        code: code,
                        nameAr: nameAr,
                        nameEn: nameEn,
                        wing: selectedWing,
                        selectedSpecies: selectedSpecies,
                        nightlyRateMajor: nightlyRateMajor,
                        defaultCapacity: defaultCapacity,
                        allowSharedOccupancy: allowSharedOccupancy,
                        active: active,
                        isCompact: true
                    )

                    // 2. Section: Tier Identity Bento
                    AdminHotelTierIdentityCard(
                        code: $code,
                        nameAr: $nameAr,
                        nameEn: $nameEn,
                        wing: selectedWing
                    )

                    // 3. Section: Wing & Species Matrix
                    AdminHotelWingAndSpeciesCard(
                        selectedWing: $selectedWing,
                        selectedSpecies: $selectedSpecies
                    )

                    // 4. Section: Pricing Engine
                    AdminHotelPricingEngineCard(
                        nightlyRateMajor: $nightlyRateMajor,
                        wing: selectedWing
                    )

                    // 5. Section: Capacity & Operational Rules
                    AdminHotelCapacityAndRulesCard(
                        defaultCapacity: $defaultCapacity,
                        allowSharedOccupancy: $allowSharedOccupancy,
                        active: $active,
                        wing: selectedWing
                    )

                    // 6. Section: Luxury Amenities & Description
                    AdminHotelDescriptionCard(
                        descriptionText: $descriptionText,
                        wing: selectedWing
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 120) // Bottom breathing room for sticky bar
            }

            // Sticky Bottom Action Bar
            stickyBottomBar
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }

    private var stickyBottomBar: some View {
        VStack(spacing: 8) {
            if let error = validationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                    Text(error)
                        .font(PPBeirutiFont.bold(12.5, relativeTo: .caption))
                }
                .foregroundStyle(Color(uiColor: .ppError))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .ppError).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button(action: onSave) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(isEditMode ? Language.get("Save_Changes", alter: "حفظ التغييرات") : Language.get("Hotel_Suites_CreateTypeCTA", alter: "إنشاء الفئة الفندقية"))
                        .font(PPBeirutiFont.bold(17, relativeTo: .headline))
                        .foregroundStyle(Color.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AdminSurface.primary)
                )
                .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, y: 3)
            }
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, max(PPStatusBarHelper.statusBarHeight > 20 ? 16 : 12, 12))
        .background(
            AdminSurface.control
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.06), radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - iPad Dedicated Native Architecture (Studio Dual-Deck Inspector)
private struct AdminHotelAccommodationTypePadView: View {
    let isEditMode: Bool
    @Binding var code: String
    @Binding var nameAr: String
    @Binding var nameEn: String
    @Binding var selectedWing: HotelWing
    @Binding var selectedSpecies: Set<String>
    @Binding var defaultCapacity: Int
    @Binding var nightlyRateMajor: String
    @Binding var allowSharedOccupancy: Bool
    @Binding var active: Bool
    @Binding var descriptionText: String
    let isSubmitting: Bool
    let validationError: String?
    let onSave: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: isEditMode ? Language.get("Hotel_Suites_EditTypeTitle", alter: "تعديل الفئة الفندقية") : Language.get("Hotel_Suites_NewTypeTitle", alter: "فئة فندقية جديدة"),
                subtitle: Language.get("Hotel_Suites_StudioSubtitle", alter: "تصميم وإدارة معايير الإقامة والأجنحة الفاخرة"),
                statusDotColor: Color(red: 0.16, green: 0.78, blue: 0.48),
                isModal: true,
                customTopSpacing: 0,
                onBack: onDismiss
            ) {
                // Trailing ⌘S Indicator
                HStack(spacing: 4) {
                    Text("⌘S")
                        .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8))
                }
            }
            .background(
                AdminSurface.card
                    .ignoresSafeArea(edges: .top)
                    .overlay(Divider(), alignment: .bottom)
            )

            HStack(alignment: .top, spacing: 20) {
                // Leading Column: Configuration Cards (Fluid Scroll)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        AdminHotelTierIdentityCard(
                            code: $code,
                            nameAr: $nameAr,
                            nameEn: $nameEn,
                            wing: selectedWing
                        )

                        AdminHotelWingAndSpeciesCard(
                            selectedWing: $selectedWing,
                            selectedSpecies: $selectedSpecies
                        )

                        AdminHotelPricingEngineCard(
                            nightlyRateMajor: $nightlyRateMajor,
                            wing: selectedWing
                        )

                        AdminHotelCapacityAndRulesCard(
                            defaultCapacity: $defaultCapacity,
                            allowSharedOccupancy: $allowSharedOccupancy,
                            active: $active,
                            wing: selectedWing
                        )

                        AdminHotelDescriptionCard(
                            descriptionText: $descriptionText,
                            wing: selectedWing
                        )
                    }
                    .padding(.vertical, 16)
                    .padding(.leading, 20)
                }
                .frame(maxWidth: .infinity)

                // Trailing Column: Studio Vitrine + Operational Telemetry Deck
                VStack(spacing: 16) {
                    // Pinned Vitrine
                    AdminHotelTierLivingVitrine(
                        code: code,
                        nameAr: nameAr,
                        nameEn: nameEn,
                        wing: selectedWing,
                        selectedSpecies: selectedSpecies,
                        nightlyRateMajor: nightlyRateMajor,
                        defaultCapacity: defaultCapacity,
                        allowSharedOccupancy: allowSharedOccupancy,
                        active: active,
                        isCompact: false
                    )

                    // Studio Telemetry Overview Card
                    studioTelemetryCard

                    if let error = validationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                            Text(error)
                                .font(PPBeirutiFont.bold(12.5, relativeTo: .caption))
                        }
                        .foregroundStyle(Color(uiColor: .ppError))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .ppError).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Primary Save Button
                    Button(action: onSave) {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }

                            Text(isEditMode ? Language.get("Save_Changes", alter: "حفظ التغييرات") : Language.get("Hotel_Suites_CreateTypeCTA", alter: "إنشاء الفئة الفندقية"))
                                .font(PPBeirutiFont.bold(17, relativeTo: .headline))
                                .foregroundStyle(Color.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AdminSurface.primary)
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, y: 3)
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .hoverEffect()
                    .disabled(isSubmitting)

                    Spacer(minLength: 0)
                }
                .frame(width: 360)
                .padding(.vertical, 16)
                .padding(.trailing, 20)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }

    private var studioTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_LivePreviewTitle", alter: "المعاينة الحية لبطاقة الفئة"), systemImage: "macwindow.on.rectangle")
                .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)

            Text(Language.get("Hotel_Suites_LivePreviewSub", alter: "تحديث فوري لبطاقة النزيل والعرض الفندقي"))
                .font(PPBeirutiFont.regular(11.5, relativeTo: .caption2))
                .foregroundStyle(AdminSurface.secondaryText)

            Divider()

            VStack(spacing: 7) {
                telemetryRow(
                    label: Language.get("Hotel_Wing", alter: "الجناح:"),
                    value: selectedWing.title,
                    color: selectedWing.tint
                )

                let rate = Double(nightlyRateMajor.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
                telemetryRow(
                    label: Language.get("Hotel_Suites_NightlyRateQAR", alter: "معدل الليلة:"),
                    value: String(format: "%.0f %@", rate, Language.get("Currency_QAR", alter: "ر.ق")),
                    color: AdminSurface.primaryText
                )

                telemetryRow(
                    label: Language.get("Hotel_Suites_PricePerNightFormula", alter: "تقدير ٣ ليالٍ:"),
                    value: String(format: "%.0f %@", rate * 3, Language.get("Currency_QAR", alter: "ر.ق")),
                    color: Color(uiColor: .ppSuccess)
                )

                telemetryRow(
                    label: Language.get("Hotel_Suites_SharedOccupancyTitle", alter: "الإقامة المشتركة:"),
                    value: allowSharedOccupancy ? Language.get("Yes", alter: "مسموحة") : Language.get("No", alter: "فردية فقط"),
                    color: allowSharedOccupancy ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText
                )
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func telemetryRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(PPBeirutiFont.medium(12, relativeTo: .caption))
                .foregroundStyle(AdminSurface.secondaryText)

            Spacer(minLength: 4)

            Text(value)
                .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                .foregroundStyle(color)
        }
    }
}

// MARK: - The Living Tier Vitrine (Sovereign Hero Component)
private struct AdminHotelTierLivingVitrine: View {
    let code: String
    let nameAr: String
    let nameEn: String
    let wing: HotelWing
    let selectedSpecies: Set<String>
    let nightlyRateMajor: String
    let defaultCapacity: Int
    let allowSharedOccupancy: Bool
    let active: Bool
    var isCompact: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing: Bool = false

    private var displayRate: String {
        let trimmed = nightlyRateMajor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "0" : trimmed
    }

    private var displayNameAr: String {
        let trimmed = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Language.get("Hotel_Suites_NameArPlaceholder", alter: "مثال: جناح كبار الشخصيات VIP") : trimmed
    }

    private var displayNameEn: String {
        let trimmed = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "e.g. VIP Presidential Suite" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 13 : 15) {
            // Header Row: Wing Tag + Status Beacon + Code Badge
            HStack(alignment: .center, spacing: 8) {
                // Wing Identity Pill
                HStack(spacing: 5) {
                    Image(systemName: wing.icon)
                        .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                    Text(wing.title)
                        .font(PPBeirutiFont.bold(12.5, relativeTo: .caption))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(wing.tint)
                )
                .shadow(color: wing.tint.opacity(0.35), radius: 4, y: 2)

                // Active / Renovation Status
                HStack(spacing: 4.5) {
                    Circle()
                        .fill(active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        .frame(width: 6, height: 6)
                        .scaleEffect(active && isPulsing ? 1.25 : 0.85)

                    Text(active ? Language.get("Hotel_Suites_ActiveBadge", alter: "نشطة ومتاحة") : Language.get("Hotel_Suites_InactiveBadge", alter: "معطلة مؤقتاً"))
                        .font(PPBeirutiFont.bold(11, relativeTo: .caption2))
                        .foregroundStyle(active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(active ? Color(uiColor: .ppSuccess).opacity(0.12) : Color(uiColor: .ppWarning).opacity(0.12))
                )

                Spacer(minLength: 4)

                // Metallic Luxury Code Squircle
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(PPBeirutiFont.bold(10, relativeTo: .caption2))
                        .foregroundStyle(wing.tint)

                    Text(code.isEmpty ? "VIP" : code.uppercased())
                        .font(PPBeirutiFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .monospacedDigit()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(wing.tint.opacity(0.25), lineWidth: 0.8)
                )
            }

            // Body: Tier Names & Species Horizon
            VStack(alignment: .leading, spacing: 3) {
                Text(displayNameAr)
                    .font(PPBeirutiFont.bold(isCompact ? 20 : 23, relativeTo: .title3))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(displayNameEn)
                    .font(PPBeirutiFont.medium(isCompact ? 13 : 14.5, relativeTo: .subheadline))
                    .foregroundStyle(nameEn.isEmpty ? AdminSurface.secondaryText.opacity(0.6) : AdminSurface.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            // Species Icons Row
            if !selectedSpecies.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(selectedSpecies).sorted(), id: \.self) { species in
                        speciesMiniChip(species)
                    }
                }
            }

            Divider()
                .overlay(wing.tint.opacity(0.15))

            // Footer Row: Policy & Price Rate
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                // Occupancy & Shared Policy Pill
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "pawprint.fill")
                            .font(PPBeirutiFont.bold(11, relativeTo: .caption2))
                            .foregroundStyle(wing.tint)

                        Text(String(format: Language.get("Hotel_Suites_PetsCountFormat", alter: "%d حيوانات"), defaultCapacity))
                            .font(PPBeirutiFont.bold(12.5, relativeTo: .caption))
                            .foregroundStyle(AdminSurface.primaryText)
                    }

                    Text(allowSharedOccupancy ? Language.get("Hotel_Suites_SharedAllowedBadge", alter: "إقامة مشتركة 🐾") : Language.get("Hotel_Suites_PrivateOnlyBadge", alter: "إقامة فردية حصراً"))
                        .font(PPBeirutiFont.regular(10.5, relativeTo: .caption2))
                        .foregroundStyle(allowSharedOccupancy ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
                }

                Spacer(minLength: 8)

                // Nightly Rate
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayRate)
                        .font(PPBeirutiFont.bold(isCompact ? 26 : 30, relativeTo: .title))
                        .foregroundStyle(AdminSurface.primaryText)
                        .monospacedDigit()

                    VStack(alignment: .leading, spacing: 0) {
                        Text(Language.get("Currency_QAR", alter: "ر.ق"))
                            .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                            .foregroundStyle(wing.tint)

                        Text(Language.get("Hotel_Suites_PerNight", alter: "/ ليلة"))
                            .font(PPBeirutiFont.regular(9.5, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
        }
        .padding(isCompact ? 16 : 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                wing.tint.opacity(colorScheme == .dark ? 0.10 : 0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(wing.tint.opacity(colorScheme == .dark ? 0.30 : 0.18), lineWidth: 1)
        )
        .shadow(
            color: wing.tint.opacity(colorScheme == .dark ? 0.18 : 0.06),
            radius: 8,
            y: 3
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func speciesMiniChip(_ species: String) -> some View {
        let icon: String = {
            switch species {
            case "dog": return "dog.fill"
            case "cat": return "cat.fill"
            case "bird": return "bird.fill"
            case "small_pets": return "hare.fill"
            default: return "pawprint.fill"
            }
        }()

        let title: String = {
            switch species {
            case "dog": return Language.get("Dogs", alter: "كلاب")
            case "cat": return Language.get("Cats", alter: "قطط")
            case "bird": return Language.get("Birds", alter: "طيور")
            case "small_pets": return Language.get("SmallPets", alter: "حيوانات صغيرة")
            default: return Language.get("Other", alter: "أخرى")
            }
        }()

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(PPBeirutiFont.bold(9, relativeTo: .caption2))
            Text(title)
                .font(PPBeirutiFont.bold(10, relativeTo: .caption2))
        }
        .foregroundStyle(wing.tint)
        .padding(.horizontal, 6.5)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(wing.tint.opacity(colorScheme == .dark ? 0.18 : 0.08))
        )
    }
}

// MARK: - Section: Tier Identity Bento Card
private struct AdminHotelTierIdentityCard: View {
    @Binding var code: String
    @Binding var nameAr: String
    @Binding var nameEn: String
    let wing: HotelWing

    @Environment(\.colorScheme) private var colorScheme

    private let quickCodes: [String] = ["VIP", "STD", "DLX", "ROYAL", "SUITE", "POD"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_TierDetails", alter: "تفاصيل الفئة الفندقية"), systemImage: "sparkles")
                .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                // Code Input + Quick Preset Chips
                VStack(alignment: .leading, spacing: 5) {
                    Text(Language.get("Hotel_Suites_TypeCode", alter: "كود الفئة (مثال: VIP / STD)"))
                        .font(PPBeirutiFont.medium(12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)

                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "number.square.fill")
                                .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                                .foregroundStyle(wing.tint)

                            TextField("VIP", text: $code)
                                .font(PPBeirutiFont.bold(15, relativeTo: .body))
                                .foregroundStyle(AdminSurface.primaryText)
                                .multilineTextAlignment(.leading)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                        )

                        // Quick code generator chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4.5) {
                                ForEach(quickCodes, id: \.self) { c in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        code = c
                                    } label: {
                                        Text(c)
                                            .font(PPBeirutiFont.bold(11, relativeTo: .caption2))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 6)
                                            .background(
                                                code.uppercased() == c
                                                    ? wing.tint
                                                    : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.white),
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            )
                                            .foregroundStyle(code.uppercased() == c ? Color.white : AdminSurface.primaryText)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }

                // Arabic Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Suites_NameAr", alter: "الاسم بالعربية"))
                        .font(PPBeirutiFont.medium(12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)

                    HStack(spacing: 6) {
                        Image(systemName: "character.bubble.fill")
                            .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(wing.tint)

                        TextField(Language.get("Hotel_Suites_NameArPlaceholder", alter: "مثال: جناح كبار الشخصيات VIP"), text: $nameAr)
                            .font(PPBeirutiFont.medium(14, relativeTo: .body))
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                    )
                }

                // English Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Suites_NameEn", alter: "الاسم بالإنجليزية"))
                        .font(PPBeirutiFont.medium(12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)

                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                            .foregroundStyle(wing.tint)

                        TextField(Language.get("Hotel_Suites_NameEnPlaceholder", alter: "e.g. VIP Presidential Suite"), text: $nameEn)
                            .font(PPBeirutiFont.medium(14, relativeTo: .body))
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                    )
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Section: Wing & Allowed Species Card
private struct AdminHotelWingAndSpeciesCard: View {
    @Binding var selectedWing: HotelWing
    @Binding var selectedSpecies: Set<String>

    @Environment(\.colorScheme) private var colorScheme

    private let allSpeciesList: [(id: String, title: String, icon: String)] = [
        ("dog", Language.get("Dogs", alter: "كلاب"), "dog.fill"),
        ("cat", Language.get("Cats", alter: "قطط"), "cat.fill"),
        ("bird", Language.get("Birds", alter: "طيور"), "bird.fill"),
        ("small_pets", Language.get("SmallPets", alter: "حيوانات صغيرة"), "hare.fill"),
        ("other", Language.get("Other", alter: "أخرى"), "pawprint.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Wing", alter: "الجناح والفصائل المصرح بها"), systemImage: "building.2.crop.circle.fill")
                .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 14) {
                // Wing Selection Grid
                AdminHotelWingSelectorGrid(
                    selectedWing: $selectedWing,
                    selectedSpecies: $selectedSpecies
                )

                Divider()

                // Allowed Species Multi-Select
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Suites_AllowedSpeciesTitle", alter: "فصائل النزلاء المصرح بها"))
                            .font(PPBeirutiFont.bold(13.5, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("Hotel_Suites_AllowedSpeciesDesc", alter: "حدد أنواع وفصائل الحيوانات المصرح بإقامتها في هذه الفئة"))
                            .font(PPBeirutiFont.regular(11, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    HStack(spacing: 6) {
                        ForEach(allSpeciesList, id: \.id) { spec in
                            let isSelected = selectedSpecies.contains(spec.id)

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if isSelected {
                                    if selectedSpecies.count > 1 {
                                        selectedSpecies.remove(spec.id)
                                    }
                                } else {
                                    selectedSpecies.insert(spec.id)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: spec.icon)
                                        .font(PPBeirutiFont.bold(11, relativeTo: .caption2))
                                    Text(spec.title)
                                        .font(PPBeirutiFont.bold(11.5, relativeTo: .caption2))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5.5)
                                .background(
                                    isSelected
                                        ? selectedWing.tint
                                        : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.white),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(isSelected ? selectedWing.tint : Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                                )
                                .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Component: Tactile Wing Selector Grid
private struct AdminHotelWingSelectorGrid: View {
    @Binding var selectedWing: HotelWing
    @Binding var selectedSpecies: Set<String>

    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.adaptive(minimum: 135), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(HotelWing.allCases) { wing in
                let isSelected = selectedWing == wing

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedWing = wing
                        syncDefaultSpecies(for: wing)
                    }
                } label: {
                    HStack(spacing: 7) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.22) : wing.tint.opacity(0.12))
                                .frame(width: 26, height: 26)

                            Image(systemName: wing.icon)
                                .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                                .foregroundStyle(isSelected ? Color.white : wing.tint)
                        }

                        Text(wing.title)
                            .font(PPBeirutiFont.bold(12.5, relativeTo: .caption))
                            .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 2)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(PPBeirutiFont.bold(11, relativeTo: .caption2))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? wing.tint : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.white))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? wing.tint : wing.tint.opacity(colorScheme == .dark ? 0.22 : 0.12), lineWidth: 0.8)
                    )
                    .shadow(color: isSelected ? wing.tint.opacity(0.28) : Color.clear, radius: 4, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func syncDefaultSpecies(for wing: HotelWing) {
        switch wing {
        case .dogs:
            if selectedSpecies.isEmpty || selectedSpecies == ["cat"] || selectedSpecies == ["bird"] {
                selectedSpecies = ["dog"]
            }
        case .cats:
            if selectedSpecies.isEmpty || selectedSpecies == ["dog"] || selectedSpecies == ["bird"] {
                selectedSpecies = ["cat"]
            }
        case .birds:
            if selectedSpecies.isEmpty || selectedSpecies == ["dog"] || selectedSpecies == ["cat"] {
                selectedSpecies = ["bird"]
            }
        case .smallPets:
            if selectedSpecies.isEmpty {
                selectedSpecies = ["small_pets"]
            }
        default:
            break
        }
    }
}

// MARK: - Section: Pricing Engine Card
private struct AdminHotelPricingEngineCard: View {
    @Binding var nightlyRateMajor: String
    let wing: HotelWing

    @Environment(\.colorScheme) private var colorScheme

    private let presets: [Double] = [35, 75, 120, 150, 250, 500]

    private var currentRate: Double {
        Double(nightlyRateMajor.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_PriceAndCapacity", alter: "السعر ومعدل الليلة"), systemImage: "banknote.fill")
                .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                // Steppers + Input Field
                HStack(spacing: 8) {
                    // Stepper -25
                    Button {
                        adjustRate(delta: -25)
                    } label: {
                        Text("-25")
                            .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(width: 44, height: 44)
                            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Stepper -10
                    Button {
                        adjustRate(delta: -10)
                    } label: {
                        Text("-10")
                            .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(width: 40, height: 44)
                            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Numeric Input Field
                    HStack(spacing: 4) {
                        TextField("150", text: $nightlyRateMajor)
                            .keyboardType(.numberPad)
                            .font(PPBeirutiFont.bold(26, relativeTo: .title))
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.center)
                            .monospacedDigit()

                        Text(Language.get("Currency_QAR", alter: "ر.ق"))
                            .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(wing.tint)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(wing.tint.opacity(0.28), lineWidth: 0.9)
                    )

                    // Stepper +10
                    Button {
                        adjustRate(delta: 10)
                    } label: {
                        Text("+10")
                            .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(width: 40, height: 44)
                            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Stepper +25
                    Button {
                        adjustRate(delta: 25)
                    } label: {
                        Text("+25")
                            .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(width: 44, height: 44)
                            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Quick Preset Chips
                VStack(alignment: .leading, spacing: 5) {
                    Text(Language.get("Hotel_Suites_PricePresetTitle", alter: "معدلات الأسعار الشائعة (ر.ق)"))
                        .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(presets, id: \.self) { val in
                                let isMatch = abs(currentRate - val) < 0.1

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    nightlyRateMajor = String(format: "%.0f", val)
                                } label: {
                                    HStack(spacing: 2.5) {
                                        Text(String(format: "%.0f", val))
                                            .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                                        Text(Language.get("Currency_QAR", alter: "ر.ق"))
                                            .font(PPBeirutiFont.medium(10, relativeTo: .caption2))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        isMatch
                                            ? wing.tint
                                            : (colorScheme == .dark ? Color.white.opacity(0.07) : Color.white),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isMatch ? wing.tint : Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                                    )
                                    .foregroundStyle(isMatch ? Color.white : AdminSurface.primaryText)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }

                // Estimation notice
                if currentRate > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(PPBeirutiFont.bold(11, relativeTo: .caption2))
                            .foregroundStyle(wing.tint)

                        Text(String(format: Language.get("Hotel_Suites_EstimateNotice", alter: "إقامة ليلتين: %@ • إقامة ٥ ليالٍ: %@"), String(format: "%.0f %@", currentRate * 2, Language.get("Currency_QAR", alter: "ر.ق")), String(format: "%.0f %@", currentRate * 5, Language.get("Currency_QAR", alter: "ر.ق"))))
                            .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(wing.tint.opacity(colorScheme == .dark ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func adjustRate(delta: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let updated = max(0, currentRate + delta)
        nightlyRateMajor = String(format: "%.0f", updated)
    }
}

// MARK: - Section: Capacity & Operational Rules Card
private struct AdminHotelCapacityAndRulesCard: View {
    @Binding var defaultCapacity: Int
    @Binding var allowSharedOccupancy: Bool
    @Binding var active: Bool
    let wing: HotelWing

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Suites_CapacitySettings", alter: "السعة وقواعد التشغيل"), systemImage: "slider.horizontal.3")
                .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 14) {
                // Capacity Stepper
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Suites_CapacityTitle", alter: "السعة الافتراضية للحيوانات"))
                            .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("Hotel_Suites_CapacityDesc", alter: "أقصى عدد حيوانات أليفة في الجناح الواحد"))
                            .font(PPBeirutiFont.regular(11, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 10) {
                        Button {
                            if defaultCapacity > 1 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                defaultCapacity -= 1
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                                .frame(width: 32, height: 32)
                                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white, in: Circle())
                                .overlay(Circle().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8))
                                .foregroundStyle(defaultCapacity > 1 ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.4))
                        }
                        .disabled(defaultCapacity <= 1)
                        .buttonStyle(PlainButtonStyle())

                        Text("\(defaultCapacity)")
                            .font(PPBeirutiFont.bold(18, relativeTo: .title3))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(minWidth: 24)
                            .monospacedDigit()

                        Button {
                            if defaultCapacity < 8 {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                defaultCapacity += 1
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(PPBeirutiFont.bold(13, relativeTo: .caption))
                                .frame(width: 32, height: 32)
                                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white, in: Circle())
                                .overlay(Circle().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8))
                                .foregroundStyle(defaultCapacity < 8 ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.4))
                        }
                        .disabled(defaultCapacity >= 8)
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Divider()

                // Shared Occupancy Toggle
                Toggle(isOn: $allowSharedOccupancy) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(Language.get("Hotel_Suites_SharedOccupancyTitle", alter: "السماح بالإقامة المشتركة"))
                                .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                                .foregroundStyle(AdminSurface.primaryText)

                            Text("🐾")
                                .font(PPBeirutiFont.regular(12, relativeTo: .caption))
                        }

                        Text(Language.get("Hotel_Suites_SharedOccupancyDesc", alter: "استضافة حيوانات متعددة من نفس العائلة في جناح واحد"))
                            .font(PPBeirutiFont.regular(11, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .tint(Color(uiColor: .ppSuccess))

                Divider()

                // Active Status Toggle
                Toggle(isOn: $active) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(active ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                                .frame(width: 7, height: 7)

                            Text(Language.get("Hotel_Suites_ActiveStatusTitle", alter: "تفعيل الفئة وجاهزيتها للحجز"))
                                .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                                .foregroundStyle(AdminSurface.primaryText)
                        }

                        Text(Language.get("Hotel_Suites_ActiveStatusDesc", alter: "الفئات المعطلة لن تظهر في اختيارات الحجز للعملاء"))
                            .font(PPBeirutiFont.regular(11, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
                .tint(AdminSurface.primary)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Section: Luxury Amenities & Description Card
private struct AdminHotelDescriptionCard: View {
    @Binding var descriptionText: String
    let wing: HotelWing

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Language.get("Hotel_Suites_DescriptionTitle", alter: "المزايا والتجهيزات الفاخرة (اختياري)"), systemImage: "text.quote")
                .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(alignment: .trailing, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if descriptionText.isEmpty {
                        Text(Language.get("Hotel_Suites_DescriptionPlaceholder", alter: "مثال: كاميرا بث مباشر 24/7، تكييف مستقل، حديقة خاصة، وجبات فاخرة..."))
                            .font(PPBeirutiFont.regular(13, relativeTo: .callout))
                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $descriptionText)
                        .font(PPBeirutiFont.regular(13.5, relativeTo: .body))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .padding(6)
                        .frame(minHeight: 74)
                }
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.8)
                )

                Text("\(descriptionText.count) / 500")
                    .font(PPBeirutiFont.regular(10.5, relativeTo: .caption2))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
