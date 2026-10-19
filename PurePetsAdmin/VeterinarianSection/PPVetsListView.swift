import SwiftUI
import FirebaseFirestore

// MARK: - Filter Scope Enum

enum VetFilterScope: Int, CaseIterable, Identifiable {
    case all = 0
    case clinics
    case doctors
    case premium
    case attention

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .all: return "Vet_Filter_All"
        case .clinics: return "AdminVet_Filter_Clinics"
        case .doctors: return "AdminVet_Filter_Doctors"
        case .premium: return "AdminVet_Filter_Premium"
        case .attention: return "AdminVet_Filter_Suspended"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .clinics: return "building.2.crop.circle.fill"
        case .doctors: return "stethoscope.circle.fill"
        case .premium: return "crown.fill"
        case .attention: return "exclamationmark.shield.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .all: return Color(red: 0.08, green: 0.72, blue: 0.65)
        case .clinics: return Color(red: 0.12, green: 0.68, blue: 0.88)
        case .doctors: return Color(red: 0.08, green: 0.72, blue: 0.65)
        case .premium: return Color(red: 0.95, green: 0.68, blue: 0.18)
        case .attention: return Color(red: 0.92, green: 0.35, blue: 0.28)
        }
    }
}

extension PPVetModel: @unchecked Sendable {}

// MARK: - Sovereign Presentation Sheets

enum VetPresentedSheet: Identifiable {
    case add
    case edit(PPVetModel)
    case detail(PPVetModel)
    case subscription(PPVetModel)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let vet): return "edit_\(vet.vetID)"
        case .detail(let vet): return "detail_\(vet.vetID)"
        case .subscription(let vet): return "sub_\(vet.vetID)"
        }
    }
}

// MARK: - Store / ViewModel

@MainActor
final class PPVeterinarianManagementStore: ObservableObject {
    static let shared = PPVeterinarianManagementStore()

    @Published private(set) var allVets: [PPVetModel] = []
    @Published private(set) var filteredVets: [PPVetModel] = []
    @Published var searchText: String = ""
    @Published var activeFilter: VetFilterScope = .all
    @Published private(set) var isLoading: Bool = true
    @Published var shouldPresentAddVet: Bool = false

    private var listener: AnyObject?

    var totalCount: Int { allVets.count }
    var activeCount: Int { allVets.filter { !$0.isDisabled }.count }
    var disabledCount: Int { allVets.filter { $0.isDisabled }.count }
    var clinicsCount: Int { allVets.filter { $0.type == .company }.count }
    var doctorsCount: Int { allVets.filter { $0.type == .personal }.count }
    var premiumCount: Int { allVets.filter { $0.subscriptionTier == .premium }.count }
    var basicCount: Int { allVets.filter { $0.subscriptionTier == .basic }.count }
    var freeCount: Int { allVets.filter { $0.subscriptionTier == .free }.count }

    var expiringSoonCount: Int {
        allVets.filter { vet in
            if vet.isSubscriptionExpired() { return true }
            guard let endDate = vet.subscriptionEndDate else { return false }
            return endDate.timeIntervalSinceNow < (7 * 86400)
        }.count
    }

    var activeUptimePercent: Int {
        guard totalCount > 0 else { return 100 }
        return Int(round(Double(activeCount) / Double(totalCount) * 100.0))
    }

    var averageCost: Double {
        let valid = allVets.map(\.vetCost).filter { $0 > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0, +) / Double(valid.count)
    }

    init() {}

    func startListening() {
        guard listener == nil else { return }
        isLoading = allVets.isEmpty
        listener = PPVetManager.shared().observeAllVets { [weak self] vets, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.allVets = vets ?? []
                self.isLoading = false
                self.applyFilter()
            }
        }
    }

    func stopListening() {
        (listener as? ListenerRegistration)?.remove()
        listener = nil
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = allVets.filter { vet in
            switch activeFilter {
            case .all:
                break
            case .clinics:
                if vet.type != .company { return false }
            case .doctors:
                if vet.type != .personal { return false }
            case .premium:
                if vet.subscriptionTier != .premium { return false }
            case .attention:
                let isExpiring = vet.isSubscriptionExpired() ||
                    (vet.subscriptionEndDate != nil && vet.subscriptionEndDate!.timeIntervalSinceNow < 7 * 86400)
                if !vet.isDisabled && !isExpiring { return false }
            }

            guard !query.isEmpty else { return true }
            let name = (vet.title ?? "").lowercased()
            let desc = (vet.descriptionText ?? "").lowercased()
            let phone = (vet.phone ?? "").lowercased()
            let whatsapp = (vet.whatsapp ?? "").lowercased()
            let costString = String(format: "%.0f", vet.vetCost)
            return name.contains(query) || desc.contains(query) || phone.contains(query) || whatsapp.contains(query) || costString.contains(query)
        }

        result.sort { a, b in
            if a.isDisabled != b.isDisabled { return !a.isDisabled }
            if a.subscriptionTier != b.subscriptionTier { return a.subscriptionTier.rawValue > b.subscriptionTier.rawValue }
            return (a.title ?? "").localizedCaseInsensitiveCompare(b.title ?? "") == .orderedAscending
        }

        filteredVets = result
    }

    func refresh() async {
        await withCheckedContinuation { continuation in
            PPVetManager.shared().fetchAllVets { [weak self] vets, _ in
                Task { @MainActor in
                    self?.allVets = vets ?? []
                    self?.applyFilter()
                    continuation.resume()
                }
            }
        }
    }

    func toggleDisabled(for vet: PPVetModel) {
        let newState = !vet.isDisabled
        // Optimistic local update
        if let idx = allVets.firstIndex(where: { $0.vetID == vet.vetID }) {
            allVets[idx].isDisabled = newState
            applyFilter()
        }
        PPVetManager.shared().setDisabled(newState, forVetID: vet.vetID, completion: nil)
    }

    func deleteVet(_ vet: PPVetModel) {
        allVets.removeAll(where: { $0.vetID == vet.vetID })
        applyFilter()
        PPVetManager.shared().deleteVet(vet, completion: nil)
    }

    func count(for scope: VetFilterScope) -> Int {
        switch scope {
        case .all: return totalCount
        case .clinics: return clinicsCount
        case .doctors: return doctorsCount
        case .premium: return premiumCount
        case .attention: return disabledCount + expiringSoonCount
        }
    }
}

// MARK: - Legacy View Model Alias

typealias PPVetsListViewModel = PPVeterinarianManagementStore

// MARK: - Category-Defining Sovereign Screen

@MainActor
struct PPVeterinarianManagementScreen: View {
    var onDismiss: (() -> Void)?
    var onPushViewController: ((UIViewController) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var store = PPVeterinarianManagementStore.shared

    @State private var presentedSheet: VetPresentedSheet?
    @State private var vetToConfirmToggle: PPVetModel?
    @State private var vetToConfirmDelete: PPVetModel?
    @State private var isPulsingBeacon: Bool = false
    @State private var hasAppeared: Bool = false

    init(
        onPushViewController: ((UIViewController) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.onPushViewController = onPushViewController
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            navigationBarHeader

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    clinicalRadarHorizon
                    filterMatrixIsland
                    searchTerminalBar
                    contentDossierGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 48)
            }
            .refreshable {
                await store.refresh()
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            store.startListening()
            if store.shouldPresentAddVet {
                store.shouldPresentAddVet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigate(to: .add)
                }
            }
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) {
                hasAppeared = true
            }
        }
        .onDisappear {
            store.stopListening()
        }
        .onChange(of: store.searchText) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                store.applyFilter()
            }
        }
        .onChange(of: store.activeFilter) { _ in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                store.applyFilter()
            }
        }
        .fullScreenCover(item: $presentedSheet) { sheet in
            switch sheet {
            case .add:
                PPVetEditorStudioScreen(
                    vetToEdit: nil,
                    onDismiss: { presentedSheet = nil },
                    onSaved: { _ in
                        Task { await store.refresh() }
                    }
                )

            case .edit(let vet):
                PPVetEditorStudioScreen(
                    vetToEdit: vet,
                    onDismiss: { presentedSheet = nil },
                    onSaved: { _ in
                        Task { await store.refresh() }
                    }
                )

            case .detail(let vet):
                PPVetDetailDossierScreen(
                    vet: vet,
                    onDismiss: { presentedSheet = nil },
                    onEdit: { editVet in
                        presentedSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            presentedSheet = .edit(editVet)
                        }
                    },
                    onSubscription: { subVet in
                        presentedSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            presentedSheet = .subscription(subVet)
                        }
                    },
                    onUpdated: { _ in
                        Task { await store.refresh() }
                    }
                )
                .ignoresSafeArea()

            case .subscription(let vet):
                PPVetSubscriptionManagementScreen(
                    vet: vet,
                    onDismiss: { presentedSheet = nil },
                    onSaved: { _ in
                        Task { await store.refresh() }
                    }
                )
                .ignoresSafeArea()
            }
        }
        .confirmationDialog(
            Language.get("Vet_Confirm_Delete_Title", alter: "حذف الطبيب البيطري أو العيادة؟"),
            isPresented: Binding(
                get: { vetToConfirmDelete != nil },
                set: { if !$0 { vetToConfirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(Language.get("Delete", alter: "حذف نهائي"), role: .destructive) {
                if let vet = vetToConfirmDelete {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.deleteVet(vet)
                }
                vetToConfirmDelete = nil
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                vetToConfirmDelete = nil
            }
        } message: {
            Text(Language.get("Vet_Confirm_Delete_Msg", alter: "لا يمكن التراجع عن هذا الإجراء. ستتم إزالة بيانات الطبيب / العيادة نهائياً."))
        }
        .confirmationDialog(
            Language.get(
                (vetToConfirmToggle?.isDisabled == true) ? "Vet_Confirm_Enable_Title" : "Vet_Confirm_Disable_Title",
                alter: (vetToConfirmToggle?.isDisabled == true) ? "تفعيل الترخيص الطبي؟" : "تعطيل الترخيص الطبي مؤقتاً؟"
            ),
            isPresented: Binding(
                get: { vetToConfirmToggle != nil },
                set: { if !$0 { vetToConfirmToggle = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let vet = vetToConfirmToggle {
                let willDisable = !vet.isDisabled
                Button(
                    Language.get(willDisable ? "Vet_Action_Disable" : "Vet_Action_Enable", alter: willDisable ? "تعطيل الحساب" : "تفعيل الحساب"),
                    role: willDisable ? .destructive : nil
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.toggleDisabled(for: vet)
                    vetToConfirmToggle = nil
                }
                Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                    vetToConfirmToggle = nil
                }
            }
        } message: {
            if let vet = vetToConfirmToggle {
                let willDisable = !vet.isDisabled
                Text(Language.get(
                    willDisable ? "Vet_Confirm_Disable_Msg" : "Vet_Confirm_Enable_Msg",
                    alter: willDisable ? "سيتم إيقاف ظهور العيادة أو الطبيب وحجب الحجوزات مؤقتاً." : "سيظهر الطبيب أو العيادة للمستخدمين ويمكن استقبال الحجوزات فوراً."
                ))
            }
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var navigationBarHeader: some View {
        AdminSovereignNavigationBar(
            title: Language.get("AdminVet_SectionTitle", alter: "الأطباء البيطريون والعيادات"),
            subtitle: Language.get("AdminVet_SectionDetail", alter: "إدارة الشبكة الطبية، الرخص المهنية، والاشتراكات"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                // Live Indicator Beacon
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                        .frame(width: 6, height: 6)
                        .scaleEffect(isPulsingBeacon ? 1.3 : 0.8)
                    Text(Language.get("LiveSync", alter: "مباشر"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: Capsule())
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isPulsingBeacon = true
                    }
                }

                // Refresh Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))

                // Primary Register Authority CTA (+ icon only)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    navigate(to: .add)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.08, green: 0.72, blue: 0.65),
                                    Color(red: 0.05, green: 0.58, blue: 0.52)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .shadow(color: Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.28), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("AdminVet_QuickAdd", alter: "تسجيل طبيب أو عيادة جديدة"))
            }
        }
    }

    // MARK: - Clinical Radar Horizon Deck

    private var clinicalRadarHorizon: some View {
        VStack(spacing: 12) {
            // Hero Medical Authority Card
            ZStack {
                // Background Gradient
                RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark ? [
                                Color(red: 0.05, green: 0.22, blue: 0.20),
                                Color(red: 0.04, green: 0.14, blue: 0.16)
                            ] : [
                                Color(red: 0.92, green: 0.98, blue: 0.97),
                                Color(red: 0.94, green: 0.99, blue: 0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.08, green: 0.72, blue: 0.65).opacity(colorScheme == .dark ? 0.45 : 0.25),
                                        Color(red: 0.12, green: 0.68, blue: 0.88).opacity(colorScheme == .dark ? 0.25 : 0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.04), radius: 8, x: 0, y: 3)

                VStack(spacing: 14) {
                    // Top Row: Network Telemetry Overview
                    HStack(alignment: .center) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.08, green: 0.72, blue: 0.65),
                                                Color(red: 0.12, green: 0.68, blue: 0.88)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                    .shadow(color: Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.35), radius: 6, x: 0, y: 2)

                                Image(systemName: "cross.case.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("AdminVet_TotalEntities", alter: "الشبكة الطبية المعتمدة"))
                                    .font(AdminType.caption1)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                HStack(spacing: 6) {
                                    Text("\(store.totalCount)")
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .foregroundStyle(AdminSurface.primaryText)
                                        .monospacedDigit()
                                    Text(Language.isRTL() ? "جهة طبية" : "entities")
                                        .font(AdminType.caption2)
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                }
                            }
                        }

                        Spacer()

                        // Operational Uptime Pill
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(red: 0.16, green: 0.78, blue: 0.48))
                                    .frame(width: 6, height: 6)
                                Text("\(store.activeUptimePercent)%")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: Capsule())

                            Text(Language.get("AdminVet_NetworkUptime", alter: "جاهزية التراخيص"))
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminCommandInk.secondary)
                        }
                    }

                    // Dual Pillars: Clinics vs Solo Doctors Split
                    HStack(spacing: 10) {
                        // Pillar 1: Clinics & Hospitals
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.activeFilter = .clinics
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "building.2.crop.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.12, green: 0.68, blue: 0.88))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(store.clinicsCount)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(AdminSurface.primaryText)
                                        .monospacedDigit()
                                    Text(Language.get("AdminVet_ClinicsCount", alter: "مراكز وعيادات"))
                                        .font(AdminType.caption2)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(
                                AdminSurface.surface.opacity(0.75),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(red: 0.12, green: 0.68, blue: 0.88).opacity(store.activeFilter == .clinics ? 0.6 : 0.18), lineWidth: store.activeFilter == .clinics ? 1.4 : 0.8)
                            )
                        }
                        .buttonStyle(.plain)

                        // Pillar 2: Independent Doctors
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.activeFilter = .doctors
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "stethoscope.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(store.doctorsCount)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(AdminSurface.primaryText)
                                        .monospacedDigit()
                                    Text(Language.get("AdminVet_DoctorsCount", alter: "أطباء مستقلون"))
                                        .font(AdminType.caption2)
                                        .foregroundStyle(AdminCommandInk.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(
                                AdminSurface.surface.opacity(0.75),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(store.activeFilter == .doctors ? 0.6 : 0.18), lineWidth: store.activeFilter == .doctors ? 1.4 : 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Bottom Micro-Bar: Subscription & Fee Telemetry
                    HStack(spacing: 12) {
                        // Premium Partners
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.18))
                            Text("\(store.premiumCount) \(Language.get("AdminVet_Filter_Premium", alter: "بريميوم"))")
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.95, green: 0.68, blue: 0.18).opacity(0.12), in: Capsule())

                        // Renewals Due Alert
                        if store.expiringSoonCount > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 0.95, green: 0.45, blue: 0.25))
                                    .frame(width: 5, height: 5)
                                Text("\(store.expiringSoonCount) \(Language.get("AdminVet_ExpiringSoon", alter: "تجديد مستحق"))")
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.25))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.95, green: 0.45, blue: 0.25).opacity(0.12), in: Capsule())
                        }

                        Spacer()

                        // Average Consultation Fee
                        if store.averageCost > 0 {
                            HStack(spacing: 3) {
                                Text(Language.get("AdminVet_AvgFee", alter: "متوسط:"))
                                    .font(AdminType.caption2)
                                    .foregroundStyle(AdminCommandInk.secondary)
                                Text(String(format: "%.0f %@", store.averageCost, Language.get("QAR", alter: "ر.ق")))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Multi-Spectral Filter Matrix Island

    private var filterMatrixIsland: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VetFilterScope.allCases) { scope in
                    let isSelected = store.activeFilter == scope
                    let count = store.count(for: scope)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            store.activeFilter = scope
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: scope.symbol)
                                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                                .foregroundStyle(isSelected ? .white : scope.accentColor)

                            Text(Language.get(scope.titleKey, alter: nil))
                                .font(isSelected ? AdminType.caption1Bold : AdminType.caption1)
                                .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)

                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? scope.accentColor : AdminCommandInk.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    isSelected ? Color.white : AdminSurface.surface.opacity(0.8),
                                    in: Capsule()
                                )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            (isSelected ? scope.accentColor : AdminSurface.surface),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isSelected ? scope.accentColor : AdminSurface.hairline, lineWidth: 0.8)
                        )
                        .shadow(
                            color: isSelected ? scope.accentColor.opacity(0.3) : Color.black.opacity(0.02),
                            radius: isSelected ? 5 : 2,
                            x: 0,
                            y: isSelected ? 2 : 1
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Search & Triage Bar

    private var searchTerminalBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))

            TextField(Language.get("Vet_Search_Placeholder", alter: "بحث بالاسم، العيادة، الهاتف، أو التكلفة..."), text: $store.searchText)
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.primaryText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !store.searchText.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
                .buttonStyle(.plain)
            }

            if !store.searchText.isEmpty {
                Text("\(store.filteredVets.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.02), radius: 4, x: 0, y: 1)
    }

    // MARK: - Dossier Grid / List

    @ViewBuilder
    private var contentDossierGrid: some View {
        if store.isLoading {
            skeletonLoadingState
        } else if store.filteredVets.isEmpty {
            emptyStateView
        } else {
            VStack(spacing: 12) {
                ForEach(store.filteredVets, id: \.vetID) { vet in
                    PPVetDossierCard(
                        vet: vet,
                        onOpenDetail: { navigate(to: .detail(vet)) },
                        onOpenEdit: { navigate(to: .edit(vet)) },
                        onOpenSubscription: { navigate(to: .subscription(vet)) },
                        onToggleDisabled: { vetToConfirmToggle = vet },
                        onConfirmDelete: { vetToConfirmDelete = vet }
                    )
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: store.searchText.isEmpty ? "cross.case" : "stethoscope")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
            }
            .padding(.top, 24)

            VStack(spacing: 4) {
                Text(store.searchText.isEmpty ? Language.get("Vet_Empty_List", alter: "لا يوجد أطباء بيطريون أو عيادات حالياً.") : Language.get("AdminVet_SearchNoResults", alter: "لا توجد نتائج مطابقة لبحثك."))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                if !store.searchText.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.searchText = ""
                        store.activeFilter = .all
                    } label: {
                        Text(Language.get("AdminVet_ResetFilter", alter: "إعادة ضبط الفلاتر"))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                            .padding(.top, 4)
                    }
                }
            }

            if store.searchText.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    navigate(to: .add)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(Language.get("Vet_Add_Title", alter: "إضافة طبيب بيطري جديد"))
                            .font(AdminType.subheadlineBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.08, green: 0.72, blue: 0.65),
                                Color(red: 0.05, green: 0.58, blue: 0.52)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.3), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.vertical, 20)
    }

    private var skeletonLoadingState: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                    .fill(AdminSurface.surface.opacity(0.6))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                    )
            }
        }
    }

    // MARK: - Navigation Router

    private func navigate(to destination: VetPresentedSheet) {
        if let pushVC = onPushViewController {
            switch destination {
            case .add:
                pushVC(PPVetEditorHostingController(vetToEdit: nil))
            case .edit(let vet):
                pushVC(PPVetEditorHostingController(vetToEdit: vet))
            case .detail(let vet):
                pushVC(PPVetDetailDossierHostingController(vet: vet))
            case .subscription(let vet):
                pushVC(PPVetSubscriptionHostingController(vet: vet))
            }
        } else {
            if presentedSheet != nil {
                presentedSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presentedSheet = destination
                }
            } else {
                presentedSheet = destination
            }
        }
    }
}

// MARK: - Category-Defining Sovereign Clinical Dossier Card

private struct PPVetDossierCard: View {
    let vet: PPVetModel
    let onOpenDetail: () -> Void
    let onOpenEdit: () -> Void
    let onOpenSubscription: () -> Void
    let onToggleDisabled: () -> Void
    let onConfirmDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isClinic: Bool { vet.type == .company }
    private var isDisabled: Bool { vet.isDisabled }
    private var isExpired: Bool { vet.isSubscriptionExpired() }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpenDetail()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Top Ribbon: Entity Badge, Status Beacon, Tier Pill
                topRibbonBar

                // Core Identity Row: Avatar + Title + Bio
                HStack(alignment: .top, spacing: 12) {
                    avatarView

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(vet.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? vet.title! : "—")
                                .font(.custom("Beiruti-Bold", size: 18))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)

                            Spacer()

                            // Consultation Fee Pill
                            if vet.vetCost > 0 {
                                HStack(spacing: 2) {
                                    Text(String(format: "%.0f", vet.vetCost))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    Text(Language.get("QAR", alter: "ر.ق"))
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.12), in: Capsule())
                            } else {
                                Text(Language.get("AdminVet_FreeConsult", alter: "استشارة مجانية"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: Capsule())
                            }
                        }

                        // Medical Description / Subtitle
                        if let desc = vet.descriptionText, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(desc)
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                        }

                        // Availability schedule badge if present
                        if let available = vet.availableDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.12, green: 0.68, blue: 0.88))
                                Text(formattedDate(available))
                                    .font(AdminType.caption2)
                                    .foregroundStyle(AdminCommandInk.tertiary)
                            }
                            .padding(.top, 1)
                        }
                    }
                }

                // Operational Action Strip: Call, WhatsApp, Fast Controls
                Divider()
                    .background(AdminSurface.hairline)

                HStack(spacing: 8) {
                    // One-Tap Call Button
                    if let phone = vet.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            callPhone(phone)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(phone)
                                    .font(AdminType.caption2Bold)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color(red: 0.14, green: 0.54, blue: 0.98))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.14, green: 0.54, blue: 0.98).opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // One-Tap WhatsApp Button
                    if let wa = vet.whatsapp, !wa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            openWhatsApp(wa)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(Language.get("WhatsApp", alter: "واتساب"))
                                    .font(AdminType.caption2Bold)
                            }
                            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Edit Profile Button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdminCommandInk.secondary)
                            .frame(width: 32, height: 32)
                            .background(AdminSurface.surface.opacity(0.9), in: Circle())
                            .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Vet_Edit_Title", alter: "تعديل"))

                    // Subscription Management Button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenSubscription()
                    } label: {
                        Image(systemName: "creditcard.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.18))
                            .frame(width: 32, height: 32)
                            .background(AdminSurface.surface.opacity(0.9), in: Circle())
                            .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Vet_Subscription", alter: "الاشتراك"))

                    // Chevron Detail Indicator (direct tap action)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenDetail()
                    } label: {
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AdminCommandInk.tertiary)
                            .frame(width: 24, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Vet_Detail_Title", alter: "الملف الطبي الشامل"))
                }
            }
            .padding(14)
            .background(
                AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                    .strokeBorder(
                        isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28).opacity(0.35) :
                            (isExpired ? Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.35) : AdminSurface.hairline),
                        lineWidth: (isDisabled || isExpired) ? 1.2 : 0.8
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.04), radius: 6, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        }
        .buttonStyle(VetCardPressStyle())
        .contextMenu {
            Button { onOpenDetail() } label: {
                Label(Language.get("Vet_Detail_Title", alter: "الملف الطبي الشامل"), systemImage: "eye")
            }
            Button { onOpenEdit() } label: {
                Label(Language.get("Vet_Edit_Title", alter: "تعديل البيانات"), systemImage: "pencil")
            }
            Button { onOpenSubscription() } label: {
                Label(Language.get("Vet_Subscription", alter: "إدارة باقة الاشتراك"), systemImage: "creditcard")
            }
            Divider()
            Button { onToggleDisabled() } label: {
                Label(
                    isDisabled ? Language.get("Vet_Action_Enable", alter: "تفعيل الترخيص") : Language.get("Vet_Action_Disable", alter: "إيقاف مؤقت"),
                    systemImage: isDisabled ? "checkmark.circle.fill" : "nosign"
                )
            }
            if let phone = vet.phone, !phone.isEmpty {
                Button { callPhone(phone) } label: {
                    Label(phone, systemImage: "phone")
                }
            }
            Divider()
            Button(role: .destructive) { onConfirmDelete() } label: {
                Label(Language.get("Delete", alter: "حذف الطبيب أو العيادة"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { onOpenEdit() } label: {
                Image(systemName: "pencil")
            }
            .tint(Color(red: 0.14, green: 0.54, blue: 0.98))

            Button { onToggleDisabled() } label: {
                Image(systemName: isDisabled ? "checkmark.circle.fill" : "nosign")
            }
            .tint(isDisabled ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.95, green: 0.55, blue: 0.20))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onConfirmDelete() } label: {
                Image(systemName: "trash.fill")
            }
        }
    }

    // MARK: - Subviews & Helpers

    private var topRibbonBar: some View {
        HStack(spacing: 8) {
            // Entity Type Badge
            HStack(spacing: 4) {
                Image(systemName: isClinic ? "building.2.crop.circle.fill" : "stethoscope.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(isClinic ? Language.get("AdminVet_VerifiedClinic", alter: "عيادة بيطرية معتمدة") : Language.get("AdminVet_LicensedDoctor", alter: "طبيب بيطري مرخص"))
                    .font(AdminType.caption2Bold)
            }
            .foregroundStyle(isClinic ? Color(red: 0.12, green: 0.68, blue: 0.88) : Color(red: 0.08, green: 0.72, blue: 0.65))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (isClinic ? Color(red: 0.12, green: 0.68, blue: 0.88) : Color(red: 0.08, green: 0.72, blue: 0.65)).opacity(0.12),
                in: Capsule()
            )

            Spacer()

            // Subscription Tier Badge
            tierBadgeView

            // License Status Beacon Toggle
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onToggleDisabled()
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48))
                        .frame(width: 6, height: 6)

                    Text(isDisabled ? Language.get("Vet_Status_Disabled", alter: "موقوف") : Language.get("Vet_Status_Active", alter: "نشط"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    (isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48)).opacity(0.12),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDisabled ? Language.get("Vet_Action_Enable", alter: "تفعيل") : Language.get("Vet_Action_Disable", alter: "تعطيل"))
        }
    }

    @ViewBuilder
    private var tierBadgeView: some View {
        if isExpired {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(Language.get("Vet_Sub_Expired", alter: "منتهي"))
                    .font(AdminType.caption2Bold)
            }
            .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.28))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Color(red: 0.92, green: 0.35, blue: 0.28).opacity(0.12), in: Capsule())
        } else {
            switch vet.subscriptionTier {
            case .premium:
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(Language.get("Vet_Sub_Premium", alter: "بريميوم"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(Color(red: 0.95, green: 0.68, blue: 0.18))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color(red: 0.95, green: 0.68, blue: 0.18).opacity(0.14), in: Capsule())
            case .basic:
                Text(Language.get("Vet_Sub_Basic", alter: "أساسي"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(Color(red: 0.12, green: 0.68, blue: 0.88))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color(red: 0.12, green: 0.68, blue: 0.88).opacity(0.12), in: Capsule())
            case .free:
                Text(Language.get("Vet_Sub_Free", alter: "مجاني"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(AdminSurface.surface.opacity(0.8), in: Capsule())
            @unknown default:
                EmptyView()
            }
        }
    }

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let logoURL = vet.logoURL, !logoURL.isEmpty, let url = URL(string: logoURL) {
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 52, height: 52)) {
                    avatarPlaceholder
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                avatarPlaceholder
            }

            // Cross verification pill
            Circle()
                .fill(isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48))
                .frame(width: 12, height: 12)
                .overlay(
                    Circle().stroke(AdminSurface.surface, lineWidth: 2)
                )
                .offset(x: 2, y: 2)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28).opacity(0.3) :
                        Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.3),
                    lineWidth: 1.0
                )
        )
    }

    private var avatarPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    (isClinic ? Color(red: 0.12, green: 0.68, blue: 0.88) : Color(red: 0.08, green: 0.72, blue: 0.65)).opacity(0.12)
                )
                .frame(width: 50, height: 50)

            Image(systemName: isClinic ? "building.2.fill" : "stethoscope")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isClinic ? Color(red: 0.12, green: 0.68, blue: 0.88) : Color(red: 0.08, green: 0.72, blue: 0.65))
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func callPhone(_ phone: String) {
        let cleaned = phone.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(cleaned)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    private func openWhatsApp(_ whatsapp: String) {
        var cleaned = whatsapp.filter { "0123456789".contains($0) }
        if cleaned.hasPrefix("00") {
            cleaned.removeFirst(2)
        }
        let greeting = Language.get("AdminVet_WhatsAppGreeting", alter: "مرحباً دكتور، نتواصل معك من إدارة منصة بيور بيتس بخصوص حسابكم المهني.")
        let encodedGreeting = greeting.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "whatsapp://send?phone=\(cleaned)&text=\(encodedGreeting)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let webURL = URL(string: "https://wa.me/\(cleaned)?text=\(encodedGreeting)") {
            UIApplication.shared.open(webURL)
        }
    }
}

// MARK: - Press Animation Style

private struct VetCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}



// MARK: - Legacy View Wrapper (for AdminRouteDestinationView & Factory)

@MainActor
struct PPVetsListView: View {
    var onDismiss: (() -> Void)?
    var onPushViewController: ((UIViewController) -> Void)?

    init(
        onPushViewController: ((UIViewController) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.onPushViewController = onPushViewController
        self.onDismiss = onDismiss
    }

    var body: some View {
        PPVeterinarianManagementScreen(
            onPushViewController: onPushViewController,
            onDismiss: onDismiss
        )
    }
}

// MARK: - Hosting Controller (Preserved Obj-C Bridge)

@objc(PPVetsListHostingController)
public class PPVetsListHostingController: UIViewController {
    @objc public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all

        let swiftUIView = PPVeterinarianManagementScreen(
            onPushViewController: { [weak self] viewController in
                if let nav = self?.navigationController {
                    nav.pushViewController(viewController, animated: true)
                } else {
                    self?.present(viewController, animated: true, completion: nil)
                }
            },
            onDismiss: { [weak self] in
                if let nav = self?.navigationController {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true, completion: nil)
                }
            }
        )

        let hostingController = UIHostingController(rootView: swiftUIView.ignoresSafeArea())
        hostingController.view.backgroundColor = .clear
        hostingController.extendedLayoutIncludesOpaqueBars = true
        hostingController.edgesForExtendedLayout = .all
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}
