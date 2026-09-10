//
//  CycleCountStudioView.swift
//  PurePetsAdmin
//
//  Category-defining Apple-grade Studio for Blind Cycle Counting,
//  Discrepancy Evaluation & Transactional Stock Reconciliation.
//  Crafted with distinct, bespoke architectures for iPhone & iPad.
//

import SwiftUI
import AudioToolbox
import FirebaseFunctions

private extension Color {
    static let emerald = Color(uiColor: .ppSuccess)
}

// MARK: - Main Container View

public struct CycleCountStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public let branchId: String
    public var onStockReconciled: (() -> Void)?

    // MARK: - Enums & Modes

    public enum StudioTab: String, CaseIterable, Identifiable {
        case count = "count"
        case review = "review"
        case history = "history"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .count:
                return Language.get("CycleCount_Tab_Count", alter: "العد الفعلي")
            case .review:
                return Language.get("CycleCount_Tab_Review", alter: "فحص الفروقات")
            case .history:
                return Language.get("CycleCount_Tab_History", alter: "سجل الجرد")
            }
        }

        public var iconName: String {
            switch self {
            case .count: return "checklist.checked"
            case .review: return "chart.pie.fill"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    public enum CountFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case counted = "counted"
        case pending = "pending"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: return Language.get("All", alter: "الكل")
            case .counted: return Language.get("CycleCount_Filter_Counted", alter: "تم العد")
            case .pending: return Language.get("CycleCount_Filter_Pending", alter: "بانتظار العد")
            }
        }
    }

    public enum ReviewFilter: String, CaseIterable, Identifiable {
        case all = "all"
        case discrepancies = "discrepancies"
        case shrinkage = "shrinkage"
        case surplus = "surplus"
        case matched = "matched"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: return Language.get("All", alter: "الكل")
            case .discrepancies: return Language.get("CycleCount_Filter_Discrepancies", alter: "فروقات فقط")
            case .shrinkage: return Language.get("CycleCount_Filter_Shrinkage", alter: "عجز / مفقود")
            case .surplus: return Language.get("CycleCount_Filter_Surplus", alter: "فائض / زيادة")
            case .matched: return Language.get("CycleCount_Filter_Matched", alter: "مطابق")
            }
        }
    }

    // MARK: - State

    @State private var selectedTab: StudioTab = .count
    @State private var activeSession: PPCycleCountSession? = nil
    @State private var pastSessions: [PPCycleCountSession] = []

    // Scope Setup
    @State private var selectedScope: String = "all"
    @State private var selectedCategory: String = ""
    @State private var shelfLocationInput: String = ""
    @State private var varianceThreshold: Int = 2

    // Active Counting State
    @State private var localCounts: [String: Int] = [:]
    @State private var itemNotes: [String: String] = [:]
    @State private var searchText: String = ""
    @State private var countFilter: CountFilter = .all
    @State private var showingScanner: Bool = false
    @State private var scannedFeedbackMessage: String? = nil

    // Direct Keypad Modal State
    @State private var itemForDirectInput: PPCycleCountItem? = nil
    @State private var directInputText: String = ""

    // Image Lookup Cache
    @State private var imageCache: [String: URL] = [:]

    // Review & Reconciliation
    @State private var reviewFilter: ReviewFilter = .all
    @State private var resolutionNotes: String = ""
    @State private var isReconciling: Bool = false

    // Operational Feedback
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successBanner: String? = nil

    private var isIPad: Bool {
        horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
    }

    // MARK: - Initialization

    public init(branchId: String, onStockReconciled: (() -> Void)? = nil) {
        self.branchId = branchId
        self.onStockReconciled = onStockReconciled
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar
                    tabSegmentedBar

                    if isLoading {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView().tint(AdminSurface.primary).scaleEffect(1.3)
                            Text(Language.get("Loading", alter: "جاري التحميل..."))
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        Spacer()
                    } else {
                        switch selectedTab {
                        case .count:
                            if let session = activeSession, session.status == "in_progress" {
                                if isIPad {
                                    iPadActiveCountingView(session: session)
                                } else {
                                    iPhoneActiveCountingView(session: session)
                                }
                            } else {
                                startSessionSetupView
                            }
                        case .review:
                            if let session = activeSession, session.status != "in_progress" {
                                discrepancyReviewView(session: session)
                            } else {
                                noActiveReviewPlaceholder
                            }
                        case .history:
                            historyListView
                        }
                    }
                }

                // Ambient Toast Feedback Banner
                if let success = successBanner {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                            Text(success)
                                .font(AdminType.calloutBold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: AdminRadius.card)
                                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        )
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .zIndex(20)
                }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingScanner) {
                barcodeScannerSheet
            }
            .sheet(item: $itemForDirectInput) { item in
                directKeypadEntrySheet(for: item)
            }
            .onAppear {
                loadInitialData()
                loadAccessoryImagesCache()
            }
        }
    }

    // MARK: - Sovereign Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Dismiss Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.card, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.5))
            }

            // Title & Branch Context Block
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("CycleCount_Studio_Title", alter: "استوديو جرد وتسوية المخزون"))
                    .font(AdminType.title3Bold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)

                    let branchTitle = BranchContextStore.shared.activeBranch?.localizedName() ?? branchId
                    Text(branchTitle)
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            Spacer()

            // Quick Laser Barcode Scope Button
            if activeSession?.status == "in_progress" {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showingScanner = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 15, weight: .bold))
                        Text(Language.get("Scan", alter: "مسح باركود"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.indigo, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color.indigo.opacity(0.35), radius: 8, y: 3)
                }
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 10)
        .background(AdminSurface.background)
    }

    // MARK: - Tab Segmented Control

    private var tabSegmentedBar: some View {
        HStack(spacing: 4) {
            ForEach(StudioTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        Text(tab.title)
                            .font(isSelected ? AdminType.captionBold : AdminType.caption)
                    }
                    .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: AdminRadius.small)
                                    .fill(AdminSurface.primary)
                                    .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AdminSurface.card)
        .cornerRadius(AdminRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.medium)
                .stroke(AdminSurface.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.bottom, 8)
    }

    // MARK: - 1. iPhone Active Counting View (One-Handed Ergonomic Deck)

    private func iPhoneActiveCountingView(session: PPCycleCountSession) -> some View {
        VStack(spacing: 0) {
            // Ambient Progress Telemetry Capsule
            telemetryHeroCapsule(session: session)
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.vertical, 6)

            // Search Bar & Filter Chips
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AdminSurface.secondaryText)
                    TextField(Language.get("Search_Placeholder", alter: "بحث بالاسم، الباركود أو الرمز..."), text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AdminType.subheadline)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AdminSurface.card)
                .cornerRadius(AdminRadius.medium)
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline, lineWidth: 0.5))

                // Count Filter Picker
                Menu {
                    ForEach(CountFilter.allCases) { f in
                        Button {
                            countFilter = f
                        } label: {
                            HStack {
                                Text(f.title)
                                if countFilter == f {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 15))
                        Text(countFilter.title)
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(countFilter == .all ? AdminSurface.secondaryText : AdminSurface.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AdminSurface.card)
                    .cornerRadius(AdminRadius.medium)
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline, lineWidth: 0.5))
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 4)

            // Blind Counting List
            let items = filteredItems(session: session)
            if items.isEmpty {
                Spacer()
                AdminEmptyStateView(
                    symbol: "tray",
                    title: Language.get("CycleCount_No_Items", alter: "لا توجد أصناف مطابقة"),
                    subtitle: Language.get("CycleCount_No_Items_Sub", alter: "جرّب تغيير البحث أو الفلتر")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: AdminSpacing.sm) {
                        ForEach(items) { item in
                            iPhoneTactileItemCard(item: item)
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                    .padding(.bottom, 96) // Space for sticky bottom bar
                }
            }

            // Bottom Sticky Frosted Action Bar
            iPhoneBottomActionBar(session: session)
        }
    }

    // MARK: - 2. iPad Active Counting View (Dual-Axis Command Tower)

    private func iPadActiveCountingView(session: PPCycleCountSession) -> some View {
        HStack(spacing: 0) {
            // Left Leading Telemetry & Command Tower (Width: 340)
            VStack(spacing: AdminSpacing.md) {
                iPadTelemetryTower(session: session)
                Spacer()

                // Submit Count Button in Sidebar
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    promptSubmitCountConfirmation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text(Language.get("CycleCount_Submit_Count", alter: "إنهاء الجرد واحتساب الفروقات"))
                            .font(AdminType.headlineBold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.emerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: AdminRadius.card)
                    )
                    .shadow(color: Color.green.opacity(0.35), radius: 8, y: 4)
                }
            }
            .padding(AdminSpacing.lg)
            .frame(width: 340)
            .background(AdminSurface.card.ignoresSafeArea())
            .overlay(
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(width: 0.5),
                alignment: .trailing
            )

            // Right Trailing Counting Grid Canvas
            VStack(spacing: 0) {
                // Top Search & Filter Bar
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AdminSurface.secondaryText)
                        TextField(Language.get("Search_Placeholder", alter: "بحث بالاسم، الباركود أو الرمز..."), text: $searchText)
                            .textFieldStyle(.plain)
                            .font(AdminType.subheadline)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AdminSurface.card)
                    .cornerRadius(AdminRadius.medium)
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline, lineWidth: 0.5))

                    // Filter Picker Segments
                    Picker("", selection: $countFilter) {
                        ForEach(CountFilter.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(.horizontal, AdminSpacing.lg)
                .padding(.vertical, 12)

                let items = filteredItems(session: session)
                if items.isEmpty {
                    Spacer()
                    AdminEmptyStateView(
                        symbol: "tray",
                        title: Language.get("CycleCount_No_Items", alter: "لا توجد أصناف مطابقة"),
                        subtitle: Language.get("CycleCount_No_Items_Sub", alter: "جرّب تغيير البحث أو الفلتر")
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 280), spacing: AdminSpacing.md),
                                GridItem(.flexible(minimum: 280), spacing: AdminSpacing.md)
                            ],
                            spacing: AdminSpacing.md
                        ) {
                            ForEach(items) { item in
                                iPadTactileItemCard(item: item)
                            }
                        }
                        .padding(AdminSpacing.lg)
                    }
                }
            }
        }
    }

    // MARK: - Telemetry Hero Capsule (iPhone)

    private func telemetryHeroCapsule(session: PPCycleCountSession) -> some View {
        let counted = countedItemsCount(session: session)
        let total = max(1, session.itemCount)
        let progress = min(1.0, Double(counted) / Double(total))

        return HStack(spacing: 14) {
            // Radial Mini Gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                    .frame(width: 46, height: 46)

                Circle()
                    .trim(from: 0.0, to: CGFloat(progress))
                    .stroke(
                        LinearGradient(
                            colors: [Color.green, Color.emerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 46, height: 46)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)

                Text(verbatim: "\(Int(progress * 100))%".normalizedEnglishDigits)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(Language.get("CycleCount_Progress_Title", alter: "التقدم في الجرد الفعلي"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(verbatim: "\(counted) / \(total) \(Language.get("Items", alter: "صنف"))".normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                }

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 5)
                        Capsule()
                            .fill(Color.green)
                            .frame(width: max(4, geo.size.width * CGFloat(progress)), height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.card)
        .cornerRadius(AdminRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .stroke(AdminSurface.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - iPad Telemetry Tower

    private func iPadTelemetryTower(session: PPCycleCountSession) -> some View {
        let counted = countedItemsCount(session: session)
        let total = max(1, session.itemCount)
        let progress = min(1.0, Double(counted) / Double(total))
        let totalUnits = localCounts.values.reduce(0, +)

        return VStack(spacing: AdminSpacing.lg) {
            // Big Radial Dial
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    .frame(width: 130, height: 130)

                Circle()
                    .trim(from: 0.0, to: CGFloat(progress))
                    .stroke(
                        LinearGradient(
                            colors: [Color.green, Color.emerald],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 130, height: 130)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)

                VStack(spacing: 2) {
                    Text(verbatim: "\(Int(progress * 100))%".normalizedEnglishDigits)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Completed", alter: "مكتمل"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .padding(.top, 8)

            // Statistics Grid
            VStack(spacing: AdminSpacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("CycleCount_Counted_Items", alter: "الأصناف المجرودة"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(verbatim: "\(counted) من \(total)".normalizedEnglishDigits)
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Language.get("CycleCount_Total_Units", alter: "إجمالي القطع"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(verbatim: "\(totalUnits)".normalizedEnglishDigits)
                            .font(AdminType.calloutBold)
                            .foregroundColor(Color.green)
                    }
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.cardElevated)
                .cornerRadius(AdminRadius.medium)

                // Scope Badge
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .foregroundColor(AdminSurface.primary)
                    Text("\(Language.get("Scope", alter: "النطاق")): \(session.scope == "all" ? Language.get("Full_Branch_Count", alter: "شامل للفرع") : session.scope)")
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Spacer()
                }
                .padding(AdminSpacing.sm)
                .background(AdminSurface.cardElevated)
                .cornerRadius(AdminRadius.small)
            }
        }
    }

    // MARK: - iPhone Tactile Item Card

    private func iPhoneTactileItemCard(item: PPCycleCountItem) -> some View {
        let current = localCounts[item.productId] ?? item.countedQuantity
        let isCounted = (localCounts[item.productId] != nil) || (item.countedQuantity > 0)
        let imageURL = imageCache[item.productId]

        return HStack(spacing: 12) {
            // Product Hero Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: AdminRadius.medium)
                    .fill(AdminSurface.cardElevated)
                    .frame(width: 62, height: 62)

                if let url = imageURL {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ProgressView().scaleEffect(0.7)
                    }
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium))
                } else {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                }
            }

            // Product Details Block
            VStack(alignment: .leading, spacing: 3) {
                Text(item.productName)
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !item.sku.isEmpty {
                        Text(verbatim: item.sku.normalizedEnglishDigits)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 4))
                    }

                    if !item.shelfLocation.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mappin")
                                .font(.system(size: 9))
                            Text(verbatim: item.shelfLocation.normalizedEnglishDigits)
                        }
                        .font(AdminType.caption2Bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                // Counted Status Pill
                if isCounted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text(verbatim: "\(Language.get("CycleCount_Counted_Badge", alter: "تم العد")): \(current) \(Language.get("Units", alter: "قطع"))".normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 2)
                } else {
                    Text(Language.get("CycleCount_Filter_Pending", alter: "بانتظار العد"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                        .padding(.top, 2)
                }
            }

            Spacer()

            // Tactical Stepper & Keypad Bubble
            HStack(spacing: 4) {
                // Decrement Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let updated = max(0, current - 1)
                    localCounts[item.productId] = updated
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(current > 0 ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.cardElevated, in: Circle())
                }
                .disabled(current == 0)

                // Numeric Keypad Trigger Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    directInputText = "\(current)"
                    itemForDirectInput = item
                } label: {
                    Text(verbatim: "\(current)".normalizedEnglishDigits)
                        .font(AdminType.headlineBold)
                        .foregroundColor(isCounted ? .white : AdminSurface.secondaryText)
                        .frame(minWidth: 38, minHeight: 34)
                        .background(
                            isCounted ? AdminSurface.primary : AdminSurface.cardElevated,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }

                // Increment Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    localCounts[item.productId] = current + 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.35), radius: 4, y: 2)
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .fill(isCounted ? AdminSurface.card : AdminSurface.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card)
                        .stroke(isCounted ? Color.green.opacity(0.35) : AdminSurface.hairline, lineWidth: isCounted ? 1.2 : 0.5)
                )
        )
    }

    // MARK: - iPad Tactile Item Card

    private func iPadTactileItemCard(item: PPCycleCountItem) -> some View {
        let current = localCounts[item.productId] ?? item.countedQuantity
        let isCounted = (localCounts[item.productId] != nil) || (item.countedQuantity > 0)
        let imageURL = imageCache[item.productId]

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Large Product Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: AdminRadius.medium)
                        .fill(AdminSurface.cardElevated)
                        .frame(width: 70, height: 70)

                    if let url = imageURL {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView().scaleEffect(0.8)
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium))
                    } else {
                        Image(systemName: "cube.box.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.productName)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if !item.sku.isEmpty {
                            Text(verbatim: "SKU: \(item.sku)".normalizedEnglishDigits)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        if !item.shelfLocation.isEmpty {
                            Text(verbatim: "• \(item.shelfLocation)".normalizedEnglishDigits)
                                .font(AdminType.captionBold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                Spacer()
            }

            Divider().background(AdminSurface.hairline)

            // Multiplier Quick Add Rail + Stepper
            HStack(spacing: 8) {
                // Stepper Controls
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    localCounts[item.productId] = max(0, current - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(AdminSurface.cardElevated, in: Circle())
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    directInputText = "\(current)"
                    itemForDirectInput = item
                } label: {
                    Text(verbatim: "\(current)".normalizedEnglishDigits)
                        .font(AdminType.title3Bold)
                        .foregroundColor(.white)
                        .frame(minWidth: 44, minHeight: 34)
                        .background(isCounted ? AdminSurface.primary : AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    localCounts[item.productId] = current + 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(AdminSurface.primary, in: Circle())
                }

                Spacer()

                // Quick Multiplier Pills
                ForEach([5, 10, 25], id: \.self) { delta in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        localCounts[item.productId] = current + delta
                    } label: {
                        Text("+\(delta)")
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AdminRadius.card)
                .fill(AdminSurface.card)
                .overlay(
                    RoundedRectangle(cornerRadius: AdminRadius.card)
                        .stroke(isCounted ? Color.green.opacity(0.35) : AdminSurface.hairline, lineWidth: isCounted ? 1.2 : 0.5)
                )
        )
    }

    // MARK: - iPhone Bottom Sticky Action Bar

    private func iPhoneBottomActionBar(session: PPCycleCountSession) -> some View {
        let counted = countedItemsCount(session: session)
        let total = session.itemCount

        return VStack(spacing: 8) {
            HStack {
                Text(verbatim: "\(Language.get("Progress", alter: "المنجز")): \(counted) / \(total) \(Language.get("Items", alter: "صنف"))".normalizedEnglishDigits)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text(verbatim: "\(Language.get("Remaining", alter: "المتبقي")): \(max(0, total - counted))".normalizedEnglishDigits)
                    .font(AdminType.caption)
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 4)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                promptSubmitCountConfirmation()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text(Language.get("CycleCount_Submit_Count", alter: "إنهاء الجرد الفعلي واحتساب الفروقات"))
                        .font(AdminType.headlineBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.emerald],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: AdminRadius.card)
                )
                .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
            }
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, AdminSpacing.md)
        .background(
            AdminSurface.background
                .overlay(
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(height: 0.5),
                    alignment: .top
                )
        )
    }

    // MARK: - Direct Numeric Keypad Studio (Reinvented for iPhone & iPad from First Principles)

    private func directKeypadEntrySheet(for item: PPCycleCountItem) -> some View {
        Group {
            if isIPad {
                iPadDirectKeypadStudio(item: item)
            } else {
                iPhoneDirectKeypadStudio(item: item)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - iPhone Tactile Quantity Studio
    private func iPhoneDirectKeypadStudio(item: PPCycleCountItem) -> some View {
        let current = Int(directInputText) ?? 0
        let expected = item.expectedOnHand ?? 0
        let delta = current - expected
        let impactCost = Double(abs(delta)) * item.costPrice
        let imageURL = imageCache[item.productId]

        return VStack(spacing: 0) {
            // Drag Indicator & Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("CycleCount_Keypad_Title", alter: "إدخال الكمية الفعلية"))
                        .font(AdminType.headlineBold)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(item.productName)
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    itemForDirectInput = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Specimen Identity Strip
            HStack(spacing: 12) {
                // Product Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.cardElevated)
                        .frame(width: 52, height: 52)

                    if let url = imageURL {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView().scaleEffect(0.7)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Image(systemName: "cube.box.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 0.8)
                )

                // Meta Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !item.sku.isEmpty {
                            Text(verbatim: item.sku.normalizedEnglishDigits)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 4))
                        }

                        if !item.shelfLocation.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 9))
                                Text(verbatim: item.shelfLocation.normalizedEnglishDigits)
                            }
                            .font(AdminType.caption2Bold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    HStack(spacing: 4) {
                        Text(Language.get("CycleCount_Keypad_Expected", alter: "الرصيد الدفتري") + ":")
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(verbatim: "\(expected)".normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("Units", alter: "وحدات"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Spacer()
            }
            .padding(10)
            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, 12)

            // Hero Count Telemetry Readout & Live Variance Pill
            VStack(spacing: 6) {
                Text(verbatim: directInputText.isEmpty ? "0" : directInputText.normalizedEnglishDigits)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundColor(AdminSurface.primaryText)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: directInputText)

                // Live Variance Telemetry Badge
                HStack(spacing: 6) {
                    if delta == 0 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.emerald)
                        Text(Language.get("CycleCount_Keypad_Matched_Badge", alter: "مطابق للرصيد الدفتري (0 فرق)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.emerald)
                    } else if delta < 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.crimson)
                        Text(verbatim: String(format: Language.get("CycleCount_Keypad_Shrinkage_Badge", alter: "عجز %d وحدة (خسارة %.2f ر.ق)"), abs(delta), impactCost).normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.crimson)
                    } else {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.amber)
                        Text(verbatim: String(format: Language.get("CycleCount_Keypad_Surplus_Badge", alter: "فائض +%d وحدة (+%.2f ر.ق)"), delta, impactCost).normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.amber)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.amber)).opacity(0.12),
                    in: Capsule()
                )
                .animation(.easeInOut(duration: 0.2), value: delta)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.amber)).opacity(0.3),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, 10)

            // Fast Accelerator Chips Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Match Expected Accelerator
                    Button {
                        handleKeypadMatchExpected(expected: expected)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "equal.circle.fill")
                                .font(.system(size: 13))
                            Text(verbatim: String(format: Language.get("CycleCount_Keypad_Match_Expected", alter: "المتوقع (%d)"), expected).normalizedEnglishDigits)
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(AdminSurface.primary.opacity(0.3), lineWidth: 0.8))
                    }

                    // Zero Out Accelerator (Out of Stock)
                    Button {
                        handleKeypadZeroOut()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slash.circle.fill")
                                .font(.system(size: 13))
                            Text(Language.get("CycleCount_Keypad_Zero_Out", alter: "0 (نفاذ الرف)"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(AdminSurface.crimson)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AdminSurface.crimson.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(AdminSurface.crimson.opacity(0.3), lineWidth: 0.8))
                    }

                    // Increment / Decrement Chips
                    ForEach([1, 5, 10], id: \.self) { plus in
                        Button {
                            handleKeypadDelta(plus)
                        } label: {
                            Text(verbatim: "+\(plus)".normalizedEnglishDigits)
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AdminSurface.cardElevated, in: Capsule())
                                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.8))
                        }
                    }

                    Button {
                        handleKeypadDelta(-1)
                    } label: {
                        Text(verbatim: "-1".normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AdminSurface.cardElevated, in: Capsule())
                            .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.8))
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
            }
            .padding(.bottom, 12)

            // Tactile Numeric Matrix (3x4 Grid)
            let keys: [[KeypadKey]] = [
                [.digit("1"), .digit("2"), .digit("3")],
                [.digit("4"), .digit("5"), .digit("6")],
                [.digit("7"), .digit("8"), .digit("9")],
                [.clear, .digit("0"), .backspace]
            ]

            VStack(spacing: 8) {
                ForEach(0..<keys.count, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(keys[row], id: \.id) { keyItem in
                            tactileKeypadButton(keyItem: keyItem, height: 50)
                        }
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)

            Spacer(minLength: 8)

            // Dynamic Sovereign Commit Button
            Button {
                commitDirectCount(for: item)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: delta == 0 ? "checkmark.circle.fill" : (delta < 0 ? "exclamationmark.triangle.fill" : "plus.circle.fill"))
                        .font(.system(size: 16, weight: .bold))

                    Text(verbatim: (delta == 0 ?
                        String(format: Language.get("CycleCount_Keypad_Commit_Matched", alter: "اعتماد الجرد (مطابق %d وحدة)"), current) :
                        String(format: Language.get("CycleCount_Keypad_Commit_Discrepancy", alter: "اعتماد الجرد (%d وحدة)"), current)
                    ).normalizedEnglishDigits)
                        .font(AdminType.headlineBold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.primary)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(
                    color: (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.primary)).opacity(0.3),
                    radius: 6, y: 3
                )
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.bottom, 14)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - iPad Tactical Command Console Studio
    private func iPadDirectKeypadStudio(item: PPCycleCountItem) -> some View {
        let current = Int(directInputText) ?? 0
        let expected = item.expectedOnHand ?? 0
        let delta = current - expected
        let impactCost = Double(abs(delta)) * item.costPrice
        let imageURL = imageCache[item.productId]

        return NavigationStack {
            VStack(spacing: 0) {
                // Top Sovereign Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("CycleCount_Keypad_Title", alter: "إدخال الكمية الفعلية"))
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("CycleCount_Keypad_Hardware_Hint", alter: "يمكنك استخدام لوحة المفاتيح الخارجية أو ماسح الباركود مباشرة"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        itemForDirectInput = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 14)

                Divider().background(AdminSurface.hairline)

                // 2-Wing Cockpit
                HStack(alignment: .top, spacing: 24) {
                    // LEFT WING (44%): Specimen Dossier, Economics, Financial Discrepancy Gauge, Accelerators
                    VStack(alignment: .leading, spacing: 14) {
                        // Product Specimen Dossier Card
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AdminSurface.cardElevated)
                                    .frame(width: 76, height: 76)

                                if let url = imageURL {
                                    AsyncImage(url: url) { img in
                                        img.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        ProgressView().scaleEffect(0.8)
                                    }
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                } else {
                                    Image(systemName: "cube.box.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
                            )

                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.productName)
                                    .font(AdminType.headlineBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .lineLimit(2)

                                HStack(spacing: 6) {
                                    if !item.sku.isEmpty {
                                        Text(verbatim: item.sku.normalizedEnglishDigits)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 4))
                                    }

                                    if !item.shelfLocation.isEmpty {
                                        HStack(spacing: 2) {
                                            Image(systemName: "mappin")
                                                .font(.system(size: 9))
                                            Text(verbatim: item.shelfLocation.normalizedEnglishDigits)
                                        }
                                        .font(AdminType.caption2Bold)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                    }
                                }

                                if !item.barcode.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "barcode.viewfinder")
                                            .font(.system(size: 10))
                                        Text(verbatim: item.barcode.normalizedEnglishDigits)
                                            .font(.system(size: 10, design: .monospaced))
                                    }
                                    .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                                }
                            }
                        }
                        .padding(14)
                        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 0.8)
                        )

                        // Economics Grid Card
                        HStack(spacing: 8) {
                            iPadMetricPill(
                                title: Language.get("CycleCount_Keypad_Expected", alter: "الرصيد الدفتري"),
                                value: "\(expected) " + Language.get("Units", alter: "وحدات"),
                                color: AdminSurface.primary
                            )

                            iPadMetricPill(
                                title: Language.get("CycleCount_Keypad_Unit_Cost", alter: "سعر التكلفة"),
                                value: String(format: "%.2f ر.ق", item.costPrice),
                                color: AdminSurface.secondaryText
                            )

                            iPadMetricPill(
                                title: Language.get("CycleCount_Keypad_Unit_Selling", alter: "سعر البيع"),
                                value: String(format: "%.2f ر.ق", item.sellingPrice),
                                color: AdminSurface.secondaryText
                            )
                        }

                        // Live Financial Discrepancy Impact Card
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(Language.get("CycleCount_Keypad_Financial_Impact", alter: "الأثر المالي للتسوية"))
                                    .font(AdminType.captionBold)
                                    .foregroundColor(AdminSurface.secondaryText)
                                Spacer()
                                if delta == 0 {
                                    Text("0.00 ر.ق")
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.emerald)
                                } else {
                                    Text(verbatim: String(format: "%@%.2f ر.ق", delta < 0 ? "-" : "+", impactCost).normalizedEnglishDigits)
                                        .font(AdminType.captionBold)
                                        .foregroundColor(delta < 0 ? AdminSurface.crimson : AdminSurface.amber)
                                }
                            }

                            HStack(spacing: 8) {
                                Image(systemName: delta == 0 ? "shield.checkmark.fill" : (delta < 0 ? "exclamationmark.triangle.fill" : "chart.line.uptrend.xyaxis.circle.fill"))
                                    .font(.system(size: 18))
                                    .foregroundColor(delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.amber))

                                Text(verbatim: (delta == 0 ?
                                    Language.get("CycleCount_Keypad_Matched_Badge", alter: "مطابق للرصيد الدفتري (0 فرق)") :
                                    (delta < 0 ?
                                        String(format: Language.get("CycleCount_Keypad_Shrinkage_Badge", alter: "عجز %d وحدة (خسارة %.2f ر.ق)"), abs(delta), impactCost) :
                                        String(format: Language.get("CycleCount_Keypad_Surplus_Badge", alter: "فائض +%d وحدة (+%.2f ر.ق)"), delta, impactCost)
                                    )
                                ).normalizedEnglishDigits)
                                    .font(AdminType.footnoteBold)
                                    .foregroundColor(delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.amber))
                            }
                        }
                        .padding(14)
                        .background(
                            (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.amber)).opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.amber)).opacity(0.3),
                                    lineWidth: 0.8
                                )
                        )

                        // Rapid Accelerators Dock
                        VStack(spacing: 8) {
                            Button {
                                handleKeypadMatchExpected(expected: expected)
                            } label: {
                                HStack {
                                    Image(systemName: "equal.circle.fill")
                                    Text(verbatim: String(format: Language.get("CycleCount_Keypad_Match_Expected", alter: "المتوقع (%d)"), expected).normalizedEnglishDigits)
                                        .font(AdminType.headlineBold)
                                    Spacer()
                                    Text("✓")
                                        .font(.system(size: 14, weight: .heavy))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            HStack(spacing: 8) {
                                Button {
                                    handleKeypadZeroOut()
                                } label: {
                                    HStack {
                                        Image(systemName: "slash.circle.fill")
                                        Text(Language.get("CycleCount_Keypad_Zero_Out", alter: "0 (نفاذ الرف)"))
                                            .font(AdminType.subheadlineBold)
                                    }
                                    .foregroundColor(AdminSurface.crimson)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AdminSurface.crimson.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.crimson.opacity(0.3), lineWidth: 0.8))
                                }

                                ForEach([1, 5, 10], id: \.self) { plus in
                                    Button {
                                        handleKeypadDelta(plus)
                                    } label: {
                                        Text(verbatim: "+\(plus)".normalizedEnglishDigits)
                                            .font(AdminType.subheadlineBold)
                                            .foregroundColor(AdminSurface.primaryText)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                    // Vertical Separator
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(width: 1)

                    // RIGHT WING (56%): Readout, Pro Tactile Matrix & Action Footer
                    VStack(spacing: 14) {
                        // Digital Readout
                        VStack(spacing: 4) {
                            Text(verbatim: directInputText.isEmpty ? "0" : directInputText.normalizedEnglishDigits)
                                .font(.system(size: 58, weight: .heavy, design: .rounded))
                                .foregroundColor(AdminSurface.primaryText)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: directInputText)

                            Text(verbatim: (delta == 0 ? ("✓ " + Language.get("CycleCount_Keypad_Matched_Badge", alter: "مطابق للرصيد الدفتري (0 فرق)")) :
                                (delta < 0 ?
                                    String(format: Language.get("CycleCount_Keypad_Shrinkage_Badge", alter: "عجز %d وحدة (خسارة %.2f ر.ق)"), abs(delta), impactCost) :
                                    String(format: Language.get("CycleCount_Keypad_Surplus_Badge", alter: "فائض +%d وحدة (+%.2f ر.ق)"), delta, impactCost)
                                )
                            ).normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.amber))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 0.8)
                        )

                        // Pro Keypad Matrix (3x4 Grid, 56pt height)
                        let keys: [[KeypadKey]] = [
                            [.digit("1"), .digit("2"), .digit("3")],
                            [.digit("4"), .digit("5"), .digit("6")],
                            [.digit("7"), .digit("8"), .digit("9")],
                            [.clear, .digit("0"), .backspace]
                        ]

                        VStack(spacing: 10) {
                            ForEach(0..<keys.count, id: \.self) { row in
                                HStack(spacing: 10) {
                                    ForEach(keys[row], id: \.id) { keyItem in
                                        tactileKeypadButton(keyItem: keyItem, height: 56)
                                    }
                                }
                            }
                        }

                        Spacer()

                        // Dual Action Buttons
                        HStack(spacing: 12) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                itemForDirectInput = nil
                            } label: {
                                Text(Language.get("Cancel", alter: "إلغاء"))
                                    .font(AdminType.headlineBold)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                            }

                            Button {
                                commitDirectCount(for: item)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text(verbatim: (delta == 0 ?
                                        String(format: Language.get("CycleCount_Keypad_Commit_Matched", alter: "اعتماد الجرد (مطابق %d وحدة)"), current) :
                                        String(format: Language.get("CycleCount_Keypad_Commit_Discrepancy", alter: "اعتماد الجرد (%d وحدة)"), current)
                                    ).normalizedEnglishDigits)
                                        .font(AdminType.headlineBold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.primary)),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                                .shadow(
                                    color: (delta == 0 ? AdminSurface.emerald : (delta < 0 ? AdminSurface.crimson : AdminSurface.primary)).opacity(0.3),
                                    radius: 6, y: 3
                                )
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .frame(minWidth: 720, minHeight: 560)
        .onKeyPress { press in
            if press.characters == "\r" || press.key == .return {
                commitDirectCount(for: item)
                return .handled
            } else if press.key == .escape {
                itemForDirectInput = nil
                return .handled
            } else if press.characters.count == 1, let char = press.characters.first, char.isNumber {
                handleKeypadPress(String(char))
                return .handled
            } else if press.key == .delete || press.key == .deleteForward {
                handleKeypadBackspace()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Keypad Helper Models & Handlers

    private enum KeypadKey: Identifiable {
        case digit(String)
        case clear
        case backspace

        var id: String {
            switch self {
            case .digit(let d): return "digit_\(d)"
            case .clear: return "clear"
            case .backspace: return "backspace"
            }
        }
    }

    private func tactileKeypadButton(keyItem: KeypadKey, height: CGFloat) -> some View {
        Button {
            switch keyItem {
            case .digit(let d):
                handleKeypadPress(d)
            case .clear:
                handleKeypadClear()
            case .backspace:
                handleKeypadBackspace()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(keyBackground(for: keyItem))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )

                switch keyItem {
                case .digit(let d):
                    Text(verbatim: d.normalizedEnglishDigits)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)
                case .clear:
                    Text(verbatim: "C")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(AdminSurface.crimson)
                case .backspace:
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(KeypadPressFeedbackStyle())
    }

    private func keyBackground(for key: KeypadKey) -> Color {
        switch key {
        case .digit:
            return AdminSurface.card
        case .clear:
            return AdminSurface.crimson.opacity(0.08)
        case .backspace:
            return AdminSurface.cardElevated
        }
    }

    private func handleKeypadPress(_ key: String) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        if directInputText == "0" && key != "0" {
            directInputText = key
        } else if directInputText.count < 6 {
            directInputText.append(key)
        }
    }

    private func handleKeypadClear() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        directInputText = ""
    }

    private func handleKeypadBackspace() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !directInputText.isEmpty {
            directInputText.removeLast()
        }
    }

    private func handleKeypadMatchExpected(expected: Int) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        directInputText = "\(expected)"
    }

    private func handleKeypadZeroOut() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        directInputText = "0"
    }

    private func handleKeypadDelta(_ change: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let current = Int(directInputText) ?? 0
        let updated = max(0, current + change)
        directInputText = "\(updated)"
    }

    private func commitDirectCount(for item: PPCycleCountItem) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let parsed = Int(directInputText) ?? 0
        localCounts[item.productId] = max(0, parsed)
        itemForDirectInput = nil
    }

    private func iPadMetricPill(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
            Text(verbatim: value.normalizedEnglishDigits)
                .font(AdminType.captionBold)
                .foregroundColor(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - 3. Discrepancy & Shrinkage Review Stage

    private func discrepancyReviewView(session: PPCycleCountSession) -> some View {
        ScrollView {
            VStack(spacing: AdminSpacing.lg) {
                // Executive Dashboard Cards
                LazyVGrid(
                    columns: isIPad
                        ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                        : [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: AdminSpacing.sm
                ) {
                    reviewMetricCard(
                        title: Language.get("CycleCount_Total_Shrinkage", alter: "العجز / المفقود"),
                        value: "\(session.totalShrinkageUnits) \(Language.get("Units", alter: "قطعة"))",
                        subvalue: String(format: "-%.2f ر.ق", session.totalShrinkageValue),
                        icon: "arrow.down.right.circle.fill",
                        color: .red
                    )

                    reviewMetricCard(
                        title: Language.get("CycleCount_Total_Surplus", alter: "الفائض / الزيادة"),
                        value: "\(session.totalSurplusUnits) \(Language.get("Units", alter: "قطعة"))",
                        subvalue: String(format: "+%.2f ر.ق", session.totalSurplusValue),
                        icon: "arrow.up.right.circle.fill",
                        color: .green
                    )

                    reviewMetricCard(
                        title: Language.get("CycleCount_Net_Variance", alter: "صافي الفروقات"),
                        value: "\(session.totalVariance > 0 ? "+" : "")\(session.totalVariance)",
                        subvalue: "\(session.discrepancyCount) \(Language.get("Items_With_Diff", alter: "صنف به فرق"))",
                        icon: "plus.forwardslash.minus",
                        color: session.totalVariance == 0 ? .green : .orange
                    )

                    reviewMetricCard(
                        title: Language.get("CycleCount_Accuracy_Score", alter: "نسبة دقة المخزون"),
                        value: String(format: "%.1f%%", session.accuracyRate),
                        subvalue: session.accuracyRate >= 95 ? Language.get("High_Accuracy", alter: "دقة ممتازة") : Language.get("Requires_Attention", alter: "تتطلب تدقيقاً"),
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        color: session.accuracyRate >= 95 ? .green : .orange
                    )
                }

                // Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ReviewFilter.allCases) { rf in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                reviewFilter = rf
                            } label: {
                                Text(rf.title)
                                    .font(AdminType.captionBold)
                                    .foregroundColor(reviewFilter == rf ? .white : AdminSurface.secondaryText)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(reviewFilter == rf ? AdminSurface.primary : AdminSurface.cardElevated, in: Capsule())
                            }
                        }
                    }
                }

                // Discrepancy Items List
                let items = filteredReviewItems(session: session)
                VStack(spacing: AdminSpacing.sm) {
                    ForEach(items) { item in
                        discrepancyCard(item: item)
                    }
                }

                // Resolution & Approval Console
                if session.status == "pending_review" {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Language.get("CycleCount_Resolution_Notes", alter: "ملاحظات وتفسير تسوية الفروقات"))
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primaryText)

                        TextField(Language.get("CycleCount_Notes_Placeholder", alter: "اكتب تقرير التسوية أو سبب الفروقات..."), text: $resolutionNotes)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                            .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline, lineWidth: 0.5))

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            promptReconcileConfirmation()
                        } label: {
                            HStack(spacing: 8) {
                                if isReconciling {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "checkmark.seal.fill")
                                    Text(Language.get("CycleCount_Approve_Reconcile", alter: "اعتماد وتطبيق التسوية في المخزون فوراً"))
                                        .font(AdminType.headlineBold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color.green, Color.emerald],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: AdminRadius.card)
                            )
                            .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
                        }
                        .disabled(isReconciling)
                    }
                    .padding(AdminSpacing.md)
                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                } else if session.status == "reconciled" {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Language.get("CycleCount_Status_Reconciled", alter: "تمت التسوية والترحيل الدفتري بنجاح"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(.green)
                            if let recBy = session.reconciledByName {
                                Text("\(Language.get("Approved_By", alter: "اعتمد بواسطة")): \(recBy)")
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }
                        Spacer()
                    }
                    .padding(AdminSpacing.md)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: AdminRadius.card))
                }
            }
            .padding(AdminSpacing.screenMargin)
        }
    }

    private func reviewMetricCard(title: String, value: String, subvalue: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 18))
                Spacer()
            }
            Text(value)
                .font(AdminType.headlineBold)
                .foregroundColor(AdminSurface.primaryText)
            Text(subvalue)
                .font(AdminType.captionBold)
                .foregroundColor(color)
            Text(title)
                .font(AdminType.caption)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 0.5))
    }

    private func discrepancyCard(item: PPCycleCountItem) -> some View {
        let variance = item.variance ?? 0
        let color: Color = variance < 0 ? .red : (variance > 0 ? .green : .gray)

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.productName)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    HStack(spacing: 6) {
                        Text(verbatim: item.sku.normalizedEnglishDigits)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AdminSurface.secondaryText)
                        if !item.shelfLocation.isEmpty {
                            Text("• \(item.shelfLocation)")
                                .font(AdminType.captionBold)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // Variance Pill Badge
                HStack(spacing: 4) {
                    Image(systemName: variance < 0 ? "arrow.down" : (variance > 0 ? "arrow.up" : "equal"))
                    Text(verbatim: "\(variance > 0 ? "+" : "")\(variance) \(Language.get("Units", alter: "وحدات"))".normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.15), in: Capsule())
                .foregroundColor(color)
            }

            Divider().background(AdminSurface.hairline)

            // Side by Side Comparison
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("CycleCount_Expected_Stock", alter: "الرصيد الدفتري"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(verbatim: "\(item.expectedOnHand ?? 0)".normalizedEnglishDigits)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("CycleCount_Counted_Stock", alter: "العدد الفعلي المجرود"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(verbatim: "\(item.countedQuantity)".normalizedEnglishDigits)
                        .font(AdminType.calloutBold)
                        .foregroundColor(color)
                }
            }

            if let costDiff = item.varianceCost, costDiff != 0 {
                HStack {
                    Text(Language.get("Financial_Impact", alter: "الأثر المالي:"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(verbatim: String(format: "%.2f ر.ق", costDiff).normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                        .foregroundColor(color)
                }
            }
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 0.5))
    }

    private var noActiveReviewPlaceholder: some View {
        VStack(spacing: AdminSpacing.md) {
            Spacer()
            AdminEmptyStateView(
                symbol: "chart.pie",
                title: Language.get("CycleCount_No_Review_Title", alter: "لا توجد نتائج جرد للمراجعة"),
                subtitle: Language.get("CycleCount_No_Review_Sub", alter: "قم بإجراء الجرد الفعلي ثم اضغط على إنهاء الجرد لعرض تقرير الفروقات والعجز.")
            )
            Spacer()
        }
    }

    // MARK: - 4. Setup / Scope View

    private var startSessionSetupView: some View {
        ScrollView {
            VStack(spacing: AdminSpacing.lg) {
                // Info Banner
                HStack(spacing: 12) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Language.get("CycleCount_Blind_Title", alter: "نظام الجرد الأعمى (Blind Counting)"))
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("CycleCount_Blind_Subtitle", alter: "يتم إخفاء الرصيد الدفتري لمنع الانحياز البشري. يتم احتساب الفروقات بعد انتهاء الجرد الفعلي."))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .padding(AdminSpacing.md)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(Color.indigo.opacity(0.3), lineWidth: 1))

                // Scope Picker Cards
                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    Text(Language.get("CycleCount_Scope_Title", alter: "نطاق الجرد"))
                        .font(AdminType.headlineBold)
                        .foregroundColor(AdminSurface.primaryText)

                    scopeCard(
                        id: "all",
                        title: Language.get("CycleCount_Scope_All", alter: "جرد شامل للفرع"),
                        subtitle: Language.get("CycleCount_Scope_All_Sub", alter: "جرد كافة أصناف ومنتجات الفرع بلا استثناء"),
                        icon: "cube.box.fill",
                        color: .blue
                    )

                    scopeCard(
                        id: "category",
                        title: Language.get("CycleCount_Scope_Category", alter: "جرد قسم / تصنيف محدد"),
                        subtitle: Language.get("CycleCount_Scope_Category_Sub", alter: "التركيز على فئة معينة (أطعمة، مستلزمات، أدوية)"),
                        icon: "folder.fill",
                        color: .orange
                    )

                    scopeCard(
                        id: "shelf",
                        title: Language.get("CycleCount_Scope_Shelf", alter: "جرد رف / موقع تخزين"),
                        subtitle: Language.get("CycleCount_Scope_Shelf_Sub", alter: "جرد موقع تخزين أو رف معين داخل الفرع"),
                        icon: "books.vertical.fill",
                        color: .teal
                    )
                }

                if selectedScope == "category" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Category", alter: "اسم القسم"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        TextField(Language.get("CycleCount_Category_Placeholder", alter: "أدخل اسم القسم (مثال: طعام قطط)..."), text: $selectedCategory)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                    }
                } else if selectedScope == "shelf" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Shelf_Location", alter: "رمز الرف / الموقع"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        TextField(Language.get("CycleCount_Shelf_Placeholder", alter: "أدخل رمز الرف (مثال: A-02-01)..."), text: $shelfLocationInput)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                    }
                }

                // Variance Threshold Stepper
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    HStack {
                        Text(Language.get("CycleCount_Threshold_Title", alter: "حد الفروقات المسموح به"))
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                        Text(verbatim: "±\(varianceThreshold) \(Language.get("Units", alter: "وحدات"))".normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(.orange)
                    }
                    Text(Language.get("CycleCount_Threshold_Sub", alter: "الفروقات التي تتجاوز هذا الحد تتطلب اعتماداً صريحاً من المدير."))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Stepper("", value: $varianceThreshold, in: 0...20)
                        .labelsHidden()
                }
                .padding(AdminSpacing.md)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card))

                // Start Session CTA
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    executeCreateSession()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 18))
                        Text(Language.get("CycleCount_Start_Session", alter: "بدء جلسة الجرد الفعلي"))
                            .font(AdminType.headlineBold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                    .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, y: 4)
                }

                if let err = errorMessage {
                    AdminErrorBanner(message: err)
                }
            }
            .padding(AdminSpacing.screenMargin)
        }
    }

    private func scopeCard(id: String, title: String, subtitle: String, icon: String, color: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedScope = id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(subtitle)
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                Image(systemName: selectedScope == id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(selectedScope == id ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.3))
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card)
                    .stroke(selectedScope == id ? AdminSurface.primary : AdminSurface.hairline, lineWidth: selectedScope == id ? 1.5 : 0.5)
            )
        }
    }

    // MARK: - 5. History List View

    private var historyListView: some View {
        ScrollView {
            LazyVStack(spacing: AdminSpacing.sm) {
                if pastSessions.isEmpty {
                    AdminEmptyStateView(
                        symbol: "clock.arrow.circlepath",
                        title: Language.get("CycleCount_No_History", alter: "لا توجد جلسات جرد سابقة"),
                        subtitle: Language.get("CycleCount_No_History_Sub", alter: "ستظهر جلسات الجرد المكتملة هنا.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(pastSessions) { session in
                        historySessionCard(session: session)
                    }
                }
            }
            .padding(AdminSpacing.screenMargin)
        }
    }

    private func historySessionCard(session: PPCycleCountSession) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeSession = session
            selectedTab = .review
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: session.id.normalizedEnglishDigits)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(session.scope == "all" ? Language.get("Full_Branch_Count", alter: "جرد شامل للفرع") : "\(Language.get("Scope", alter: "نطاق")): \(session.scope)")
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    Spacer()
                    historyStatusBadge(status: session.status)
                }

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                        Text(verbatim: "\(session.itemCount) \(Language.get("Items", alter: "أصناف"))".normalizedEnglishDigits)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(verbatim: "\(session.discrepancyCount) \(Language.get("Diffs", alter: "فروقات"))".normalizedEnglishDigits)
                    }
                    Spacer()
                    if let date = session.createdAt {
                        Text(date, style: .date)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .font(AdminType.caption)
                .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(AdminSpacing.md)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline, lineWidth: 0.5))
        }
    }

    private func historyStatusBadge(status: String) -> some View {
        let (title, color): (String, Color) = {
            switch status {
            case "in_progress": return (Language.get("In_Progress", alter: "قيد الجرد"), .blue)
            case "pending_review": return (Language.get("Pending_Review", alter: "قيد التدقيق"), .orange)
            case "reconciled": return (Language.get("Reconciled", alter: "تمت التسوية"), .green)
            default: return (status, .gray)
            }
        }()

        return Text(title)
            .font(AdminType.captionBold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundColor(color)
    }

    // MARK: - Barcode Scanner Sheet

    private var barcodeScannerSheet: some View {
        ZStack {
            POSBarcodeCameraView(
                onResult: { code in
                    handleScannedCode(code)
                },
                onFailure: {
                    showingScanner = false
                }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        showingScanner = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6), in: Circle())
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                if let msg = scannedFeedbackMessage {
                    Text(msg)
                        .font(AdminType.calloutBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.95), in: Capsule())
                        .shadow(color: .green.opacity(0.4), radius: 10, y: 4)
                        .padding(.bottom, 50)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Networking & Business Logic

    private func loadInitialData() {
        isLoading = true
        PPBranchInventoryService.shared.fetchCycleCounts(branchId: branchId) { result in
            Task { @MainActor in
                self.isLoading = false
                if case .success(let sessions) = result {
                    self.pastSessions = sessions
                    if let ongoing = sessions.first(where: { $0.status == "in_progress" || $0.status == "pending_review" }) {
                        self.activeSession = ongoing
                        self.selectedTab = (ongoing.status == "in_progress") ? .count : .review
                    }
                }
            }
        }
    }

    private func loadAccessoryImagesCache() {
        AccessoryManager.shared().observeAllAccessories { items, _ in
            guard let items = items else { return }
            var map: [String: URL] = [:]
            for acc in items {
                if let url = PetAccessory.firstImageURL(for: acc) {
                    map[acc.accessoryID] = url
                }
            }
            Task { @MainActor in
                self.imageCache = map
            }
        }
    }

    // MARK: - Confirmation Dialogs via PPAlertHelper

    private func promptSubmitCountConfirmation() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("CycleCount_Confirm_Submit_Title", alter: "إنهاء الجرد الفعلي"),
            subtitle: Language.get("CycleCount_Confirm_Submit_Message", alter: "هل انتهيت من عد الأصناف؟ سيتم تجميد الأعداد واحتساب العجز والفائض."),
            confirmButton: Language.get("CycleCount_Confirm_Submit_Action", alter: "إرسال الجرد واحتساب الفروقات"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "checkmark.circle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                self.executeSubmitCount()
            },
            cancelBlock: nil
        )
    }

    private func promptReconcileConfirmation() {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("CycleCount_Confirm_Reconcile_Title", alter: "اعتماد وتسوية المخزون"),
            subtitle: Language.get("CycleCount_Confirm_Reconcile_Message", alter: "سيتم تعديل رصيد المخزون الدفتري في الفرع والكتالوج وتوليد قيود دفتر الأستاذ غير القابلة للتعديل."),
            confirmButton: Language.get("CycleCount_Confirm_Reconcile_Action", alter: "تطبيق التسوية في المخزون فوراً"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "arrow.triangle.2.circlepath.circle.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                self.executeReconcile()
            },
            cancelBlock: nil
        )
    }

    private func executeCreateSession() {
        isLoading = true
        errorMessage = nil

        PPBranchInventoryService.shared.createCycleCountSession(
            branchId: branchId,
            scope: selectedScope,
            category: selectedScope == "category" ? selectedCategory : nil,
            shelfLocation: selectedScope == "shelf" ? shelfLocationInput : nil,
            varianceThreshold: varianceThreshold
        ) { result in
            Task { @MainActor in
                self.isLoading = false
                switch result {
                case .success(let session):
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.activeSession = session
                    self.localCounts.removeAll()
                    self.selectedTab = .count
                    self.showBanner(Language.get("CycleCount_Session_Started", alter: "تم بدء جلسة الجرد بنجاح."))
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.get("Success", alter: "تم بنجاح"),
                        subtitle: Language.get("CycleCount_Session_Started", alter: "تم بدء جلسة الجرد بنجاح.")
                    )
                case .failure(let error):
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    let err = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    self.errorMessage = err
                    PPAlertHelper.showError(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ"),
                        subtitle: err
                    )
                }
            }
        }
    }

    private func executeSubmitCount() {
        guard let session = activeSession else { return }
        isLoading = true
        errorMessage = nil

        let countsPayload: [[String: Any]] = session.items.map { item in
            let c = localCounts[item.productId] ?? item.countedQuantity
            let notes = itemNotes[item.productId] ?? ""
            return [
                "productId": item.productId,
                "countedQuantity": c,
                "notes": notes
            ]
        }

        PPBranchInventoryService.shared.submitCycleCount(
            auditId: session.id,
            branchId: branchId,
            counts: countsPayload
        ) { result in
            Task { @MainActor in
                self.isLoading = false
                switch result {
                case .success(let updated):
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.activeSession = updated
                    self.selectedTab = .review
                    self.showBanner(Language.get("CycleCount_Submitted_Success", alter: "تم احتساب الفروقات بنجاح."))
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.get("Success", alter: "تم بنجاح"),
                        subtitle: Language.get("CycleCount_Submitted_Success", alter: "تم احتساب الفروقات بنجاح.")
                    )
                case .failure(let error):
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    let err = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    self.errorMessage = err
                    PPAlertHelper.showError(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ"),
                        subtitle: err
                    )
                }
            }
        }
    }

    private func executeReconcile() {
        guard let session = activeSession else { return }
        isReconciling = true
        errorMessage = nil

        PPBranchInventoryService.shared.reconcileCycleCount(
            auditId: session.id,
            branchId: branchId,
            resolutionNotes: resolutionNotes
        ) { result in
            Task { @MainActor in
                self.isReconciling = false
                switch result {
                case .success:
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.showBanner(Language.get("CycleCount_Reconciled_Success", alter: "تم اعتماد وتسوية المخزون بنجاح."))
                    PPAlertHelper.showSuccess(
                        in: nil,
                        title: Language.get("Success", alter: "تم بنجاح"),
                        subtitle: Language.get("CycleCount_Reconciled_Success", alter: "تم اعتماد وتسوية المخزون بنجاح.")
                    )
                    self.onStockReconciled?()
                    self.loadInitialData()
                case .failure(let error):
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    let err = PPBranchInventoryErrorHelper.localizedMessage(for: error)
                    self.errorMessage = err
                    PPAlertHelper.showError(
                        in: nil,
                        title: Language.get("Error", alter: "خطأ"),
                        subtitle: err
                    )
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        guard let session = activeSession else { return }
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if let matching = session.items.first(where: { $0.barcode == clean || $0.sku == clean }) {
            let current = localCounts[matching.productId] ?? matching.countedQuantity
            localCounts[matching.productId] = current + 1

            AudioServicesPlaySystemSound(1057) // Beep/shutter
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                scannedFeedbackMessage = "\(matching.productName) (+1)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    self.scannedFeedbackMessage = nil
                }
            }
        }
    }

    private func showBanner(_ message: String) {
        withAnimation {
            successBanner = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                self.successBanner = nil
            }
        }
    }

    // MARK: - Helpers & Filtering

    private func countedItemsCount(session: PPCycleCountSession) -> Int {
        session.items.filter { (localCounts[$0.productId] ?? $0.countedQuantity) > 0 }.count
    }

    private func filteredItems(session: PPCycleCountSession) -> [PPCycleCountItem] {
        var result = session.items
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.productName.lowercased().contains(q) ||
                $0.sku.lowercased().contains(q) ||
                $0.barcode.lowercased().contains(q) ||
                $0.shelfLocation.lowercased().contains(q)
            }
        }
        switch countFilter {
        case .all: break
        case .counted:
            result = result.filter { (localCounts[$0.productId] ?? $0.countedQuantity) > 0 }
        case .pending:
            result = result.filter { (localCounts[$0.productId] ?? $0.countedQuantity) == 0 }
        }
        return result
    }

    private func filteredReviewItems(session: PPCycleCountSession) -> [PPCycleCountItem] {
        switch reviewFilter {
        case .all:
            return session.items
        case .discrepancies:
            return session.items.filter { ($0.variance ?? 0) != 0 }
        case .shrinkage:
            return session.items.filter { ($0.variance ?? 0) < 0 }
        case .surplus:
            return session.items.filter { ($0.variance ?? 0) > 0 }
        case .matched:
            return session.items.filter { ($0.variance ?? 0) == 0 }
        }
    }
}

// MARK: - Keypad Tactile Press Feedback Style

private struct KeypadPressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
