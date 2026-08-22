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
    case superAdmin = "super_admin"
    case owner = "owner"
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

    var defaultPermissionsCount: Int {
        switch self {
        case .superAdmin: return 32
        case .owner: return 32
        case .operationsManager: return 20
        case .inventoryManager: return 12
        case .paymentsManager: return 10
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

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AdminSpacing.sectionSpacing) {
                    dossierHeaderView
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
        .onChange(of: viewModel.searchText) { _ in
            viewModel.applyFilter()
        }
        .onChange(of: viewModel.selectedFilter) { _ in
            viewModel.applyFilter()
        }
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

    // MARK: - Dossier Header (PPAccessoryEditorView Pattern)

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Button(action: {
                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Back", alter: "رجوع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(minHeight: 44)
                }

                Spacer()

                if viewModel.isLoading {
                    ProgressView().tint(AdminSurface.primary)
                } else {
                    Button(action: { viewModel.startListening() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                            .frame(width: 36, height: 36)
                            .background(AdminSurface.primary.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
                }
            }

            Text(Language.get("CommandCenter_Customers_Workspace", alter: "مساحة العملاء") + " / " + Language.get("StaffMembers_Title", alter: "فريق العمل"))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.top, 2)

            Text(Language.get("StaffMembers_Title", alter: "فريق العمل والوصول"))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)

            if let error = viewModel.errorMessage {
                AdminErrorBanner(message: error) { viewModel.startListening() }
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

// MARK: - Staff Member Editor View (Exact Screenshot 3 Match)

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
    @State private var showPermissionsBreakdown: Bool = false

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
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        heroCard
                        identitySection
                        accessPostureSection
                        accountCapabilitiesSection

                        if let error = validationError {
                            AdminErrorBanner(message: error)
                        }

                        saveButton
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.vertical, AdminSpacing.base)
                }
            }
            .navigationTitle(isEditing ? Language.get("Staff_EditMember_Title", alter: "تعديل عضو الفريق") : Language.get("Staff_Create_New", alter: "إضافة موظف جديد"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: nil)) { onDismiss() }
                }
            }
            .onAppear {
                loadExistingUserCapabilities()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Hero Summary Card (Screenshot 3 Header)

    private var heroCard: some View {
        AdminCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    // Avatar Shell
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Eyebrow
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Staff_Access_Eyebrow", alter: "إدارة الفريق والوصول"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(AdminSurface.primary)

                        // Title
                        Text(isEditing ? Language.get("Staff_EditMember_Title", alter: "تعديل عضو الفريق") : Language.get("Staff_Access_Create_Title", alter: "إضافة موظف جديد"))
                            .font(AdminType.title3)
                            .foregroundColor(AdminSurface.primaryText)

                        // Subtitle
                        Text(Language.get("Staff_EditMember_Subtitle", alter: "راجع وصول الموظف ودوره وصلاحياته وميزات التطبيق قبل الحفظ."))
                            .font(AdminType.footnote)
                            .foregroundColor(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Action Link with Checkmark
                Button {
                    saveSettings()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().tint(AdminSurface.primary).scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(Language.get("Staff_Access_Save", alter: "حفظ إعدادات الوصول"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                }
                .disabled(isSaving)
                .frame(maxWidth: .infinity, alignment: .trailing)

                // 3-Segment Summary Status Bar
                HStack(spacing: 0) {
                    // Status Pill
                    Text(isActive ? Language.get("Active", alter: "نشط") : Language.get("Disabled", alter: "معطل"))
                        .font(AdminType.captionBold)
                        .foregroundColor(isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                    Divider().frame(height: 20)

                    // Role Pill
                    Text(selectedRole.title)
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                    Divider().frame(height: 20)

                    // Permissions Pill
                    Text(String(format: Language.get("Staff_Access_Module_Permissions_Format", alter: "%lu صلاحية"), selectedRole.defaultPermissionsCount))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
            }
            .padding(AdminSpacing.cardPadding)
        }
    }

    // MARK: - Section 1: Member Identity (هوية العضو)

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Staff_Access_Identity_Title", alter: "هوية العضو"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("Staff_Access_Identity_Subtitle", alter: "اختر الحساب الذي سيحمل وصول الفريق."))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            AdminCard {
                VStack(alignment: .leading, spacing: 14) {
                    if !isEditing {
                        Picker("", selection: $isCreatingAccount) {
                            Text(Language.get("Staff_Assign_Existing", alter: "ربط حساب قائم")).tag(false)
                            Text(Language.get("Staff_Create_New", alter: "إنشاء حساب جديد")).tag(true)
                        }
                        .pickerStyle(.segmented)

                        Divider()
                    }

                    if isCreatingAccount && !isEditing {
                        VStack(spacing: 12) {
                            editorField(title: Language.get("Name", alter: "الاسم"), text: $newName, placeholder: "اسم الموظف")
                            Divider()
                            editorField(title: Language.get("Email", alter: "البريد الإلكتروني"), text: $newEmail, placeholder: "staff@purepets.qa", keyboard: .emailAddress)
                            Divider()
                            editorField(title: Language.get("Password", alter: "كلمة المرور"), text: $newPassword, placeholder: "••••••••", isSecure: true)
                            Divider()
                            editorField(title: Language.get("Phone", alter: "الهاتف"), text: $newPhone, placeholder: "+974 0000 0000", keyboard: .phonePad)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(Language.get("User", alter: "مستخدم"))
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)
                                Spacer()
                                Rectangle().fill(AdminSurface.primary).frame(width: 3, height: 14).cornerRadius(1.5)
                            }

                            if isEditing {
                                HStack {
                                    Text(selectedUserDisplayName.isEmpty ? (staffDoc?.displayName ?? "") : selectedUserDisplayName)
                                        .font(AdminType.body)
                                        .foregroundColor(AdminSurface.primaryText)
                                    Spacer()
                                    if let email = staffDoc?.email {
                                        Text(email)
                                            .font(AdminType.caption1)
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                HStack {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AdminSurface.secondaryText)

                                    TextField(Language.get("Staff_Select_User_Search_Placeholder", alter: "لدي حساب بالفعل"), text: $existingUserSearch)
                                        .font(AdminType.body)
                                        .foregroundColor(AdminSurface.primaryText)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Section 2: Access Posture (وضع الوصول)

    private var accessPostureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Staff_Access_Posture_Title", alter: "وضع الوصول"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("Staff_Access_Posture_Subtitle", alter: "حدّد الدور والحالة التشغيلي قبل الحفظ."))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            AdminCard {
                VStack(spacing: 14) {
                    // Role Picker
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Language.get("Staff_Role", alter: "دور الموظف"))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Rectangle().fill(AdminSurface.primary).frame(width: 3, height: 14).cornerRadius(1.5)
                        }

                        Menu {
                            ForEach(StaffRoleOption.allCases) { role in
                                Button {
                                    selectedRole = role
                                } label: {
                                    HStack {
                                        Text(role.title)
                                        if selectedRole == role {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AdminSurface.secondaryText)

                                Text(selectedRole.title)
                                    .font(AdminType.body)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
                        }
                    }

                    Divider()

                    // Active Toggle
                    HStack {
                        Toggle(isOn: $isActive) {
                            HStack {
                                Text(Language.get("Active", alter: "نشط"))
                                    .font(AdminType.body)
                                    .foregroundColor(AdminSurface.primaryText)
                                Spacer()
                                Rectangle().fill(AdminSurface.primary).frame(width: 3, height: 14).cornerRadius(1.5)
                            }
                        }
                        .tint(AdminSurface.primary)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Section 3: Account Capabilities (قدرات الحساب)

    private var accountCapabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Staff_Access_Capabilities_Title", alter: "قدرات الحساب"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("Staff_Access_Capabilities_Subtitle", alter: "تُحدّث هذه المزايا ملف المستخدم ولا تمنح صلاحيات الإدارة."))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            AdminCard {
                VStack(spacing: 14) {
                    capabilityToggleRow(title: "نشر إعلانات الحيوانات", binding: $canPostAnimalAds)
                    Divider()
                    capabilityToggleRow(title: "نشر إعلانات التبني", binding: $canPostAdoptionAds)
                    Divider()
                    capabilityToggleRow(title: "نشر الخدمات", binding: $canPostServices)
                    Divider()
                    capabilityToggleRow(title: "حساب موثق", binding: $isVerified)
                }
                .padding(14)
            }
        }
    }

    private func capabilityToggleRow(title: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack {
                Text(title)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Rectangle().fill(AdminSurface.primary).frame(width: 3, height: 14).cornerRadius(1.5)
            }
        }
        .tint(AdminSurface.primary)
    }

    private func editorField(title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
            } else {
                TextField(placeholder, text: text)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
            }
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveSettings()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(Language.get("Save", alter: "حفظ"))
                    .font(AdminType.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
        }
        .disabled(isSaving)
        .padding(.top, 8)
    }

    // MARK: - Data Operations

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
                validationError = Language.get("Error_RequiredFields", alter: "Please enter name and email.")
                return
            }
            guard newPassword.count >= 8 else {
                validationError = Language.get("Staff_Error_Password_Min", alter: "Password must be at least 8 characters.")
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
                        self.onSaved(Language.get("Saved", alter: "تم الحفظ بنجاح"))
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
                            self.onSaved(Language.get("Staff_Access_Create", alter: "تم إنشاء عضو الفريق بنجاح"))
                        }
                    } else {
                        self.isSaving = false
                        self.onSaved(Language.get("Staff_Access_Create", alter: "تم إنشاء عضو الفريق بنجاح"))
                    }
                }
            }
        } else {
            // Assign existing user
            guard !selectedUserUID.isEmpty else {
                isSaving = false
                validationError = Language.get("Staff_Select_Existing_User", alter: "اختر مستخدمًا أولاً")
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
                        self.onSaved(Language.get("Saved", alter: "تم ربط الحساب وتحديث الصلاحيات"))
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