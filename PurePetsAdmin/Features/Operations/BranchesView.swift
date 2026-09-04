//
//  BranchesView.swift
//  PurePetsAdmin
//
//  NextGen V6 Native SwiftUI Branches Management.
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

// MARK: - Branch List ViewModel

@MainActor
final class AdminBranchesViewModel: ObservableObject {
    @Published private(set) var branches: [PPBranchModel] = []
    @Published private(set) var filteredBranches: [PPBranchModel] = []
    @Published private(set) var agentCounts: [String: Int] = [:]
    @Published var searchText: String = ""
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var canManage: Bool = false

    private nonisolated(unsafe) var branchesListener: (any ListenerRegistration)?
    private nonisolated(unsafe) var agentsListener: (any ListenerRegistration)?

    var totalCount: Int { filteredBranches.count }
    var activeCount: Int { filteredBranches.filter { $0.isActive }.count }

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
        if query.isEmpty {
            filteredBranches = branches
        } else {
            filteredBranches = branches.filter { b in
                b.nameEn.lowercased().contains(query) ||
                b.nameAr.contains(query) ||
                b.code.lowercased().contains(query) ||
                b.address.lowercased().contains(query)
            }
        }
    }

    func agentCount(for branchID: String) -> Int {
        guard !branchID.isEmpty else { return 0 }
        return agentCounts[branchID] ?? 0
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

// MARK: - Main Branches View

@MainActor
struct AdminBranchesView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminBranchesViewModel()
    @State private var editingBranch: PPBranchModel? = nil
    @State private var isPresentingNewBranch = false
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
                        searchSection
                        branchListContent
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
        .onChange(of: viewModel.searchText) { _ in
            viewModel.applyFilter()
        }
        .sheet(item: $editingBranch) { branch in
            AdminBranchEditorSheet(
                branch: branch,
                canManage: viewModel.canManage,
                agentCount: viewModel.agentCount(for: branch.branchID),
                onDismiss: { editingBranch = nil },
                onSaved: { msg in
                    editingBranch = nil
                    PPAlertHelper.showSuccess(in: nil, title: Language.get("Branches_Updated", alter: "تم التحديث"), subtitle: msg)
                },
                onDelete: { b in
                    editingBranch = nil
                    confirmDeleteBranch(b)
                }
            )
        }
        .sheet(isPresented: $isPresentingNewBranch) {
            AdminBranchEditorSheet(
                branch: nil,
                canManage: viewModel.canManage,
                agentCount: 0,
                onDismiss: { isPresentingNewBranch = false },
                onSaved: { msg in
                    isPresentingNewBranch = false
                    PPAlertHelper.showSuccess(in: nil, title: Language.get("Branches_Created", alter: "تم إنشاء الفرع"), subtitle: msg)
                },
                onDelete: nil
            )
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            AdminSovereignNavigationBar(
                title: Language.get("Branches_Title", alter: "إدارة الفروع والمواقع"),
                subtitle: Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات"),
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
                        Text(Language.get("Branches_Title", alter: nil))
                            .font(AdminType.title2)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("Branches_Subtitle", alter: nil))
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 52, height: 52)
                        Image(systemName: "building.2")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AdminSurface.primary)
                    }
                    .accessibilityHidden(true)
                }

                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(String(format: Language.get("Branches_Count_Format", alter: nil), viewModel.totalCount, viewModel.activeCount))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())

                    Spacer()

                    if viewModel.canManage {
                        Button {
                            isPresentingNewBranch = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                Text(Language.get("Branches_New", alter: nil))
                                    .font(AdminType.captionBold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(AdminSurface.primary, in: Capsule())
                        }
                        .accessibilityLabel(Language.get("Branches_New", alter: nil))
                    }
                }
            }
            .padding(AdminSpacing.cardPadding)
        }
    }

    // MARK: - Search Bar

    private var searchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AdminSurface.secondaryText)
                .font(.system(size: 16, weight: .medium))

            TextField(Language.get("Branches_Search", alter: nil), text: $viewModel.searchText)
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

    // MARK: - Branch List Content

    @ViewBuilder
    private var branchListContent: some View {
        if viewModel.isLoading {
            VStack(spacing: 16) {
                ProgressView().tint(AdminSurface.primary).scaleEffect(1.2)
                Text(Language.get("Branches_Loading", alter: nil))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if viewModel.branches.isEmpty {
            AdminEmptyStateView(
                symbol: "building.2",
                title: Language.get("Branches_Empty_Title", alter: nil),
                subtitle: Language.get("Branches_Empty_Subtitle", alter: nil),
                actionTitle: viewModel.canManage ? Language.get("Branches_Empty_CTA", alter: nil) : nil,
                action: { isPresentingNewBranch = true }
            )
        } else if viewModel.filteredBranches.isEmpty {
            AdminEmptyStateView(
                symbol: "magnifyingglass",
                title: Language.get("Branches_NoResults_Title", alter: nil),
                subtitle: Language.get("Branches_NoResults_Subtitle", alter: nil)
            )
        } else {
            LazyVStack(spacing: AdminSpacing.md) {
                ForEach(viewModel.filteredBranches) { branch in
                    branchCard(branch: branch)
                }
            }
        }
    }

    // MARK: - Branch Card

    private func branchCard(branch: PPBranchModel) -> some View {
        let count = viewModel.agentCount(for: branch.branchID)
        let agentsWord = Language.get(count == 1 ? "Branches_Agent_Count" : "Branches_Agent_Count_Plural", alter: nil)
        let isRTL = Language.isRTL()

        return Button {
            if viewModel.canManage {
                editingBranch = branch
            }
        } label: {
            HStack(spacing: AdminSpacing.md) {
                // Leading Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        .fill(branch.isActive ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.20))
                        .frame(width: 48, height: 48)
                    Image(systemName: branch.isDefault ? "building.columns.fill" : "building.2.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                }
                .accessibilityHidden(true)

                // Info Stack
                VStack(alignment: .leading, spacing: 3) {
                    Text(branch.localizedName())
                        .font(AdminType.headline)
                        .foregroundColor(branch.isActive ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .lineLimit(1)

                    if !branch.code.isEmpty {
                        Text(branch.code)
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Text("\(branch.localizedStockModeName()) • \(count) \(agentsWord)")
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.80))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing Badges & Chevron
                HStack(spacing: 8) {
                    if branch.isDefault {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(Language.get("Branches_Default", alter: nil))
                                .font(AdminType.captionBold)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else if branch.isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(AdminSurface.secondaryText.opacity(0.40))
                            .frame(width: 8, height: 8)
                    }

                    if viewModel.canManage {
                        Image(systemName: isRTL ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.60))
                    }
                }
            }
            .padding(AdminSpacing.base)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(branch.isDefault ? AdminSurface.primary.opacity(0.40) : AdminSurface.hairline)
            )
            .shadow(color: AdminShadow.card.color, radius: AdminShadow.card.radius, y: AdminShadow.card.y)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if viewModel.canManage {
                Button {
                    editingBranch = branch
                } label: {
                    Label(Language.get("Edit", alter: nil), systemImage: "pencil")
                }

                if !branch.isDefault {
                    Button {
                        confirmSetDefaultBranch(branch)
                    } label: {
                        Label(Language.get("Branches_Default_Label", alter: nil), systemImage: "star.fill")
                    }

                    Button {
                        confirmToggleActiveBranch(branch)
                    } label: {
                        Label(
                            branch.isActive ? Language.get("Branches_Deactivate", alter: nil) : Language.get("Branches_Activate", alter: nil),
                            systemImage: branch.isActive ? "pause.circle" : "play.circle"
                        )
                    }

                    if count == 0 {
                        Button(role: .destructive) {
                            confirmDeleteBranch(branch)
                        } label: {
                            Label(Language.get("Delete", alter: nil), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func confirmSetDefaultBranch(_ branch: PPBranchModel) {
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
                    if success {
                        PPAlertHelper.showSuccess(in: nil, title: Language.get("Branches_Updated", alter: "تم التحديث"), subtitle: msg)
                    } else {
                        PPAlertHelper.showError(in: nil, title: Language.get("Error_Generic", alter: "خطأ"), subtitle: msg)
                    }
                }
            },
            cancelBlock: nil
        )
    }

    private func confirmToggleActiveBranch(_ branch: PPBranchModel) {
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
                        if success {
                            PPAlertHelper.showSuccess(in: nil, title: Language.get("Branches_Updated", alter: "تم التحديث"), subtitle: msg)
                        } else {
                            PPAlertHelper.showError(in: nil, title: Language.get("Error_Generic", alter: "خطأ"), subtitle: msg)
                        }
                    }
                },
                cancelBlock: nil
            )
        } else {
            viewModel.toggleActive(for: branch) { success, msg in
                if success {
                    PPAlertHelper.showSuccess(in: nil, title: Language.get("Branches_Updated", alter: "تم التحديث"), subtitle: msg)
                } else {
                    PPAlertHelper.showError(in: nil, title: Language.get("Error_Generic", alter: "خطأ"), subtitle: msg)
                }
            }
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
                        PPAlertHelper.showSuccess(in: nil, title: Language.get("Deleted", alter: "تم الحذف"), subtitle: msg)
                    } else {
                        PPAlertHelper.showError(in: nil, title: Language.get("Error_Generic", alter: "خطأ"), subtitle: msg)
                    }
                }
            },
            cancelBlock: nil
        )
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

// MARK: - Branch Editor Sheet

@MainActor
struct AdminBranchEditorSheet: View {
    let branch: PPBranchModel?
    let canManage: Bool
    let agentCount: Int
    let onDismiss: () -> Void
    let onSaved: (String) -> Void
    let onDelete: ((PPBranchModel) -> Void)?

    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var code: String = ""
    @State private var address: String = ""
    @State private var phone: String = ""
    @State private var stockMode: PPBranchStockMode = .perAgent
    @State private var isActive: Bool = true
    @State private var isDefault: Bool = false
    @State private var isSaving: Bool = false
    @State private var validationError: String? = nil

    private var isEditing: Bool { branch != nil }

    init(
        branch: PPBranchModel?,
        canManage: Bool,
        agentCount: Int = 0,
        onDismiss: @escaping () -> Void,
        onSaved: @escaping (String) -> Void,
        onDelete: ((PPBranchModel) -> Void)? = nil
    ) {
        self.branch = branch
        self.canManage = canManage
        self.agentCount = agentCount
        self.onDismiss = onDismiss
        self.onSaved = onSaved
        self.onDelete = onDelete
        _nameAr = State(initialValue: branch?.nameAr ?? "")
        _nameEn = State(initialValue: branch?.nameEn ?? "")
        _code = State(initialValue: branch?.code ?? "")
        _address = State(initialValue: branch?.address ?? "")
        _phone = State(initialValue: branch?.phone ?? "")
        _stockMode = State(initialValue: branch?.stockMode ?? .perAgent)
        _isActive = State(initialValue: branch?.isActive ?? true)
        _isDefault = State(initialValue: branch?.isDefault ?? false)
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        heroCard
                        generalFieldsSection
                        contactFieldsSection
                        stockModeSection
                        settingsTogglesSection

                        if let error = validationError {
                            AdminErrorBanner(message: error)
                        }

                        saveButton
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.vertical, AdminSpacing.base)
                }
            }
            .navigationTitle(isEditing ? Language.get("Branches_Edit", alter: nil) : Language.get("Branches_New", alter: nil))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: nil)) { onDismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var heroCard: some View {
        AdminCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: isDefault ? "building.columns.fill" : "building.2.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditing ? (branch?.localizedName() ?? "") : Language.get("Branches_New", alter: nil))
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(isEditing ? (branch?.code ?? "") : Language.get("Branches_Info", alter: nil))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AdminSpacing.cardPadding)
        }
    }

    private var generalFieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Branches_Info", alter: nil))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            AdminCard {
                VStack(spacing: 12) {
                    editorField(title: Language.get("Branches_Name_Ar", alter: nil), text: $nameAr, placeholder: "اسم الفرع بالعربية")
                    Divider().padding(.leading, 12)
                    editorField(title: Language.get("Branches_Name_En", alter: nil), text: $nameEn, placeholder: "Branch Name in English")
                    Divider().padding(.leading, 12)
                    editorField(title: Language.get("Branches_Code", alter: nil), text: $code, placeholder: "PP-BRCH-01")
                }
                .padding(14)
            }
        }
    }

    private var contactFieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Branches_Contact", alter: nil))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            AdminCard {
                VStack(spacing: 12) {
                    editorField(title: Language.get("Branches_Address", alter: nil), text: $address, placeholder: "الدوحة، قطر")
                    Divider().padding(.leading, 12)
                    editorField(title: Language.get("Branches_Phone", alter: nil), text: $phone, placeholder: "+974 0000 0000", keyboard: .phonePad)
                }
                .padding(14)
            }
        }
    }

    private var stockModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Branches_Stock_Mode", alter: nil))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            AdminCard {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(Language.get("Branches_Stock_Mode", alter: nil), selection: $stockMode) {
                        Text(Language.get("Branches_Stock_Separate", alter: "مخزون الوكيل")).tag(PPBranchStockMode.perAgent)
                        Text(Language.get("Branches_Stock_Shared", alter: "مخزون مشترك")).tag(PPBranchStockMode.branch)
                    }
                    .pickerStyle(.segmented)

                    Text(stockMode == .perAgent ? Language.get("Branches_Stock_Separate_Help", alter: nil) : Language.get("Branches_Stock_Shared_Help", alter: nil))
                        .font(AdminType.footnote)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .padding(14)
            }
        }
    }

    private var settingsTogglesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Branches_Settings", alter: nil))
                .font(AdminType.headline)
                .foregroundColor(AdminSurface.primaryText)

            AdminCard {
                VStack(spacing: 14) {
                    Toggle(isOn: $isActive) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Active", alter: "نشط"))
                                .font(AdminType.body)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(isActive ? Language.get("Branches_Activated", alter: nil) : Language.get("Branches_Deactivated", alter: nil))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .tint(AdminSurface.primary)

                    Divider().padding(.leading, 12)

                    Toggle(isOn: $isDefault) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Branches_Default_Label", alter: nil))
                                .font(AdminType.body)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("Branches_Default", alter: nil))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .tint(AdminSurface.primary)
                }
                .padding(14)
            }
        }
    }

    private func editorField(title: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
            TextField(placeholder, text: text)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.primaryText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        VStack(spacing: 8) {
            Button {
                saveBranch()
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(Language.get("Save", alter: nil))
                        .font(AdminType.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
            }
            .disabled(isSaving || !canManage)

            if isEditing, canManage, !isDefault, agentCount == 0, let b = branch {
                Button(role: .destructive) {
                    onDelete?(b)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(Language.get("Delete", alter: "حذف الفرع"))
                            .font(AdminType.headline)
                    }
                    .foregroundColor(Color(uiColor: .ppError))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                            .stroke(Color(uiColor: .ppError).opacity(0.24), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.top, 8)
    }

    private func saveBranch() {
        let trimmedAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAr.isEmpty && trimmedEn.isEmpty {
            let requiredMsg = Language.get("Branches_Name_Required", alter: "Branch name is required")
            validationError = requiredMsg
            PPAlertHelper.showError(in: nil, title: Language.get("Error_Generic", alter: "خطأ"), subtitle: requiredMsg)
            return
        }

        validationError = nil
        isSaving = true

        let docID: String = {
            if let existingID = branch?.branchID, !existingID.isEmpty {
                return existingID
            }
            return Firestore.firestore().collection(kPPBranchesCol).document().documentID
        }()
        let uid = Auth.auth().currentUser?.uid ?? ""

        var payload: [String: Any] = [
            "nameAr": trimmedAr,
            "nameEn": trimmedEn,
            "code": trimmedCode.isEmpty ? "PP-\(docID.prefix(6).uppercased())" : trimmedCode,
            "address": address.trimmingCharacters(in: .whitespacesAndNewlines),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "stockMode": stockMode == .branch ? "branch" : "perAgent",
            "isActive": isActive,
            "isDefault": isDefault,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if !isEditing {
            payload["createdAt"] = FieldValue.serverTimestamp()
            payload["createdBy"] = uid
        }

        let ref = Firestore.firestore().collection(kPPBranchesCol).document(docID)

        if isDefault {
            let batch = Firestore.firestore().batch()
            batch.setData(payload, forDocument: ref, merge: true)

            Firestore.firestore().collection(kPPBranchesCol).whereField("isDefault", isEqualTo: true).getDocuments { snapshot, _ in
                if let docs = snapshot?.documents {
                    for doc in docs where doc.documentID != docID {
                        batch.updateData(["isDefault": false], forDocument: doc.reference)
                    }
                }
                batch.commit { error in
                    DispatchQueue.main.async {
                        self.isSaving = false
                        if let error {
                            self.validationError = error.localizedDescription
                            PPAlertHelper.showError(in: nil, title: Language.get("Error_Generic", alter: "خطأ"), subtitle: error.localizedDescription)
                        } else {
                            self.writeSaveAuditLog(branchID: docID, isNew: !self.isEditing)
                            self.onSaved(self.isEditing ? Language.get("Branches_Updated", alter: nil) : Language.get("Branches_Created", alter: nil))
                        }
                    }
                }
            }
        } else {
            ref.setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if let error {
                        self.validationError = error.localizedDescription
                        PPAlertHelper.showError(in: nil, title: Language.get("Error_Generic", alter: "خطأ"), subtitle: error.localizedDescription)
                    } else {
                        self.writeSaveAuditLog(branchID: docID, isNew: !self.isEditing)
                        self.onSaved(self.isEditing ? Language.get("Branches_Updated", alter: nil) : Language.get("Branches_Created", alter: nil))
                    }
                }
            }
        }
    }

    private func writeSaveAuditLog(branchID: String, isNew: Bool) {
        let uid = Auth.auth().currentUser?.uid ?? ""
        Firestore.firestore().collection("AdminAuditLogs").document().setData([
            "action": isNew ? "create_branch" : "update_branch",
            "targetCollection": kPPBranchesCol,
            "targetId": branchID,
            "adminUid": uid,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }
}