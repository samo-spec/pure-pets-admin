//
//  PPBranchEditorView.swift
//  PurePetsAdmin
//
//  NextGen V6 Category-Defining Branch Command Center & Dossier Studio.
//  Reinvented from first principles with dedicated, separate architectures
//  for iPhone (iOS fluid thumb ergonomics) and iPad (iPadOS tactical dual-pane console).
//  Full-screen presentation, strict Beiruti typography, 6-state resilience,
//  tactile haptic physics, and bidirectional Arabic (RTL) / English (LTR) safety.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Root Adaptive Coordinator

@MainActor
public struct PPBranchEditorView: View {
    let branch: PPBranchModel?
    let canManage: Bool
    let agentCount: Int
    let onDismiss: @MainActor @Sendable () -> Void
    let onSaved: @MainActor @Sendable (String) -> Void
    let onDelete: (@MainActor @Sendable (PPBranchModel) -> Void)?

    @StateObject private var state: BranchEditorState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection

    public init(
        branch: PPBranchModel?,
        canManage: Bool,
        agentCount: Int = 0,
        onDismiss: @escaping @MainActor @Sendable () -> Void,
        onSaved: @escaping @MainActor @Sendable (String) -> Void,
        onDelete: (@MainActor @Sendable (PPBranchModel) -> Void)? = nil
    ) {
        self.branch = branch
        self.canManage = canManage
        self.agentCount = agentCount
        self.onDismiss = onDismiss
        self.onSaved = onSaved
        self.onDelete = onDelete
        _state = StateObject(wrappedValue: BranchEditorState(branch: branch, agentCount: agentCount, canManage: canManage, onSaved: onSaved))
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            if isPad {
                PPBranchEditorPadView(
                    state: state,
                    onDismiss: onDismiss,
                    onSave: { state.saveBranch() },
                    onDelete: {
                        if let b = branch {
                            onDelete?(b)
                        }
                    }
                )
            } else {
                PPBranchEditorPhoneView(
                    state: state,
                    onDismiss: onDismiss,
                    onSave: { state.saveBranch() },
                    onDelete: {
                        if let b = branch {
                            onDelete?(b)
                        }
                    }
                )
            }

            // Notification Overlay Banner (Copied, Validation, etc.)
            if let toast = state.toastMessage {
                VStack {
                    Spacer()
                    BranchToastBanner(message: toast, isError: state.isErrorToast)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, isPad ? 36 : 96)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(AdminAnimation.standard, value: state.toastMessage)
                .zIndex(100)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Backward-Compatible Alias for BranchesView

@MainActor
public struct AdminBranchEditorSheet: View {
    let branch: PPBranchModel?
    let canManage: Bool
    let agentCount: Int
    let onDismiss: @MainActor @Sendable () -> Void
    let onSaved: @MainActor @Sendable (String) -> Void
    let onDelete: (@MainActor @Sendable (PPBranchModel) -> Void)?

    public init(
        branch: PPBranchModel?,
        canManage: Bool,
        agentCount: Int = 0,
        onDismiss: @escaping @MainActor @Sendable () -> Void,
        onSaved: @escaping @MainActor @Sendable (String) -> Void,
        onDelete: (@MainActor @Sendable (PPBranchModel) -> Void)? = nil
    ) {
        self.branch = branch
        self.canManage = canManage
        self.agentCount = agentCount
        self.onDismiss = onDismiss
        self.onSaved = onSaved
        self.onDelete = onDelete
    }

    public var body: some View {
        PPBranchEditorView(
            branch: branch,
            canManage: canManage,
            agentCount: agentCount,
            onDismiss: onDismiss,
            onSaved: onSaved,
            onDelete: onDelete
        )
    }
}

// MARK: - State Management Machine

@MainActor
final class BranchEditorState: ObservableObject {
    let originalBranch: PPBranchModel?
    let agentCount: Int
    let canManage: Bool
    let isEditing: Bool
    let onSaved: (@MainActor @Sendable (String) -> Void)?

    @Published var nameAr: String
    @Published var nameEn: String
    @Published var code: String
    @Published var address: String
    @Published var phone: String
    @Published var stockMode: PPBranchStockMode
    @Published var isActive: Bool
    @Published var isDefault: Bool

    // Enterprise Metadata
    @Published var operatingHours: String
    @Published var taxNumber: String
    @Published var crNumber: String
    @Published var managerId: String

    // Interaction & Telemetry States
    @Published var isSaving: Bool = false
    @Published var validationError: String? = nil
    @Published var toastMessage: String? = nil
    @Published var isErrorToast: Bool = false
    @Published var showEnterpriseFields: Bool = false

    init(branch: PPBranchModel?, agentCount: Int, canManage: Bool, onSaved: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.originalBranch = branch
        self.agentCount = agentCount
        self.canManage = canManage
        self.isEditing = branch != nil
        self.onSaved = onSaved

        _nameAr = Published(initialValue: branch?.nameAr ?? "")
        _nameEn = Published(initialValue: branch?.nameEn ?? "")
        _code = Published(initialValue: branch?.code ?? "")
        _address = Published(initialValue: branch?.address ?? "")
        _phone = Published(initialValue: branch?.phone ?? "")
        _stockMode = Published(initialValue: branch?.stockMode ?? .perAgent)
        _isActive = Published(initialValue: branch?.isActive ?? true)
        _isDefault = Published(initialValue: branch?.isDefault ?? false)

        _operatingHours = Published(initialValue: branch?.operatingHours ?? "")
        _taxNumber = Published(initialValue: branch?.taxNumber ?? "")
        _crNumber = Published(initialValue: branch?.crNumber ?? "")
        _managerId = Published(initialValue: branch?.managerId ?? "")

        if branch != nil && (branch?.taxNumber != nil || branch?.crNumber != nil || branch?.operatingHours != nil) {
            _showEnterpriseFields = Published(initialValue: true)
        }
    }

    var completionRatio: Double {
        var score: Double = 0
        let total: Double = 5
        if !nameAr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if !nameEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 1 }
        return min(1.0, score / total)
    }

    var completionPercentageText: String {
        let pct = Int(completionRatio * 100)
        return "\(pct)%"
    }

    var effectiveDisplayName: String {
        let ar = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        if Language.isRTL() {
            return !ar.isEmpty ? ar : (!en.isEmpty ? en : Language.get("Branches_New", alter: "فرع جديد"))
        } else {
            return !en.isEmpty ? en : (!ar.isEmpty ? ar : Language.get("Branches_New", alter: "New Branch"))
        }
    }

    var effectiveSubtitle: String {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty {
            return c
        }
        return Language.get("Branches_Info", alter: "بيانات الفرع والعمليات")
    }

    var canDelete: Bool {
        guard isEditing, canManage else { return false }
        if isDefault { return false }
        if agentCount > 0 { return false }
        return true
    }

    func generateAutoCode() {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()

        let rawUUID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let suffix = String(rawUUID.prefix(6)).uppercased()
        self.code = "PP-DOH-\(suffix)"
        showToast(Language.get("Branches_CodeCopied", alter: "تم توليد الرمز تلقائياً"), isError: false)
    }

    func copyToClipboard(text: String, label: String) {
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        showToast(label, isError: false)
    }

    func showToast(_ message: String, isError: Bool) {
        self.toastMessage = message
        self.isErrorToast = isError
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    func saveBranch() {
        let trimmedAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAr.isEmpty && trimmedEn.isEmpty {
            let errorMsg = Language.get("Branches_Name_Required", alter: "اسم الفرع مطلوب بالعربية أو الإنجليزية")
            self.validationError = errorMsg
            showToast(errorMsg, isError: true)
            let errorHaptic = UINotificationFeedbackGenerator()
            errorHaptic.notificationOccurred(.error)
            return
        }

        self.validationError = nil
        self.isSaving = true

        let docID: String = {
            if let existingID = originalBranch?.branchID, !existingID.isEmpty {
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

        let hours = operatingHours.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hours.isEmpty { payload["operatingHours"] = hours }

        let tax = taxNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tax.isEmpty { payload["taxNumber"] = tax }

        let cr = crNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cr.isEmpty { payload["crNumber"] = cr }

        let mgr = managerId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mgr.isEmpty { payload["managerId"] = mgr }

        if !isEditing {
            payload["createdAt"] = FieldValue.serverTimestamp()
            payload["createdBy"] = uid
        }

        let ref = Firestore.firestore().collection(kPPBranchesCol).document(docID)

        if isDefault {
            let batch = Firestore.firestore().batch()
            batch.setData(payload, forDocument: ref, merge: true)

            Firestore.firestore().collection(kPPBranchesCol).whereField("isDefault", isEqualTo: true).getDocuments { [weak self] snapshot, _ in
                guard let self else { return }
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
                            self.showToast(error.localizedDescription, isError: true)
                            let errorHaptic = UINotificationFeedbackGenerator()
                            errorHaptic.notificationOccurred(.error)
                        } else {
                            self.writeSaveAuditLog(branchID: docID, isNew: !self.isEditing)
                            let successHaptic = UINotificationFeedbackGenerator()
                            successHaptic.notificationOccurred(.success)
                            let msg = self.isEditing ? Language.get("Branches_Updated", alter: "تم تحديث بيانات الفرع") : Language.get("Branches_Created", alter: "تم إنشاء الفرع بنجاح")
                            self.onSaved?(msg)
                        }
                    }
                }
            }
        } else {
            ref.setData(payload, merge: true) { [weak self] error in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isSaving = false
                    if let error {
                        self.validationError = error.localizedDescription
                        self.showToast(error.localizedDescription, isError: true)
                        let errorHaptic = UINotificationFeedbackGenerator()
                        errorHaptic.notificationOccurred(.error)
                    } else {
                        self.writeSaveAuditLog(branchID: docID, isNew: !self.isEditing)
                        let successHaptic = UINotificationFeedbackGenerator()
                        successHaptic.notificationOccurred(.success)
                        let msg = self.isEditing ? Language.get("Branches_Updated", alter: "تم تحديث بيانات الفرع") : Language.get("Branches_Created", alter: "تم إنشاء الفرع بنجاح")
                        self.onSaved?(msg)
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
            "stockMode": stockMode == .branch ? "branch" : "perAgent",
            "isDefault": isDefault,
            "isActive": isActive,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - iPhone Architecture (`PPBranchEditorPhoneView`)

struct PPBranchEditorPhoneView: View {
    @ObservedObject var state: BranchEditorState
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Sovereign Mobile Header
            phoneHeader

            ScrollView {
                VStack(spacing: AdminSpacing.lg) {
                    // Hero Branch Identity & Telemetry Card
                    BranchHeroIdentityCard(state: state)

                    // Error Banner if present
                    if let err = state.validationError {
                        BranchActionableErrorBanner(message: err)
                    }

                    // Section 1: Official Identity & Codes
                    phoneIdentitySection

                    // Section 2: Location & Direct Connectivity
                    phoneContactSection

                    // Section 3: Inventory Architecture & Supply Topology
                    BranchInventoryTopologyCard(state: state)

                    // Section 4: Operational Governance & Flags
                    BranchOperationalTogglesCard(state: state)

                    // Section 5: Enterprise Compliance & Tax (Expandable)
                    BranchEnterpriseDataCard(state: state)

                    // Section 6: Audit & Telemetry Ledger
                    if state.isEditing {
                        BranchAuditTelemetryCard(state: state)
                    }

                    // Section 7: Administrative Deletion (Danger Zone)
                    if state.isEditing && state.canManage {
                        phoneDangerZone
                    }

                    // Safe padding for bottom dock
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.base)
            }

            // Floating Bottom Action Bar
            phoneBottomDock
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }

    private var phoneHeader: some View {
        HStack(spacing: AdminSpacing.md) {
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AdminType.bodyBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.borderSubtle, lineWidth: 0.8))
            }
            .buttonStyle(BranchPressStyle())
            .accessibilityLabel(Language.get("Cancel", alter: "إلغاء"))

            VStack(alignment: .leading, spacing: 2) {
                Text(state.isEditing ? Language.get("Branches_Edit", alter: "تعديل الفرع") : Language.get("Branches_New", alter: "فرع جديد"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isActive ? AdminSurface.emerald : AdminSurface.amber)
                        .frame(width: 7, height: 7)

                    Text(state.isActive ? Language.get("Branches_Activated", alter: "الفرع نشط") : Language.get("Branches_Deactivated", alter: "الفرع غير نشط"))
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            Spacer()

            // Completion Telemetry Pill
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(AdminType.caption1Bold)
                Text(state.completionPercentageText)
                    .font(AdminType.caption1Bold)
            }
            .foregroundColor(state.completionRatio >= 1.0 ? AdminSurface.emerald : AdminSurface.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((state.completionRatio >= 1.0 ? AdminSurface.emerald : AdminSurface.primary).opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    private var phoneIdentitySection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            BranchSectionHeader(
                title: Language.get("Branches_Info", alter: "الهوية والمسميات الرسمية"),
                icon: "signature"
            )

            AdminCard {
                VStack(spacing: AdminSpacing.md) {
                    BranchInputField(
                        title: Language.get("Branches_Name_Ar", alter: "الاسم (AR)"),
                        placeholder: "مثال: فرع اللؤلؤة - الدوحة",
                        text: $state.nameAr,
                        icon: "character.arabic"
                    )

                    Divider().padding(.horizontal, AdminSpacing.xs)

                    BranchInputField(
                        title: Language.get("Branches_Name_En", alter: "الاسم (EN)"),
                        placeholder: "e.g. The Pearl Branch - Doha",
                        text: $state.nameEn,
                        icon: "textformat"
                    )

                    Divider().padding(.horizontal, AdminSpacing.xs)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Language.get("Branches_Code", alter: "رمز الفرع"))
                                .font(AdminType.caption1Bold)
                                .foregroundColor(AdminSurface.secondaryText)

                            Spacer()

                            Button {
                                state.generateAutoCode()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text(Language.get("Branches_GenerateCode", alter: "توليد تلقائي"))
                                }
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primary)
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "barcode.viewfinder")
                                .foregroundColor(AdminSurface.primary)
                                .font(AdminType.body)

                            TextField("PP-DOH-01", text: $state.code)
                                .font(AdminType.bodyBold)
                                .foregroundColor(AdminSurface.primaryText)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)

                            if !state.code.isEmpty {
                                Button {
                                    state.copyToClipboard(text: state.code, label: Language.get("Branches_CodeCopied", alter: "تم نسخ رمز الفرع"))
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(AdminType.caption1)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                        }
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    }
                }
                .padding(AdminSpacing.cardPadding)
            }
        }
    }

    private var phoneContactSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            BranchSectionHeader(
                title: Language.get("Branches_Contact", alter: "قنوات التواصل والموقع"),
                icon: "mappin.and.ellipse"
            )

            AdminCard {
                VStack(spacing: AdminSpacing.md) {
                    BranchInputField(
                        title: Language.get("Branches_Address", alter: "العنوان الميداني"),
                        placeholder: "مثال: شارع المطار القديم، الدوحة، قطر",
                        text: $state.address,
                        icon: "mappin.circle.fill"
                    )

                    Divider().padding(.horizontal, AdminSpacing.xs)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(Language.get("Branches_Phone", alter: "الهاتف المباشر"))
                            .font(AdminType.caption1Bold)
                            .foregroundColor(AdminSurface.secondaryText)

                        HStack(spacing: 8) {
                            Text("+974")
                                .font(AdminType.bodyBold)
                                .foregroundColor(AdminSurface.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                            TextField("0000 0000", text: $state.phone)
                                .font(AdminType.body)
                                .foregroundColor(AdminSurface.primaryText)
                                .keyboardType(.phonePad)

                            if !state.phone.isEmpty, let phoneUrl = URL(string: "tel://\(state.phone)"), UIApplication.shared.canOpenURL(phoneUrl) {
                                Button {
                                    UIApplication.shared.open(phoneUrl)
                                } label: {
                                    Image(systemName: "phone.fill")
                                        .font(AdminType.caption1)
                                        .foregroundColor(AdminSurface.emerald)
                                }
                            }
                        }
                        .padding(12)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    }
                }
                .padding(AdminSpacing.cardPadding)
            }
        }
    }

    private var phoneDangerZone: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            BranchSectionHeader(
                title: Language.get("Branches_DangerZone", alter: "إجراءات الحذف الإداري"),
                icon: "exclamationmark.triangle.fill",
                tint: Color(uiColor: .ppError)
            )

            AdminCard {
                VStack(alignment: .leading, spacing: 12) {
                    if !state.canDelete {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(Color(uiColor: .ppError))
                                .font(AdminType.subheadline)

                            Text(state.isDefault ? Language.get("Branches_Cannot_Delete_Default", alter: "لا يمكن حذف الفرع الرئيسي الافتراضي للنظام.") : String(format: Language.get("Branches_CannotDeleteAgents", alter: "لا يمكن حذف الفرع لوجود %ld وكيل نشط مرتبط به."), state.agentCount))
                                .font(AdminType.footnote)
                                .foregroundColor(Color(uiColor: .ppError))
                        }
                        .padding(10)
                        .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
                    }

                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        onDelete()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                                .font(AdminType.bodyBold)
                            Text(Language.get("Delete", alter: "حذف الفرع نهائياً"))
                                .font(AdminType.headline)
                        }
                        .foregroundColor(state.canDelete ? Color(uiColor: .ppError) : Color(uiColor: .ppError).opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Color(uiColor: .ppError).opacity(state.canDelete ? 0.10 : 0.04),
                            in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                                .stroke(Color(uiColor: .ppError).opacity(state.canDelete ? 0.25 : 0.10), lineWidth: 1)
                        )
                    }
                    .disabled(!state.canDelete)
                    .buttonStyle(BranchPressStyle())
                }
                .padding(AdminSpacing.cardPadding)
            }
        }
    }

    private var phoneBottomDock: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    onDismiss()
                } label: {
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(maxWidth: 100)
                        .frame(height: 52)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                }
                .buttonStyle(BranchPressStyle())

                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    onSave()
                } label: {
                    HStack(spacing: 8) {
                        if state.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(AdminType.headline)
                        }

                        Text(state.isEditing ? Language.get("Save", alter: "حفظ التحديثات") : Language.get("Branches_New", alter: "إنشاء الفرع"))
                            .font(AdminType.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                    .shadow(color: AdminSurface.primary.opacity(0.24), radius: 8, y: 4)
                }
                .disabled(state.isSaving || !state.canManage)
                .buttonStyle(BranchPressStyle())
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - iPad Architecture (`PPBranchEditorPadView`)

struct PPBranchEditorPadView: View {
    @ObservedObject var state: BranchEditorState
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Sovereign Command Top Bar
            padTopBar

            HStack(spacing: 0) {
                // Leading Column: Master Dossier & Live Telemetry Sidebar (~380pt)
                padLeadingDossier
                    .frame(width: 380)
                    .background(AdminSurface.backgroundSecondary.opacity(0.6))
                    .overlay(Divider(), alignment: .trailing)

                // Trailing Column: Interactive Workdesk
                padTrailingWorkdesk
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }

    private var padTopBar: some View {
        HStack(spacing: 16) {
            Button {
                onDismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                    Text(Language.get("Cancel", alter: "إلغاء"))
                }
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous))
            }
            .buttonStyle(BranchPressStyle())
            .hoverEffect(.highlight)
            .keyboardShortcut(.escape)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(state.isEditing ? Language.get("Branches_Edit", alter: "تعديل الفرع") : Language.get("Branches_New", alter: "إنشاء فرع جديد"))
                        .font(AdminType.title3Bold)
                        .foregroundColor(AdminSurface.primaryText)

                    if state.isDefault {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                            Text(Language.get("Branches_Default", alter: "الرئيسي"))
                        }
                        .font(AdminType.caption2Bold)
                        .foregroundColor(Color(uiColor: .ppWarning))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .ppWarning).opacity(0.15), in: Capsule())
                    }
                }

                Text(state.effectiveDisplayName)
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            // Completion Indicator
            HStack(spacing: 6) {
                Text(Language.get("Branches_Completion", alter: "اكتمال البيانات"))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)

                Text(state.completionPercentageText)
                    .font(AdminType.caption1Bold)
                    .foregroundColor(state.completionRatio >= 1.0 ? AdminSurface.emerald : AdminSurface.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AdminSurface.control, in: Capsule())

            // Primary Save Action
            Button {
                onSave()
            } label: {
                HStack(spacing: 8) {
                    if state.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(AdminType.subheadlineBold)
                    }

                    Text(state.isEditing ? Language.get("Branches_SaveChanges", alter: "حفظ التغييرات (⌘S)") : Language.get("Branches_New", alter: "إنشاء الفرع (⌘S)"))
                        .font(AdminType.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                .shadow(color: AdminSurface.primary.opacity(0.20), radius: 6, y: 3)
            }
            .disabled(state.isSaving || !state.canManage)
            .buttonStyle(BranchPressStyle())
            .hoverEffect(.lift)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    private var padLeadingDossier: some View {
        ScrollView {
            VStack(spacing: AdminSpacing.lg) {
                // Emblem & Realtime Identity
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 88, height: 88)

                        Image(systemName: state.isDefault ? "building.columns.fill" : "building.2.crop.circle.fill")
                            .font(AdminType.largeTitle)
                            .foregroundColor(AdminSurface.primary)
                    }

                    VStack(spacing: 4) {
                        Text(state.effectiveDisplayName)
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.primaryText)
                            .multilineTextAlignment(.center)

                        Text(state.effectiveSubtitle)
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    // Status & Flagship Pills
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(state.isActive ? AdminSurface.emerald : AdminSurface.amber)
                                .frame(width: 8, height: 8)
                            Text(state.isActive ? Language.get("Active", alter: "نشط") : Language.get("Branches_Filter_Inactive", alter: "غير نشط"))
                                .font(AdminType.caption1Bold)
                                .foregroundColor(state.isActive ? AdminSurface.emerald : AdminSurface.amber)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background((state.isActive ? AdminSurface.emerald : AdminSurface.amber).opacity(0.12), in: Capsule())

                        Text(state.stockMode == .branch ? Language.get("Branches_Stock_Shared", alter: "مخزون موحد") : Language.get("Branches_Stock_Separate", alter: "مخزون وكيل"))
                            .font(AdminType.caption1Bold)
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    }
                }
                .padding(AdminSpacing.cardPadding)
                .frame(maxWidth: .infinity)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))

                // Telemetry & Metrics HUD Card
                VStack(alignment: .leading, spacing: 12) {
                    Text(Language.get("Branches_LiveTelemtry", alter: "المؤشرات الميدانية"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.primaryText)

                    VStack(spacing: 10) {
                        HStack {
                            Label(Language.get("Branches_Agents", alter: "الكوادر المعتمدة"), systemImage: "person.2.fill")
                                .font(AdminType.footnote)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(String(format: Language.get("Staff_Branches_Count", alter: "%d كوادر"), state.agentCount))
                                .font(AdminType.footnoteBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }

                        Divider()

                        HStack {
                            Label(Language.get("Branches_Code", alter: "رمز الفرع"), systemImage: "qrcode")
                                .font(AdminType.footnote)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(state.code.isEmpty ? "—" : state.code)
                                .font(AdminType.footnoteBold)
                                .foregroundColor(AdminSurface.primary)
                        }

                        Divider()

                        HStack {
                            Label(Language.get("Branches_Phone", alter: "الهاتف المباشر"), systemImage: "phone.fill")
                                .font(AdminType.footnote)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(state.phone.isEmpty ? "—" : state.phone)
                                .font(AdminType.footnoteBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }
                    }
                    .padding(14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                }
                .padding(AdminSpacing.cardPadding)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))

                // System Governance & Audit Card
                if state.isEditing {
                    BranchAuditTelemetryCard(state: state)
                }

                // Destructive Danger Drawer
                if state.isEditing && state.canManage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("Branches_DangerZone", alter: "إجراءات الحذف الإداري"))
                            .font(AdminType.caption1Bold)
                            .foregroundColor(Color(uiColor: .ppError))

                        Button {
                            onDelete()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                Text(Language.get("Delete", alter: "حذف هذا الفرع"))
                            }
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(state.canDelete ? Color(uiColor: .ppError) : Color(uiColor: .ppError).opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                Color(uiColor: .ppError).opacity(state.canDelete ? 0.12 : 0.04),
                                in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                            )
                        }
                        .disabled(!state.canDelete)
                        .buttonStyle(BranchPressStyle())
                        .hoverEffect(.highlight)

                        if !state.canDelete {
                            Text(state.isDefault ? Language.get("Branches_Cannot_Delete_Default", alter: "لا يمكن حذف الفرع الرئيسي الافتراضي للنظام.") : String(format: Language.get("Branches_CannotDeleteAgents", alter: "لا يمكن حذف الفرع لوجود %ld وكيل نشط."), state.agentCount))
                                .font(AdminType.caption2)
                                .foregroundColor(Color(uiColor: .ppError))
                        }
                    }
                    .padding(AdminSpacing.cardPadding)
                    .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                }
            }
            .padding(AdminSpacing.cardPadding)
        }
    }

    private var padTrailingWorkdesk: some View {
        ScrollView {
            VStack(spacing: AdminSpacing.lg) {
                if let err = state.validationError {
                    BranchActionableErrorBanner(message: err)
                }

                // Identity Section
                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    BranchSectionHeader(
                        title: Language.get("Branches_Info", alter: "الهوية والمسميات الرسمية"),
                        icon: "character.book.closed.fill"
                    )

                    AdminCard {
                        VStack(spacing: AdminSpacing.md) {
                            HStack(spacing: 16) {
                                BranchInputField(
                                    title: Language.get("Branches_Name_Ar", alter: "الاسم (AR)"),
                                    placeholder: "اسم الفرع بالعربية",
                                    text: $state.nameAr,
                                    icon: "character.arabic"
                                )

                                BranchInputField(
                                    title: Language.get("Branches_Name_En", alter: "الاسم (EN)"),
                                    placeholder: "Branch Name in English",
                                    text: $state.nameEn,
                                    icon: "textformat"
                                )
                            }

                            Divider()

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(Language.get("Branches_Code", alter: "رمز الفرع"))
                                            .font(AdminType.caption1Bold)
                                            .foregroundColor(AdminSurface.secondaryText)
                                        Spacer()
                                        Button {
                                            state.generateAutoCode()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "sparkles")
                                                Text(Language.get("Branches_GenerateCode", alter: "توليد تلقائي"))
                                            }
                                            .font(AdminType.caption2Bold)
                                            .foregroundColor(AdminSurface.primary)
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Image(systemName: "barcode")
                                            .foregroundColor(AdminSurface.primary)
                                        TextField("PP-DOH-01", text: $state.code)
                                            .font(AdminType.bodyBold)
                                            .foregroundColor(AdminSurface.primaryText)
                                    }
                                    .padding(12)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                                }

                                BranchInputField(
                                    title: Language.get("Branches_Phone", alter: "الهاتف المباشر"),
                                    placeholder: "+974 0000 0000",
                                    text: $state.phone,
                                    icon: "phone.fill",
                                    keyboard: .phonePad
                                )
                            }

                            Divider()

                            BranchInputField(
                                title: Language.get("Branches_Address", alter: "العنوان الجغرافي المعتمد"),
                                placeholder: "الدوحة، قطر",
                                text: $state.address,
                                icon: "mappin.circle.fill"
                            )
                        }
                        .padding(AdminSpacing.cardPadding)
                    }
                }

                // Inventory Architecture
                BranchInventoryTopologyCard(state: state)

                // Governance Toggles
                BranchOperationalTogglesCard(state: state)

                // Enterprise Compliance
                BranchEnterpriseDataCard(state: state)

                Spacer().frame(height: 40)
            }
            .padding(AdminSpacing.lg)
        }
    }
}

// MARK: - Shared High-Craft Visual Components

struct BranchHeroIdentityCard: View {
    @ObservedObject var state: BranchEditorState

    var body: some View {
        AdminCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: AdminSurface.primary.opacity(0.24), radius: 8, y: 4)

                    Image(systemName: state.isDefault ? "building.columns.fill" : "building.2.fill")
                        .font(AdminType.title3Bold)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(state.effectiveDisplayName)
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        if state.isDefault {
                            Image(systemName: "crown.fill")
                                .font(AdminType.caption1)
                                .foregroundColor(Color(uiColor: .ppWarning))
                        }
                    }

                    Text(state.effectiveSubtitle)
                        .font(AdminType.footnote)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isActive ? AdminSurface.emerald : AdminSurface.amber)
                            .frame(width: 7, height: 7)

                        Text(state.isActive ? Language.get("Active", alter: "نشط") : Language.get("Branches_Filter_Inactive", alter: "غير نشط"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(state.isActive ? AdminSurface.emerald : AdminSurface.amber)

                        Text("•")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)

                        Text(state.stockMode == .branch ? Language.get("Branches_Stock_Shared", alter: "مخزون موحد") : Language.get("Branches_Stock_Separate", alter: "مخزون وكيل"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primary)
                    }
                }

                Spacer()
            }
            .padding(AdminSpacing.cardPadding)
        }
    }
}

struct BranchInventoryTopologyCard: View {
    @ObservedObject var state: BranchEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            BranchSectionHeader(
                title: Language.get("Branches_Stock_Mode", alter: "معمارية المخزون وسلسلة التوريد"),
                icon: "cube.transparent.fill"
            )

            AdminCard {
                VStack(spacing: 12) {
                    // Option A: Per-Agent Stock
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        state.stockMode = .perAgent
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                                    .fill(state.stockMode == .perAgent ? AdminSurface.primary.opacity(0.12) : AdminSurface.control)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "person.crop.circle.badge.fill")
                                    .font(AdminType.headline)
                                    .foregroundColor(state.stockMode == .perAgent ? AdminSurface.primary : AdminSurface.secondaryText)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(Language.get("Branches_Stock_Separate", alter: "مخزون الوكيل المستقل"))
                                        .font(AdminType.bodyBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                    Spacer()
                                    if state.stockMode == .perAgent {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(AdminType.headline)
                                            .foregroundColor(AdminSurface.primary)
                                    }
                                }

                                Text(Language.get("Branches_PerAgentDesc", alter: "كل وكيل يدير مخزونه وحقائبه بشكل مستقل داخل نطاق الفرع"))
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(12)
                        .background(
                            state.stockMode == .perAgent ? AdminSurface.primary.opacity(0.04) : Color.clear,
                            in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                .stroke(state.stockMode == .perAgent ? AdminSurface.primary : AdminSurface.borderSubtle, lineWidth: state.stockMode == .perAgent ? 1.5 : 0.8)
                        )
                    }
                    .buttonStyle(BranchPressStyle())

                    // Option B: Shared Warehouse Stock
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        state.stockMode = .branch
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: AdminRadius.small, style: .continuous)
                                    .fill(state.stockMode == .branch ? AdminSurface.primary.opacity(0.12) : AdminSurface.control)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "shippingbox.fill")
                                    .font(AdminType.headline)
                                    .foregroundColor(state.stockMode == .branch ? AdminSurface.primary : AdminSurface.secondaryText)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(Language.get("Branches_Stock_Shared", alter: "مخزون الفرع الموحد"))
                                        .font(AdminType.bodyBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                    Spacer()
                                    if state.stockMode == .branch {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(AdminType.headline)
                                            .foregroundColor(AdminSurface.primary)
                                    }
                                }

                                Text(Language.get("Branches_SharedDesc", alter: "مستودع مركزي مشترك يوزع البضائع على جميع كوادر ومندوبي الفرع"))
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(12)
                        .background(
                            state.stockMode == .branch ? AdminSurface.primary.opacity(0.04) : Color.clear,
                            in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                                .stroke(state.stockMode == .branch ? AdminSurface.primary : AdminSurface.borderSubtle, lineWidth: state.stockMode == .branch ? 1.5 : 0.8)
                        )
                    }
                    .buttonStyle(BranchPressStyle())
                }
                .padding(AdminSpacing.cardPadding)
            }
        }
    }
}

struct BranchOperationalTogglesCard: View {
    @ObservedObject var state: BranchEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            BranchSectionHeader(
                title: Language.get("Branches_Settings", alter: "حوكمة النظام والسيادة التشغيلية"),
                icon: "slider.horizontal.3"
            )

            AdminCard {
                VStack(spacing: 16) {
                    // Active Toggle
                    Toggle(isOn: $state.isActive) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Language.get("Active", alter: "تفعيل تشغيل الفرع"))
                                .font(AdminType.bodyBold)
                                .foregroundColor(AdminSurface.primaryText)

                            Text(state.isActive ? Language.get("Branches_Activated", alter: "الفرع نشط ومتاح لتعيين الطلبات والمخزون") : Language.get("Branches_Deactivated", alter: "الفرع معطل مؤقتاً ومخفي عن العمليات"))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .tint(AdminSurface.primary)

                    Divider()

                    // Default Flagship Toggle
                    Toggle(isOn: $state.isDefault) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color(uiColor: .ppWarning).opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "crown.fill")
                                    .font(AdminType.caption1)
                                    .foregroundColor(Color(uiColor: .ppWarning))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(Language.get("Branches_Default_Label", alter: "تعيين كفرع رئيسي افتراضي"))
                                    .font(AdminType.bodyBold)
                                    .foregroundColor(AdminSurface.primaryText)

                                Text(Language.get("Branches_FlagshipBadge", alter: "الفرع الرئيسي المعتمد لدولة قطر في العمليات"))
                                    .font(AdminType.caption1)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }
                    }
                    .tint(Color(uiColor: .ppWarning))
                }
                .padding(AdminSpacing.cardPadding)
            }
        }
    }
}

struct BranchEnterpriseDataCard: View {
    @ObservedObject var state: BranchEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack {
                BranchSectionHeader(
                    title: Language.get("Branches_EnterpriseSection", alter: "بيانات الامتثال والسجل التجاري"),
                    icon: "doc.text.badge.plus"
                )

                Spacer()

                Button {
                    withAnimation(AdminAnimation.standard) {
                        state.showEnterpriseFields.toggle()
                    }
                } label: {
                    Image(systemName: state.showEnterpriseFields ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            if state.showEnterpriseFields {
                AdminCard {
                    VStack(spacing: AdminSpacing.md) {
                        BranchInputField(
                            title: Language.get("Branches_CRNumber", alter: "السجل التجاري (CR)"),
                            placeholder: "مثال: 12345/6",
                            text: $state.crNumber,
                            icon: "building.2.crop.circle"
                        )

                        Divider()

                        BranchInputField(
                            title: Language.get("Branches_TaxNumber", alter: "الرقم الضريبي (TIN)"),
                            placeholder: "مثال: QA-TAX-98765",
                            text: $state.taxNumber,
                            icon: "percent"
                        )

                        Divider()

                        BranchInputField(
                            title: Language.get("Branches_OperatingHours", alter: "ساعات العمل التشغيلية"),
                            placeholder: "مثال: 08:00 AM - 10:00 PM",
                            text: $state.operatingHours,
                            icon: "clock.fill"
                        )
                    }
                    .padding(AdminSpacing.cardPadding)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct BranchAuditTelemetryCard: View {
    @ObservedObject var state: BranchEditorState

    private func formatDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            BranchSectionHeader(
                title: Language.get("Branches_AuditSection", alter: "سجل الحوكمة والتدقيق"),
                icon: "shield.checkered"
            )

            AdminCard {
                VStack(spacing: 10) {
                    if let docID = state.originalBranch?.branchID, !docID.isEmpty {
                        HStack {
                            Text(Language.get("Branches_DocID", alter: "معرّف الوثيقة"))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(docID)
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primary)
                                .lineLimit(1)

                            Button {
                                state.copyToClipboard(text: docID, label: Language.get("Copied", alter: "تم النسخ"))
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }
                        Divider()
                    }

                    HStack {
                        Text(Language.get("Branches_CreatedAt", alter: "تاريخ الإنشاء"))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                        Text(formatDate(state.originalBranch?.createdAt))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.primaryText)
                    }

                    Divider()

                    HStack {
                        Text(Language.get("Branches_UpdatedAt", alter: "آخر تحديث"))
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                        Text(formatDate(state.originalBranch?.updatedAt))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.primaryText)
                    }

                    if let createdBy = state.originalBranch?.createdBy, !createdBy.isEmpty {
                        Divider()
                        HStack {
                            Text(Language.get("Branches_CreatedBy", alter: "أنشئ بواسطة"))
                                .font(AdminType.caption1)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(createdBy)
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(AdminSpacing.cardPadding)
            }
        }
    }
}

struct BranchInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AdminType.caption1Bold)
                .foregroundColor(AdminSurface.secondaryText)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 20)

                TextField(placeholder, text: $text)
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)
                    .keyboardType(keyboard)
                    .disableAutocorrection(true)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        }
    }
}

struct BranchSectionHeader: View {
    let title: String
    let icon: String
    var tint: Color = AdminSurface.primary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AdminType.caption1Bold)
                .foregroundColor(tint)
            Text(title)
                .font(AdminType.caption1Bold)
                .foregroundColor(AdminSurface.primaryText)
        }
    }
}

struct BranchActionableErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundColor(Color(uiColor: .ppError))
                .font(AdminType.headline)

            Text(message)
                .font(AdminType.footnoteBold)
                .foregroundColor(Color(uiColor: .ppError))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                .stroke(Color(uiColor: .ppError).opacity(0.25), lineWidth: 1)
        )
    }
}

struct BranchToastBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? Color(uiColor: .ppError) : AdminSurface.emerald)
                .font(AdminType.headline)

            Text(message)
                .font(AdminType.footnoteBold)
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isError ? Color(uiColor: .ppError).opacity(0.3) : AdminSurface.emerald.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

struct BranchPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : AdminAnimation.fast, value: configuration.isPressed)
    }
}
