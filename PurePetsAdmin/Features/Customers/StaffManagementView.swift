//
//  StaffManagementView.swift
//  PurePetsAdmin
//
//  NextGen V6 Native SwiftUI Staff & Team Access Management.
//  Preserves all Firestore PPStaffAuth listeners, AdminService Cloud Functions,
//  RPManager permission registries, user feature flags, and audit logging.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Sendable & Identifiable Conformance

extension PPStaffDoc: @unchecked Sendable, Identifiable {
    public var id: String { uid }
}

// MARK: - Staff Roles

enum StaffRoleOption: String, CaseIterable, Identifiable {
    case owner = "owner"
    case superAdmin = "super_admin"
    case operationsManager = "operations_manager"
    case inventoryManager = "inventory_manager"
    case paymentsManager = "payments_manager"
    case supportAgent = "support_agent"
    case viewer = "viewer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .superAdmin: return Language.get("RoleSuperAdmin", alter: "مدير نظام")
        case .owner: return Language.get("RoleOwner", alter: "مالك")
        case .operationsManager: return Language.get("RoleOperationsManager", alter: "مدير عمليات")
        case .inventoryManager: return Language.get("RoleInventoryManager", alter: "مدير مخزون")
        case .paymentsManager: return Language.get("RolePaymentsManager", alter: "مدير مدفوعات")
        case .supportAgent: return Language.get("RoleSupportAgent", alter: "دعم فني")
        case .viewer: return Language.get("RoleViewer", alter: "مشاهد")
        }
    }

    var subtitle: String {
        switch self {
        case .owner: return Language.get("RoleDesc_Owner", alter: "صلاحيات سيادية مطلقة تشمل الهيكلة المالية وإدارة النظام")
        case .superAdmin: return Language.get("RoleDesc_SuperAdmin", alter: "تحكّم كامل في جميع وحدات المنصة وإدارة الموظفين والسياسات")
        case .operationsManager: return Language.get("RoleDesc_OperationsManager", alter: "إشراف شامل على الطلبات والتنفيذ والشحن والمخزون")
        case .inventoryManager: return Language.get("RoleDesc_InventoryManager", alter: "إدارة كتالوج المنتجات والمستلزمات والمخزون والباركود")
        case .paymentsManager: return Language.get("RoleDesc_PaymentsManager", alter: "إدارة المدفوعات ونقاط البيع واسترداد المبالغ والمحاسبة")
        case .supportAgent: return Language.get("RoleDesc_SupportAgent", alter: "خدمة العملاء والرد على المحادثات ومتابعة المستخدمين")
        case .viewer: return Language.get("RoleDesc_Viewer", alter: "اطلاع ومراقبة فقط دون إمكانية التعديل أو إجراء العمليات")
        }
    }

    var clearanceTier: String {
        switch self {
        case .owner: return "سلطة سيادية عليا • Tier 1"
        case .superAdmin: return "إدارة النظام العليا • Tier 1"
        case .operationsManager: return "قيادة العمليات • Tier 2"
        case .inventoryManager: return "إدارة المخزون • Tier 2"
        case .paymentsManager: return "إدارة الخزينة والمالية • Tier 2"
        case .supportAgent: return "خدمة العملاء • Tier 3"
        case .viewer: return "اطلاع ومراقبة • Tier 4"
        }
    }

    var icon: String {
        switch self {
        case .owner: return "crown.fill"
        case .superAdmin: return "shield.checkered"
        case .operationsManager: return "gearshape.2.fill"
        case .inventoryManager: return "cube.box.fill"
        case .paymentsManager: return "creditcard.fill"
        case .supportAgent: return "headphones"
        case .viewer: return "eye.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .owner: return Color(red: 0.85, green: 0.65, blue: 0.15)
        case .superAdmin: return Color(red: 0.72, green: 0.05, blue: 0.18)
        case .operationsManager: return Color(red: 0.10, green: 0.55, blue: 0.85)
        case .inventoryManager: return Color(red: 0.90, green: 0.45, blue: 0.10)
        case .paymentsManager: return Color(red: 0.08, green: 0.65, blue: 0.45)
        case .supportAgent: return Color(red: 0.55, green: 0.25, blue: 0.85)
        case .viewer: return Color(uiColor: .ppTextSecondary)
        }
    }

    var defaultPermissionsCount: Int {
        switch self {
        case .superAdmin: return 32
        case .owner: return 32
        case .operationsManager: return 20
        case .inventoryManager: return 12
        case .paymentsManager: return 14
        case .supportAgent: return 6
        case .viewer: return 0
        }
    }
}

// MARK: - Staff List ViewModel

@MainActor
final class AdminStaffManagementViewModel: ObservableObject {
    @Published private(set) var staffMembers: [PPStaffDoc] = []
    @Published private(set) var filteredStaff: [PPStaffDoc] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: StaffStatusFilter = .all
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var canManage: Bool = false

    private nonisolated(unsafe) var staffListener: (any ListenerRegistration)?

    enum StaffStatusFilter: Int, CaseIterable {
        case all = 0
        case active
        case disabled

        var title: String {
            switch self {
            case .all: return Language.get("All", alter: "الكل")
            case .active: return Language.get("Active", alter: "نشط")
            case .disabled: return Language.get("Disabled", alter: "معطل")
            }
        }
    }

    var totalCount: Int { staffMembers.count }
    var activeCount: Int { staffMembers.filter { $0.status == .active }.count }
    var disabledCount: Int { staffMembers.filter { $0.status != .active }.count }

    init() {
        evaluatePermissions()
    }

    deinit {
        staffListener?.remove()
    }

    func evaluatePermissions() {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        self.canManage = staff?.hasPermission(kStaffPermStaffManage) ?? false
    }

    func startListening() {
        evaluatePermissions()
        isLoading = true
        errorMessage = nil

        staffListener?.remove()
        staffListener = PPStaffAuth.shared().listenAllStaff { [weak self] docs, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.staffMembers = docs ?? []
                self.applyFilter()
            }
        }
    }

    func stopListening() {
        staffListener?.remove()
        staffListener = nil
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        filteredStaff = staffMembers.filter { member in
            let matchesStatus: Bool = {
                switch selectedFilter {
                case .all: return true
                case .active: return member.status == .active
                case .disabled: return member.status != .active
                }
            }()
            guard matchesStatus else { return false }
            guard !query.isEmpty else { return true }
            return (member.displayName?.lowercased().contains(query) ?? false) ||
                   (member.email?.lowercased().contains(query) ?? false) ||
                   member.roleIdentifier.lowercased().contains(query)
        }
    }

    func disableMember(_ member: PPStaffDoc, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard !member.uid.isEmpty else { return }
        let uid = member.uid
        AdminService.disableStaffMember(uid) { _, error in
            let errDesc = error?.localizedDescription
            DispatchQueue.main.async {
                if let errDesc {
                    completion(false, errDesc)
                } else {
                    completion(true, Language.get("Staff_Member_Disabled", alter: "تم تعطيل وصول الموظف"))
                }
            }
        }
    }
}

// MARK: - Main Staff Management View

@MainActor
struct AdminStaffManagementView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminStaffManagementViewModel()
    @State private var selectedMemberForEdit: PPStaffDoc? = nil
    @State private var isCreatingNew = false
    @State private var toastMessage: String? = nil
    @State private var isErrorToast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                dossierHeaderView

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        heroHeader
                        filterSegment
                        searchSection
                        staffListContent
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.xs)
                    .padding(.bottom, AdminSpacing.xxl)
                }
                .refreshable {
                    viewModel.startListening()
                }
            }

            if let message = toastMessage {
                VStack {
                    Spacer()
                    toastBanner(message: message, isError: isErrorToast)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, AdminSpacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(AdminAnimation.standard, value: toastMessage)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onChange(of: viewModel.searchText, perform: { _ in
            viewModel.applyFilter()
        })
        .onChange(of: viewModel.selectedFilter, perform: { _ in
            viewModel.applyFilter()
        })
        .sheet(item: $selectedMemberForEdit) { member in
            AdminStaffMemberEditorView(
                staffDoc: member,
                onDismiss: { selectedMemberForEdit = nil },
                onSaved: { msg in
                    selectedMemberForEdit = nil
                    showToast(msg, isError: false)
                }
            )
        }
        .sheet(isPresented: $isCreatingNew) {
            AdminStaffMemberEditorView(
                staffDoc: nil,
                onDismiss: { isCreatingNew = false },
                onSaved: { msg in
                    isCreatingNew = false
                    showToast(msg, isError: false)
                }
            )
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            AdminSovereignNavigationBar(
                title: Language.get("StaffMembers_Title", alter: "فريق العمل والوصول"),
                subtitle: Language.get("CommandCenter_Customers_Workspace", alter: "مساحة العملاء"),
                onBack: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }
            ) {
                if viewModel.isLoading {
                    ProgressView().tint(AdminSurface.primary)
                } else {
                    Button(action: { viewModel.startListening() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.startListening() }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("StaffMembers_Title", alter: "فريق العمل والوصول"))
                            .font(AdminType.title2)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("StaffMembers_Subtitle", alter: "إدارة أعضاء الفريق والأدوار وصلاحيات النظام."))
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "person.3.sequence.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .accessibilityHidden(true)
                }

                HStack(spacing: 10) {
                    statPill(value: viewModel.totalCount, titleKey: "Total", accent: AdminSurface.primary)
                    statPill(value: viewModel.activeCount, titleKey: "Active", accent: Color(uiColor: .ppSuccess))
                    statPill(value: viewModel.disabledCount, titleKey: "Disabled", accent: Color(uiColor: .ppWarning))

                    Spacer()

                    if viewModel.canManage {
                        Button {
                            isCreatingNew = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                Text(Language.get("Staff_Create_New", alter: "عضو جديد"))
                                    .font(AdminType.captionBold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(AdminSurface.primary, in: Capsule())
                        }
                        .accessibilityLabel(Language.get("Staff_Create_New", alter: nil))
                    }
                }
            }
            .padding(AdminSpacing.cardPadding)
        }
    }

    private func statPill(value: Int, titleKey: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text("\(value) \(Language.get(titleKey, alter: titleKey))")
                .font(AdminType.captionBold)
                .foregroundColor(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(accent.opacity(0.09), in: Capsule())
    }

    // MARK: - Filter Segment

    private var filterSegment: some View {
        HStack(spacing: 0) {
            ForEach(AdminStaffManagementViewModel.StaffStatusFilter.allCases, id: \.rawValue) { filter in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        viewModel.selectedFilter = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(viewModel.selectedFilter == filter ? AdminType.footnoteBold : AdminType.footnote)
                        .foregroundColor(viewModel.selectedFilter == filter ? .white : AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            viewModel.selectedFilter == filter ? AdminSurface.primary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
            }
        }
        .padding(4)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - Search Section

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AdminSurface.secondaryText)
                .font(.system(size: 16, weight: .medium))

            TextField(Language.get("Search", alter: "بحث في أعضاء الفريق..."), text: $viewModel.searchText)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.primaryText)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AdminSurface.secondaryText)
                        .font(.system(size: 16))
                }
                .frame(minWidth: AdminTouchTarget.minimum, minHeight: AdminTouchTarget.minimum)
                .accessibilityLabel(Language.get("Clear", alter: nil))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - Staff List Content

    @ViewBuilder
    private var staffListContent: some View {
        if viewModel.isLoading {
            VStack(spacing: 16) {
                ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
                Text(Language.get("Loading", alter: nil))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if viewModel.staffMembers.isEmpty {
            AdminEmptyStateView(
                symbol: "person.3.sequence",
                title: Language.get("Staff_Preview_Empty", alter: "لا يوجد أعضاء فريق بعد"),
                subtitle: Language.get("MissionControl_Staff_SourceEmpty_Subtitle", alter: "أنشئ أول حساب موظف لإدارة الصلاحيات."),
                actionTitle: viewModel.canManage ? Language.get("Staff_Create_New", alter: nil) : nil,
                action: { isCreatingNew = true }
            )
        } else if viewModel.filteredStaff.isEmpty {
            AdminEmptyStateView(
                symbol: "magnifyingglass",
                title: Language.get("MissionControl_Staff_FilteredEmpty_Title", alter: "لا توجد نتائج مطابقة"),
                subtitle: Language.get("MissionControl_Staff_FilteredEmpty_Subtitle", alter: "جرّب بحثاً آخر أو غيّر الفلتر.")
            )
        } else {
            LazyVStack(spacing: AdminSpacing.md) {
                ForEach(viewModel.filteredStaff, id: \.uid) { member in
                    staffMemberCard(member: member)
                }
            }
        }
    }

    // MARK: - Staff Member Card

    private func staffMemberCard(member: PPStaffDoc) -> some View {
        let isRTL = Language.isRTL()
        let isCurrent = Auth.auth().currentUser?.uid == member.uid
        let isActive = member.status == .active
        let permsCount = member.permissions.count

        return Button {
            selectedMemberForEdit = member
        } label: {
            HStack(spacing: AdminSpacing.md) {
                // Avatar Shell
                ZStack {
                    Circle()
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(AdminSurface.primary)
                }
                .accessibilityHidden(true)

                // Info Stack
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(member.displayName ?? Language.get("Staff_Edit_Existing", alter: "عضو فريق"))
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        if isCurrent {
                            Text(Language.get("You", alter: "أنت"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                        }
                    }

                    if let email = member.email, !email.isEmpty {
                        Text(email)
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        // Role Pill
                        Text(PPAdminSessionBridge.localizedRoleName(for: member.roleIdentifier))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AdminSurface.primary.opacity(0.08), in: Capsule())

                        // Permissions Count
                        Text(String(format: Language.get("Staff_Access_Module_Permissions_Format", alter: "%lu صلاحية"), permsCount))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Status & Chevron
                HStack(spacing: 8) {
                    Circle()
                        .fill(isActive ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.60))
                }
            }
            .padding(AdminSpacing.base)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(AdminSurface.hairline)
            )
            .shadow(color: AdminShadow.card.color, radius: AdminShadow.card.radius, y: AdminShadow.card.y)
        }
        .buttonStyle(.plain)
    }

    private func showToast(_ message: String, isError: Bool) {
        guard !message.isEmpty else { return }
        toastMessage = message
        isErrorToast = isError
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func toastBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
                .font(.system(size: 18))
            Text(message)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3))
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Flagship Staff Member Editor Horizon (Reimagined from First Principles)

@MainActor
struct AdminStaffMemberEditorView: View {
    let staffDoc: PPStaffDoc?
    let onDismiss: () -> Void
    let onSaved: (String) -> Void

    @State private var isCreatingAccount = false
    @State private var selectedRole: StaffRoleOption = .viewer
    @State private var isActive: Bool = true
    @State private var canPostAnimalAds: Bool = false
    @State private var canPostAdoptionAds: Bool = false
    @State private var canPostServices: Bool = false
    @State private var isVerified: Bool = false

    // Form inputs for new user
    @State private var newEmail: String = ""
    @State private var newName: String = ""
    @State private var newPassword: String = ""
    @State private var newPhone: String = ""

    // Existing user assignment search
    @State private var existingUserSearch: String = ""
    @State private var selectedUserUID: String = ""
    @State private var selectedUserDisplayName: String = ""

    @State private var isSaving: Bool = false
    @State private var validationError: String? = nil
    @State private var showPermissionsInspector: Bool = false
    @State private var toastMessage: String? = nil

    private var isEditing: Bool { staffDoc != nil }

    init(staffDoc: PPStaffDoc?, onDismiss: @escaping () -> Void, onSaved: @escaping (String) -> Void) {
        self.staffDoc = staffDoc
        self.onDismiss = onDismiss
        self.onSaved = onSaved

        let initialRole = StaffRoleOption(rawValue: staffDoc?.roleIdentifier ?? "") ?? .viewer
        _selectedRole = State(initialValue: initialRole)
        _isActive = State(initialValue: staffDoc?.status == .active)
        _selectedUserUID = State(initialValue: staffDoc?.uid ?? "")
        _selectedUserDisplayName = State(initialValue: staffDoc?.displayName ?? "")
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Executive Member Identity Deck
                        if isEditing {
                            executiveProfileDeck
                        } else {
                            onboardingIdentityChamber
                        }

                        // 2. Authority & Security Posture Bento Deck
                        authorityTelemetryBento

                        // 3. Interactive Role & Clearance Matrix
                        roleClearanceMatrixChamber

                        // 4. Platform Profile Capabilities (Consumer/App features)
                        platformCapabilitiesChamber

                        // Validation Error Banner
                        if let error = validationError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.primaryText)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.red.opacity(0.25), lineWidth: 1))
                        }

                        // Bottom Spacer for floating action bar
                        Spacer().frame(height: 70)
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }

                // Pinned Bottom Floating Executive Action Bar
                floatingExecutiveActionBar

                // Floating Toast
                if let toast = toastMessage {
                    floatingToastView(toast)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(isEditing ? Language.get("Staff_EditMember_Title", alter: "تعديل عضو الفريق") : Language.get("Staff_Create_New", alter: "تعيين عضو فريق جديد"))
                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)

                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(uiColor: .ppSuccess))
                            Text(Language.get("Staff_Security_Badge", alter: "بروتوكول IAM المعتمد • سحابي"))
                                .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDismiss()
                    } label: {
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AdminSurface.control, in: Capsule())
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        saveSettings()
                    } label: {
                        if isSaving {
                            ProgressView().tint(AdminSurface.primary).scaleEffect(0.8)
                        } else {
                            Text(Language.get("Save", alter: "حفظ"))
                                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                loadExistingUserCapabilities()
            }
            .sheet(isPresented: $showPermissionsInspector) {
                AdminStaffPermissionsInspectorSheet(
                    role: selectedRole,
                    staffDoc: staffDoc,
                    onDismiss: { showPermissionsInspector = false }
                )
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .navigationViewStyle(.stack)
    }

    // MARK: - 1. Executive Member Profile Deck

    private var executiveProfileDeck: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Avatar with Live Presence & Status Halo
                ZStack(alignment: .bottomTrailing) {
                    if let photo = staffDoc?.photoURL, let url = URL(string: photo), !photo.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: monogramView
                            }
                        }
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        monogramView
                    }

                    // Live Status Halo
                    Circle()
                        .fill(isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                        .offset(x: 2, y: 2)
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(Font.custom("Beiruti-Bold", size: 19, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        if isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
                        }

                        Spacer()

                        // Role Insignia Capsule
                        HStack(spacing: 4) {
                            Image(systemName: selectedRole.icon)
                                .font(.system(size: 10, weight: .bold))
                            Text(selectedRole.title)
                                .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                        }
                        .foregroundColor(selectedRole.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(selectedRole.accentColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(selectedRole.accentColor.opacity(0.25), lineWidth: 0.5))
                    }

                    if let email = staffDoc?.email, !email.isEmpty {
                        Text(email)
                            .font(Font.custom("Beiruti-Regular", size: 12.5, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        // 1-Tap Copy UID Chip
                        if let uid = staffDoc?.uid, !uid.isEmpty {
                            Button {
                                UIPasteboard.general.string = uid
                                showToast(Language.get("UID_Copied", alter: "تم نسخ معرّف الموظف (UID)"))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "number.circle.fill")
                                        .font(.system(size: 8))
                                    Text(shortUID(uid))
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 8))
                                }
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(AdminSurface.control, in: Capsule())
                                .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.5))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        if let phone = staffDoc?.phone, !phone.isEmpty {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                            Text(phone)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AdminSurface.secondaryText)
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 1)
                }
            }

            // Quick Contact Action Strip
            if let phone = staffDoc?.phone, !phone.isEmpty {
                Divider().background(AdminSurface.hairline)

                HStack(spacing: 8) {
                    quickContactButton(title: "محادثة واتساب", icon: "message.fill", color: Color(uiColor: .ppSuccess)) {
                        let digits = phone.filter { "0123456789".contains($0) }
                        guard let url = URL(string: "https://wa.me/\(digits)") else { return }
                        UIApplication.shared.open(url)
                    }

                    quickContactButton(title: "اتصال هاتفي", icon: "phone.fill", color: AdminSurface.primary) {
                        let clean = phone.filter { "0123456789+".contains($0) }
                        guard let url = URL(string: "tel://\(clean)") else { return }
                        UIApplication.shared.open(url)
                    }

                    if let email = staffDoc?.email, !email.isEmpty {
                        quickContactButton(title: "إرسال بريد", icon: "envelope.fill", color: Color(red: 0.12, green: 0.50, blue: 0.90)) {
                            guard let url = URL(string: "mailto:\(email)") else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }

    private var monogramView: some View {
        ZStack {
            LinearGradient(
                colors: selectedRole.accentColor == Color(uiColor: .ppTextSecondary)
                    ? [Color(red: 0.35, green: 0.40, blue: 0.45), Color(red: 0.45, green: 0.50, blue: 0.55)]
                    : [selectedRole.accentColor, selectedRole.accentColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(userInitials)
                .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                .foregroundColor(.white)
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var displayName: String {
        if !selectedUserDisplayName.isEmpty { return selectedUserDisplayName }
        if let name = staffDoc?.displayName, !name.isEmpty { return name }
        return Language.get("Staff_Member_Default", alter: "عضو الفريق")
    }

    private var userInitials: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "PP" }
        let comps = name.components(separatedBy: " ")
        if comps.count >= 2, let f = comps.first?.first, let l = comps.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func shortUID(_ uid: String) -> String {
        guard uid.count > 10 else { return uid }
        return "\(uid.prefix(4))...\(uid.suffix(4))"
    }

    private func quickContactButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 2. Authority & Security Posture Bento Deck

    private var authorityTelemetryBento: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Pod 1: Operational Status Toggle
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isActive.toggle()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                            Text(Language.get("Staff_Operational_Status", alter: "الحالة التشغيلية"))
                                .font(Font.custom("Beiruti-Regular", size: 10.5, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                        }

                        HStack {
                            Text(isActive ? Language.get("Active", alter: "نشط ومفوّض") : Language.get("Disabled", alter: "معطّل وموقوف"))
                                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                                .foregroundColor(isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))

                            Spacer()

                            Circle()
                                .fill(isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity)
                    .background(
                        isActive ? Color(uiColor: .ppSuccess).opacity(0.08) : Color(uiColor: .ppWarning).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isActive ? Color(uiColor: .ppSuccess).opacity(0.25) : Color(uiColor: .ppWarning).opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Pod 2: Permissions Count & Inspector Trigger
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showPermissionsInspector = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "key.viewfinder")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(AdminSurface.primary)
                            Text(Language.get("Staff_Authorized_Ops", alter: "الصلاحيات"))
                                .font(Font.custom("Beiruti-Regular", size: 10.5, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                        }

                        HStack {
                            Text(String(format: Language.get("Staff_Access_Module_Permissions_Format", alter: "%d صلاحية"), selectedRole.defaultPermissionsCount))
                                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                                .foregroundColor(AdminSurface.primaryText)
                                .monospacedDigit()

                            Spacer()

                            Text(Language.get("Inspect", alter: "فحص"))
                                .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Clearance Tier Sub-banner
            HStack(spacing: 6) {
                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(selectedRole.accentColor)
                Text(selectedRole.clearanceTier)
                    .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text(selectedRole.subtitle)
                    .font(Font.custom("Beiruti-Regular", size: 10.5, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedRole.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - 3. Role & Security Clearance Matrix Chamber

    private var roleClearanceMatrixChamber: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("Staff_Role_Selection_Title", alter: "رتبة الدور والمستوى الأمني"))
                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Text(Language.get("Tap_To_Switch", alter: "اختر الدور لتحديث الصلاحيات"))
                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
            }

            VStack(spacing: 8) {
                ForEach(StaffRoleOption.allCases) { role in
                    let isSelected = selectedRole == role
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selectedRole = role
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? role.accentColor : role.accentColor.opacity(0.12))
                                    .frame(width: 40, height: 40)
                                Image(systemName: role.icon)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(isSelected ? .white : role.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(role.title)
                                        .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .body))
                                        .foregroundColor(AdminSurface.primaryText)

                                    Text("\(role.defaultPermissionsCount) صلاحية")
                                        .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                                        .foregroundColor(role.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(role.accentColor.opacity(0.10), in: Capsule())
                                }

                                Text(role.subtitle)
                                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            ZStack {
                                Circle()
                                    .stroke(isSelected ? role.accentColor : AdminSurface.hairline, lineWidth: isSelected ? 2 : 1)
                                    .frame(width: 22, height: 22)
                                if isSelected {
                                    Circle()
                                        .fill(role.accentColor)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                        .padding(11)
                        .background(
                            isSelected ? role.accentColor.opacity(0.08) : AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isSelected ? role.accentColor.opacity(0.4) : AdminSurface.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - 4. Platform Profile Capabilities Chamber

    private var platformCapabilitiesChamber: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "slider.horizontal.2.square.on.square")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
                Text(Language.get("Staff_Access_Capabilities_Title", alter: "قدرات حساب التطبيق (المستهلك)"))
                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }

            VStack(spacing: 10) {
                // Section A: Commercial Features
                VStack(spacing: 8) {
                    capabilityRow(
                        title: "نشر إعلانات الحيوانات",
                        subtitle: "إمكانية عرض حيوانات للبيع في الكتالوج العام",
                        icon: "pawprint.fill",
                        tint: Color(red: 0.85, green: 0.35, blue: 0.15),
                        binding: $canPostAnimalAds
                    )

                    Divider().background(AdminSurface.hairline)

                    capabilityRow(
                        title: "نشر إعلانات التبني",
                        subtitle: "إضافة حيوانات متاحة للتبني الإنساني",
                        icon: "heart.circle.fill",
                        tint: Color(red: 0.90, green: 0.20, blue: 0.45),
                        binding: $canPostAdoptionAds
                    )

                    Divider().background(AdminSurface.hairline)

                    capabilityRow(
                        title: "نشر الخدمات والرعاية",
                        subtitle: "طرح خدمات العيادات والتدريب والاستشارات",
                        icon: "cross.case.fill",
                        tint: Color(red: 0.55, green: 0.20, blue: 0.80),
                        binding: $canPostServices
                    )
                }
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))

                // Section B: Official Verification
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.12, green: 0.50, blue: 0.90).opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "shield.checkmark.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(Language.get("Customer_Verified_Title", alter: "توثيق الحساب رسمياً"))
                            .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("Customer_Verified_Sub", alter: "منح شارة التوثيق الزرقاء لحساب المستخدم المربوط"))
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Toggle("", isOn: $isVerified)
                        .labelsHidden()
                        .tint(Color(red: 0.12, green: 0.50, blue: 0.90))
                }
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }

    private func capabilityRow(title: String, subtitle: String, icon: String, tint: Color, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                    .foregroundColor(AdminSurface.primaryText)
                Text(subtitle)
                    .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 5. Onboarding Identity Chamber (When Creating / Linking)

    private var onboardingIdentityChamber: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 13))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("Staff_Access_Identity_Title", alter: "هوية عضو الفريق الجديد"))
                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }

            // Segmented Mode Selector
            Picker("", selection: $isCreatingAccount) {
                Text(Language.get("Staff_Assign_Existing", alter: "ربط حساب مستخدم قائم")).tag(false)
                Text(Language.get("Staff_Create_New", alter: "إنشاء حساب موظف جديد")).tag(true)
            }
            .pickerStyle(.segmented)

            if isCreatingAccount {
                // New Account Form
                VStack(spacing: 12) {
                    // Live Monogram Hero
                    VStack(spacing: 4) {
                        ZStack {
                            LinearGradient(
                                colors: [AdminSurface.primary, Color(red: 0.85, green: 0.15, blue: 0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Text(newName.isEmpty ? "PP" : String(newName.prefix(2)).uppercased())
                                .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                                .foregroundColor(.white)
                        }
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text(newName.isEmpty ? "معاينة هوية الموظف" : newName)
                            .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .padding(.vertical, 4)

                    editorInputField(title: "الاسم الكامل *", icon: "person.fill", placeholder: "مثال: عبد الله المري", text: $newName)
                    editorInputField(title: "البريد الإلكتروني المهني *", icon: "envelope.fill", placeholder: "staff@purepets.qa", text: $newEmail, keyboard: .emailAddress)

                    // Phone with Qatar Prefix
                    VStack(alignment: .leading, spacing: 4) {
                        Text("رقم الهاتف المهني")
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.primaryText)

                        HStack(spacing: 8) {
                            Text("🇶🇦 +974")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AdminSurface.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            TextField("5512 3456", text: $newPhone)
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .keyboardType(.phonePad)
                        }
                        .padding(6)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Password with Generator
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("كلمة المرور *")
                                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                            Button("توليد كلمة سر آمنة") {
                                newPassword = generateSecureStaffPassword()
                            }
                            .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.primary)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(AdminSurface.secondaryText)
                                .font(.system(size: 13))
                                .frame(width: 20)

                            TextField("••••••••", text: $newPassword)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .autocorrectionDisabled(true)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                    }
                }
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
            } else {
                // Link Existing User Form
                VStack(alignment: .leading, spacing: 10) {
                    Text(Language.get("Staff_Select_Existing_User", alter: "ابحث عن حساب مسجل بالمنصة لمنحه صلاحيات الفريق:"))
                        .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundColor(AdminSurface.secondaryText)

                        TextField(Language.get("Staff_Select_User_Search_Placeholder", alter: "ابحث بالبريد أو الاسم أو UID..."), text: $existingUserSearch)
                            .font(Font.custom("Beiruti-Regular", size: 13.5, relativeTo: .body))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))

                    if !selectedUserUID.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(uiColor: .ppSuccess))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(selectedUserDisplayName.isEmpty ? selectedUserUID : selectedUserDisplayName)
                                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(selectedUserUID)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(14)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }

    private func editorInputField(title: String, icon: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 13))
                    .frame(width: 20)

                TextField(placeholder, text: text)
                    .font(Font.custom("Beiruti-Regular", size: 13.5, relativeTo: .body))
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    private func generateSecureStaffPassword() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%"
        return String((0..<12).compactMap { _ in chars.randomElement() })
    }

    // MARK: - 6. Floating Executive Action Bar

    private var floatingExecutiveActionBar: some View {
        HStack(spacing: 12) {
            // Left Status Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedRole.title)
                        .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                        .foregroundColor(AdminSurface.primaryText)
                    Text(isActive ? "نشط ومفوّض" : "معطّل")
                        .font(Font.custom("Beiruti-Regular", size: 10, relativeTo: .caption2))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AdminSurface.control, in: Capsule())

            Spacer()

            // Main Save CTA
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                saveSettings()
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 13, weight: .bold))
                    }

                    Text(Language.get("Staff_Access_Save", alter: "حفظ إعدادات الوصول"))
                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.72, green: 0.05, blue: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: AdminSurface.primary.opacity(0.28), radius: 8, y: 3)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AdminSurface.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 4)
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.bottom, 12)
    }

    private func floatingToastView(_ toast: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(toast)
                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.14, blue: 0.18), Color(red: 0.18, green: 0.20, blue: 0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.20), radius: 12, y: 6)
            .padding(.bottom, 80)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastMessage)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.toastMessage == message {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.toastMessage = nil
                }
            }
        }
    }

    // MARK: - Data Operations & Cloud Functions

    private func loadExistingUserCapabilities() {
        guard let uid = staffDoc?.uid, !uid.isEmpty else { return }
        Firestore.firestore().collection("UsersCol").document(uid).getDocument { snapshot, _ in
            guard let data = snapshot?.data() else { return }
            let postAds = (data["canPostAds"] as? Bool) ?? (data["canPostAnimalAds"] as? Bool) ?? false
            let postAdoption = (data["canPostAdoptionAds"] as? Bool) ?? false
            let postServices = (data["canPostServices"] as? Bool) ?? false
            let verified = (data["verified"] as? Bool) ?? false
            DispatchQueue.main.async {
                self.canPostAnimalAds = postAds
                self.canPostAdoptionAds = postAdoption
                self.canPostServices = postServices
                self.isVerified = verified
            }
        }
    }

    private func saveSettings() {
        validationError = nil

        if isCreatingAccount && !isEditing {
            guard !newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                validationError = Language.get("Error_RequiredFields", alter: "يرجى كتابة الاسم والبريد الإلكتروني.")
                return
            }
            guard newPassword.count >= 8 else {
                validationError = Language.get("Staff_Error_Password_Min", alter: "كلمة المرور يجب أن لا تقل عن ٨ خانات.")
                return
            }
        }

        isSaving = true

        let staffRole: PPStaffRole = {
            switch selectedRole {
            case .superAdmin: return .superAdmin
            case .owner: return .owner
            case .operationsManager: return .operationsManager
            case .inventoryManager: return .inventoryManager
            case .paymentsManager: return .paymentsManager
            case .supportAgent: return .supportAgent
            case .viewer: return .viewer
            }
        }()

        if isEditing, let uid = staffDoc?.uid {
            // Update staff member
            let updates: [String: Any] = [
                "role": selectedRole.rawValue,
                "status": isActive ? PPStaffStatus.active.rawValue : PPStaffStatus.disabled.rawValue
            ]

            AdminService.updateStaffMember(uid, updates: updates) { _, error in
                let errDesc = error?.localizedDescription
                DispatchQueue.main.async {
                    if let errDesc {
                        self.isSaving = false
                        self.validationError = errDesc
                        return
                    }

                    // Update capabilities on UsersCol
                    self.updateUserCapabilities(uid: uid) {
                        self.isSaving = false
                        self.onSaved(Language.get("Saved", alter: "تم حفظ وتحديث إعدادات الوصول بنجاح"))
                    }
                }
            }
        } else if isCreatingAccount {
            // Create new staff member
            AdminService.createStaffMember(
                withEmail: newEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                password: newPassword,
                role: staffRole,
                permissions: nil,
                scope: nil
            ) { result, error in
                let errDesc = error?.localizedDescription
                let createdUID = result?["uid"] as? String
                DispatchQueue.main.async {
                    if let errDesc {
                        self.isSaving = false
                        self.validationError = errDesc
                        return
                    }

                    if let createdUID {
                        self.updateUserCapabilities(uid: createdUID) {
                            self.isSaving = false
                            self.onSaved(Language.get("Staff_Access_Create", alter: "تم إنشاء عضو الفريق وتفعيل الصلاحيات بنجاح"))
                        }
                    } else {
                        self.isSaving = false
                        self.onSaved(Language.get("Staff_Access_Create", alter: "تم إنشاء عضو الفريق وتفعيل الصلاحيات بنجاح"))
                    }
                }
            }
        } else {
            // Assign existing user
            guard !selectedUserUID.isEmpty else {
                isSaving = false
                validationError = Language.get("Staff_Select_Existing_User", alter: "يرجى تحديد حساب مستخدم أولاً")
                return
            }

            AdminService.assignExistingUser(
                asStaff: selectedUserUID,
                role: staffRole,
                permissions: nil,
                scope: nil
            ) { _, error in
                let errDesc = error?.localizedDescription
                DispatchQueue.main.async {
                    if let errDesc {
                        self.isSaving = false
                        self.validationError = errDesc
                        return
                    }

                    self.updateUserCapabilities(uid: self.selectedUserUID) {
                        self.isSaving = false
                        self.onSaved(Language.get("Saved", alter: "تم ربط الحساب وتحديث الصلاحيات بنجاح"))
                    }
                }
            }
        }
    }

    private func updateUserCapabilities(uid: String, completion: @escaping @MainActor @Sendable () -> Void) {
        let features: [String: Any] = [
            "canPostAds": canPostAnimalAds,
            "canPostAnimalAds": canPostAnimalAds,
            "canPostAdoptionAds": canPostAdoptionAds,
            "canPostServices": canPostServices,
            "verified": isVerified,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        Firestore.firestore().collection("UsersCol").document(uid).setData(features, merge: true) { _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}

// MARK: - Interactive Deep Staff Permissions Inspector Sheet

private struct AdminStaffPermissionsInspectorSheet: View {
    let role: StaffRoleOption
    let staffDoc: PPStaffDoc?
    let onDismiss: () -> Void

    @State private var selectedDomainIndex: Int = 0

    private struct PermissionItem: Identifiable {
        let id: String
        let title: String
        let domain: String
        let domainIcon: String
        let isGranted: Bool
    }

    private var allPermissions: [PermissionItem] {
        [
            // Inventory & Catalog
            PermissionItem(id: "stock.view", title: "استعراض الكتالوج والمستلزمات", domain: "المخزون والمنتجات", domainIcon: "cube.box.fill", isGranted: role != .viewer && role != .supportAgent),
            PermissionItem(id: "stock.manage", title: "تعديل تفاصيل وأسعار المخزون", domain: "المخزون والمنتجات", domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .inventoryManager),
            PermissionItem(id: "stock.create", title: "إضافة منتجات جديدة للكتالوج", domain: "المخزون والمنتجات", domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .inventoryManager),
            PermissionItem(id: "stock.delete", title: "حذف وأرشفة المنتجات", domain: "المخزون والمنتجات", domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .inventoryManager),
            PermissionItem(id: "categories.manage", title: "إدارة وتصنيف الأقسام", domain: "المخزون والمنتجات", domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .inventoryManager),

            // Payments & Financials
            PermissionItem(id: "payments.view", title: "استعراض سجل المعاملات المالية", domain: "المدفوعات والمحاسبة", domainIcon: "creditcard.fill", isGranted: role != .viewer && role != .supportAgent),
            PermissionItem(id: "payments.manage", title: "إدارة بوابات الدفع والمعاملات", domain: "المدفوعات والمحاسبة", domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),
            PermissionItem(id: "payments.refund", title: "تنفيذ استرداد المبالغ للعملاء", domain: "المدفوعات والمحاسبة", domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),
            PermissionItem(id: "pos.sell", title: "تنفيذ مبيعات الكاشير ونقاط البيع", domain: "المدفوعات والمحاسبة", domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .paymentsManager),
            PermissionItem(id: "delivery.cod.reconcile", title: "تحصيل ومطابقة الدفع عند الاستلام", domain: "المدفوعات والمحاسبة", domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),
            PermissionItem(id: "accounting.view", title: "الدفاتر والقيود المحاسبية", domain: "المدفوعات والمحاسبة", domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),

            // Orders & Fulfillment
            PermissionItem(id: "orders.view", title: "استعراض طلبات الشراء والمبيعات", domain: "الطلبات والتنفيذ", domainIcon: "shippingbox.fill", isGranted: role != .viewer),
            PermissionItem(id: "orders.manage", title: "تعديل حالات ومسارات الطلبات", domain: "الطلبات والتنفيذ", domainIcon: "shippingbox.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager),
            PermissionItem(id: "fulfillment.manage", title: "توزيع وتعيين مزودي الشحن", domain: "الطلبات والتنفيذ", domainIcon: "shippingbox.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager),
            PermissionItem(id: "delivery.settings.manage", title: "إعدادات شركات التوصيل", domain: "الطلبات والتنفيذ", domainIcon: "shippingbox.fill", isGranted: role == .owner || role == .superAdmin),

            // Customers & Support
            PermissionItem(id: "users.view", title: "استعراض دليل حسابات العملاء", domain: "العملاء والدعم", domainIcon: "person.2.fill", isGranted: role != .viewer),
            PermissionItem(id: "users.manage", title: "تعديل بيانات وحسابات العملاء", domain: "العملاء والدعم", domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .supportAgent),
            PermissionItem(id: "users.features.manage", title: "إدارة مزايا وصلاحيات المستخدمين", domain: "العملاء والدعم", domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .supportAgent),
            PermissionItem(id: "users.restrictions.manage", title: "حظر وتقييد حسابات المخالفين", domain: "العملاء والدعم", domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .supportAgent),
            PermissionItem(id: "support.manage", title: "إدارة محادثات وتذاكر الدعم الفني", domain: "العملاء والدعم", domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .supportAgent),

            // System Security & IAM
            PermissionItem(id: "staff.view", title: "استعراض قائمة أعضاء الفريق", domain: "الأمان والنظام", domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager),
            PermissionItem(id: "staff.manage", title: "تعديل رتب وصلاحيات الموظفين", domain: "الأمان والنظام", domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin),
            PermissionItem(id: "audit.view", title: "سجل التدقيق الأمني الشامل", domain: "الأمان والنظام", domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin),
            PermissionItem(id: "notifications.manage", title: "إرسال الإشعارات الشاملة للمستخدمين", domain: "الأمان والنظام", domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager)
        ]
    }

    private var domains: [String] {
        Array(Set(allPermissions.map { $0.domain })).sorted()
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Header Role Badge
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(role.accentColor.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: role.icon)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(role.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(role.title)
                                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .title3))
                                        .foregroundColor(AdminSurface.primaryText)
                                    Text(role.clearanceTier)
                                        .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                                        .foregroundColor(role.accentColor)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(role.accentColor.opacity(0.12), in: Capsule())
                                }

                                Text(role.subtitle)
                                    .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))

                        // Grouped Permissions List
                        VStack(spacing: 14) {
                            ForEach(domains, id: \.self) { domain in
                                let items = allPermissions.filter { $0.domain == domain }
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        if let first = items.first {
                                            Image(systemName: first.domainIcon)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(AdminSurface.primary)
                                        }
                                        Text(domain)
                                            .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .caption))
                                            .foregroundColor(AdminSurface.secondaryText)
                                        Spacer()
                                        let grantedCount = items.filter { $0.isGranted }.count
                                        Text("\(grantedCount)/\(items.count)")
                                            .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                                            .foregroundColor(grantedCount > 0 ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
                                    }

                                    VStack(spacing: 0) {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { index, perm in
                                            HStack(spacing: 10) {
                                                Image(systemName: perm.isGranted ? "checkmark.circle.fill" : "nosign")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(perm.isGranted ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText.opacity(0.4))

                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(perm.title)
                                                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .body))
                                                        .foregroundColor(perm.isGranted ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                                    Text(perm.id)
                                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                                        .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                                                }

                                                Spacer()

                                                Text(perm.isGranted ? "مفوّض" : "محظور")
                                                    .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                                                    .foregroundColor(perm.isGranted ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText.opacity(0.5))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        perm.isGranted ? Color(uiColor: .ppSuccess).opacity(0.10) : AdminSurface.control,
                                                        in: Capsule()
                                                    )
                                            }
                                            .padding(.vertical, 9)

                                            if index < items.count - 1 {
                                                Divider().background(AdminSurface.hairline)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline))
                                }
                            }
                        }
                    }
                    .padding(AdminSpacing.screenMargin)
                }
            }
            .navigationTitle("فحص وتدقيق الصلاحيات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") {
                        onDismiss()
                    }
                    .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                    .foregroundColor(AdminSurface.primary)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}