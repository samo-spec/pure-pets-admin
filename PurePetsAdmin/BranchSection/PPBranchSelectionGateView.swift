//
//  PPBranchSelectionGateView.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for PurePets Flagship Admin.
//  Category-defining Spatial Branch Selection Deck with Live Telemetry,
//  Instant Search, Active Context Showcase, and Backend Synchronization.
//

import SwiftUI

public struct PPBranchSelectionGateView: View {
    @ObservedObject var contextStore = BranchContextStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var selectedBranchAnimID: String? = nil
    @State private var isBeaconPulsing = false
    @State private var settingDefaultBranchID: String? = nil
    @State private var showDefaultSuccessToast = false

    public var customTitle: String? = nil
    public var customSubtitle: String? = nil
    public var selectedBranchID: String? = nil
    public var allowGlobalAccess: Bool = true
    public var onSelectBranch: ((PPBranchModel) -> Void)? = nil

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        selectedBranchID: String? = nil,
        allowGlobalAccess: Bool = true,
        onSelectBranch: ((PPBranchModel) -> Void)? = nil
    ) {
        self.customTitle = title
        self.customSubtitle = subtitle
        self.selectedBranchID = selectedBranchID
        self.allowGlobalAccess = allowGlobalAccess
        self.onSelectBranch = onSelectBranch
    }

    private var heroBranch: PPBranchModel? {
        if let selID = selectedBranchID, !selID.isEmpty {
            return contextStore.availableBranches.first { $0.branchID == selID } ?? contextStore.activeBranch
        }
        return contextStore.activeBranch
    }

    private var filteredBranches: [PPBranchModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return contextStore.availableBranches
        }
        return contextStore.availableBranches.filter { branch in
            branch.localizedName().lowercased().contains(query) ||
            branch.code.lowercased().contains(query) ||
            branch.address.lowercased().contains(query) ||
            branch.phone.lowercased().contains(query)
        }
    }

    public var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Background
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // ── Ambient Spatial Canopy Header ────────────────────
                        canopyHeader

                        // ── Real-Time Search & Filter Bar ────────────────────
                        searchBar

                        // ── Currently Active Horizon (Hero Card) ─────────────
                        if let current = heroBranch, searchText.isEmpty {
                            activeBranchHeroShowcase(branch: current)
                        }

                        // ── Global Enterprise Access Card (SuperAdmin) ────────
                        if contextStore.isGlobal && searchText.isEmpty && allowGlobalAccess && onSelectBranch == nil {
                            globalAccessOptionCard
                        }

                        // ── Available Branches Deck ──────────────────────────
                        availableBranchesDeck
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 60)
                }

                // Default Sync Toast
                if showDefaultSuccessToast {
                    defaultSuccessToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !contextStore.needsBranchSelection {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        }
                    }
                }
            }
            .interactiveDismissDisabled(contextStore.needsBranchSelection)
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            contextStore.reload()
            withAnimation(
                .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
            ) {
                isBeaconPulsing = true
            }
        }
    }

    // ── Canopy Header ─────────────────────────────────────────────────────

    private var canopyHeader: some View {
        VStack(spacing: 12) {
            // Layered Floating Architectural Beacon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AdminSurface.primary.opacity(isBeaconPulsing ? 0.28 : 0.12),
                                AdminSurface.primary.opacity(0.02)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 45
                        )
                    )
                    .frame(width: 86, height: 86)
                    .scaleEffect(isBeaconPulsing ? 1.08 : 0.95)

                Circle()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                    .overlay(
                        Circle()
                            .stroke(AdminSurface.primary.opacity(0.25), lineWidth: 1)
                    )

                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(customTitle ?? (Language.isRTL() ? "نطاق العمليات والفرع النشط" : "Operational Scope & Branch"))
                    .font(Font.custom("Beiruti-Bold", size: 22))
                    .foregroundColor(.primary)

                Text(customSubtitle ?? (Language.isRTL()
                     ? "حدد فرع العمل لربط العمليات، المخزون، ونقاط البيع. يتم تعيين الفرع المختار كافتراضي للعمليات السحابية."
                     : "Choose your active working branch. Operations, inventory, and POS run under this branch and sync as default."))
                    .font(Font.custom("Beiruti-Regular", size: 13.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // Telemetry Chips Row
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10))
                    Text("\(contextStore.availableBranches.count) " + (Language.isRTL() ? "فروع مصرح بها" : "Authorized Branches"))
                        .font(Font.custom("Beiruti-Bold", size: 11.5))
                }
                .foregroundColor(AdminSurface.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(AdminSurface.primary.opacity(0.08))
                .cornerRadius(6)

                if contextStore.isGlobal {
                    HStack(spacing: 4) {
                        Image(systemName: "globe.badge.chevron.backward")
                            .font(.system(size: 10))
                        Text(Language.isRTL() ? "وصول إداري شامل" : "Global Admin Access")
                            .font(Font.custom("Beiruti-Bold", size: 11.5))
                    }
                    .foregroundColor(.emerald600)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(Color.emerald600.opacity(0.1))
                    .cornerRadius(6)
                }
            }
        }
    }

    // ── Search & Filter Bar ───────────────────────────────────────────────

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            TextField(
                Language.isRTL() ? "بحث بالاسم، الرمز (PP-1)، أو العنوان..." : "Search by name, code, or address...",
                text: $searchText
            )
            .font(Font.custom("Beiruti-Medium", size: 14))
            .autocapitalization(.none)
            .disableAutocorrection(true)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.75)
        )
    }

    // ── Active Branch Hero Showcase ───────────────────────────────────────

    private func activeBranchHeroShowcase(branch: PPBranchModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(Color.emerald600.opacity(isBeaconPulsing ? 0.35 : 0.15))
                            .frame(width: 12, height: 12)
                            .scaleEffect(isBeaconPulsing ? 1.3 : 0.85)

                        Circle()
                            .fill(Color.emerald600)
                            .frame(width: 6, height: 6)
                    }

                    Text(onSelectBranch != nil
                         ? (Language.isRTL() ? "الفرع المختار حالياً" : "Currently Selected Branch")
                         : (Language.isRTL() ? "الفرع النشط حالياً للجلسة" : "Current Active Session Branch"))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(Color.emerald600)
                }

                Spacer()

                if branch.isDefault {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8.5))
                        Text(Language.isRTL() ? "الافتراضي للنظام" : "System Default")
                            .font(Font.custom("Beiruti-Bold", size: 10.5))
                    }
                    .foregroundColor(.amber600)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.amber600.opacity(0.12))
                    .cornerRadius(5)
                }
            }

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary)
                        .frame(width: 44, height: 44)
                        .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, x: 0, y: 3)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(branch.localizedName())
                            .font(Font.custom("Beiruti-Bold", size: 17))
                            .foregroundColor(.primary)

                        Text(branch.code)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.primary.opacity(0.1))
                            .cornerRadius(4)
                    }

                    if !branch.address.isEmpty {
                        Text(branch.address)
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AdminSurface.primary.opacity(0.35), lineWidth: 1.25)
        )
    }

    // ── Global Enterprise Access Card ─────────────────────────────────────

    private var globalAccessOptionCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            contextStore.clear()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.isRTL() ? "وصول شامل لكافة الفروع" : "Global Enterprise View")
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundColor(.primary)

                    Text(Language.isRTL()
                         ? "عرض جميع البيانات والعمليات دون تصفية جغرافية"
                         : "View all platform data without branch boundaries")
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if contextStore.activeBranch == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(contextStore.activeBranch == nil ? Color.blue.opacity(0.4) : Color(uiColor: .separator).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(CardPressFeedbackStyle())
    }

    // ── Available Branches Deck ───────────────────────────────────────────

    private var availableBranchesDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.isRTL() ? "الفروع المتاحة" : "Available Branches")
                    .font(Font.custom("Beiruti-Bold", size: 14.5))
                    .foregroundColor(AdminCommandInk.secondary)

                Spacer()

                Text("\(filteredBranches.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 4)

            if filteredBranches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "building.2.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(Language.isRTL() ? "لا توجد فروع مطابقة للبحث" : "No branches match your search")
                        .font(Font.custom("Beiruti-Medium", size: 13.5))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredBranches, id: \.branchID) { branch in
                        branchInteractiveCard(for: branch)
                    }
                }
            }
        }
    }

    private func branchInteractiveCard(for branch: PPBranchModel) -> some View {
        let isSelected: Bool = {
            if let selID = selectedBranchID, !selID.isEmpty {
                return branch.branchID == selID
            }
            return contextStore.activeBranch?.branchID == branch.branchID
        }()
        let isDefault = branch.isDefault || branch.branchID == contextStore.currentStaff?.defaultBranchID

        return Button {
            selectBranchWithFeedback(branch)
        } label: {
            HStack(spacing: 14) {
                // Leading Architecture Avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isSelected
                            ? LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [
                                    Color(uiColor: .tertiarySystemGroupedBackground),
                                    Color(uiColor: .secondarySystemGroupedBackground)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: isSelected ? AdminSurface.primary.opacity(0.3) : Color.clear, radius: 6, x: 0, y: 3)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "building.2.fill")
                        .font(.system(size: isSelected ? 22 : 19, weight: .bold))
                        .foregroundColor(isSelected ? .white : AdminSurface.primary)
                }

                // Center Information Stack
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(branch.localizedName())
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundColor(.primary)

                        Spacer()

                        Text(branch.code)
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(isSelected ? AdminSurface.primary : .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? AdminSurface.primary.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                    }

                    if !branch.address.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9.5))
                                .foregroundColor(Color(uiColor: .tertiaryLabel))
                            Text(branch.address)
                                .font(Font.custom("Beiruti-Regular", size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Bottom Badges Row
                    HStack(spacing: 6) {
                        if isDefault {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                Text(Language.isRTL() ? "الافتراضي" : "Default")
                                    .font(Font.custom("Beiruti-Bold", size: 10.5))
                            }
                            .foregroundColor(.amber600)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.amber600.opacity(0.12))
                            .cornerRadius(4)
                        }

                        HStack(spacing: 3) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 8))
                            Text(branch.localizedStockModeName())
                                .font(Font.custom("Beiruti-Medium", size: 10.5))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .cornerRadius(4)

                        if !branch.phone.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 7.5))
                                Text(branch.phone)
                                    .font(.system(size: 9.5, design: .monospaced))
                            }
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                        }
                    }
                }

                // Trailing Selection Cue
                VStack {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                    } else {
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(isSelected ? 0.07 : 0.03), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected
                        ? AdminSurface.primary
                        : Color(uiColor: .separator).opacity(0.3),
                        lineWidth: isSelected ? 1.75 : 0.6
                    )
            )
        }
        .buttonStyle(CardPressFeedbackStyle())
    }

    private func selectBranchWithFeedback(_ branch: PPBranchModel) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if let onSelect = onSelectBranch {
            onSelect(branch)
        } else {
            _ = contextStore.selectBranch(branch)
        }
        selectedBranchAnimID = branch.branchID

        // Smooth dismissal after brief visual confirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            dismiss()
        }
    }

    // ── Toast ─────────────────────────────────────────────────────────────

    private var defaultSuccessToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundColor(.amber600)
            Text(Language.isRTL() ? "تم تعيين الفرع كافتراضي في النظام" : "Branch set as default across system")
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Card Press Feedback Button Style

fileprivate struct CardPressFeedbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension Color {
    static let emerald600 = Color(red: 5/255, green: 150/255, blue: 105/255)
    static let amber600 = Color(red: 217/255, green: 119/255, blue: 6/255)
}

