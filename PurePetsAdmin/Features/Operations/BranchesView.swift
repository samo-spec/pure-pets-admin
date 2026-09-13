//
//  BranchesView.swift
//  PurePetsAdmin
//
//  NextGen V6 Category-Defining Native SwiftUI Branches Management.
//  First-principles architecture with distinct form-factor separation for
//  iPhone (Tactile Operations Deck) and iPad (Dual-Wing Operations Console).
//  Enforces 100% Beiruti brand typography with zero system font references.
//  Preserves all business logic, Firestore listeners, permissions, swipe
//  actions, search, default branch mutual exclusion, and audit logging.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Sendable & Identifiable Conformance

extension PPBranchModel: @unchecked Sendable, Identifiable {
    public var id: String { branchID }
}

// MARK: - Strict Brand Typography Engine (100% Beiruti)

enum BranchType {
    // Large Titles
    static let largeTitle = Font.custom("Beiruti-Bold", size: 34, relativeTo: .largeTitle)
    static let heroTitle = Font.custom("Beiruti-Bold", size: 28, relativeTo: .title)
    static let title2 = Font.custom("Beiruti-Bold", size: 22, relativeTo: .title2)
    static let title3 = Font.custom("Beiruti-Bold", size: 19, relativeTo: .title3)
    static let headline = Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline)
    static let headlineMedium = Font.custom("Beiruti-Medium", size: 17, relativeTo: .headline)

    // Body & Callouts
    static let body = Font.custom("Beiruti-Regular", size: 16, relativeTo: .body)
    static let bodyMedium = Font.custom("Beiruti-Medium", size: 16, relativeTo: .body)
    static let bodyBold = Font.custom("Beiruti-Bold", size: 16, relativeTo: .body)
    static let callout = Font.custom("Beiruti-Regular", size: 15, relativeTo: .callout)
    static let calloutBold = Font.custom("Beiruti-Bold", size: 15, relativeTo: .callout)

    // Subheadline & Footnotes
    static let subheadline = Font.custom("Beiruti-Regular", size: 14, relativeTo: .subheadline)
    static let subheadlineMedium = Font.custom("Beiruti-Medium", size: 14, relativeTo: .subheadline)
    static let subheadlineBold = Font.custom("Beiruti-Bold", size: 14, relativeTo: .subheadline)
    static let footnote = Font.custom("Beiruti-Regular", size: 13, relativeTo: .footnote)
    static let footnoteMedium = Font.custom("Beiruti-Medium", size: 13, relativeTo: .footnote)
    static let footnoteBold = Font.custom("Beiruti-Bold", size: 13, relativeTo: .footnote)

    // Captions & Micro Badges
    static let caption = Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption)
    static let captionMedium = Font.custom("Beiruti-Medium", size: 12, relativeTo: .caption)
    static let captionBold = Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption)
    static let micro = Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2)
    static let microBold = Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2)
    static let badgePill = Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2)

    // Numerical & Telemetry Displays
    static let telemetryValue = Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2)
    static let telemetryLarge = Font.custom("Beiruti-Bold", size: 36, relativeTo: .largeTitle)
    static let chipText = Font.custom("Beiruti-Medium", size: 13, relativeTo: .caption)
    static let chipTextBold = Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption)
    static let buttonTitle = Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline)
}

// MARK: - Branch Filter Categories

enum BranchFilterCategory: String, CaseIterable, Identifiable {
    case all = "all"
    case active = "active"
    case inactive = "inactive"
    case defaultOnly = "default"
    case sharedStock = "shared"
    case perAgentStock = "perAgent"

    var id: String { rawValue }

    func title() -> String {
        switch self {
        case .all:
            return Language.get("Branches_Filter_All", alter: "الكل")
        case .active:
            return Language.get("Branches_Filter_Active", alter: "نشط")
        case .inactive:
            return Language.get("Branches_Filter_Inactive", alter: "غير نشط")
        case .defaultOnly:
            return Language.get("Branches_Filter_Default", alter: "الرئيسي")
        case .sharedStock:
            return Language.get("Branches_Filter_Shared", alter: "مخزون مشترك")
        case .perAgentStock:
            return Language.get("Branches_Filter_Separate", alter: "مخزون الوكيل")
        }
    }

    func icon() -> String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .active: return "checkmark.circle.fill"
        case .inactive: return "pause.circle.fill"
        case .defaultOnly: return "star.fill"
        case .sharedStock: return "shippingbox.fill"
        case .perAgentStock: return "person.2.fill"
        }
    }
}

// MARK: - Branch List ViewModel

@MainActor
final class AdminBranchesViewModel: ObservableObject {
    @Published private(set) var branches: [PPBranchModel] = []
    @Published private(set) var filteredBranches: [PPBranchModel] = []
    @Published private(set) var agentCounts: [String: Int] = [:]
    @Published var searchText: String = ""
    @Published var selectedFilter: BranchFilterCategory = .all
    @Published var selectedBranchID: String? = nil
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var canManage: Bool = false

    private nonisolated(unsafe) var branchesListener: (any ListenerRegistration)?
    private nonisolated(unsafe) var agentsListener: (any ListenerRegistration)?

    var totalCount: Int { branches.count }
    var activeCount: Int { branches.filter { $0.isActive }.count }
    var inactiveCount: Int { branches.filter { !$0.isActive }.count }
    var defaultBranch: PPBranchModel? { branches.first { $0.isDefault } }
    var totalAgentsCount: Int { agentCounts.values.reduce(0, +) }

    init() {
        evaluatePermissions()
    }

    deinit {
        branchesListener?.remove()
        agentsListener?.remove()
    }

    func evaluatePermissions() {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        let hasManage = staff?.hasPermission(kStaffPermBranchesManage) ?? false
        self.canManage = hasManage
    }

    func startListening() {
        evaluatePermissions()
        isLoading = true
        errorMessage = nil

        let query = Firestore.firestore().collection(kPPBranchesCol).order(by: "createdAt", descending: true)
        branchesListener = query.addSnapshotListener { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let documents = snapshot?.documents else { return }
                self.branches = documents.compactMap { doc in
                    PPBranchModel.fromDictionary(doc.data(), withID: doc.documentID)
                }
                self.applyFilter()

                // Default selection for iPad master-detail if needed
                if self.selectedBranchID == nil || !self.branches.contains(where: { $0.branchID == self.selectedBranchID }) {
                    self.selectedBranchID = self.defaultBranch?.branchID ?? self.branches.first?.branchID
                }
            }
        }

        startAgentCountListener()
    }

    private func startAgentCountListener() {
        agentsListener = Firestore.firestore().collection("agents").addSnapshotListener { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self, error == nil, let documents = snapshot?.documents else { return }
                var counts: [String: Int] = [:]
                for doc in documents {
                    let data = doc.data()
                    if (data["isActive"] as? Bool) == true, let branchId = data["branchId"] as? String, !branchId.isEmpty {
                        counts[branchId, default: 0] += 1
                    }
                }
                self.agentCounts = counts
            }
        }
    }

    func stopListening() {
        branchesListener?.remove()
        branchesListener = nil
        agentsListener?.remove()
        agentsListener = nil
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var pool = branches

        // Category filter
        switch selectedFilter {
        case .all:
            break
        case .active:
            pool = pool.filter { $0.isActive }
        case .inactive:
            pool = pool.filter { !$0.isActive }
        case .defaultOnly:
            pool = pool.filter { $0.isDefault }
        case .sharedStock:
            pool = pool.filter { $0.stockMode == .branch }
        case .perAgentStock:
            pool = pool.filter { $0.stockMode == .perAgent }
        }

        // Search text filter
        if query.isEmpty {
            filteredBranches = pool
        } else {
            filteredBranches = pool.filter { b in
                b.nameEn.lowercased().contains(query) ||
                b.nameAr.contains(query) ||
                b.code.lowercased().contains(query) ||
                b.address.lowercased().contains(query)
            }
        }
    }

    func countForFilter(_ category: BranchFilterCategory) -> Int {
        switch category {
        case .all:
            return branches.count
        case .active:
            return branches.filter { $0.isActive }.count
        case .inactive:
            return branches.filter { !$0.isActive }.count
        case .defaultOnly:
            return branches.filter { $0.isDefault }.count
        case .sharedStock:
            return branches.filter { $0.stockMode == .branch }.count
        case .perAgentStock:
            return branches.filter { $0.stockMode == .perAgent }.count
        }
    }

    func agentCount(for branchID: String) -> Int {
        guard !branchID.isEmpty else { return 0 }
        return agentCounts[branchID] ?? 0
    }

    func selectedBranch() -> PPBranchModel? {
        guard let id = selectedBranchID else { return nil }
        return branches.first { $0.branchID == id }
    }

    func toggleActive(for branch: PPBranchModel, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        let branchID = branch.branchID
        guard !branchID.isEmpty else { return }

        if branch.isActive {
            let count = agentCount(for: branchID)
            if count > 0 {
                let format = Language.get("Branches_Cannot_Deactivate_Agents", alter: nil)
                let message = String(format: format, count)
                completion(false, message)
                return
            }
        }

        let newActive = !branch.isActive
        let docRef = Firestore.firestore().collection(kPPBranchesCol).document(branchID)
        docRef.updateData([
            "isActive": newActive,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    let successMsg = newActive ? Language.get("Branches_Activated", alter: nil) : Language.get("Branches_Deactivated", alter: nil)
                    self?.writeToggleAuditLog(branch: branch, newActive: newActive)
                    completion(true, successMsg)
                }
            }
        }
    }

    func setDefaultBranch(_ branch: PPBranchModel, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        let targetID = branch.branchID
        guard !targetID.isEmpty else { return }
        let batch = Firestore.firestore().batch()

        for b in branches {
            let bID = b.branchID
            guard !bID.isEmpty else { continue }
            let ref = Firestore.firestore().collection(kPPBranchesCol).document(bID)
            if bID == targetID {
                batch.updateData([
                    "isDefault": true,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: ref)
            } else if b.isDefault {
                batch.updateData([
                    "isDefault": false,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: ref)
            }
        }

        batch.commit { error in
            DispatchQueue.main.async {
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, Language.get("Branches_Updated", alter: nil))
                }
            }
        }
    }

    func deleteBranch(_ branch: PPBranchModel, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        let branchID = branch.branchID
        guard !branchID.isEmpty else { return }
        guard canManage else {
            completion(false, Language.get("PPAlert_Error_Permission_Message", alter: "Missing or insufficient permissions."))
            return
        }
        if branch.isDefault {
            completion(false, Language.get("Branches_Cannot_Delete_Default", alter: "Cannot delete default branch"))
            return
        }
        let count = agentCount(for: branchID)
        if count > 0 {
            let format = Language.get("Branches_Cannot_Deactivate_Agents", alter: nil)
            completion(false, String(format: format, count))
            return
        }

        Firestore.firestore().collection(kPPBranchesCol).document(branchID).delete { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.writeDeleteAuditLog(branch: branch)
                    completion(true, Language.get("Deleted", alter: nil))
                }
            }
        }
    }

    private func writeToggleAuditLog(branch: PPBranchModel, newActive: Bool) {
        let uid = Auth.auth().currentUser?.uid ?? ""
        Firestore.firestore().collection("AdminAuditLogs").document().setData([
            "action": "toggle_branch_active",
            "targetCollection": kPPBranchesCol,
            "targetId": branch.branchID,
            "adminUid": uid,
            "before": ["isActive": !newActive],
            "after": ["isActive": newActive],
            "timestamp": FieldValue.serverTimestamp()
        ])
    }

    private func writeDeleteAuditLog(branch: PPBranchModel) {
        let uid = Auth.auth().currentUser?.uid ?? ""
        Firestore.firestore().collection("AdminAuditLogs").document().setData([
            "action": "delete_branch",
            "targetCollection": kPPBranchesCol,
            "targetId": branch.branchID,
            "adminUid": uid,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - Root Branches View (Form Factor Dispatcher)

@MainActor
struct AdminBranchesView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel = AdminBranchesViewModel()
    @State private var editingBranch: PPBranchModel? = nil
    @State private var isPresentingNewBranch = false
    @State private var toastMessage: String? = nil
    @State private var isErrorToast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isPad {
                BranchesiPadStudioLayout(
                    viewModel: viewModel,
                    onDismiss: handleDismiss,
                    onEditBranch: { branch in editingBranch = branch },
                    onNewBranch: { isPresentingNewBranch = true },
                    onShowToast: { msg, isErr in showToast(msg, isError: isErr) }
                )
            } else {
                BranchesiPhoneLayout(
                    viewModel: viewModel,
                    onDismiss: handleDismiss,
                    onEditBranch: { branch in editingBranch = branch },
                    onNewBranch: { isPresentingNewBranch = true },
                    onShowToast: { msg, isErr in showToast(msg, isError: isErr) }
                )
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
        .fullScreenCover(item: $editingBranch) { branch in
            AdminBranchEditorSheet(
                branch: branch,
                canManage: viewModel.canManage,
                agentCount: viewModel.agentCount(for: branch.branchID),
                onDismiss: { editingBranch = nil },
                onSaved: { msg in
                    editingBranch = nil
                    showToast(msg, isError: false)
                },
                onDelete: { b in
                    editingBranch = nil
                    confirmDeleteBranch(b)
                }
            )
        }
        .fullScreenCover(isPresented: $isPresentingNewBranch) {
            AdminBranchEditorSheet(
                branch: nil,
                canManage: viewModel.canManage,
                agentCount: 0,
                onDismiss: { isPresentingNewBranch = false },
                onSaved: { msg in
                    isPresentingNewBranch = false
                    showToast(msg, isError: false)
                },
                onDelete: nil
            )
        }
    }

    private func handleDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func confirmDeleteBranch(_ branch: PPBranchModel) {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Delete", alter: "حذف الفرع"),
            subtitle: String(format: Language.get("ConfirmDelete_Branch_Format", alter: "هل أنت متأكد من رغبتك في حذف الفرع \"%@\" نهائياً؟ لن تتمكن من استرجاع هذا الفرع بعد الحذف."), branch.localizedName()),
            confirmButton: Language.get("Delete", alter: "تأكيد الحذف"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "trash.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.deleteBranch(branch) { success, msg in
                    if success {
                        showToast(Language.get("Deleted", alter: "تم الحذف"), isError: false)
                    } else if let msg {
                        showToast(msg, isError: true)
                    }
                }
            },
            cancelBlock: nil
        )
    }

    private func showToast(_ message: String, isError: Bool) {
        guard !message.isEmpty else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(isError ? .error : .success)
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
        HStack(spacing: 12) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
                .font(BranchType.headline)

            Text(message)
                .font(BranchType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isError ? Color(uiColor: .ppError).opacity(0.35) : Color(uiColor: .ppSuccess).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 5)
    }
}

// MARK: - iPhone Layout: Tactile Operations Deck

@MainActor
private struct BranchesiPhoneLayout: View {
    @ObservedObject var viewModel: AdminBranchesViewModel
    let onDismiss: () -> Void
    let onEditBranch: (PPBranchModel) -> Void
    let onNewBranch: () -> Void
    let onShowToast: (String, Bool) -> Void

    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    executiveTelemetryDeck
                    commandRibbonSection
                    branchRosterContent
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 8)
                .padding(.bottom, AdminSpacing.xxl)
            }
            .refreshable {
                viewModel.startListening()
            }
        }
    }

    // MARK: Navigation Header

    private var navigationHeader: some View {
        HStack(spacing: 14) {
            Button(action: onDismiss) {
                HStack(spacing: 6) {
                    Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                        .font(BranchType.headline)
                }
                .foregroundColor(AdminSurface.primaryText)
                .frame(width: 44, height: 44)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("Back", alter: "رجوع"))

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Branches_Title", alter: "الفروع"))
                    .font(BranchType.heroTitle)
                    .foregroundColor(AdminSurface.primaryText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 7, height: 7)
                    Text(Language.get("CommandCenter_Operations_Workspace", alter: "مساحة عمل العمليات"))
                        .font(BranchType.captionBold)
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                withAnimation(.easeInOut(duration: 0.5)) { isRefreshing = true }
                viewModel.startListening()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isRefreshing = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(BranchType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: Executive Telemetry Deck

    private var executiveTelemetryDeck: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Branches_Subtitle", alter: "إدارة فروع المتجر وأنواع المخزون والمواقع."))
                        .font(BranchType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.canManage {
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        onNewBranch()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(BranchType.captionBold)
                            Text(Language.get("Branches_New", alter: "فرع جديد"))
                                .font(BranchType.buttonTitle)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 4 Live Telemetry Tiles
            HStack(spacing: 10) {
                telemetryCapsule(
                    title: Language.get("Branches_Telemetry_Total", alter: "إجمالي الفروع"),
                    value: "\(viewModel.totalCount)",
                    icon: "building.2.fill",
                    color: AdminSurface.primary
                )

                telemetryCapsule(
                    title: Language.get("Branches_Telemetry_Active", alter: "الفروع النشطة"),
                    value: "\(viewModel.activeCount)",
                    icon: "checkmark.seal.fill",
                    color: Color(uiColor: .ppSuccess)
                )

                telemetryCapsule(
                    title: Language.get("Branches_Telemetry_Default", alter: "الفرع الرئيسي"),
                    value: viewModel.defaultBranch?.code ?? "-",
                    icon: "building.columns.fill",
                    color: Color(uiColor: .ppWarning)
                )

                telemetryCapsule(
                    title: Language.get("Branches_Telemetry_Workforce", alter: "القوة الميدانية"),
                    value: "\(viewModel.totalAgentsCount)",
                    icon: "person.2.fill",
                    color: Color(uiColor: .ppAccent)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
        )
    }

    private func telemetryCapsule(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(BranchType.microBold)
                    .foregroundColor(color)
                Text(title)
                    .font(BranchType.micro)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Text(value)
                .font(BranchType.telemetryValue)
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Command Ribbon (Search & Filters)

    private var commandRibbonSection: some View {
        VStack(spacing: 12) {
            // Search Field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(BranchType.body)

                TextField(Language.get("Branches_Search", alter: "بحث في الفروع…"), text: $viewModel.searchText)
                    .font(BranchType.body)
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
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(BranchType.body)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
            )

            // Horizontal Filter Ribbon
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BranchFilterCategory.allCases) { category in
                        let isSelected = viewModel.selectedFilter == category
                        let count = viewModel.countForFilter(category)

                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                viewModel.selectedFilter = category
                                viewModel.applyFilter()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: category.icon())
                                    .font(BranchType.captionBold)

                                Text(category.title())
                                    .font(isSelected ? BranchType.chipTextBold : BranchType.chipText)

                                Text("\(count)")
                                    .font(BranchType.microBold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        isSelected ? Color.white.opacity(0.25) : AdminSurface.primary.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? AdminSurface.primary : AdminSurface.surface,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.7),
                                        lineWidth: 0.8
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Branch Roster Content

    @ViewBuilder
    private var branchRosterContent: some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    BranchCardSkeletonView()
                }
            }
        } else if viewModel.branches.isEmpty {
            AdminEmptyStateView(
                symbol: "building.2",
                title: Language.get("Branches_Empty_Title", alter: "لا توجد فروع بعد"),
                subtitle: Language.get("Branches_Empty_Subtitle", alter: "أنشئ أول فرع لتنظيم المخزون والمواقع."),
                actionTitle: viewModel.canManage ? Language.get("Branches_Empty_CTA", alter: "فرع جديد") : nil,
                action: onNewBranch
            )
            .padding(.top, 30)
        } else if viewModel.filteredBranches.isEmpty {
            AdminEmptyStateView(
                symbol: "magnifyingglass",
                title: Language.get("Branches_NoResults_Title", alter: "لا توجد نتائج"),
                subtitle: Language.get("Branches_NoResults_Subtitle", alter: "جرّب كلمة بحث أو تصنيفاً مختلفاً.")
            )
            .padding(.top, 30)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredBranches) { branch in
                    SovereignBranchCard(
                        branch: branch,
                        agentCount: viewModel.agentCount(for: branch.branchID),
                        canManage: viewModel.canManage,
                        isSelected: false,
                        onTap: {
                            if viewModel.canManage {
                                onEditBranch(branch)
                            }
                        },
                        onToggleActive: {
                            confirmToggleActive(branch)
                        },
                        onSetDefault: {
                            confirmSetDefault(branch)
                        }
                    )
                }
            }
        }
    }

    private func confirmSetDefault(_ branch: PPBranchModel) {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Branches_Default_Label", alter: "الفرع الافتراضي"),
            subtitle: String(format: Language.get("Branches_Default_Confirm_Format", alter: "هل تريد تعيين الفرع \"%@\" كفرع رئيسي افتراضي؟"), branch.localizedName()),
            confirmButton: Language.get("Confirm", alter: "تأكيد"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "star.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.setDefaultBranch(branch) { success, msg in
                    onShowToast(msg ?? "", !success)
                }
            },
            cancelBlock: nil
        )
    }

    private func confirmToggleActive(_ branch: PPBranchModel) {
        if branch.isActive {
            PPAlertHelper.showConfirmation(
                in: nil,
                title: Language.get("Branches_Deactivate", alter: "تعطيل الفرع"),
                subtitle: String(format: Language.get("Branches_Deactivate_Confirm_Format", alter: "هل تريد تعطيل الفرع \"%@\"؟ لن يظهر هذا الفرع في عمليات البيع حتى يتم تنشيطه مجدداً."), branch.localizedName()),
                confirmButton: Language.get("Branches_Deactivate", alter: "تعطيل"),
                cancelButton: Language.get("Cancel", alter: "إلغاء"),
                icon: UIImage(systemName: "pause.circle.fill"),
                confirmBlock: { _, didConfirm in
                    guard didConfirm else { return }
                    viewModel.toggleActive(for: branch) { success, msg in
                        onShowToast(msg ?? "", !success)
                    }
                },
                cancelBlock: nil
            )
        } else {
            viewModel.toggleActive(for: branch) { success, msg in
                onShowToast(msg ?? "", !success)
            }
        }
    }
}

// MARK: - iPad Layout: Dual-Wing Branch Operations Console

@MainActor
private struct BranchesiPadStudioLayout: View {
    @ObservedObject var viewModel: AdminBranchesViewModel
    let onDismiss: () -> Void
    let onEditBranch: (PPBranchModel) -> Void
    let onNewBranch: () -> Void
    let onShowToast: (String, Bool) -> Void

    @State private var isRefreshing = false

    var body: some View {
        HStack(spacing: 0) {
            // Left Wing: Sovereign Branch Roster & Filter Deck
            VStack(spacing: 0) {
                leftWingHeader
                leftWingCommandBar
                leftWingRosterList
                leftWingFooterCTA
            }
            .frame(width: 400)
            .background(AdminSurface.surface)
            .overlay(
                Rectangle()
                    .fill(Color(uiColor: .ppSurfaceBorder).opacity(0.8))
                    .frame(width: 1),
                alignment: Language.isRTL() ? .leading : .trailing
            )

            // Right Wing: Branch Tactical Intelligence & Live Inspector
            VStack(spacing: 0) {
                if let selected = viewModel.selectedBranch() {
                    BranchStudioInspectorView(
                        branch: selected,
                        agentCount: viewModel.agentCount(for: selected.branchID),
                        canManage: viewModel.canManage,
                        onEdit: { onEditBranch(selected) },
                        onToggleActive: { confirmToggleActive(selected) },
                        onSetDefault: { confirmSetDefault(selected) },
                        onShowToast: onShowToast
                    )
                } else {
                    studioEmptyInspector
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AdminSurface.background)
        }
    }

    // MARK: Left Wing Header

    private var leftWingHeader: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                    .font(BranchType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Branches_Title", alter: "الفروع"))
                    .font(BranchType.heroTitle)
                    .foregroundColor(AdminSurface.primaryText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(uiColor: .ppSuccess))
                        .frame(width: 7, height: 7)
                    Text("\(viewModel.activeCount) \(Language.get("Branches_Filter_Active", alter: "نشط")) · \(viewModel.totalCount) \(Language.get("Branches_Telemetry_Total", alter: "إجمالي"))")
                        .font(BranchType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                withAnimation(.easeInOut(duration: 0.5)) { isRefreshing = true }
                viewModel.startListening()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isRefreshing = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(BranchType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
    }

    // MARK: Left Wing Search & Filter Bar

    private var leftWingCommandBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(BranchType.body)

                TextField(Language.get("Branches_Search", alter: "بحث في الفروع…"), text: $viewModel.searchText)
                    .font(BranchType.body)
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
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(BranchType.body)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
            )

            // Category Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BranchFilterCategory.allCases) { cat in
                        let isSel = viewModel.selectedFilter == cat
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            viewModel.selectedFilter = cat
                            viewModel.applyFilter()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon())
                                    .font(BranchType.microBold)
                                Text(cat.title())
                                    .font(isSel ? BranchType.chipTextBold : BranchType.chipText)
                            }
                            .foregroundColor(isSel ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSel ? AdminSurface.primary : AdminSurface.control, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Left Wing Roster List

    @ViewBuilder
    private var leftWingRosterList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 8) {
                if viewModel.isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        BranchCardSkeletonView()
                    }
                } else if viewModel.filteredBranches.isEmpty {
                    AdminEmptyStateView(
                        symbol: "magnifyingglass",
                        title: Language.get("Branches_NoResults_Title", alter: "لا توجد نتائج"),
                        subtitle: Language.get("Branches_NoResults_Subtitle", alter: "جرّب كلمة بحث مختلفة.")
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(viewModel.filteredBranches) { branch in
                        let isSelected = viewModel.selectedBranchID == branch.branchID
                        SovereignBranchCard(
                            branch: branch,
                            agentCount: viewModel.agentCount(for: branch.branchID),
                            canManage: viewModel.canManage,
                            isSelected: isSelected,
                            onTap: {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                viewModel.selectedBranchID = branch.branchID
                            },
                            onToggleActive: { confirmToggleActive(branch) },
                            onSetDefault: { confirmSetDefault(branch) }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Left Wing Footer CTA

    private var leftWingFooterCTA: some View {
        VStack(spacing: 0) {
            Divider()
            if viewModel.canManage {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    onNewBranch()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(BranchType.headline)
                        Text(Language.get("Branches_New", alter: "إضافة فرع جديد"))
                            .font(BranchType.buttonTitle)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
                .padding(16)
            }
        }
        .background(AdminSurface.surface)
    }

    // MARK: Right Wing Empty Placeholder

    private var studioEmptyInspector: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 100, height: 100)

                Image(systemName: "building.2.crop.circle")
                    .font(BranchType.telemetryLarge)
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(spacing: 6) {
                Text(Language.get("Branches_Studio_SelectBranch", alter: "اختر فرعاً للمعاينة"))
                    .font(BranchType.heroTitle)
                    .foregroundColor(AdminSurface.primaryText)

                Text(Language.get("Branches_Studio_SelectBranch_Desc", alter: "اختر أي فرع من القائمة الجانبية لعرض العمليات والمخزون وجهات الاتصال."))
                    .font(BranchType.body)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func confirmSetDefault(_ branch: PPBranchModel) {
        PPAlertHelper.showConfirmation(
            in: nil,
            title: Language.get("Branches_Default_Label", alter: "الفرع الافتراضي"),
            subtitle: String(format: Language.get("Branches_Default_Confirm_Format", alter: "هل تريد تعيين الفرع \"%@\" كفرع رئيسي افتراضي؟"), branch.localizedName()),
            confirmButton: Language.get("Confirm", alter: "تأكيد"),
            cancelButton: Language.get("Cancel", alter: "إلغاء"),
            icon: UIImage(systemName: "star.fill"),
            confirmBlock: { _, didConfirm in
                guard didConfirm else { return }
                viewModel.setDefaultBranch(branch) { success, msg in
                    onShowToast(msg ?? "", !success)
                }
            },
            cancelBlock: nil
        )
    }

    private func confirmToggleActive(_ branch: PPBranchModel) {
        if branch.isActive {
            PPAlertHelper.showConfirmation(
                in: nil,
                title: Language.get("Branches_Deactivate", alter: "تعطيل الفرع"),
                subtitle: String(format: Language.get("Branches_Deactivate_Confirm_Format", alter: "هل تريد تعطيل الفرع \"%@\"؟ لن يظهر هذا الفرع في عمليات البيع حتى يتم تنشيطه مجدداً."), branch.localizedName()),
                confirmButton: Language.get("Branches_Deactivate", alter: "تعطيل"),
                cancelButton: Language.get("Cancel", alter: "إلغاء"),
                icon: UIImage(systemName: "pause.circle.fill"),
                confirmBlock: { _, didConfirm in
                    guard didConfirm else { return }
                    viewModel.toggleActive(for: branch) { success, msg in
                        onShowToast(msg ?? "", !success)
                    }
                },
                cancelBlock: nil
            )
        } else {
            viewModel.toggleActive(for: branch) { success, msg in
                onShowToast(msg ?? "", !success)
            }
        }
    }
}

// MARK: - Sovereign Branch Card (Shared across iPhone and iPad)

@MainActor
private struct SovereignBranchCard: View {
    let branch: PPBranchModel
    let agentCount: Int
    let canManage: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onToggleActive: () -> Void
    let onSetDefault: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                leadingIconBox

                VStack(alignment: .leading, spacing: 4) {
                    titleRow
                    metadataRow
                    telemetryRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(BranchType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AdminSurface.primary.opacity(0.06) : AdminSurface.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.7),
                        lineWidth: isSelected ? 1.5 : 0.8
                    )
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0.02), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            if canManage {
                Button(action: onTap) {
                    Label(Language.get("Edit", alter: "تعديل"), systemImage: "pencil")
                }

                if !branch.isDefault {
                    Button(action: onSetDefault) {
                        Label(Language.get("Branches_Default_Label", alter: "تعيين كفرع رئيسي"), systemImage: "star.fill")
                    }

                    Button(action: onToggleActive) {
                        Label(
                            branch.isActive ? Language.get("Branches_Deactivate", alter: "تعطيل") : Language.get("Branches_Activate", alter: "تفعيل"),
                            systemImage: branch.isActive ? "pause.circle" : "play.circle"
                        )
                    }
                }
            }
        }
    }

    private var leadingIconBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: branch.isActive
                            ? [AdminSurface.primary, AdminSurface.primary.opacity(0.85)]
                            : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .shadow(color: branch.isActive ? AdminSurface.primary.opacity(0.25) : Color.clear, radius: 6, y: 2)

            Image(systemName: branch.isDefault ? "building.columns.fill" : "building.2.fill")
                .font(BranchType.title3)
                .foregroundColor(branch.isActive ? .white : AdminSurface.secondaryText)

            // Operational Status Indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(branch.isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: Language.isRTL() ? -2 : 2, y: 2)
                }
            }
            .frame(width: 52, height: 52)
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(branch.localizedName())
                .font(BranchType.headline)
                .foregroundColor(branch.isActive ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .lineLimit(1)

            if branch.isDefault {
                defaultBadge
            }
        }
    }

    private var defaultBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill")
                .font(BranchType.microBold)
            Text(Language.get("Branches_Default", alter: "الرئيسي"))
                .font(BranchType.badgePill)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            LinearGradient(
                colors: [Color(uiColor: .ppWarning), Color(uiColor: .ppWarning).opacity(0.85)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: Capsule()
        )
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if !branch.code.isEmpty {
                Text(branch.code)
                    .font(BranchType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            if !branch.address.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(BranchType.micro)
                    Text(branch.address)
                        .font(BranchType.caption)
                        .lineLimit(1)
                }
                .foregroundColor(AdminSurface.secondaryText)
            }
        }
    }

    private var telemetryRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: branch.stockMode == .branch ? "shippingbox.fill" : "person.2.fill")
                    .font(BranchType.micro)
                Text(branch.localizedStockModeName())
                    .font(BranchType.captionMedium)
            }
            .foregroundColor(AdminSurface.secondaryText)

            Text("•")
                .font(BranchType.caption)
                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))

            HStack(spacing: 4) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(BranchType.micro)
                Text("\(agentCount) \(Language.get(agentCount == 1 ? "Branches_Agent_Count" : "Branches_Agent_Count_Plural", alter: "وكلاء"))")
                    .font(BranchType.captionMedium)
            }
            .foregroundColor(agentCount > 0 ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
        }
    }
}

// MARK: - iPad Studio Inspector View (Right Wing)

@MainActor
private struct BranchStudioInspectorView: View {
    let branch: PPBranchModel
    let agentCount: Int
    let canManage: Bool
    let onEdit: () -> Void
    let onToggleActive: () -> Void
    let onSetDefault: () -> Void
    let onShowToast: (String, Bool) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                heroStudioBanner
                telemetryGrid
                stockArchitectureCard
                workforceCard
                locationContactCard
                governanceCard
            }
            .padding(24)
        }
    }

    // Hero Studio Banner
    private var heroStudioBanner: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: branch.isActive
                                ? [AdminSurface.primary, AdminSurface.primary.opacity(0.85)]
                                : [Color.gray.opacity(0.35), Color.gray.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: branch.isActive ? AdminSurface.primary.opacity(0.3) : Color.clear, radius: 10, y: 4)

                Image(systemName: branch.isDefault ? "building.columns.fill" : "building.2.fill")
                    .font(BranchType.telemetryLarge)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(branch.localizedName())
                        .font(BranchType.heroTitle)
                        .foregroundColor(AdminSurface.primaryText)

                    if branch.isDefault {
                        Text(Language.get("Branches_Studio_IsDefaultBadge", alter: "الفرع الرئيسي للنظام"))
                            .font(BranchType.captionBold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color(uiColor: .ppWarning), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Text(branch.code)
                        .font(BranchType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 4) {
                        Circle()
                            .fill(branch.isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))
                            .frame(width: 8, height: 8)
                        Text(branch.isActive ? Language.get("Active", alter: "نشط") : Language.get("Inactive", alter: "غير نشط"))
                            .font(BranchType.captionBold)
                            .foregroundColor(branch.isActive ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Direct Action Buttons
            if canManage {
                HStack(spacing: 10) {
                    if !branch.isDefault {
                        Button(action: onSetDefault) {
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .font(BranchType.captionBold)
                                Text(Language.get("Branches_Studio_MakeDefault", alter: "تعيين كفرع رئيسي"))
                                    .font(BranchType.buttonTitle)
                            }
                            .foregroundColor(Color(uiColor: .ppWarning))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Color(uiColor: .ppWarning).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)

                        Button(action: onToggleActive) {
                            HStack(spacing: 6) {
                                Image(systemName: branch.isActive ? "pause.circle.fill" : "play.circle.fill")
                                    .font(BranchType.captionBold)
                                Text(branch.isActive ? Language.get("Branches_Deactivate", alter: "تعطيل") : Language.get("Branches_Activate", alter: "تفعيل"))
                                    .font(BranchType.buttonTitle)
                            }
                            .foregroundColor(branch.isActive ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background((branch.isActive ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }

                    Button(action: onEdit) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(BranchType.captionBold)
                            Text(Language.get("Edit", alter: "تعديل"))
                                .font(BranchType.buttonTitle)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
        )
    }

    // Telemetry Grid
    private var telemetryGrid: some View {
        HStack(spacing: 14) {
            studioMetricCard(
                title: Language.get("Branches_Stock_Mode", alter: "نمط المخزون"),
                value: branch.localizedStockModeName(),
                subtitle: branch.stockMode == .branch ? Language.get("Branches_Stock_Shared_Help", alter: "مخزون مركزي موحد") : Language.get("Branches_Stock_Separate_Help", alter: "مخزون مخصص لكل وكيل"),
                icon: branch.stockMode == .branch ? "shippingbox.fill" : "person.2.fill",
                color: AdminSurface.primary
            )

            studioMetricCard(
                title: Language.get("Branches_Agents", alter: "القوة الميدانية"),
                value: "\(agentCount)",
                subtitle: agentCount > 0 ? Language.get("Branches_Telemetry_Agents_Unit", alter: "وكيل نشط مسجل") : Language.get("Branches_No_Agents_Assigned", alter: "لا يوجد وكلاء معينون"),
                icon: "person.badge.shield.checkmark.fill",
                color: Color(uiColor: .ppSuccess)
            )

            studioMetricCard(
                title: Language.get("Branches_Address", alter: "الموقع الميداني"),
                value: branch.address.isEmpty ? "-" : branch.address,
                subtitle: "دولة قطر",
                icon: "mappin.and.ellipse",
                color: Color(uiColor: .ppAccent)
            )
        }
    }

    private func studioMetricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(BranchType.subheadlineMedium)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                Image(systemName: icon)
                    .font(BranchType.headline)
                    .foregroundColor(color)
            }

            Text(value)
                .font(BranchType.title2)
                .foregroundColor(AdminSurface.primaryText)
                .lineLimit(1)

            Text(subtitle)
                .font(BranchType.caption)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                )
        )
    }

    // Stock Architecture Card
    private var stockArchitectureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cube.transparent.fill")
                    .font(BranchType.headline)
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("Branches_Studio_StockArchitecture", alter: "بنية إدارة المخزون"))
                    .font(BranchType.title3)
                    .foregroundColor(AdminSurface.primaryText)
            }

            Text(branch.stockMode == .branch
                 ? Language.get("Branches_Stock_Shared_Help", alter: "جميع الفروع والوكلاء في هذا الفرع يتشاركون نفس مستودع المخزون المركزي.")
                 : Language.get("Branches_Stock_Separate_Help", alter: "كل وكيل مبيعات في هذا الفرع يدير عهدته ومخزونه الخاص بشكل مستقل."))
                .font(BranchType.body)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                )
        )
    }

    // Workforce Card
    private var workforceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(BranchType.headline)
                    .foregroundColor(Color(uiColor: .ppSuccess))
                Text(Language.get("Branches_Studio_WorkforceDeployment", alter: "توزيع القوة البشرية"))
                    .font(BranchType.title3)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text("\(agentCount) \(Language.get("Branches_Agents", alter: "وكيل"))")
                    .font(BranchType.captionBold)
                    .foregroundColor(Color(uiColor: .ppSuccess))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
            }

            Text(agentCount > 0
                 ? "يوجد \(agentCount) وكلاء مسجلون حالياً ضمن هذا النطاق التشغيلي لتنفيذ الطلبات وحركة المخزون."
                 : "لم يتم ربط أي وكلاء مبيعات بهذا الفرع حتى الآن. يمكنك تعيين الوكلاء من قسم إدارة الوكلاء.")
                .font(BranchType.body)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                )
        )
    }

    // Location & Contact Card
    private var locationContactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "phone.fill")
                    .font(BranchType.headline)
                    .foregroundColor(Color(uiColor: .ppAccent))
                Text(Language.get("Branches_Studio_LocationDispatch", alter: "الموقع والاتصال الميداني"))
                    .font(BranchType.title3)
                    .foregroundColor(AdminSurface.primaryText)
            }

            HStack(spacing: 12) {
                // Address Box
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Branches_Address", alter: "العنوان"))
                        .font(BranchType.captionMedium)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(branch.address.isEmpty ? "-" : branch.address)
                        .font(BranchType.bodyBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !branch.address.isEmpty {
                    Button(action: {
                        UIPasteboard.general.string = branch.address
                        onShowToast(Language.get("Branches_Address_Copied", alter: "تم نسخ العنوان إلى الحافظة"), false)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(BranchType.captionBold)
                            Text(Language.get("Branches_Copy_Address", alter: "نسخ"))
                                .font(BranchType.captionBold)
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }

                Divider().frame(height: 36)

                // Phone Box
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Branches_Phone", alter: "الهاتف"))
                        .font(BranchType.captionMedium)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(branch.phone.isEmpty ? "-" : branch.phone)
                        .font(BranchType.bodyBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !branch.phone.isEmpty, let url = URL(string: "tel://\(branch.phone.replacingOccurrences(of: " ", with: ""))") {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.arrow.up.right.fill")
                                .font(BranchType.captionBold)
                            Text(Language.get("Branches_Call_Phone", alter: "اتصال"))
                                .font(BranchType.captionBold)
                        }
                        .foregroundColor(Color(uiColor: .ppSuccess))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .ppSuccess).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                )
        )
    }

    // Governance & Metadata Card
    private var governanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .font(BranchType.headline)
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("Branches_Studio_Governance", alter: "الحوكمة والسجلات"))
                    .font(BranchType.title3)
                    .foregroundColor(AdminSurface.primaryText)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("معرّف الفرع (ID)")
                        .font(BranchType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Text(branch.branchID)
                        .font(BranchType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                if let created = branch.createdAt {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("تاريخ الإنشاء")
                            .font(BranchType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(formatDate(created))
                            .font(BranchType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                }

                if let updated = branch.updatedAt {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("آخر تحديث")
                            .font(BranchType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(formatDate(updated))
                            .font(BranchType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                )
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Skeleton Shimmer Card

@MainActor
private struct BranchCardSkeletonView: View {
    @State private var isShimmering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 140, height: 16)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 90, height: 12)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.10))
                    .frame(width: 180, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
                )
        )
        .opacity(reduceMotion ? 1.0 : (isShimmering ? 0.5 : 1.0))
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isShimmering = true
                }
            }
        }
    }
}

// Note: AdminBranchEditorSheet and PPBranchEditorView are defined in PPBranchEditorView.swift