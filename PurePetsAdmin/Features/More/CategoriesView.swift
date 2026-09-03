//
//  CategoriesView.swift
//  PurePetsAdmin
//
//  NextGen V6 Native SwiftUI Animal Categories & Taxonomy Studio.
//  Reimagined from first principles with a bespoke Dossier Navigation Bar,
//  Taxonomy Intelligence Pulse, Spatial Species Cards, Hierarchical Tree Inspector,
//  In-Place Storefront Toggles, Batch Reordering, and a Live Storefront Preview Editor.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

struct AdminCategoryItem: Identifiable, Equatable, Sendable {
    var id: String { documentID.isEmpty ? "\(numericID)" : documentID }
    var documentID: String
    var numericID: Int
    var sortingKey: Int
    var nameAr: String
    var nameEn: String
    var iconName: String
    var imageName: String
    var imageUrl: String
    var lightenAmount: Double
    var professionalAngle: Double
    var isVisible: Bool
    var subKinds: [AdminSubKindItem]
    var colorHex: String

    var localizedName: String {
        if Language.isRTL() {
            return !nameAr.isEmpty ? nameAr : nameEn
        } else {
            return !nameEn.isEmpty ? nameEn : nameAr
        }
    }

    var secondaryName: String {
        if Language.isRTL() {
            return !nameEn.isEmpty ? nameEn : ""
        } else {
            return !nameAr.isEmpty ? nameAr : ""
        }
    }

    var accentColor: Color {
        if !colorHex.isEmpty {
            return Color(hex: colorHex)
        }
        // Palette cycle based on numeric ID
        let palette: [Color] = [
            Color(red: 0.94, green: 0.44, blue: 0.28), // Coral orange
            Color(red: 0.25, green: 0.65, blue: 0.85), // Cyan azure
            Color(red: 0.48, green: 0.78, blue: 0.35), // Emerald green
            Color(red: 0.88, green: 0.62, blue: 0.22), // Golden amber
            Color(red: 0.60, green: 0.45, blue: 0.88), // Royal violet
            Color(red: 0.92, green: 0.38, blue: 0.55), // Rose ruby
            Color(red: 0.30, green: 0.75, blue: 0.65), // Teal mint
            Color(red: 0.75, green: 0.50, blue: 0.35)  // Desert sand
        ]
        let idx = abs(numericID) % palette.count
        return palette[idx]
    }

    static func fromSnapshot(_ doc: DocumentSnapshot) -> AdminCategoryItem? {
        guard let data = doc.data() else { return nil }
        return fromDictionary(data, documentID: doc.documentID)
    }

    static func fromDictionary(_ data: [String: Any], documentID: String) -> AdminCategoryItem {
        let numID = (data["ID"] as? NSNumber)?.intValue ?? 0
        let sortKey = (data["sortingKey"] as? NSNumber)?.intValue ?? numID
        let ar = data["KindNameAr"] as? String ?? ""
        let en = data["KindNameEn"] as? String ?? (data["KindName"] as? String ?? "")
        let icon = data["KindIconName"] as? String ?? ""
        let imgName = data["KindImageNamed"] as? String ?? ""
        let imgUrl = data["KindImageUrl"] as? String ?? ""
        let lighten = (data["LightenAmount"] as? NSNumber)?.doubleValue ?? 0.0
        let angle = (data["professionalAngle"] as? NSNumber)?.doubleValue ?? 0.0
        let visible = (data["is_visible_in_user_app"] as? Bool) ?? true
        let petColor = data["PetColor"] as? String ?? ""

        var subKinds: [AdminSubKindItem] = []
        if let rawSub = data["SubKindsArray"] as? [[String: Any]] {
            subKinds = rawSub.compactMap { AdminSubKindItem.fromDictionary($0) }
        }

        return AdminCategoryItem(
            documentID: documentID,
            numericID: numID,
            sortingKey: sortKey,
            nameAr: ar,
            nameEn: en,
            iconName: icon,
            imageName: imgName,
            imageUrl: imgUrl,
            lightenAmount: lighten,
            professionalAngle: angle,
            isVisible: visible,
            subKinds: subKinds,
            colorHex: petColor
        )
    }

    func toFirestoreDictionary() -> [String: Any] {
        return [
            "ID": numericID,
            "sortingKey": sortingKey,
            "KindNameAr": nameAr,
            "KindNameEn": nameEn,
            "KindName": !nameEn.isEmpty ? nameEn : nameAr,
            "KindIconName": iconName,
            "KindImageNamed": imageName,
            "KindImageUrl": imageUrl,
            "LightenAmount": lightenAmount,
            "professionalAngle": professionalAngle,
            "is_visible_in_user_app": isVisible,
            "PetColor": colorHex,
            "SubKindsArray": subKinds.map { $0.toDictionary() }
        ]
    }
}

struct AdminSubKindItem: Identifiable, Equatable, Sendable {
    var id: String
    var numericID: Int
    var mainKindID: Int
    var nameAr: String
    var nameEn: String
    var iconUrl: String
    var imageName: String
    var adultHood: Int
    var haveSubSub: Int
    var haveItems: Int

    var localizedName: String {
        if Language.isRTL() {
            return !nameAr.isEmpty ? nameAr : nameEn
        } else {
            return !nameEn.isEmpty ? nameEn : nameAr
        }
    }

    var secondaryName: String {
        if Language.isRTL() {
            return !nameEn.isEmpty ? nameEn : ""
        } else {
            return !nameAr.isEmpty ? nameAr : ""
        }
    }

    static func fromDictionary(_ dict: [String: Any]) -> AdminSubKindItem {
        let numID = (dict["ID"] as? NSNumber)?.intValue ?? 0
        let mainID = (dict["MainKindID"] as? NSNumber)?.intValue ?? 0
        let ar = dict["SubKindNameAr"] as? String ?? ""
        let en = dict["SubKindNameEn"] as? String ?? ""
        let iconUrl = dict["subKindIconUrl"] as? String ?? (dict["SubKindIconUrl"] as? String ?? "")
        let imgName = dict["SubKindImageName"] as? String ?? ""
        let adult = (dict["adultHood"] as? NSNumber)?.intValue ?? 0
        let subSub = (dict["have_subSub"] as? NSNumber)?.intValue ?? 0
        let items = (dict["have_items"] as? NSNumber)?.intValue ?? 0

        return AdminSubKindItem(
            id: "\(mainID)_\(numID)_\(UUID().uuidString.prefix(6))",
            numericID: numID,
            mainKindID: mainID,
            nameAr: ar,
            nameEn: en,
            iconUrl: iconUrl,
            imageName: imgName,
            adultHood: adult,
            haveSubSub: subSub,
            haveItems: items
        )
    }

    func toDictionary() -> [String: Any] {
        return [
            "ID": numericID,
            "MainKindID": mainKindID,
            "SubKindNameAr": nameAr,
            "SubKindNameEn": nameEn,
            "subKindIconUrl": iconUrl,
            "SubKindImageName": imageName,
            "adultHood": adultHood,
            "have_subSub": haveSubSub,
            "have_items": haveItems
        ]
    }
}

// MARK: - Enums

enum CategoryFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case visible = "visible"
    case hidden = "hidden"
    case withSubKinds = "with_sub_kinds"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return Language.get("Categories_Filter_All", alter: "الكل")
        case .visible: return Language.get("Categories_Filter_Visible", alter: "ظاهر بالمتجر")
        case .hidden: return Language.get("Categories_Filter_Hidden", alter: "مخفي")
        case .withSubKinds: return Language.get("Categories_Filter_WithSubKinds", alter: "مع سلالات")
        }
    }
}

enum CategoryViewMode: String, CaseIterable, Identifiable {
    case cards = "cards"
    case tree = "tree"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return Language.get("Categories_ViewMode_Cards", alter: "بطاقات")
        case .tree: return Language.get("Categories_ViewMode_Tree", alter: "شجرة التصنيف")
        }
    }

    var icon: String {
        switch self {
        case .cards: return "square.grid.2x2.fill"
        case .tree: return "list.bullet.indent"
        }
    }
}

// MARK: - Color Hex Extension Helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Model

@MainActor
final class AdminCategoriesViewModel: ObservableObject {
    @Published private(set) var categories: [AdminCategoryItem] = []
    @Published private(set) var filteredCategories: [AdminCategoryItem] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: CategoryFilter = .all
    @Published var viewMode: CategoryViewMode = .cards
    @Published var isReorderMode: Bool = false
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var errorMessage: String? = nil
    @Published private(set) var canManage: Bool = false
    @Published var toastMessage: String? = nil
    @Published var isErrorToast: Bool = false

    private nonisolated(unsafe) var listener: (any ListenerRegistration)?

    var totalCount: Int { categories.count }
    var visibleCount: Int { categories.filter { $0.isVisible }.count }
    var hiddenCount: Int { categories.filter { !$0.isVisible }.count }
    var totalBreedsCount: Int { categories.reduce(0) { $0 + $1.subKinds.count } }

    init() {
        evaluatePermissions()
    }

    deinit {
        listener?.remove()
    }

    func evaluatePermissions() {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        let hasManage = staff?.hasPermission(kStaffPermCategoriesManage) ?? false
        self.canManage = hasManage
    }

    func startListening() {
        evaluatePermissions()
        isLoading = true
        errorMessage = nil

        let query = Firestore.firestore().collection("MainKindsCollection").order(by: "sortingKey", descending: false)
        listener = query.addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self.categories = docs.compactMap { AdminCategoryItem.fromSnapshot($0) }
                self.applyFilter()
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var list = categories

        switch selectedFilter {
        case .all:
            break
        case .visible:
            list = list.filter { $0.isVisible }
        case .hidden:
            list = list.filter { !$0.isVisible }
        case .withSubKinds:
            list = list.filter { !$0.subKinds.isEmpty }
        }

        if !query.isEmpty {
            list = list.filter { item in
                item.nameAr.contains(query) ||
                item.nameEn.lowercased().contains(query) ||
                "\(item.numericID)".contains(query) ||
                item.documentID.lowercased().contains(query) ||
                item.subKinds.contains { sub in
                    sub.nameAr.contains(query) || sub.nameEn.lowercased().contains(query)
                }
            }
        }

        filteredCategories = list
    }

    func showToast(_ message: String, isError: Bool = false) {
        toastMessage = message
        isErrorToast = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    // MARK: - Actions

    func toggleVisibility(for item: AdminCategoryItem) {
        guard canManage else { return }
        let newVisible = !item.isVisible
        let docID = item.documentID.isEmpty ? "\(item.numericID)" : item.documentID
        let itemID = item.id

        // Optimistic UI update
        if let idx = categories.firstIndex(where: { $0.id == itemID }) {
            categories[idx].isVisible = newVisible
            applyFilter()
        }

        let ref = Firestore.firestore().collection("MainKindsCollection").document(docID)
        ref.updateData([
            "is_visible_in_user_app": newVisible
        ]) { [weak self] error in
            Task { @MainActor in
                if let error {
                    // Rollback
                    if let idx = self?.categories.firstIndex(where: { $0.id == itemID }) {
                        self?.categories[idx].isVisible = !newVisible
                        self?.applyFilter()
                    }
                    self?.showToast(error.localizedDescription, isError: true)
                } else {
                    let msg = newVisible
                        ? Language.get("Categories_Toggled_Visible", alter: "تم تفعيل ظهور التصنيف للمستخدمين")
                        : Language.get("Categories_Toggled_Hidden", alter: "تم إخفاء التصنيف من واجهة المستخدمين")
                    self?.showToast(msg)
                    self?.writeAuditLog(action: "toggle_category_visibility", targetID: docID, before: ["visible": !newVisible], after: ["visible": newVisible])
                }
            }
        }
    }

    func moveCategory(from source: IndexSet, to destination: Int) {
        var reordered = filteredCategories
        reordered.move(fromOffsets: source, toOffset: destination)
        filteredCategories = reordered

        // Reassign sorting keys
        let batch = Firestore.firestore().batch()
        for (index, item) in reordered.enumerated() {
            let docID = item.documentID.isEmpty ? "\(item.numericID)" : item.documentID
            let ref = Firestore.firestore().collection("MainKindsCollection").document(docID)
            batch.updateData(["sortingKey": index + 1], forDocument: ref)
        }

        let count = reordered.count
        batch.commit { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.showToast(error.localizedDescription, isError: true)
                } else {
                    self?.showToast(Language.get("Categories_Reordered_Success", alter: "تم حفظ الترتيب الجديد للفئات بنجاح"))
                    self?.writeAuditLog(action: "reorder_categories", targetID: "batch", before: nil, after: ["count": count])
                }
            }
        }
    }

    func deleteCategory(_ item: AdminCategoryItem, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية الحذف"))
            return
        }
        let docID = item.documentID.isEmpty ? "\(item.numericID)" : item.documentID
        let nameAr = item.nameAr
        let nameEn = item.nameEn

        Firestore.firestore().collection("MainKindsCollection").document(docID).delete { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.writeAuditLog(action: "delete_category", targetID: docID, before: ["nameAr": nameAr, "nameEn": nameEn], after: nil)
                    completion(true, Language.get("Category_Deleted", alter: "تم حذف التصنيف بنجاح"))
                }
            }
        }
    }

    func saveCategory(_ item: AdminCategoryItem, isNew: Bool, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية التعديل"))
            return
        }

        let docID = item.documentID.isEmpty ? "\(item.numericID)" : item.documentID
        guard !docID.isEmpty, item.numericID > 0 else {
            completion(false, Language.get("Category_Error_ID", alter: "يرجى إدخال معرف تصنيف صالح"))
            return
        }

        let payload = item.toFirestoreDictionary()
        let ref = Firestore.firestore().collection("MainKindsCollection").document(docID)
        let action = isNew ? "create_category" : "update_category"
        let numID = item.numericID
        let nameAr = item.nameAr
        let nameEn = item.nameEn

        ref.setData(payload, merge: true) { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.writeAuditLog(action: action, targetID: docID, before: nil, after: ["numericID": numID, "nameAr": nameAr, "nameEn": nameEn])
                    completion(true, Language.get("Category_Saved", alter: "تم حفظ التصنيف بنجاح."))
                }
            }
        }
    }

    private func writeAuditLog(action: String, targetID: String, before: [String: Any]?, after: [String: Any]?) {
        let uid = Auth.auth().currentUser?.uid ?? ""
        var payload: [String: Any] = [
            "action": action,
            "targetCollection": "MainKindsCollection",
            "targetId": targetID,
            "adminUid": uid,
            "timestamp": FieldValue.serverTimestamp()
        ]
        if let before { payload["before"] = before }
        if let after { payload["after"] = after }

        Firestore.firestore().collection("AdminAuditLogs").document().setData(payload)
    }
}

// MARK: - Main Categories View

@MainActor
struct AdminCategoriesView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminCategoriesViewModel()
    @State private var editingCategory: AdminCategoryItem? = nil
    @State private var isCreatingCategory: Bool = false
    @State private var categoryToDelete: AdminCategoryItem? = nil
    @State private var expandedCategoryIDs: Set<String> = []

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Dossier Navigation Bar
                dossierHeaderView

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        // Live Telemetry Pulse Header
                        telemetryPulseSection

                        // Search & Discovery Bar
                        searchAndFilterSection

                        // Category Canvas
                        categoryCanvasContent
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.xs)
                    .padding(.bottom, AdminSpacing.xxl)
                }
                .refreshable {
                    viewModel.startListening()
                }
            }

            // Toast Alert Overlay
            if let message = viewModel.toastMessage {
                VStack {
                    Spacer()
                    toastBanner(message: message, isError: viewModel.isErrorToast)
                        .padding(.horizontal, AdminSpacing.screenMargin)
                        .padding(.bottom, AdminSpacing.lg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(AdminAnimation.standard, value: viewModel.toastMessage)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $editingCategory) { cat in
            AdminCategoryEditorSheet(
                category: cat,
                isNew: false,
                onSave: { updated in
                    viewModel.saveCategory(updated, isNew: false) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            editingCategory = nil
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                },
                onDelete: {
                    categoryToDelete = cat
                    editingCategory = nil
                }
            )
        }
        .sheet(isPresented: $isCreatingCategory) {
            let nextID = (viewModel.categories.map { $0.numericID }.max() ?? 0) + 1
            let draft = AdminCategoryItem(
                documentID: "\(nextID)",
                numericID: nextID,
                sortingKey: nextID,
                nameAr: "",
                nameEn: "",
                iconName: "pawprint.fill",
                imageName: "",
                imageUrl: "",
                lightenAmount: 0.25,
                professionalAngle: 0.0,
                isVisible: true,
                subKinds: [],
                colorHex: ""
            )
            AdminCategoryEditorSheet(
                category: draft,
                isNew: true,
                onSave: { newCat in
                    viewModel.saveCategory(newCat, isNew: true) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            isCreatingCategory = false
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                },
                onDelete: nil
            )
        }
        .confirmationDialog(
            Language.get("Categories_Delete_Confirm_Title", alter: "تأكيد حذف التصنيف"),
            isPresented: Binding(get: { categoryToDelete != nil }, set: { if !$0 { categoryToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let cat = categoryToDelete {
                Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                    viewModel.deleteCategory(cat) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                        categoryToDelete = nil
                    }
                }
                Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                    categoryToDelete = nil
                }
            }
        } message: {
            if let cat = categoryToDelete {
                Text(String(format: Language.get("Categories_Delete_Confirm_Body", alter: "هل أنت متأكد من حذف تصنيف \"%@\" نهائياً؟"), cat.localizedName))
            }
        }
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
    }

    // MARK: - Bespoke Dossier Navigation Bar

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Categories_Title", alter: "تصنيفات الحيوانات"),
            subtitle: "\(viewModel.totalCount) " + Language.get("Categories_Total_Sub", alter: "تصنيف"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                // View Mode Switcher
                Menu {
                    ForEach(CategoryViewMode.allCases) { mode in
                        Button {
                            withAnimation(AdminAnimation.standard) {
                                viewModel.viewMode = mode
                            }
                        } label: {
                            Label(mode.title, systemImage: mode.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: viewModel.viewMode.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(viewModel.viewMode.title)
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )
                }

                // Reorder Mode Toggle
                if viewModel.canManage {
                    Button {
                        withAnimation(AdminAnimation.standard) {
                            viewModel.isReorderMode.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.isReorderMode ? "checkmark" : "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(viewModel.isReorderMode ? .white : AdminSurface.primaryText)
                            .frame(width: 38, height: 38)
                            .background(viewModel.isReorderMode ? AdminSurface.primary : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                    }
                    .accessibilityLabel(Language.get("Categories_Reorder_Mode", alter: "إعادة الترتيب"))
                }

                // Add Category Pill Button
                if viewModel.canManage {
                    AdminPrimaryPillButton(
                        title: Language.get("Category_New", alter: "تصنيف جديد"),
                        systemImage: "plus"
                    ) {
                        isCreatingCategory = true
                    }
                }
            }
        }
    }

    // MARK: - Telemetry Pulse Section

    private var telemetryPulseSection: some View {
        VStack(spacing: AdminSpacing.md) {
            // Metrics 4-Card Grid
            HStack(spacing: AdminSpacing.sm) {
                telemetryCard(
                    title: Language.get("Categories_Pulse_Total", alter: "إجمالي الفئات"),
                    value: "\(viewModel.totalCount)",
                    symbol: "pawprint.fill",
                    tint: AdminSurface.primary
                )
                telemetryCard(
                    title: Language.get("Categories_Pulse_Visible", alter: "نشط بالمتجر"),
                    value: "\(viewModel.visibleCount)",
                    symbol: "eye.fill",
                    tint: .green
                )
                telemetryCard(
                    title: Language.get("Categories_Pulse_Hidden", alter: "مخفي"),
                    value: "\(viewModel.hiddenCount)",
                    symbol: "eye.slash.fill",
                    tint: .orange
                )
                telemetryCard(
                    title: Language.get("Categories_Pulse_Breeds", alter: "إجمالي السلالات"),
                    value: "\(viewModel.totalBreedsCount)",
                    symbol: "point.3.connected.trianglepath.dotted",
                    tint: .blue
                )
            }

            // Interactive Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.xs) {
                    ForEach(CategoryFilter.allCases) { filter in
                        let isSelected = viewModel.selectedFilter == filter
                        Button {
                            withAnimation(AdminAnimation.fast) {
                                viewModel.selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(filter.title)
                                    .font(AdminType.captionBold)
                                if filter == .visible {
                                    Text("\(viewModel.visibleCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(isSelected ? Color.white.opacity(0.25) : AdminSurface.primary.opacity(0.12), in: Capsule())
                                }
                            }
                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? AdminSurface.primary : AdminSurface.control,
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline))
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
    }

    private func telemetryCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
                Spacer()
            }
            Text(value)
                .font(AdminType.title3)
                .foregroundColor(AdminSurface.primaryText)
            Text(title)
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .padding(AdminSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
    }

    // MARK: - Search Section

    private var searchAndFilterSection: some View {
        AdminSearchField(
            text: $viewModel.searchText,
            placeholder: Language.get("Categories_Search_Placeholder", alter: "بحث باسم الحيوان، السلالة، أو المعرف...")
        )
    }

    // MARK: - Category Canvas Content

    @ViewBuilder
    private var categoryCanvasContent: some View {
        if viewModel.isLoading && viewModel.categories.isEmpty {
            VStack(spacing: AdminSpacing.md) {
                Spacer().frame(height: 40)
                ProgressView()
                    .tint(AdminSurface.primary)
                    .scaleEffect(1.2)
                Text(Language.get("Loading", alter: "جاري التحميل..."))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
            }
        } else if let error = viewModel.errorMessage {
            AdminErrorBanner(message: error) {
                viewModel.startListening()
            }
        } else if viewModel.filteredCategories.isEmpty {
            AdminEmptyStateView(
                symbol: "pawprint",
                title: Language.get("Categories_Empty_Title", alter: "لا توجد تصنيفات"),
                subtitle: Language.get("Categories_Empty_Sub", alter: "لم يتم العثور على أي تصنيفات مطابقة لخيارات البحث.")
            )
        } else {
            if viewModel.isReorderMode {
                reorderListView
            } else {
                switch viewModel.viewMode {
                case .cards:
                    cardsGridView
                case .tree:
                    taxonomyTreeListView
                }
            }
        }
    }

    // MARK: - Cards Grid View

    private var cardsGridView: some View {
        LazyVStack(spacing: AdminSpacing.md) {
            ForEach(viewModel.filteredCategories) { category in
                AdminCategoryCardView(
                    category: category,
                    canManage: viewModel.canManage,
                    onTap: {
                        editingCategory = category
                    },
                    onToggleVisibility: {
                        viewModel.toggleVisibility(for: category)
                    },
                    onDelete: {
                        categoryToDelete = category
                    }
                )
            }
        }
    }

    // MARK: - Taxonomy Tree List View

    private var taxonomyTreeListView: some View {
        LazyVStack(spacing: AdminSpacing.sm) {
            ForEach(viewModel.filteredCategories) { category in
                let isExpanded = expandedCategoryIDs.contains(category.id)
                VStack(spacing: 0) {
                    // Category Header Row
                    HStack(spacing: AdminSpacing.sm) {
                        // Expand/Collapse Chevron
                        Button {
                            withAnimation(AdminAnimation.fast) {
                                if isExpanded {
                                    expandedCategoryIDs.remove(category.id)
                                } else {
                                    expandedCategoryIDs.insert(category.id)
                                }
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : (Language.isRTL() ? "chevron.left" : "chevron.right"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AdminSurface.secondaryText)
                                .frame(width: 28, height: 28)
                        }

                        // Mascot Thumbnail
                        categoryAvatarView(category: category, size: 38)

                        // Title & Breeds Count
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(category.localizedName)
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                if !category.secondaryName.isEmpty {
                                    Text(category.secondaryName)
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                            Text(String(format: Language.get("Categories_Breeds_Count", alter: "%ld سلالة"), category.subKinds.count))
                                .font(AdminType.caption2)
                                .foregroundColor(category.accentColor)
                        }

                        Spacer()

                        // Visibility Indicator
                        Circle()
                            .fill(category.isVisible ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)

                        // Edit Button
                        Button {
                            editingCategory = category
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }
                    .padding(AdminSpacing.cardPadding)

                    // Expanded SubKinds Tree
                    if isExpanded {
                        Divider().background(AdminSurface.hairline)

                        if category.subKinds.isEmpty {
                            Text(Language.get("Categories_No_SubKinds", alter: "لا توجد سلالات فرعية مسجلة"))
                                .font(AdminType.footnote)
                                .foregroundColor(AdminSurface.secondaryText)
                                .padding(AdminSpacing.md)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(category.subKinds) { sub in
                                    HStack(spacing: AdminSpacing.sm) {
                                        // Indent connector
                                        Rectangle()
                                            .fill(category.accentColor.opacity(0.35))
                                            .frame(width: 2, height: 32)
                                            .padding(.horizontal, 8)

                                        // SubKind Icon
                                        if !sub.iconUrl.isEmpty, let url = URL(string: sub.iconUrl) {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable().scaledToFit()
                                                default:
                                                    Image(systemName: "pawprint")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(category.accentColor)
                                                }
                                            }
                                            .frame(width: 26, height: 26)
                                            .background(category.accentColor.opacity(0.12), in: Circle())
                                        } else {
                                            Image(systemName: "pawprint")
                                                .font(.system(size: 12))
                                                .foregroundColor(category.accentColor)
                                                .frame(width: 26, height: 26)
                                                .background(category.accentColor.opacity(0.12), in: Circle())
                                        }

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(sub.localizedName)
                                                .font(AdminType.callout)
                                                .foregroundColor(AdminSurface.primaryText)
                                            if !sub.secondaryName.isEmpty {
                                                Text(sub.secondaryName)
                                                    .font(AdminType.caption2)
                                                    .foregroundColor(AdminSurface.secondaryText)
                                            }
                                        }

                                        Spacer()

                                        if sub.adultHood > 0 {
                                            Text(String(format: Language.get("Categories_SubKind_Adult_Format", alter: "البلوغ: %ld شهر"), sub.adultHood))
                                                .font(AdminType.caption2)
                                                .foregroundColor(AdminSurface.secondaryText)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AdminSurface.control, in: Capsule())
                                        }
                                    }
                                    .padding(.horizontal, AdminSpacing.cardPadding)
                                    .padding(.vertical, 6)

                                    if sub.id != category.subKinds.last?.id {
                                        Divider()
                                            .background(AdminSurface.hairline.opacity(0.5))
                                            .padding(.leading, 50)
                                    }
                                }
                            }
                            .padding(.vertical, AdminSpacing.xs)
                            .background(AdminSurface.control.opacity(0.35))
                        }
                    }
                }
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }

    // MARK: - Reorder List View

    private var reorderListView: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack {
                Text(Language.get("Categories_Reorder_Hint", alter: "اسحب لتغيير ترتيب ظهور الفئات في التطبيق"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(Array(viewModel.filteredCategories.enumerated()), id: \.element.id) { index, category in
                HStack(spacing: AdminSpacing.sm) {
                    Text("\(index + 1)")
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(width: 24)

                    categoryAvatarView(category: category, size: 36)

                    Text(category.localizedName)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)

                    Spacer()

                    // Quick Up / Down Controls
                    HStack(spacing: 4) {
                        Button {
                            if index > 0 {
                                viewModel.moveCategory(from: IndexSet(integer: index), to: index - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(index > 0 ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .background(AdminSurface.control, in: Circle())
                        }
                        .disabled(index == 0)

                        Button {
                            if index < viewModel.filteredCategories.count - 1 {
                                viewModel.moveCategory(from: IndexSet(integer: index), to: index + 2)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(index < viewModel.filteredCategories.count - 1 ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .background(AdminSurface.control, in: Circle())
                        }
                        .disabled(index == viewModel.filteredCategories.count - 1)
                    }
                }
                .padding(AdminSpacing.cardPadding)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }

    private func categoryAvatarView(category: AdminCategoryItem, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [category.accentColor.opacity(0.22), category.accentColor.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if !category.imageUrl.isEmpty, let url = URL(string: category.imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    default:
                        glyphIcon(category.iconName, size: size * 0.48, tint: category.accentColor)
                    }
                }
                .padding(3)
            } else {
                glyphIcon(category.iconName, size: size * 0.48, tint: category.accentColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func glyphIcon(_ name: String, size: CGFloat, tint: Color) -> some View {
        let sym = !name.isEmpty ? name : "pawprint.fill"
        return Image(systemName: sym)
            .font(.system(size: size, weight: .medium))
            .foregroundColor(tint)
    }

    // MARK: - Toast Banner

    private func toastBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: AdminSpacing.sm) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.35) : AdminSurface.hairline)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Spatial Category Card View

@MainActor
struct AdminCategoryCardView: View {
    let category: AdminCategoryItem
    let canManage: Bool
    let onTap: () -> Void
    let onToggleVisibility: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Main Info Row
                HStack(alignment: .center, spacing: AdminSpacing.md) {
                    // Category Mascot Artwork / Avatar
                    mascotArtworkView

                    // Title & Taxonomy Hierarchy
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(category.localizedName)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)

                            // Sorting Index Tag
                            Text("#\(category.sortingKey)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AdminSurface.secondaryText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.control, in: Capsule())
                        }

                        if !category.secondaryName.isEmpty {
                            Text(category.secondaryName)
                                .font(AdminType.subheadline)
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        // Breed Count & Technical ID Pill
                        HStack(spacing: 6) {
                            Text(String(format: Language.get("Categories_Breeds_Count", alter: "%ld سلالة"), category.subKinds.count))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(category.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(category.accentColor.opacity(0.12), in: Capsule())

                            Text("ID: \(category.numericID)")
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(.top, 2)
                    }

                    Spacer()

                    // Storefront Visibility Toggle Button
                    VStack(spacing: 6) {
                        Button(action: onToggleVisibility) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(category.isVisible ? Color.green : Color.orange)
                                    .frame(width: 7, height: 7)
                                Text(category.isVisible
                                     ? Language.get("Categories_Filter_Visible", alter: "ظاهر")
                                     : Language.get("Categories_Filter_Hidden", alter: "مخفي"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(category.isVisible ? .green : .orange)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                (category.isVisible ? Color.green : Color.orange).opacity(0.12),
                                in: Capsule()
                            )
                        }
                        .disabled(!canManage)

                        // Edit Indicator Chevron
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                }
                .padding(AdminSpacing.cardPadding)

                // SubKinds Pills Preview (if available)
                if !category.subKinds.isEmpty {
                    Divider().background(AdminSurface.hairline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(category.subKinds.prefix(6)) { sub in
                                Text(sub.localizedName)
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.primaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AdminSurface.control, in: Capsule())
                            }
                            if category.subKinds.count > 6 {
                                Text("+\(category.subKinds.count - 6)")
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(category.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(category.accentColor.opacity(0.10), in: Capsule())
                            }
                        }
                        .padding(.horizontal, AdminSpacing.cardPadding)
                        .padding(.vertical, 8)
                    }
                    .background(AdminSurface.control.opacity(0.25))
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .stroke(category.isVisible ? AdminSurface.hairline : Color.orange.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canManage {
                Button(action: onToggleVisibility) {
                    Label(
                        category.isVisible
                            ? Language.get("Categories_Filter_Hidden", alter: "إخفاء من المتجر")
                            : Language.get("Categories_Filter_Visible", alter: "إظهار بالمتجر"),
                        systemImage: category.isVisible ? "eye.slash" : "eye"
                    )
                }
                Button(action: onTap) {
                    Label(Language.get("Edit", alter: "تعديل"), systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label(Language.get("Delete", alter: "حذف"), systemImage: "trash")
                }
            }
        }
    }

    private var mascotArtworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            category.accentColor.opacity(0.26),
                            category.accentColor.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if !category.imageUrl.isEmpty, let url = URL(string: category.imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFit()
                            .rotationEffect(.degrees(category.professionalAngle))
                    default:
                        fallbackGlyph
                    }
                }
                .padding(6)
            } else {
                fallbackGlyph
            }
        }
        .frame(width: 58, height: 58)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(category.accentColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var fallbackGlyph: some View {
        let sym = !category.iconName.isEmpty ? category.iconName : "pawprint.fill"
        return Image(systemName: sym)
            .font(.system(size: 26, weight: .medium))
            .foregroundColor(category.accentColor)
    }
}

// MARK: - Category Dossier & Taxonomy Studio Sheet

@MainActor
struct AdminCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: AdminCategoryItem
    let isNew: Bool
    let onSave: (AdminCategoryItem) -> Void
    let onDelete: (() -> Void)?

    @State private var draftAr: String = ""
    @State private var draftEn: String = ""
    @State private var draftNumericID: Int = 0
    @State private var draftDocID: String = ""
    @State private var draftSortingKey: Int = 0
    @State private var draftIconName: String = ""
    @State private var draftImageUrl: String = ""
    @State private var draftLighten: Double = 0.25
    @State private var draftAngle: Double = 0.0
    @State private var draftIsVisible: Bool = true
    @State private var draftSubKinds: [AdminSubKindItem] = []
    @State private var draftColorHex: String = ""

    @State private var isPresentingAddBreed: Bool = false
    @State private var editingBreed: AdminSubKindItem? = nil

    // Curated animal icon presets
    private let popularGlyphs: [String] = [
        "pawprint.fill", "bird.fill", "hare.fill", "tortoise.fill", "fish.fill",
        "ladybug.fill", "ant.fill", "crown.fill", "star.fill", "heart.fill"
    ]

    init(category: AdminCategoryItem, isNew: Bool, onSave: @escaping (AdminCategoryItem) -> Void, onDelete: (() -> Void)?) {
        self.category = category
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete

        _draftAr = State(initialValue: category.nameAr)
        _draftEn = State(initialValue: category.nameEn)
        _draftNumericID = State(initialValue: category.numericID)
        _draftDocID = State(initialValue: category.documentID)
        _draftSortingKey = State(initialValue: category.sortingKey)
        _draftIconName = State(initialValue: category.iconName.isEmpty ? "pawprint.fill" : category.iconName)
        _draftImageUrl = State(initialValue: category.imageUrl)
        _draftLighten = State(initialValue: category.lightenAmount)
        _draftAngle = State(initialValue: category.professionalAngle)
        _draftIsVisible = State(initialValue: category.isVisible)
        _draftSubKinds = State(initialValue: category.subKinds)
        _draftColorHex = State(initialValue: category.colorHex)
    }

    var builtDraft: AdminCategoryItem {
        AdminCategoryItem(
            documentID: draftDocID.isEmpty ? "\(draftNumericID)" : draftDocID,
            numericID: draftNumericID,
            sortingKey: draftSortingKey,
            nameAr: draftAr,
            nameEn: draftEn,
            iconName: draftIconName,
            imageName: category.imageName,
            imageUrl: draftImageUrl,
            lightenAmount: draftLighten,
            professionalAngle: draftAngle,
            isVisible: draftIsVisible,
            subKinds: draftSubKinds,
            colorHex: draftColorHex
        )
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AdminSpacing.sectionSpacing) {
                    // Live Storefront Simulation Card
                    liveConsumerPreviewSection

                    // Identity & Naming Section
                    identitySection

                    // Visuals & Artwork Studio
                    visualStudioSection

                    // Breeds & SubKinds Taxonomy Studio
                    subKindsManagerSection

                    // Storefront Governance
                    governanceSection

                    // Destructive Actions
                    if !isNew && onDelete != nil {
                        destructiveSection
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, AdminSpacing.base)
                .padding(.bottom, AdminSpacing.xxl)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(isNew ? Language.get("Category_New", alter: "تصنيف جديد") : Language.get("Category_Edit", alter: "تعديل التصنيف"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .foregroundColor(AdminSurface.primary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(builtDraft)
                    } label: {
                        Text(Language.get("Save", alter: "حفظ"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primary)
                    }
                    .disabled(draftNumericID <= 0 || (draftAr.isEmpty && draftEn.isEmpty))
                }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .sheet(isPresented: $isPresentingAddBreed) {
                let nextSubID = (draftSubKinds.map { $0.numericID }.max() ?? 0) + 1
                AdminAddBreedSheet(
                    breed: AdminSubKindItem(
                        id: UUID().uuidString,
                        numericID: nextSubID,
                        mainKindID: draftNumericID,
                        nameAr: "",
                        nameEn: "",
                        iconUrl: "",
                        imageName: "",
                        adultHood: 12,
                        haveSubSub: 0,
                        haveItems: 0
                    ),
                    onSave: { newBreed in
                        draftSubKinds.append(newBreed)
                        isPresentingAddBreed = false
                    }
                )
            }
            .sheet(item: $editingBreed) { b in
                AdminAddBreedSheet(
                    breed: b,
                    onSave: { updated in
                        if let idx = draftSubKinds.firstIndex(where: { $0.id == b.id }) {
                            draftSubKinds[idx] = updated
                        }
                        editingBreed = nil
                    }
                )
            }
        }
    }

    // MARK: - Live Consumer Preview Card

    private var liveConsumerPreviewSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                Text(Language.get("Categories_Preview_Title", alter: "معاينة واجهة المتجر للمستخدمين"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                Spacer()
            }

            // High-fidelity iOS Consumer Card Mockup
            HStack(spacing: AdminSpacing.md) {
                // Dynamic Artwork Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(builtDraft.accentColor.opacity(draftLighten > 0 ? draftLighten : 0.20))

                    if !draftImageUrl.isEmpty, let url = URL(string: draftImageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .scaledToFit()
                                    .rotationEffect(.degrees(draftAngle))
                            default:
                                Image(systemName: draftIconName)
                                    .font(.system(size: 28))
                                    .foregroundColor(builtDraft.accentColor)
                            }
                        }
                        .padding(4)
                    } else {
                        Image(systemName: draftIconName)
                            .font(.system(size: 28))
                            .foregroundColor(builtDraft.accentColor)
                    }
                }
                .frame(width: 64, height: 64)
                .shadow(color: builtDraft.accentColor.opacity(0.20), radius: 6, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(builtDraft.localizedName.isEmpty ? Language.get("Category_New", alter: "اسم الحيوان") : builtDraft.localizedName)
                        .font(AdminType.title3)
                        .foregroundColor(AdminSurface.primaryText)

                    if !builtDraft.secondaryName.isEmpty {
                        Text(builtDraft.secondaryName)
                            .font(AdminType.subheadline)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    HStack(spacing: 6) {
                        Text(String(format: Language.get("Categories_Breeds_Count", alter: "%ld سلالة"), draftSubKinds.count))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(builtDraft.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(builtDraft.accentColor.opacity(0.12), in: Capsule())

                        if !draftIsVisible {
                            Text(Language.get("Categories_Filter_Hidden", alter: "مخفي"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Spacer()
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))

            Text(Language.get("Categories_Preview_Hint", alter: "تحديث فوري يحاكي بطاقة الحيوان كما تظهر لعملاء التطبيق"))
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            sectionHeader(title: Language.get("Category_Identity", alter: "الهوية والمُعرّفات"), symbol: "number.circle.fill")

            VStack(spacing: AdminSpacing.md) {
                formTextField(
                    title: Language.get("Category_NameAr", alter: "الاسم بالعربية"),
                    text: $draftAr,
                    placeholder: "مثال: طيور، قطط، خيول"
                )

                formTextField(
                    title: Language.get("Category_NameEn", alter: "الاسم بالإنجليزية"),
                    text: $draftEn,
                    placeholder: "e.g. Birds, Cats, Horses"
                )

                HStack(spacing: AdminSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Category_NumericID", alter: "المعرف الرقمي (ID)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        TextField("ID", value: $draftNumericID, format: .number)
                            .keyboardType(.numberPad)
                            .font(AdminType.callout)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                            .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
                            .disabled(!isNew)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Category_SortingKey", alter: "ترتيب العرض"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        TextField("Sorting Key", value: $draftSortingKey, format: .number)
                            .keyboardType(.numberPad)
                            .font(AdminType.callout)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                            .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
                    }
                }
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    // MARK: - Visual Studio Section

    private var visualStudioSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            sectionHeader(title: Language.get("Category_Appearance", alter: "المظهر والأيقونة"), symbol: "paintpalette.fill")

            VStack(spacing: AdminSpacing.md) {
                // SF Symbol Preset Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Category_IconName", alter: "اسم الأيقونة (SF Symbol)"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(popularGlyphs, id: \.self) { glyph in
                                let isSelected = draftIconName == glyph
                                Button {
                                    draftIconName = glyph
                                } label: {
                                    Image(systemName: glyph)
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                        .frame(width: 42, height: 42)
                                        .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.clear : AdminSurface.hairline))
                                }
                            }
                        }
                    }

                    TextField("SF Symbol Name", text: $draftIconName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(AdminType.callout)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
                }

                // Cloud Storage Image URL
                formTextField(
                    title: Language.get("Category_ImageURL", alter: "رابط صورة الفئة"),
                    text: $draftImageUrl,
                    placeholder: "https://firebasestorage.googleapis.com/..."
                )

                // Lighten Amount Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Language.get("Category_Lighten", alter: "قيمة تفتيح الخلفية"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                        Text(String(format: "%.2f", draftLighten))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                    }
                    Slider(value: $draftLighten, in: 0.0...1.0, step: 0.05)
                        .tint(AdminSurface.primary)
                }

                // Tilt Angle Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Language.get("Category_Angle", alter: "زاوية الميل الاحترافي"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                        Text(String(format: "%.0f°", draftAngle))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primary)
                    }
                    Slider(value: $draftAngle, in: -45.0...45.0, step: 1.0)
                        .tint(AdminSurface.primary)
                }
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    // MARK: - SubKinds Manager Section

    private var subKindsManagerSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack {
                sectionHeader(title: Language.get("Categories_SubKinds_Header", alter: "السلالات والتصنيفات الفرعية"), symbol: "point.3.connected.trianglepath.dotted")
                Spacer()

                Button {
                    isPresentingAddBreed = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Categories_Add_SubKind", alter: "إضافة سلالة"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }
            }

            VStack(spacing: 0) {
                if draftSubKinds.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 24))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                        Text(Language.get("Categories_No_SubKinds", alter: "لا توجد سلالات فرعية مسجلة"))
                            .font(AdminType.callout)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else {
                    ForEach(Array(draftSubKinds.enumerated()), id: \.element.id) { idx, breed in
                        HStack(spacing: AdminSpacing.sm) {
                            Text("\(idx + 1)")
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.secondaryText)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(breed.localizedName)
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                if !breed.secondaryName.isEmpty {
                                    Text(breed.secondaryName)
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }

                            Spacer()

                            if breed.adultHood > 0 {
                                Text(String(format: Language.get("Categories_SubKind_Adult_Format", alter: "البلوغ: %ld شهر"), breed.adultHood))
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.control, in: Capsule())
                            }

                            Button {
                                editingBreed = breed
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AdminSurface.primary)
                                    .frame(width: 28, height: 28)
                                    .background(AdminSurface.control, in: Circle())
                            }

                            Button {
                                draftSubKinds.removeAll { $0.id == breed.id }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.red)
                                    .frame(width: 28, height: 28)
                                    .background(Color.red.opacity(0.10), in: Circle())
                            }
                        }
                        .padding(.horizontal, AdminSpacing.cardPadding)
                        .padding(.vertical, 10)

                        if idx < draftSubKinds.count - 1 {
                            Divider().background(AdminSurface.hairline)
                        }
                    }
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    // MARK: - Governance Section

    private var governanceSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            sectionHeader(title: Language.get("Category_Settings", alter: "إعدادات الظهور بالمتجر"), symbol: "gearshape.fill")

            VStack(spacing: AdminSpacing.sm) {
                Toggle(isOn: $draftIsVisible) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Categories_Visibility", alter: "ظهور التصنيف بالمتجر"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("Categories_Visibility_Toggle_Hint", alter: "التحكم في ظهور هذا التصنيف في الصفحة الرئيسية وقوائم البحث للمستخدمين."))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .tint(AdminSurface.primary)
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    // MARK: - Destructive Section

    private var destructiveSection: some View {
        Button(role: .destructive) {
            onDelete?()
        } label: {
            HStack {
                Spacer()
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                Text(Language.get("Categories_Delete_Category", alter: "حذف هذا التصنيف"))
                    .font(AdminType.calloutBold)
                Spacer()
            }
            .foregroundColor(.red)
            .frame(height: 48)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.medium))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(Color.red.opacity(0.20)))
        }
    }

    private func sectionHeader(title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AdminSurface.primary)
            Text(title)
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
        }
        .padding(.horizontal, 4)
    }

    private func formTextField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)
            TextField(placeholder, text: text)
                .font(AdminType.callout)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
        }
    }
}

// MARK: - Add / Edit Breed Sheet

@MainActor
struct AdminAddBreedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let breed: AdminSubKindItem
    let onSave: (AdminSubKindItem) -> Void

    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var adultMonths: Int = 12
    @State private var iconUrl: String = ""
    @State private var numericID: Int = 0

    init(breed: AdminSubKindItem, onSave: @escaping (AdminSubKindItem) -> Void) {
        self.breed = breed
        self.onSave = onSave

        _nameAr = State(initialValue: breed.nameAr)
        _nameEn = State(initialValue: breed.nameEn)
        _adultMonths = State(initialValue: breed.adultHood)
        _iconUrl = State(initialValue: breed.iconUrl)
        _numericID = State(initialValue: breed.numericID)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(Language.get("Category_Names", alter: "الأسماء واللغات"))) {
                    TextField(Language.get("Categories_SubKind_NameAr", alter: "اسم السلالة (عربي)"), text: $nameAr)
                    TextField(Language.get("Categories_SubKind_NameEn", alter: "اسم السلالة (إنجليزي)"), text: $nameEn)
                }

                Section(header: Text(Language.get("Categories_SubKind_Properties", alter: "خصائص السلالة"))) {
                    Stepper(value: $adultMonths, in: 0...120) {
                        HStack {
                            Text(Language.get("Categories_SubKind_AdultMonths", alter: "سن البلوغ"))
                            Spacer()
                            Text("\(adultMonths) " + Language.get("Months", alter: "شهر"))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }

                    TextField(Language.get("Categories_SubKind_IconUrl", alter: "رابط الأيقونة (URL)"), text: $iconUrl)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(Language.get("Categories_Add_SubKind", alter: "إضافة سلالة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Language.get("Save", alter: "حفظ")) {
                        var updated = breed
                        updated.nameAr = nameAr
                        updated.nameEn = nameEn
                        updated.adultHood = adultMonths
                        updated.iconUrl = iconUrl
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(nameAr.isEmpty && nameEn.isEmpty)
                }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }
}