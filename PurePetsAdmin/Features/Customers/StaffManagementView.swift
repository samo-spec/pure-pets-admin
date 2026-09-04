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
        case .owner: return Language.get("ClearanceTier_Owner", alter: "سلطة سيادية عليا • Tier 1")
        case .superAdmin: return Language.get("ClearanceTier_SuperAdmin", alter: "إدارة النظام العليا • Tier 1")
        case .operationsManager: return Language.get("ClearanceTier_OperationsManager", alter: "قيادة العمليات • Tier 2")
        case .inventoryManager: return Language.get("ClearanceTier_InventoryManager", alter: "إدارة المخزون • Tier 2")
        case .paymentsManager: return Language.get("ClearanceTier_PaymentsManager", alter: "إدارة الخزينة والمالية • Tier 2")
        case .supportAgent: return Language.get("ClearanceTier_SupportAgent", alter: "خدمة العملاء • Tier 3")
        case .viewer: return Language.get("ClearanceTier_Viewer", alter: "اطلاع ومراقبة • Tier 4")
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
                self.enrichStaffMembersFromUsersCol()
            }
        }
    }

    private func enrichStaffMembersFromUsersCol() {
        let missing = staffMembers.filter { ($0.displayName?.isEmpty ?? true) || ($0.email?.isEmpty ?? true) }
        guard !missing.isEmpty else { return }

        let db = Firestore.firestore()
        for member in missing {
            guard !member.uid.isEmpty else { continue }
            db.collection("UsersCol").document(member.uid).getDocument { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data(), snapshot?.exists == true else { return }
                DispatchQueue.main.async {
                    let name = (data["UserName"] as? String)
                        ?? (data["displayName"] as? String)
                        ?? (data["FirstName"] as? String)
                        ?? (data["name"] as? String)
                        ?? (data["FullName"] as? String)
                    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                        member.displayName = name
                    }
                    let email = (data["UserEmail"] as? String)
                        ?? (data["email"] as? String)
                        ?? (data["mail"] as? String)
                    if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
                        member.email = email
                    }
                    let phone = (data["MobileNo"] as? String)
                        ?? (data["phone"] as? String)
                        ?? (data["phoneNumber"] as? String)
                    if let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                        member.phone = phone
                    }
                    let photo = (data["UserImageUrl"] as? String)
                        ?? (data["photoURL"] as? String)
                        ?? (data["photoUrl"] as? String)
                        ?? (data["UserImageName"] as? String)
                    if let photo = photo?.trimmingCharacters(in: .whitespacesAndNewlines), !photo.isEmpty {
                        member.photoURL = photo
                    }
                    let verified = (data["verified"] as? Bool) ?? (data["isVerified"] as? Bool) ?? false
                    member.isVerified = verified
                    self.applyFilter()
                }
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
    @State private var isShowingRoleRankMatrix = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    dossierHeaderView

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: AdminSpacing.sectionSpacing) {
                            staffCommandCockpit
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

                // Push Navigation Link for Editing Member
                NavigationLink(
                    destination: Group {
                        if let member = selectedMemberForEdit {
                            AdminStaffMemberEditorView(
                                staffDoc: member,
                                onDismiss: { selectedMemberForEdit = nil },
                                onSaved: { msg in
                                    selectedMemberForEdit = nil
                                    showToast(msg, isError: false)
                                }
                            )
                        }
                    },
                    isActive: Binding(
                        get: { selectedMemberForEdit != nil },
                        set: { if !$0 { selectedMemberForEdit = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()

                // Push Navigation Link for Creating New Member
                NavigationLink(
                    destination: AdminStaffMemberEditorView(
                        staffDoc: nil,
                        onDismiss: { isCreatingNew = false },
                        onSaved: { msg in
                            isCreatingNew = false
                            showToast(msg, isError: false)
                        }
                    ),
                    isActive: $isCreatingNew
                ) {
                    EmptyView()
                }
                .hidden()

                // Push Navigation Link for Sovereign Role Rank & Security Levels Matrix
                NavigationLink(
                    destination: AdminRoleRankSecurityLevelsView(
                        onDismiss: { isShowingRoleRankMatrix = false }
                    ),
                    isActive: $isShowingRoleRankMatrix
                ) {
                    EmptyView()
                }
                .hidden()

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
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
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

    // MARK: - Reimagined Command Cockpit (Hero + Telemetry Matrix + Precision Search)

    private var staffCommandCockpit: some View {
        VStack(spacing: 14) {
            // ─── TIER 1: Executive Identity & Fast Provisioning Dock ───
            HStack(alignment: .center, spacing: 14) {
                // Holographic Security Crest / Avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AdminSurface.primary,
                                    Color(red: 0.92, green: 0.18, blue: 0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.28), radius: 10, x: 0, y: 4)

                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                .accessibilityHidden(true)

                // Identity Typography Stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("StaffMembers_Title", alter: "أعضاء الفريق والوصول"))
                        .font(Font.custom("Beiruti-Bold", size: 21))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(Language.get("StaffMembers_Subtitle", alter: "إدارة الصلاحيات والوصول الإداري."))
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Flagship Quick Provisioning Action (+ Create Account)
                if viewModel.canManage {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isCreatingNew = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .black))
                            Text(Language.get("Staff_Create_New", alter: "إنشاء حساب"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.32), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(StaffCockpitPressStyle())
                    .accessibilityLabel(Language.get("Staff_Create_New", alter: nil))
                }
            }

            // ─── TIER 2: Interactive Telemetry Spectrum (Metrics Fused With Filters) ───
            HStack(spacing: 8) {
                cockpitTelemetryTab(
                    filter: .all,
                    count: viewModel.totalCount,
                    title: Language.get("All", alter: "الكل"),
                    symbol: "person.3.fill",
                    accentColor: AdminSurface.primary
                )

                cockpitTelemetryTab(
                    filter: .active,
                    count: viewModel.activeCount,
                    title: Language.get("Active", alter: "نشط"),
                    symbol: "checkmark.shield.fill",
                    accentColor: Color(uiColor: .ppSuccess)
                )

                cockpitTelemetryTab(
                    filter: .disabled,
                    count: viewModel.disabledCount,
                    title: Language.get("Disabled", alter: "معطل"),
                    symbol: "slash.circle.fill",
                    accentColor: Color(uiColor: .ppWarning)
                )
            }
            .padding(4)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )

            // ─── TIER 2.5: Sovereign Role Rank & Security Levels Matrix Entry Deck ───
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isShowingRoleRankMatrix = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.82, green: 0.12, blue: 0.28),
                                        Color(red: 0.50, green: 0.10, blue: 0.60)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
                            )
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(Language.get("RoleRank_Entry_Button", alter: "مصفوفة رتب الأدوار ومستويات الأمان"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundColor(AdminSurface.primaryText)
                            Text("IAM")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(Color(red: 0.82, green: 0.12, blue: 0.28))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(red: 0.82, green: 0.12, blue: 0.28).opacity(0.12), in: Capsule())
                        }

                        Text(Language.get("RoleRank_Entry_Subtitle", alter: "حوكمة تسلسل القيادة وحصانة الصلاحيات"))
                            .font(Font.custom("Beiruti-Regular", size: 11.5))
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.82, green: 0.12, blue: 0.28).opacity(0.2), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(StaffCockpitPressStyle())

            // ─── TIER 3: Precision Search & Match Radar ───
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(viewModel.searchText.isEmpty ? AdminSurface.secondaryText : AdminSurface.primary)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20, height: 20)

                TextField(Language.get("Search", alter: "بحث في أعضاء الفريق..."), text: $viewModel.searchText)
                    .font(Font.custom("Beiruti-Medium", size: 14.5))
                    .foregroundColor(AdminSurface.primaryText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                // Match Radar Telemetry Pill
                if !viewModel.searchText.isEmpty {
                    Text("\(viewModel.filteredStaff.count) / \(viewModel.totalCount)")
                        .font(Font.custom("Beiruti-Bold", size: 11.5))
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        .transition(.scale.combined(with: .opacity))

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        !viewModel.searchText.isEmpty ? AdminSurface.primary.opacity(0.35) : AdminSurface.hairline,
                        lineWidth: 0.75
                    )
            )
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 5)
    }

    private func cockpitTelemetryTab(
        filter: AdminStaffManagementViewModel.StaffStatusFilter,
        count: Int,
        title: String,
        symbol: String,
        accentColor: Color
    ) -> some View {
        let isSelected = viewModel.selectedFilter == filter

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) {
                viewModel.selectedFilter = filter
            }
        } label: {
            HStack(spacing: 8) {
                // Live Status Indicator Icon / Glyph
                ZStack {
                    Circle()
                        .fill(isSelected ? accentColor.opacity(0.18) : accentColor.opacity(0.10))
                        .frame(width: 26, height: 26)

                    if filter == .active {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(accentColor.opacity(0.4), lineWidth: 2)
                                    .scaleEffect(isSelected ? 1.4 : 1.0)
                            )
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                }

                // Data Metric & Label Stack
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("\(count)")
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.primaryText.opacity(0.85))

                        Text(title)
                            .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 12))
                            .foregroundColor(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                isSelected ? AdminSurface.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? accentColor.opacity(0.35) : Color.clear,
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected ? Color.black.opacity(0.06) : Color.clear,
                radius: 6,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(StaffCockpitPressStyle())
        .accessibilityLabel("\(title): \(count)")
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

    // MARK: - Sovereign Flagship Staff Member Card (Reimagined from First Principles)

    private func staffMemberCard(member: PPStaffDoc) -> some View {
        let isCurrent = Auth.auth().currentUser?.uid == member.uid

        return StaffMemberSovereignCard(
            member: member,
            isCurrent: isCurrent,
            onTap: {
                selectedMemberForEdit = member
            }
        )
    }

    // MARK: - Toast Banner & Notifications

    private func showToast(_ message: String, isError: Bool = false) {
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

// MARK: - Sovereign Flagship Staff Member Card Component

private struct StaffMemberSovereignCard: View {
    let member: PPStaffDoc
    let isCurrent: Bool
    let onTap: () -> Void

    private var isRTL: Bool { Language.isRTL() }
    private var isActive: Bool { member.isActive() }

    private var roleOption: StaffRoleOption? {
        StaffRoleOption(rawValue: member.roleIdentifier)
    }

    private var roleTitle: String {
        roleOption?.title ?? PPAdminSessionBridge.localizedRoleName(for: member.roleIdentifier)
    }

    private var roleAccentColor: Color {
        roleOption?.accentColor ?? AdminSurface.primary
    }

    private var roleIcon: String {
        roleOption?.icon ?? "shield.fill"
    }

    private var permsCount: Int {
        member.permissions.count > 0 ? member.permissions.count : (roleOption?.defaultPermissionsCount ?? 0)
    }

    private var userInitials: String {
        let name = (member.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "عضو فريق", name != "Staff Member" else {
            if let email = member.email, !email.isEmpty {
                return String(email.prefix(2)).uppercased()
            }
            return "PP"
        }
        let comps = name.components(separatedBy: " ").filter { !$0.isEmpty }
        if comps.count >= 2, let f = comps.first?.first, let l = comps.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                avatarView
                identityAndMetadataView
                trailingActionView
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.surface)
                    .overlay(
                        LinearGradient(
                            colors: [
                                roleAccentColor.opacity(0.035),
                                Color.clear
                            ],
                            startPoint: isRTL ? .trailing : .leading,
                            endPoint: isRTL ? .leading : .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isCurrent
                            ? AdminSurface.primary.opacity(0.4)
                            : (isActive ? AdminSurface.hairline : Color.orange.opacity(0.25)),
                        lineWidth: isCurrent ? 1.2 : 0.75
                    )
            )
            .shadow(color: Color.black.opacity(0.035), radius: 8, y: 3)
        }
        .buttonStyle(StaffCardPressStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Avatar & Authority Emblem

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let photo = member.photoURL, let url = URL(string: photo), !photo.isEmpty {
                    AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 52, height: 52)) {
                        monogramFallback
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    monogramFallback
                }
            }
            .frame(width: 52, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isCurrent ? AdminSurface.primary.opacity(0.4) : roleAccentColor.opacity(0.25), lineWidth: 1.2)
            )

            // Live presence beacon
            Circle()
                .fill(isActive ? Color(red: 0.12, green: 0.78, blue: 0.45) : Color.orange)
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(AdminSurface.surface, lineWidth: 2.2))
                .shadow(color: isActive ? Color.green.opacity(0.4) : Color.orange.opacity(0.3), radius: 3, y: 1)
                .offset(x: 2, y: 2)
        }
        .frame(width: 54, height: 54)
    }

    private var monogramFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    roleAccentColor.opacity(0.95),
                    roleAccentColor.opacity(0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(userInitials)
                .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Identity & Operational Metadata

    private var identityAndMetadataView: some View {
        VStack(alignment: .leading, spacing: 3.5) {
            // Row 1: Name + Current Pill + Verified Badge
            HStack(spacing: 6) {
                Text(member.displayName ?? Language.get("Staff_Edit_Existing", alter: "عضو فريق"))
                    .font(Font.custom("Beiruti-Bold", size: 16.5, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                if isCurrent {
                    HStack(spacing: 3) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 8))
                        Text(Language.get("You", alter: "أنت"))
                            .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, Color(red: 1.0, green: 0.35, blue: 0.48)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.25), radius: 3, y: 1)
                }

                if member.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.15, green: 0.52, blue: 0.95))
                }
            }

            // Row 2: Contact Info (Email or Phone)
            if let email = member.email, !email.isEmpty {
                HStack(spacing: 4.5) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 9))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.75))

                    Text(email)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            } else if let phone = member.phone, !phone.isEmpty {
                HStack(spacing: 4.5) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 9))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.75))

                    Text(phone)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }

            // Row 3: Role Insignia + Permissions Count + Scope
            HStack(spacing: 6) {
                // Role Capsule
                HStack(spacing: 4) {
                    Image(systemName: roleIcon)
                        .font(.system(size: 9.5, weight: .bold))
                    Text(roleTitle)
                        .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                }
                .foregroundColor(roleAccentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(roleAccentColor.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(roleAccentColor.opacity(0.25), lineWidth: 0.6))

                // Permissions Count
                HStack(spacing: 3) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 8))
                    Text(String(format: Language.get("Staff_Access_Module_Permissions_Format", alter: "%lu صلاحية"), permsCount))
                        .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                }
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AdminSurface.control, in: Capsule())
                .overlay(Capsule().stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.5))

                // Global Scope Badge
                if member.hasGlobalScope() {
                    HStack(spacing: 3) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 8))
                        Text(Language.get("Staff_Branch_Scope_Global", alter: "شامل"))
                            .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                    }
                    .foregroundColor(Color(red: 0.10, green: 0.65, blue: 0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.10, green: 0.65, blue: 0.45).opacity(0.10), in: Capsule())
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Trailing Status & Navigation Affordance

    private var trailingActionView: some View {
        HStack(spacing: 8) {
            // Status Capsule
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive ? Color(red: 0.12, green: 0.78, blue: 0.45) : Color.orange)
                    .frame(width: 6, height: 6)

                Text(isActive ? Language.get("Active", alter: "نشط") : Language.get("Disabled", alter: "معطل"))
                    .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                    .foregroundColor(isActive ? Color(red: 0.10, green: 0.65, blue: 0.35) : Color.orange)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background((isActive ? Color.green : Color.orange).opacity(0.08), in: Capsule())

            // Chevron Action Disc
            ZStack {
                Circle()
                    .fill(AdminSurface.control)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.6))

                Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
            }
        }
    }
}

private struct StaffCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
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
    @State private var selectedUserAccount: PPCustomerAccountModel? = nil
    @State private var isUserPickerPresented: Bool = false

    @State private var isSaving: Bool = false
    @State private var validationError: String? = nil
    @State private var showPermissionsInspector: Bool = false
    @State private var toastMessage: String? = nil

    // Working branch permissions & scope
    @State private var isGlobalScope: Bool = false
    @State private var selectedBranchIDs: Set<String> = []
    @State private var defaultBranchID: String = ""
    @State private var availableBranches: [PPBranchModel] = []
    @State private var isLoadingBranches: Bool = false

    // Live User Profile Enrichment (UsersCol & PublicUserProfiles)
    @State private var loadedUserName: String? = nil
    @State private var loadedUserEmail: String? = nil
    @State private var loadedUserPhone: String? = nil
    @State private var loadedUserPhotoURL: String? = nil
    @State private var loadedUserCreatedAt: Date? = nil
    @State private var loadedUserLastSeen: Date? = nil
    @State private var isProfileLoading: Bool = false

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

        let isGlobal = (staffDoc?.hasGlobalScope() ?? false) || (initialRole == .superAdmin || initialRole == .owner)
        _isGlobalScope = State(initialValue: isGlobal)
        let initialBranches = Set(staffDoc?.assignedBranchIDs ?? [])
        _selectedBranchIDs = State(initialValue: initialBranches)
        _defaultBranchID = State(initialValue: staffDoc?.defaultBranchID ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            editorNavigationBar

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

                        // 4. Working Branch Permissions & Scope Chamber
                        workingBranchPermissionsChamber

                        // 5. Platform Profile Capabilities (Consumer/App features)
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
        }
        .background(
            NavigationLink(
                destination: AdminStaffPermissionsInspectorSheet(
                    role: selectedRole,
                    staffDoc: staffDoc,
                    onDismiss: { showPermissionsInspector = false }
                ),
                isActive: $showPermissionsInspector
            ) {
                EmptyView()
            }
            .hidden()
        )
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            loadExistingUserCapabilities()
            fetchBranches()
        }
        .onChange(of: selectedRole) { newRole in
            if newRole == .superAdmin || newRole == .owner {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    isGlobalScope = true
                }
            }
        }
        .sheet(isPresented: $isUserPickerPresented) {
            AdminUserPickerSheet(
                selectedUID: selectedUserUID,
                onSelectUser: { chosenUser in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    self.selectedUserAccount = chosenUser
                    self.selectedUserUID = chosenUser.id
                    self.selectedUserDisplayName = chosenUser.name
                    self.newEmail = chosenUser.email
                    self.newPhone = chosenUser.phone
                    if self.newName.isEmpty { self.newName = chosenUser.name }
                    self.validationError = nil
                    self.isUserPickerPresented = false
                },
                onDismiss: {
                    self.isUserPickerPresented = false
                }
            )
        }
    }

    // MARK: - Redesigned Sovereign Navigation Bar (Push Mode)

    private var editorNavigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 1. Squircle Back Button Jewel (Leading in RTL)
                AdminSquircleBackButton {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }

                // 2. Title & Protocol Badge Stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(isEditing ? Language.get("Staff_EditMember_Title", alter: "تعديل عضو الفريق") : (isCreatingAccount ? Language.get("Staff_Create_New", alter: "إنشاء حساب") : Language.get("Staff_Link_Existing", alter: "تعيين عضو فريق")))
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                        Text(Language.get("Staff_Security_Badge", alter: "بروتوكول IAM المعتمد • سحابي"))
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // 3. Trailing Action: Save Pill / Action Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    saveSettings()
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                            Text(Language.get("Save", alter: "حفظ"))
                                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(AdminSurface.primary, in: Capsule())
                    .shadow(color: AdminSurface.primary.opacity(0.32), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityLabel(Language.get("Save", alter: "حفظ"))
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(AdminSurface.background)
        }
    }

    // MARK: - 1. Executive Member Profile Deck

    // MARK: - 1. Executive Member Profile Deck

    private var executiveProfileDeck: some View {
        VStack(spacing: 14) {
            // ── Primary Identity & Presence Row ────────────────────────────
            HStack(alignment: .top, spacing: 14) {
                // Avatar with Live Presence & Status Halo
                ZStack(alignment: .bottomTrailing) {
                    if let photo = effectivePhotoURL, let url = URL(string: photo), !photo.isEmpty {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 70, height: 70)) {
                            monogramView
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        monogramView
                    }

                    // Live Status Halo
                    Circle()
                        .fill(isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                        .offset(x: 2, y: 2)
                }
                .frame(width: 70, height: 70)

                // Identity & Contact Details
                VStack(alignment: .leading, spacing: 4) {
                    // Name & Verification & Role Badge
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .headline))
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
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(selectedRole.accentColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(selectedRole.accentColor.opacity(0.25), lineWidth: 0.5))
                    }

                    // Contact: Email
                    if let email = effectiveEmail, !email.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 10))
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(email)
                                .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    // Contact: Phone
                    if let phone = effectivePhone, !phone.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 10))
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(phone)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    if effectiveEmail == nil && effectivePhone == nil {
                        if isProfileLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.65)
                                Text(Language.get("Loading_Profile_Data", alter: "جاري تحميل بيانات المستخدم..."))
                                    .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption2))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }

            Divider().background(AdminSurface.hairline)

            // ── Comprehensive Telemetry & Data Strip ("data on top hero") ──
            HStack(spacing: 8) {
                // 1. UID Chip with Copy Action
                if let uid = staffDoc?.uid ?? (selectedUserUID.isEmpty ? nil : selectedUserUID), !uid.isEmpty {
                    Button {
                        UIPasteboard.general.string = uid
                        showToast(Language.get("UID_Copied", alter: "تم نسخ معرّف الموظف (UID)"))
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "number.circle.fill")
                                .font(.system(size: 8.5))
                            Text(shortUID(uid))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.control, in: Capsule())
                        .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // 2. Created / Joined Date Chip
                if let created = loadedUserCreatedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 8.5))
                        Text(formatMemberDate(created))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.control, in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.5))
                }

                // 3. Operational Branch Scope Chip
                HStack(spacing: 4) {
                    Image(systemName: isGlobalScope ? "globe" : "building.2.fill")
                        .font(.system(size: 8.5))
                    Text(branchScopeBadgeText)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(isGlobalScope ? .blue : AdminSurface.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (isGlobalScope ? Color.blue : AdminSurface.control).opacity(isGlobalScope ? 0.08 : 1),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke((isGlobalScope ? Color.blue.opacity(0.3) : AdminSurface.hairline), lineWidth: 0.5)
                )

                Spacer(minLength: 0)
            }

            // ── Interactive Quick Contact Strip ("contant on top hero") ────
            if let phone = effectivePhone, !phone.isEmpty || (effectiveEmail != nil && !effectiveEmail!.isEmpty) {
                HStack(spacing: 8) {
                    if let phone = effectivePhone, !phone.isEmpty {
                        // WhatsApp Button
                        quickContactButton(
                            title: Language.get("WhatsApp", alter: Language.isRTL() ? "واتساب" : "WhatsApp"),
                            icon: "message.fill",
                            color: Color(red: 37/255, green: 211/255, blue: 102/255)
                        ) {
                            let digits = phone.filter { "0123456789".contains($0) }
                            guard let url = URL(string: "https://wa.me/\(digits)") else { return }
                            UIApplication.shared.open(url)
                        }

                        // Phone Call Button
                        quickContactButton(
                            title: Language.get("Call", alter: Language.isRTL() ? "اتصال" : "Call"),
                            icon: "phone.fill",
                            color: AdminSurface.primary
                        ) {
                            let clean = phone.filter { "0123456789+".contains($0) }
                            guard let url = URL(string: "tel://\(clean)") else { return }
                            UIApplication.shared.open(url)
                        }
                    }

                    if let email = effectiveEmail, !email.isEmpty {
                        // Email Button
                        quickContactButton(
                            title: Language.get("Email", alter: Language.isRTL() ? "بريد" : "Email"),
                            icon: "envelope.fill",
                            color: Color(red: 0.12, green: 0.50, blue: 0.90)
                        ) {
                            guard let url = URL(string: "mailto:\(email)") else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
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
        .frame(width: 70, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var displayName: String {
        if let loaded = loadedUserName, !loaded.isEmpty { return loaded }
        if !selectedUserDisplayName.isEmpty { return selectedUserDisplayName }
        if let name = staffDoc?.displayName, !name.isEmpty { return name }
        return Language.get("Staff_Member_Default", alter: "عضو الفريق")
    }

    private var effectiveEmail: String? {
        if let loaded = loadedUserEmail, !loaded.isEmpty { return loaded }
        if let email = staffDoc?.email, !email.isEmpty { return email }
        return nil
    }

    private var effectivePhone: String? {
        if let loaded = loadedUserPhone, !loaded.isEmpty { return loaded }
        if let phone = staffDoc?.phone, !phone.isEmpty { return phone }
        return nil
    }

    private var effectivePhotoURL: String? {
        if let loaded = loadedUserPhotoURL, !loaded.isEmpty { return loaded }
        if let photo = staffDoc?.photoURL, !photo.isEmpty { return photo }
        return nil
    }

    private var userInitials: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "عضو الفريق", name != "Staff Member" else {
            if let email = effectiveEmail, !email.isEmpty {
                return String(email.prefix(2)).uppercased()
            }
            return "PP"
        }
        let comps = name.components(separatedBy: " ").filter { !$0.isEmpty }
        if comps.count >= 2, let f = comps.first?.first, let l = comps.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var selectedUserInitials: String {
        let name = selectedUserDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "PP" }
        let comps = name.components(separatedBy: " ").filter { !$0.isEmpty }
        if comps.count >= 2, let f = comps.first?.first, let l = comps.last?.first {
            return "\(f)\(l)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var branchScopeBadgeText: String {
        if isGlobalScope {
            return Language.get("Staff_Scope_Global", alter: Language.isRTL() ? "وصول عام" : "Global Scope")
        }
        if !defaultBranchID.isEmpty, let branch = availableBranches.first(where: { $0.branchID == defaultBranchID }) {
            return branch.localizedName()
        }
        if !selectedBranchIDs.isEmpty {
            return String(format: Language.get("Staff_Branches_Count", alter: "%d فروع"), selectedBranchIDs.count)
        }
        return Language.get("Staff_Scope_Unset", alter: Language.isRTL() ? "غير محدد" : "Unset")
    }

    private func formatMemberDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        let prefix = Language.get("Staff_Member_Joined_Prefix", alter: Language.isRTL() ? "انضم: " : "Joined: ")
        return prefix + formatter.string(from: date)
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

                                    Text(String.localizedStringWithFormat(Language.get("Staff_Access_Module_Permissions_Format", alter: "%ld صلاحية"), role.defaultPermissionsCount))
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

    // MARK: - 3.5 Working Branch Permissions & Scope Chamber

    private var workingBranchPermissionsChamber: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Chamber Header
            HStack(spacing: 8) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("Staff_Branch_Scope_Title", alter: "نطاق العمل وفروع الصلاحيات"))
                    .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                // Scope Status Badge
                HStack(spacing: 4) {
                    Image(systemName: isGlobalScope ? "globe.americas.fill" : "mappin.circle.fill")
                        .font(.system(size: 9))
                    Text(isGlobalScope ? Language.get("Staff_Branch_Global_Pill", alter: "وصول شامل لكافة الفروع") : "\(selectedBranchIDs.count) " + Language.get("Staff_Branch_Count_Pill", alter: "فروع محددة"))
                        .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                }
                .foregroundColor(isGlobalScope ? Color.emerald600 : AdminSurface.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((isGlobalScope ? Color.emerald600 : AdminSurface.primary).opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke((isGlobalScope ? Color.emerald600 : AdminSurface.primary).opacity(0.25), lineWidth: 0.5))
            }

            VStack(spacing: 12) {
                // Card 1: Global Scope Toggle
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        isGlobalScope.toggle()
                        if !isGlobalScope && selectedBranchIDs.isEmpty {
                            if let firstBranch = availableBranches.first {
                                selectedBranchIDs.insert(firstBranch.branchID)
                                defaultBranchID = firstBranch.branchID
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill((isGlobalScope ? Color.emerald600 : Color.gray).opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: "globe")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(isGlobalScope ? Color.emerald600 : Color.gray)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Staff_Branch_Global_Access", alter: "وصول شامل لكافة الفروع (Global Scope)"))
                                .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("Staff_Branch_Global_Access_Desc", alter: "يمنح العضو صلاحية التنقل والوصول والعمل عبر كافة فروع ومستودعات المنصة"))
                                .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(2)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { isGlobalScope },
                            set: { val in
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                    isGlobalScope = val
                                    if !isGlobalScope && selectedBranchIDs.isEmpty {
                                        if let firstBranch = availableBranches.first {
                                            selectedBranchIDs.insert(firstBranch.branchID)
                                            defaultBranchID = firstBranch.branchID
                                        }
                                    }
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(Color.emerald600)
                    }
                    .padding(14)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isGlobalScope ? Color.emerald600.opacity(0.3) : AdminSurface.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Card 2: Specific Branches Assignment (Visible when Global Access is OFF)
                if !isGlobalScope {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(Language.get("Staff_Branch_Authorized_List", alter: "فروع العمل المصرح بها"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(Language.get("Staff_Branch_Tap_Hint", alter: "انقر لتحديد الفروع أو تعيين الفرع الافتراضي"))
                                .font(Font.custom("Beiruti-Regular", size: 10.5, relativeTo: .caption2))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.8))
                        }

                        if isLoadingBranches {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 16)
                                Spacer()
                            }
                        } else if availableBranches.isEmpty {
                            HStack {
                                Spacer()
                                Text(Language.get("Branches_Empty", alter: "لا توجد فروع مسجلة في النظام"))
                                    .font(Font.custom("Beiruti-Medium", size: 12, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .padding(.vertical, 14)
                                Spacer()
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(availableBranches, id: \.branchID) { branch in
                                    branchSelectionRow(branch: branch)
                                }
                            }
                        }

                        // Validation Helper
                        if selectedBranchIDs.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(uiColor: .ppWarning))
                                Text(Language.get("Staff_Branch_Selection_Empty_Warning", alter: "تنبيه: يجب اختيار فرع واحد على الأقل، أو تفعيل خيار الوصول الشامل لجميع الفروع."))
                                    .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                                    .foregroundColor(Color(uiColor: .ppWarning))
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func branchSelectionRow(branch: PPBranchModel) -> some View {
        let isSelected = selectedBranchIDs.contains(branch.branchID)
        let isDefault = defaultBranchID == branch.branchID

        return HStack(spacing: 12) {
            // Checkbox Indicator
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    if isSelected {
                        selectedBranchIDs.remove(branch.branchID)
                        if isDefault {
                            defaultBranchID = selectedBranchIDs.first ?? ""
                        }
                    } else {
                        selectedBranchIDs.insert(branch.branchID)
                        if defaultBranchID.isEmpty {
                            defaultBranchID = branch.branchID
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? AdminSurface.primary : Color.clear)
                            .frame(width: 22, height: 22)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1.5)
                            .frame(width: 22, height: 22)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(branch.localizedName())
                                .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .body))
                                .foregroundColor(AdminSurface.primaryText)

                            if !branch.code.isEmpty {
                                Text(branch.code)
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                            }
                        }

                        if !branch.address.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 8))
                                Text(branch.address)
                                    .font(Font.custom("Beiruti-Regular", size: 10.5, relativeTo: .caption2))
                                    .lineLimit(1)
                            }
                            .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Default Working Branch Star Pill / Action
            if isSelected {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        defaultBranchID = branch.branchID
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isDefault ? "star.fill" : "star")
                            .font(.system(size: 10, weight: .bold))
                        Text(isDefault ? Language.get("Staff_Branch_Default_Badge", alter: "الافتراضي") : Language.get("Staff_Branch_Set_Default", alter: "تعيين افتراضي"))
                            .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                    }
                    .foregroundColor(isDefault ? Color(red: 0.85, green: 0.55, blue: 0.05) : AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isDefault ? Color(red: 0.85, green: 0.55, blue: 0.05).opacity(0.12) : AdminSurface.control),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(
                            isDefault ? Color(red: 0.85, green: 0.55, blue: 0.05).opacity(0.3) : AdminSurface.hairline,
                            lineWidth: 0.5
                        )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? AdminSurface.control.opacity(0.5) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fetchBranches() {
        isLoadingBranches = true
        Firestore.firestore().collection(kPPBranchesCol)
            .whereField("isActive", isEqualTo: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    self.isLoadingBranches = false
                    guard let docs = snapshot?.documents else { return }
                    var list: [PPBranchModel] = []
                    for doc in docs {
                        let branch = PPBranchModel.fromDictionary(doc.data(), withID: doc.documentID)
                        list.append(branch)
                    }
                    self.availableBranches = list
                    if self.defaultBranchID.isEmpty, let first = self.selectedBranchIDs.first {
                        self.defaultBranchID = first
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
                        Image(systemName: "checkmark.shield.fill")
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

            // Custom Font-Controlled Segmented Selector
            PPCustomSegmentedPicker(
                selection: $isCreatingAccount,
                items: [
                    (false, Language.get("Staff_Assign_Existing", alter: "ربط حساب قائم")),
                    (true, Language.get("Staff_Create_New", alter: "إنشاء حساب"))
                ],
                font: Font.custom("Beiruti-Bold", size: 14, relativeTo: .subheadline)
            )

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

                        Text(newName.isEmpty ? Language.get("Staff_Identity_Preview", alter: "معاينة هوية الموظف") : newName)
                            .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .padding(.vertical, 4)

                    editorInputField(
                        title: Language.get("FullName_Staff_Field", alter: "الاسم الكامل *"),
                        icon: "person.fill",
                        placeholder: Language.get("FullName_Staff_Placeholder", alter: "مثال: عبد الله المري"),
                        text: $newName
                    )
                    editorInputField(
                        title: Language.get("Staff_Work_Email_Field", alter: "البريد الإلكتروني المهني *"),
                        icon: "envelope.fill",
                        placeholder: "staff@purepets.qa",
                        text: $newEmail,
                        keyboard: .emailAddress
                    )

                    // Phone with Qatar Prefix
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Staff_Work_Phone_Field", alter: "رقم الهاتف المهني"))
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
                            Text(Language.get("Password_Field_Required", alter: "كلمة المرور *"))
                                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                            Button(Language.get("Generate_Password", alter: "توليد كلمة سر آمنة")) {
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
                // Link Existing User Form — Horizon Specimen Experience
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "link.badge.plus")
                            .font(.system(size: 12))
                            .foregroundColor(AdminSurface.primary)
                        Text(Language.get("Staff_Select_Existing_User", alter: "اختر حساباً مسجلاً في قاعدة بيانات PurePets لربطه وترقيته:"))
                            .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                    }

                    if !selectedUserUID.isEmpty {
                        // Linked User Dossier Monolith
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                // Avatar / Monogram
                                ZStack {
                                    LinearGradient(
                                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.15, blue: 0.35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    Text(selectedUserInitials)
                                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(selectedUserDisplayName.isEmpty ? selectedUserUID : selectedUserDisplayName)
                                            .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .body))
                                            .foregroundColor(AdminSurface.primaryText)
                                            .lineLimit(1)

                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
                                    }

                                    if !newEmail.isEmpty {
                                        Text(newEmail)
                                            .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .lineLimit(1)
                                    }

                                    HStack(spacing: 4) {
                                        Text("UID:")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(shortUID(selectedUserUID))
                                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    }
                                    .foregroundColor(AdminSurface.secondaryText.opacity(0.85))
                                }

                                Spacer()

                                // Change button
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    isUserPickerPresented = true
                                } label: {
                                    Text(Language.get("Change", alter: "تغيير"))
                                        .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            Divider().background(AdminSurface.hairline)

                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(uiColor: .ppSuccess))
                                    .font(.system(size: 11))
                                Text(Language.get("Staff_User_Ready_To_Link", alter: "تم تحديد الحساب وجاهز لتعيين الصلاحيات"))
                                    .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                                    .foregroundColor(Color(uiColor: .ppSuccess))
                                Spacer()
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedUserUID = ""
                                    selectedUserDisplayName = ""
                                    selectedUserAccount = nil
                                } label: {
                                    Text(Language.get("Clear", alter: "إلغاء"))
                                        .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                                        .foregroundColor(Color(uiColor: .ppError))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(12)
                        .background(Color(uiColor: .ppSuccess).opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(uiColor: .ppSuccess).opacity(0.20), lineWidth: 1))
                    } else {
                        // Interactive Launcher Card
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isUserPickerPresented = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    AdminSurface.primary.opacity(0.10)
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 20))
                                        .foregroundColor(AdminSurface.primary)
                                }
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Language.get("Staff_Select_User_Action", alter: "اختر مستخدماً من المنصة"))
                                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                                        .foregroundColor(AdminSurface.primaryText)

                                    Text(Language.get("Staff_Select_User_Action_Sub", alter: "انقر للبحث بالاسم أو الهاتف أو البريد الإلكتروني"))
                                        .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }

                                Spacer()

                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(8)
                                    .background(AdminSurface.primary.opacity(0.08), in: Circle())
                            }
                            .padding(12)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AdminSurface.primary.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
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
                    Text(isActive ? Language.get("Staff_Status_Active_Auth", alter: "نشط ومفوّض") : Language.get("Staff_Status_Disabled_Susp", alter: "معطّل"))
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
        let effectiveUid = staffDoc?.uid ?? (selectedUserUID.isEmpty ? nil : selectedUserUID)
        guard let uid = effectiveUid, !uid.isEmpty else { return }
        isProfileLoading = true

        Firestore.firestore().collection("UsersCol").document(uid).getDocument { snapshot, _ in
            if let data = snapshot?.data(), snapshot?.exists == true {
                DispatchQueue.main.async {
                    self.isProfileLoading = false
                    self.applyUserProfileData(data)
                }
            } else {
                Firestore.firestore().collection("PublicUserProfiles").document(uid).getDocument { pSnap, _ in
                    DispatchQueue.main.async {
                        self.isProfileLoading = false
                        if let pData = pSnap?.data() {
                            self.applyUserProfileData(pData)
                        }
                    }
                }
            }
        }
    }

    private func applyUserProfileData(_ data: [String: Any]) {
        let name = (data["UserName"] as? String)
            ?? (data["displayName"] as? String)
            ?? (data["FirstName"] as? String)
            ?? (data["name"] as? String)
            ?? (data["FullName"] as? String)
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            self.loadedUserName = name
        }

        let email = (data["UserEmail"] as? String)
            ?? (data["email"] as? String)
            ?? (data["mail"] as? String)
        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            self.loadedUserEmail = email
        }

        let phone = (data["MobileNo"] as? String)
            ?? (data["phone"] as? String)
            ?? (data["phoneNumber"] as? String)
            ?? (data["mobile"] as? String)
        if let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            self.loadedUserPhone = phone
        }

        let photo = (data["UserImageUrl"] as? String)
            ?? (data["photoURL"] as? String)
            ?? (data["photoUrl"] as? String)
            ?? (data["UserImageName"] as? String)
        if let photo = photo?.trimmingCharacters(in: .whitespacesAndNewlines), !photo.isEmpty {
            self.loadedUserPhotoURL = photo
        }

        if let ts = (data["createdAt"] as? Timestamp) ?? (data["CreatedAt"] as? Timestamp) ?? (data["loginDate"] as? Timestamp) {
            self.loadedUserCreatedAt = ts.dateValue()
        }

        if let lastTs = (data["lastSeen"] as? Timestamp) ?? (data["lastLogin"] as? Timestamp) {
            self.loadedUserLastSeen = lastTs.dateValue()
        }

        let postAds = (data["canPostAds"] as? Bool) ?? (data["canPostAnimalAds"] as? Bool) ?? false
        let postAdoption = (data["canPostAdoptionAds"] as? Bool) ?? false
        let postServices = (data["canPostServices"] as? Bool) ?? false
        let verified = (data["verified"] as? Bool) ?? (data["isVerified"] as? Bool) ?? false

        self.canPostAnimalAds = postAds
        self.canPostAdoptionAds = postAdoption
        self.canPostServices = postServices
        self.isVerified = verified
    }

    private func saveSettings() {
        validationError = nil

        if !isGlobalScope && selectedBranchIDs.isEmpty {
            validationError = Language.get("Staff_Error_BranchRequired", alter: "يرجى تحديد فرع عمل واحد على الأقل، أو تفعيل الوصول الشامل لكافة الفروع.")
            return
        }

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

        var finalDefaultBranchID = defaultBranchID
        if !isGlobalScope {
            if finalDefaultBranchID.isEmpty || !selectedBranchIDs.contains(finalDefaultBranchID) {
                finalDefaultBranchID = selectedBranchIDs.first ?? ""
            }
        } else {
            finalDefaultBranchID = ""
        }

        let scopeDict: [String: Any] = [
            "global": isGlobalScope,
            "branchIds": isGlobalScope ? [] : Array(selectedBranchIDs),
            "defaultBranchId": finalDefaultBranchID,
            "regionIds": [],
            "agentIds": [],
            "branchPermissions": [:]
        ]

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
                "status": isActive ? PPStaffStatus.active.rawValue : PPStaffStatus.disabled.rawValue,
                "scope": scopeDict
            ]

            AdminService.updateStaffMember(uid, updates: updates) { _, error in
                let errDesc = error?.localizedDescription
                DispatchQueue.main.async {
                    if let errDesc {
                        self.isSaving = false
                        self.validationError = errDesc
                        return
                    }

                    // If editing currently logged in user, immediately refresh staff doc & branch context
                    if uid == Auth.auth().currentUser?.uid {
                        PPStaffAuth.shared().fetchStaffDoc(uid) { updatedStaff, _ in
                            PPBranchContextManager.shared().configure(withStaff: updatedStaff, completion: nil)
                        }
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
                scope: scopeDict
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
                scope: scopeDict
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
        let secDomain = Language.get("Staff_Domain_Security", alter: "الأمان والنظام")
        let ordDomain = Language.get("Staff_Domain_Orders", alter: "الطلبات والتنفيذ")
        let usrDomain = Language.get("Staff_Domain_Customers", alter: "العملاء والدعم")
        let payDomain = Language.get("Staff_Domain_Payments", alter: "المدفوعات والمحاسبة")
        let invDomain = Language.get("Staff_Domain_Inventory", alter: "المخزون والمنتجات")

        return [
            // System Security & IAM
            PermissionItem(id: "staff.view", title: Language.get("StaffPermTitle_staff_view", alter: "استعراض قائمة أعضاء الفريق"), domain: secDomain, domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager),
            PermissionItem(id: "staff.manage", title: Language.get("StaffPermTitle_staff_manage", alter: "تعديل رتب وصلاحيات الموظفين"), domain: secDomain, domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin),
            PermissionItem(id: "audit.view", title: Language.get("StaffPermTitle_audit_view", alter: "سجل التدقيق الأمني الشامل"), domain: secDomain, domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin),
            PermissionItem(id: "notifications.manage", title: Language.get("StaffPermTitle_notifications_manage", alter: "إرسال الإشعارات الشاملة للمستخدمين"), domain: secDomain, domainIcon: "lock.shield.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager),

            // Orders & Fulfillment
            PermissionItem(id: "orders.view", title: Language.get("StaffPermTitle_orders_view", alter: "استعراض طلبات الشراء والمبيعات"), domain: ordDomain, domainIcon: "shippingbox.fill", isGranted: role != .viewer),
            PermissionItem(id: "orders.manage", title: Language.get("StaffPermTitle_orders_manage", alter: "تعديل حالات ومسارات الطلبات"), domain: ordDomain, domainIcon: "shippingbox.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager),
            PermissionItem(id: "fulfillment.manage", title: Language.get("StaffPermTitle_fulfillment_manage", alter: "توزيع وتعيين مزودي الشحن"), domain: ordDomain, domainIcon: "shippingbox.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager),
            PermissionItem(id: "delivery.settings.manage", title: Language.get("StaffPermTitle_delivery_settings_manage", alter: "إعدادات شركات التوصيل"), domain: ordDomain, domainIcon: "shippingbox.fill", isGranted: role == .owner || role == .superAdmin),

            // Customers & Support
            PermissionItem(id: "users.view", title: Language.get("StaffPermTitle_users_view", alter: "استعراض دليل حسابات العملاء"), domain: usrDomain, domainIcon: "person.2.fill", isGranted: role != .viewer),
            PermissionItem(id: "users.manage", title: Language.get("StaffPermTitle_users_manage", alter: "تعديل بيانات وحسابات العملاء"), domain: usrDomain, domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .supportAgent),
            PermissionItem(id: "users.features.manage", title: Language.get("StaffPermTitle_users_features_manage", alter: "إدارة مزايا وصلاحيات المستخدمين"), domain: usrDomain, domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .supportAgent),
            PermissionItem(id: "users.restrictions.manage", title: Language.get("StaffPermTitle_users_restrictions_manage", alter: "حظر وتقييد حسابات المخالفين"), domain: usrDomain, domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .supportAgent),
            PermissionItem(id: "support.manage", title: Language.get("StaffPermTitle_support_manage", alter: "إدارة محادثات وتذاكر الدعم الفني"), domain: usrDomain, domainIcon: "person.2.fill", isGranted: role == .owner || role == .superAdmin || role == .supportAgent),

            // Payments & Financials
            PermissionItem(id: "payments.view", title: Language.get("StaffPermTitle_payments_view", alter: "استعراض سجل المعاملات المالية"), domain: payDomain, domainIcon: "creditcard.fill", isGranted: role != .viewer && role != .supportAgent),
            PermissionItem(id: "payments.manage", title: Language.get("StaffPermTitle_payments_manage", alter: "إدارة بوابات الدفع والمعاملات"), domain: payDomain, domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),
            PermissionItem(id: "payments.refund", title: Language.get("StaffPermTitle_payments_refund", alter: "تنفيذ استرداد المبالغ للعملاء"), domain: payDomain, domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),
            PermissionItem(id: "pos.sell", title: Language.get("StaffPermTitle_pos_sell", alter: "تنفيذ مبيعات الكاشير ونقاط البيع"), domain: payDomain, domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .paymentsManager),
            PermissionItem(id: "delivery.cod.reconcile", title: Language.get("StaffPermTitle_delivery_cod_reconcile", alter: "تحصيل ومطابقة الدفع عند الاستلام"), domain: payDomain, domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),
            PermissionItem(id: "accounting.view", title: Language.get("StaffPermTitle_accounting_view", alter: "الدفاتر والقيود المحاسبية"), domain: payDomain, domainIcon: "creditcard.fill", isGranted: role == .owner || role == .superAdmin || role == .paymentsManager),

            // Inventory & Catalog
            PermissionItem(id: "stock.view", title: Language.get("StaffPermTitle_stock_view", alter: "استعراض الكتالوج والمستلزمات"), domain: invDomain, domainIcon: "cube.box.fill", isGranted: role != .viewer && role != .supportAgent),
            PermissionItem(id: "stock.manage", title: Language.get("StaffPermTitle_stock_manage", alter: "تعديل تفاصيل وأسعار المخزون"), domain: invDomain, domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .operationsManager || role == .inventoryManager),
            PermissionItem(id: "stock.create", title: Language.get("StaffPermTitle_stock_create", alter: "إضافة منتجات جديدة للكتالوج"), domain: invDomain, domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .inventoryManager),
            PermissionItem(id: "stock.delete", title: Language.get("StaffPermTitle_stock_delete", alter: "حذف وأرشفة المنتجات"), domain: invDomain, domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .inventoryManager),
            PermissionItem(id: "categories.manage", title: Language.get("StaffPermTitle_categories_manage", alter: "إدارة وتصنيف الأقسام"), domain: invDomain, domainIcon: "cube.box.fill", isGranted: role == .owner || role == .superAdmin || role == .inventoryManager)
        ]
    }

    private var domains: [String] {
        var ordered: [String] = []
        for perm in allPermissions {
            if !ordered.contains(perm.domain) {
                ordered.append(perm.domain)
            }
        }
        return ordered
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectorNavigationBar

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

                                            Text(perm.isGranted ? Language.get("Staff_Perm_Granted", alter: "مفوّض") : Language.get("Staff_Perm_Restricted", alter: "محظور"))
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
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Redesigned Sovereign Permissions Inspector Navigation Bar

    private var inspectorNavigationBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 1. Squircle Back Button Jewel (Leading in RTL)
                AdminSquircleBackButton {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }

                // 2. Title & Subtitle Stack
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Staff_Permissions_Audit_Title", alter: "فحص وتدقيق الصلاحيات"))
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 6, height: 6)
                        Text(Language.get("Staff_Permissions_Audit_Subtitle", alter: "مصفوفة الوصول الأمني والسياسات"))
                            .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // 3. Trailing Authority Role Pill
                HStack(spacing: 6) {
                    Image(systemName: role.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(role.accentColor)
                    Text(role.title)
                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                        .foregroundColor(AdminSurface.primaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(role.accentColor.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(role.accentColor.opacity(0.25), lineWidth: 0.8))
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(AdminSurface.background)
        }
    }
}

// MARK: - Bespoke Font-Controlled Segmented Control

struct PPCustomSegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let items: [(T, String)]
    var font: Font = Font.custom("Beiruti-Bold", size: 14, relativeTo: .subheadline)
    var selectedTextColor: Color = AdminSurface.primaryText
    var unselectedTextColor: Color = AdminSurface.secondaryText
    var selectedBackground: Color = AdminSurface.surface
    var containerBackground: Color = AdminSurface.control
    var cornerRadius: CGFloat = 16.0
    @Namespace private var segmentNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                let isSelected = selection == item.0
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = item.0
                    }
                } label: {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: cornerRadius - 3.5, style: .continuous)
                                .fill(selectedBackground)
                                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cornerRadius - 3.5, style: .continuous)
                                        .stroke(AdminSurface.hairline, lineWidth: 0.5)
                                )
                                .matchedGeometryEffect(id: "PPCustomSegmentSelectionPill", in: segmentNamespace)
                        }

                        Text(item.1)
                            .font(font)
                            .foregroundColor(isSelected ? selectedTextColor : unselectedTextColor)
                            .padding(.vertical, 9)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(3.5)
        .background(containerBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.75)
        )
    }
}

// MARK: - Flagship Horizon User Picker Sheet

struct AdminUserPickerSheet: View {
    var selectedUID: String = ""
    let onSelectUser: (PPCustomerAccountModel) -> Void
    let onDismiss: () -> Void

    @StateObject private var viewModel = AdminCustomerAccountsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("Staff_Picker_Title", alter: "اختيار حساب من المنصة"),
                subtitle: String(format: Language.get("Staff_Picker_Subtitle_Count", alter: "%d مستخدم مسجل بالمنصة"), viewModel.allCustomers.count),
                statusDotColor: Color(uiColor: .ppSuccess),
                isModal: true,
                onBack: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }
            )

            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    pickerTopSearchBar
                    pickerFilterChips
                    pickerUserList
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // Search Bar
    private var pickerTopSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AdminSurface.primary)

            TextField(Language.get("Staff_Picker_Search_Placeholder", alter: "ابحث بالاسم، البريد، الهاتف، أو المعرّف (UID)..."), text: $viewModel.searchText)
                .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                .foregroundColor(AdminSurface.primaryText)
                .onChange(of: viewModel.searchText) { _ in
                    viewModel.applyFilter()
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    viewModel.applyFilter()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // Filter Chips
    private var pickerFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CustomerFilterTab.allCases) { tab in
                    let isSelected = viewModel.activeTab == tab
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            viewModel.activeTab = tab
                            viewModel.applyFilter()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10, weight: .bold))
                            Text(tab.title)
                                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isSelected ? AdminSurface.primary : AdminSurface.control,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 6)
        }
    }

    // User List Section
    private var pickerUserList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.isLoading {
                    ForEach(0..<6, id: \.self) { _ in
                        pickerSkeletonCard
                    }
                } else if viewModel.filteredCustomers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 42))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                            .padding(.top, 40)

                        Text(Language.get("Staff_Picker_No_Results", alter: "لم يتم العثور على مستخدم مطابق"))
                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("Staff_Picker_No_Results_Sub", alter: "تأكد من كتابة الاسم أو البريد أو رقم الهاتف بشكل صحيح"))
                            .font(Font.custom("Beiruti-Regular", size: 12.5, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                            .multilineTextAlignment(.center)

                        if !viewModel.searchText.isEmpty {
                            Button {
                                viewModel.searchText = ""
                                viewModel.applyFilter()
                            } label: {
                                Text(Language.get("ClearSearch", alter: "مسح البحث"))
                                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .body))
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(24)
                } else {
                    ForEach(viewModel.filteredCustomers) { user in
                        pickerUserRowCard(user)
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 6)
            .padding(.bottom, 30)
        }
    }

    // Specimen User Card
    private func pickerUserRowCard(_ user: PPCustomerAccountModel) -> some View {
        let isChosen = user.id == selectedUID

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSelectUser(user)
        } label: {
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    if let photo = user.photoURL, let url = URL(string: photo), !photo.isEmpty {
                        AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 48, height: 48)) {
                            pickerMonogram(user)
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    } else {
                        pickerMonogram(user)
                    }

                    if user.isOnline {
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 1, y: 1)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(user.name)
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        if user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 0.12, green: 0.50, blue: 0.90))
                        }

                        Spacer()

                        // Selection indicator
                        ZStack {
                            Circle()
                                .stroke(isChosen ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isChosen ? 2 : 1.5)
                                .frame(width: 20, height: 20)

                            if isChosen {
                                Circle()
                                    .fill(AdminSurface.primary)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        if !user.email.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 9))
                                Text(user.email)
                                    .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                                    .lineLimit(1)
                            }
                            .foregroundColor(AdminSurface.secondaryText)
                        }

                        if !user.phone.isEmpty {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.4))

                            Text(user.phone)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AdminSurface.secondaryText)
                                .monospacedDigit()
                        }
                    }

                    HStack(spacing: 6) {
                        // UID tag
                        HStack(spacing: 3) {
                            Text("UID:")
                                .font(.system(size: 9, weight: .bold))
                            Text(user.shortUID)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        // Status pill
                        HStack(spacing: 3) {
                            Circle()
                                .fill(user.status.color)
                                .frame(width: 5, height: 5)
                            Text(user.status.title)
                                .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                                .foregroundColor(user.status.color)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(user.status.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
            .padding(12)
            .background(
                isChosen ? AdminSurface.primary.opacity(0.06) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isChosen ? AdminSurface.primary.opacity(0.35) : AdminSurface.hairline, lineWidth: isChosen ? 1.5 : 1)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 6, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func pickerMonogram(_ user: PPCustomerAccountModel) -> some View {
        ZStack {
            LinearGradient(colors: user.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(user.initials)
                .font(Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline))
                .foregroundColor(.white)
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var pickerSkeletonCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AdminSurface.control)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AdminSurface.control)
                    .frame(width: 140, height: 14)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AdminSurface.control)
                    .frame(width: 200, height: 11)
            }
            Spacer()
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }
}

fileprivate struct StaffCockpitPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
