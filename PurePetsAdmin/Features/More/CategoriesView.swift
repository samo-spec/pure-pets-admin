//
//  CategoriesView.swift
//  PurePetsAdmin
//
//  NextGen V6 Sovereign Animal Taxonomy & Species Spatial Studio.
//  Reimagined from absolute first principles with a 4-Tier Deep Subcollection Hierarchy:
//  - Tier 1: MainKindsCollection/{mainKindDocID} (Species / Root Categories)
//  - Tier 2: SubKinds/{subKindDocID} (Breeds & SubKinds) + synced to SubKindsArray
//  - Tier 3: SubSubKinds/{subSubDocID} (Sub-Varieties & Precision Strains)
//  - Tier 4: Items/{itemDocID} (Specifications, Traits & Gender Characteristics)
//
//  Featuring Spatial Specimen Cards, Phylogenetic Tree Atlas, Real-time Consumer
//  Storefront Simulator, Cascading Multi-Tier Workbench, and Sovereign Modal Sheets.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import PhotosUI

// MARK: - 1. Domain Models

/// Level 1: MainKind (Species / Category)
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
        let lighten = (data["LightenAmount"] as? NSNumber)?.doubleValue ?? 0.25
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

/// Level 2: SubKind (Breed / Variety)
struct AdminSubKindItem: Identifiable, Equatable, Sendable {
    var id: String
    var numericID: Int
    var mainKindID: Int
    var nameAr: String
    var nameEn: String
    var iconUrl: String
    var iconName: String
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

    static func fromSnapshot(_ doc: DocumentSnapshot) -> AdminSubKindItem? {
        guard let dict = doc.data() else { return nil }
        var item = fromDictionary(dict)
        item.id = doc.documentID
        return item
    }

    static func fromDictionary(_ dict: [String: Any]) -> AdminSubKindItem {
        let numID = (dict["ID"] as? NSNumber)?.intValue ?? 0
        let mainID = (dict["MainKindID"] as? NSNumber)?.intValue ?? 0
        let ar = dict["SubKindNameAr"] as? String ?? ""
        let en = dict["SubKindNameEn"] as? String ?? ""
        let iconUrl = dict["subKindIconUrl"] as? String ?? (dict["SubKindIconUrl"] as? String ?? "")
        let iconName = dict["subKindIcon"] as? String ?? ""
        let imgName = dict["SubKindImageName"] as? String ?? ""
        let adult = (dict["adultHood"] as? NSNumber)?.intValue ?? 12
        let subSub = (dict["have_subSub"] as? NSNumber)?.intValue ?? 0
        let items = (dict["have_items"] as? NSNumber)?.intValue ?? 0

        return AdminSubKindItem(
            id: "\(numID)",
            numericID: numID,
            mainKindID: mainID,
            nameAr: ar,
            nameEn: en,
            iconUrl: iconUrl,
            iconName: iconName,
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
            "subKindIcon": iconName,
            "SubKindImageName": imageName,
            "adultHood": adultHood,
            "have_subSub": haveSubSub,
            "have_items": haveItems
        ]
    }
}

/// Level 3: SubSubKind (Sub-Variety / Strain)
struct AdminSubSubKindItem: Identifiable, Equatable, Sendable {
    var id: String
    var numericID: Int
    var subKindID: Int
    var nameAr: String
    var nameEn: String
    var imageUrl: String = ""

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

    static func fromSnapshot(_ doc: DocumentSnapshot) -> AdminSubSubKindItem? {
        guard let data = doc.data() else { return nil }
        let numID = (data["ID"] as? NSNumber)?.intValue ?? 0
        let sID = (data["subKindID"] as? NSNumber)?.intValue ?? 0
        let ar = data["nameAr"] as? String ?? ""
        let en = data["nameEn"] as? String ?? ""
        let img = data["imageUrl"] as? String ?? (data["iconUrl"] as? String ?? "")

        return AdminSubSubKindItem(
            id: doc.documentID,
            numericID: numID,
            subKindID: sID,
            nameAr: ar,
            nameEn: en,
            imageUrl: img
        )
    }

    func toDictionary() -> [String: Any] {
        return [
            "ID": numericID,
            "subKindID": subKindID,
            "nameAr": nameAr,
            "nameEn": nameEn,
            "imageUrl": imageUrl
        ]
    }
}

/// Level 4: SubKindItemDetail (Item / Specification & Gender Traits)
struct AdminSubKindItemDetail: Identifiable, Equatable, Sendable {
    var id: String
    var numericID: Int
    var subSubKindID: Int
    var itemNameAr: String
    var itemNameEn: String
    var male: String
    var female: String
    var imageUrl: String = ""

    var localizedName: String {
        if Language.isRTL() {
            return !itemNameAr.isEmpty ? itemNameAr : itemNameEn
        } else {
            return !itemNameEn.isEmpty ? itemNameEn : itemNameAr
        }
    }

    var secondaryName: String {
        if Language.isRTL() {
            return !itemNameEn.isEmpty ? itemNameEn : ""
        } else {
            return !itemNameAr.isEmpty ? itemNameAr : ""
        }
    }

    static func fromSnapshot(_ doc: DocumentSnapshot) -> AdminSubKindItemDetail? {
        guard let data = doc.data() else { return nil }
        let numID = (data["ID"] as? NSNumber)?.intValue ?? 0
        let sID = (data["subSubKindID"] as? NSNumber)?.intValue ?? 0
        let ar = data["itemNameAr"] as? String ?? ""
        let en = data["itemNameEn"] as? String ?? ""
        let m = data["Male"] as? String ?? ""
        let f = data["Female"] as? String ?? ""
        let img = data["imageUrl"] as? String ?? (data["iconUrl"] as? String ?? "")

        return AdminSubKindItemDetail(
            id: doc.documentID,
            numericID: numID,
            subSubKindID: sID,
            itemNameAr: ar,
            itemNameEn: en,
            male: m,
            female: f,
            imageUrl: img
        )
    }

    func toDictionary() -> [String: Any] {
        return [
            "ID": numericID,
            "subSubKindID": subSubKindID,
            "itemNameAr": itemNameAr,
            "itemNameEn": itemNameEn,
            "Male": male,
            "Female": female,
            "imageUrl": imageUrl
        ]
    }
}

// MARK: - 2. Enums & Helpers

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
        case .cards: return Language.get("Categories_ViewMode_Cards", alter: "بطاقات الفصائل")
        case .tree: return Language.get("Categories_ViewMode_Tree", alter: "الهيكل الشجري")
        }
    }

    var icon: String {
        switch self {
        case .cards: return "square.grid.2x2.fill"
        case .tree: return "list.bullet.indent"
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
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

// MARK: - 3. Master ViewModel

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

    // MARK: - Level 1: MainKinds Real-time Stream

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

    // MARK: - MainKind Actions

    func toggleVisibility(for item: AdminCategoryItem) {
        guard canManage else { return }
        let newVisible = !item.isVisible
        let docID = item.documentID.isEmpty ? "\(item.numericID)" : item.documentID
        let itemID = item.id

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
                    if let idx = self?.categories.firstIndex(where: { $0.id == itemID }) {
                        self?.categories[idx].isVisible = !newVisible
                        self?.applyFilter()
                    }
                    self?.showToast(error.localizedDescription, isError: true)
                } else {
                    let msg = newVisible
                        ? Language.get("Categories_Toggled_Visible", alter: "تم تفعيل ظهور التصنيف بالمتجر")
                        : Language.get("Categories_Toggled_Hidden", alter: "تم إخفاء التصنيف من المتجر")
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
                    self?.showToast(Language.get("Categories_Reordered_Success", alter: "تم حفظ الترتيب الجديد بنجاح"))
                    self?.writeAuditLog(action: "reorder_categories", targetID: "batch", before: nil, after: ["count": count])
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

        ref.setData(payload, merge: true) { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    NotificationCenter.default.post(name: NSNotification.Name("MainKindsUpdatedNotification"), object: nil)
                    self?.writeAuditLog(action: action, targetID: docID, before: nil, after: ["numericID": item.numericID, "nameAr": item.nameAr, "nameEn": item.nameEn])
                    completion(true, Language.get("Category_Saved", alter: "تم حفظ التصنيف بنجاح"))
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

        Firestore.firestore().collection("MainKindsCollection").document(docID).delete { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    NotificationCenter.default.post(name: NSNotification.Name("MainKindsUpdatedNotification"), object: nil)
                    self?.writeAuditLog(action: "delete_category", targetID: docID, before: ["nameAr": item.nameAr, "nameEn": item.nameEn], after: nil)
                    completion(true, Language.get("Category_Deleted", alter: "تم حذف التصنيف بنجاح"))
                }
            }
        }
    }

    // MARK: - Level 2: SubKinds Subcollection Stream & Sync

    func listenToSubKinds(for mainKindDocID: String, onUpdate: @escaping @MainActor ([AdminSubKindItem]) -> Void) -> any ListenerRegistration {
        let db = Firestore.firestore()
        let ref = db.collection("MainKindsCollection").document(mainKindDocID).collection("SubKinds").order(by: "ID", descending: false)
        return ref.addSnapshotListener { snapshot, _ in
            Task { @MainActor in
                guard let docs = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                let items = docs.compactMap { AdminSubKindItem.fromSnapshot($0) }
                onUpdate(items)
            }
        }
    }

    func saveSubKind(mainKindDocID: String, subKind: AdminSubKindItem, isNew: Bool, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية التعديل"))
            return
        }

        let docID = subKind.id.isEmpty ? "\(subKind.numericID)" : subKind.id
        let db = Firestore.firestore()
        let mainRef = db.collection("MainKindsCollection").document(mainKindDocID)
        let subRef = mainRef.collection("SubKinds").document(docID)

        let payload = subKind.toDictionary()
        let action = isNew ? "create_subkind" : "update_subkind"
        let target = "\(mainKindDocID)/\(docID)"

        subRef.setData(payload, merge: true) { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    // Sync with parent document SubKindsArray for consumer app parity
                    self?.syncParentSubKindsArray(mainKindDocID: mainKindDocID)
                    NotificationCenter.default.post(name: NSNotification.Name("MainKindsUpdatedNotification"), object: nil)
                    self?.writeAuditLog(action: action, targetID: target, before: nil, after: ["ID": subKind.numericID, "nameAr": subKind.nameAr, "nameEn": subKind.nameEn])
                    completion(true, Language.get("SubKind_Saved", alter: "تم حفظ السلالة بنجاح"))
                }
            }
        }
    }

    func deleteSubKind(mainKindDocID: String, subKind: AdminSubKindItem, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية الحذف"))
            return
        }

        let docID = subKind.id.isEmpty ? "\(subKind.numericID)" : subKind.id
        let db = Firestore.firestore()
        let mainRef = db.collection("MainKindsCollection").document(mainKindDocID)
        let subRef = mainRef.collection("SubKinds").document(docID)
        let target = "\(mainKindDocID)/\(docID)"

        subRef.delete { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.syncParentSubKindsArray(mainKindDocID: mainKindDocID)
                    NotificationCenter.default.post(name: NSNotification.Name("MainKindsUpdatedNotification"), object: nil)
                    self?.writeAuditLog(action: "delete_subkind", targetID: target, before: ["ID": subKind.numericID, "nameAr": subKind.nameAr, "nameEn": subKind.nameEn], after: nil)
                    completion(true, Language.get("SubKind_Deleted", alter: "تم حذف السلالة بنجاح"))
                }
            }
        }
    }

    private func syncParentSubKindsArray(mainKindDocID: String) {
        let db = Firestore.firestore()
        let mainRef = db.collection("MainKindsCollection").document(mainKindDocID)
        mainRef.collection("SubKinds").order(by: "ID", descending: false).getDocuments { snapshot, _ in
            guard let docs = snapshot?.documents else { return }
            let arr = docs.compactMap { AdminSubKindItem.fromSnapshot($0)?.toDictionary() }
            mainRef.updateData(["SubKindsArray": arr])
        }
    }

    // MARK: - Level 3: SubSubKinds Subcollection Stream

    func listenToSubSubKinds(mainKindDocID: String, subKindDocID: String, onUpdate: @escaping @MainActor ([AdminSubSubKindItem]) -> Void) -> any ListenerRegistration {
        let db = Firestore.firestore()
        let ref = db.collection("MainKindsCollection")
            .document(mainKindDocID)
            .collection("SubKinds")
            .document(subKindDocID)
            .collection("SubSubKinds")
            .order(by: "ID", descending: false)

        return ref.addSnapshotListener { snapshot, _ in
            Task { @MainActor in
                guard let docs = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                let items = docs.compactMap { AdminSubSubKindItem.fromSnapshot($0) }
                onUpdate(items)
            }
        }
    }

    func saveSubSubKind(mainKindDocID: String, subKindDocID: String, subSub: AdminSubSubKindItem, isNew: Bool, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية التعديل"))
            return
        }

        let docID = subSub.id.isEmpty ? "\(subSub.numericID)" : subSub.id
        let db = Firestore.firestore()
        let ref = db.collection("MainKindsCollection")
            .document(mainKindDocID)
            .collection("SubKinds")
            .document(subKindDocID)
            .collection("SubSubKinds")
            .document(docID)

        let payload = subSub.toDictionary()
        let action = isNew ? "create_subsubkind" : "update_subsubkind"
        let target = "\(mainKindDocID)/\(subKindDocID)/\(docID)"

        ref.setData(payload, merge: true) { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.writeAuditLog(action: action, targetID: target, before: nil, after: ["ID": subSub.numericID, "nameAr": subSub.nameAr, "nameEn": subSub.nameEn])
                    completion(true, Language.get("SubSubKind_Saved", alter: "تم حفظ التفريع بنجاح"))
                }
            }
        }
    }

    func deleteSubSubKind(mainKindDocID: String, subKindDocID: String, subSub: AdminSubSubKindItem, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية الحذف"))
            return
        }

        let docID = subSub.id.isEmpty ? "\(subSub.numericID)" : subSub.id
        let db = Firestore.firestore()
        let ref = db.collection("MainKindsCollection")
            .document(mainKindDocID)
            .collection("SubKinds")
            .document(subKindDocID)
            .collection("SubSubKinds")
            .document(docID)
        let target = "\(mainKindDocID)/\(subKindDocID)/\(docID)"

        ref.delete { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.writeAuditLog(action: "delete_subsubkind", targetID: target, before: ["ID": subSub.numericID, "nameAr": subSub.nameAr, "nameEn": subSub.nameEn], after: nil)
                    completion(true, Language.get("SubSubKind_Deleted", alter: "تم حذف التفريع بنجاح"))
                }
            }
        }
    }

    // MARK: - Level 4: Items Subcollection Stream

    func listenToItems(mainKindDocID: String, subKindDocID: String, subSubDocID: String, onUpdate: @escaping @MainActor ([AdminSubKindItemDetail]) -> Void) -> any ListenerRegistration {
        let db = Firestore.firestore()
        let ref = db.collection("MainKindsCollection")
            .document(mainKindDocID)
            .collection("SubKinds")
            .document(subKindDocID)
            .collection("SubSubKinds")
            .document(subSubDocID)
            .collection("Items")
            .order(by: "ID", descending: false)

        return ref.addSnapshotListener { snapshot, _ in
            Task { @MainActor in
                guard let docs = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                let items = docs.compactMap { AdminSubKindItemDetail.fromSnapshot($0) }
                onUpdate(items)
            }
        }
    }

    func saveItem(mainKindDocID: String, subKindDocID: String, subSubDocID: String, item: AdminSubKindItemDetail, isNew: Bool, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية التعديل"))
            return
        }

        let docID = item.id.isEmpty ? "\(item.numericID)" : item.id
        let db = Firestore.firestore()
        let ref = db.collection("MainKindsCollection")
            .document(mainKindDocID)
            .collection("SubKinds")
            .document(subKindDocID)
            .collection("SubSubKinds")
            .document(subSubDocID)
            .collection("Items")
            .document(docID)

        let payload = item.toDictionary()
        let action = isNew ? "create_kind_item" : "update_kind_item"
        let target = "\(mainKindDocID)/\(subKindDocID)/\(subSubDocID)/\(docID)"

        ref.setData(payload, merge: true) { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.writeAuditLog(action: action, targetID: target, before: nil, after: ["ID": item.numericID, "itemNameAr": item.itemNameAr, "itemNameEn": item.itemNameEn])
                    completion(true, Language.get("KindItem_Saved", alter: "تم حفظ العنصر بنجاح"))
                }
            }
        }
    }

    func deleteItem(mainKindDocID: String, subKindDocID: String, subSubDocID: String, item: AdminSubKindItemDetail, completion: @escaping @MainActor @Sendable (Bool, String?) -> Void) {
        guard canManage else {
            completion(false, Language.get("Permission_Denied", alter: "ليس لديك صلاحية الحذف"))
            return
        }

        let docID = item.id.isEmpty ? "\(item.numericID)" : item.id
        let db = Firestore.firestore()
        let ref = db.collection("MainKindsCollection")
            .document(mainKindDocID)
            .collection("SubKinds")
            .document(subKindDocID)
            .collection("SubSubKinds")
            .document(subSubDocID)
            .collection("Items")
            .document(docID)
        let target = "\(mainKindDocID)/\(subKindDocID)/\(subSubDocID)/\(docID)"

        ref.delete { [weak self] error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                } else {
                    self?.writeAuditLog(action: "delete_kind_item", targetID: target, before: ["ID": item.numericID, "itemNameAr": item.itemNameAr, "itemNameEn": item.itemNameEn], after: nil)
                    completion(true, Language.get("KindItem_Deleted", alter: "تم حذف العنصر بنجاح"))
                }
            }
        }
    }

    // MARK: - Audit Log Helper

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

// MARK: - 4. Main Screen: AdminCategoriesView

@MainActor
public struct AdminCategoriesView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminCategoriesViewModel()

    // Navigation & Inspection State
    @State private var selectedCategoryForStudio: AdminCategoryItem? = nil
    @State private var isCreatingCategory: Bool = false
    @State private var categoryToDelete: AdminCategoryItem? = nil
    @State private var expandedCategoryIDs: Set<String> = []

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top Sovereign Navigation Bar
                    dossierHeaderView

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: AdminSpacing.sectionSpacing) {
                            // Live Telemetry Pulse Section
                            telemetryPulseSection

                            // Multi-Attribute Search & Discovery Field
                            searchAndFilterSection

                            // Species Canvas
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

                // Toast Notification Overlay
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

                // Push Navigation Link to Category Studio
                NavigationLink(
                    destination: Group {
                        if let cat = selectedCategoryForStudio {
                            AdminCategoryStudioView(
                                category: cat,
                                viewModel: viewModel,
                                onDismiss: {
                                    selectedCategoryForStudio = nil
                                }
                            )
                        }
                    },
                    isActive: Binding(
                        get: { selectedCategoryForStudio != nil },
                        set: { if !$0 { selectedCategoryForStudio = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $isCreatingCategory) {
            let nextID = (viewModel.categories.map { $0.numericID }.max() ?? 0) + 1
            AdminCategoryCreateSheet(
                nextNumericID: nextID,
                onSave: { newCat in
                    viewModel.saveCategory(newCat, isNew: true) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            isCreatingCategory = false
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                }
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

    // MARK: - Navigation Header

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Categories_Title", alter: "تصنيفات وفصائل الحيوانات"),
            subtitle: "\(viewModel.totalCount) " + Language.get("Categories_Total_Sub", alter: "فصائل") + " • \(viewModel.totalBreedsCount) " + Language.get("Categories_Total_Breeds", alter: "سلالة"),
            statusDotColor: Color(uiColor: .ppSuccess),
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

                // Add Category Button
                if viewModel.canManage {
                    AdminPrimaryPillButton(
                        title: Language.get("Category_New", alter: "فصيلة جديدة"),
                        systemImage: "plus"
                    ) {
                        isCreatingCategory = true
                    }
                }
            }
        }
    }

    // MARK: - Telemetry Intelligence Pulse

    private var telemetryPulseSection: some View {
        HStack(spacing: AdminSpacing.sm) {
            telemetryCard(
                title: Language.get("Categories_Pulse_Total", alter: "إجمالي الفصائل"),
                value: "\(viewModel.totalCount)",
                symbol: "pawprint.fill",
                tint: AdminSurface.primary
            )
            telemetryCard(
                title: Language.get("Categories_Pulse_Visible", alter: "معروض بالمتجر"),
                value: "\(viewModel.visibleCount)",
                symbol: "eye.fill",
                tint: Color(uiColor: .ppSuccess)
            )
            telemetryCard(
                title: Language.get("Categories_Pulse_Hidden", alter: "مخفي"),
                value: "\(viewModel.hiddenCount)",
                symbol: "eye.slash.fill",
                tint: Color(uiColor: .ppWarning)
            )
            telemetryCard(
                title: Language.get("Categories_Pulse_Breeds", alter: "سلالات موثقة"),
                value: "\(viewModel.totalBreedsCount)",
                symbol: "point.3.connected.trianglepath.dotted",
                tint: Color(uiColor: .ppInfo)
            )
        }
    }

    private func telemetryCard(title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 19, weight: .bold).monospacedDigit())
                .foregroundColor(AdminSurface.primaryText)
            Text(title)
                .font(AdminType.caption2)
                .foregroundColor(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
        )
    }

    // MARK: - Search & Filter Engine

    private var searchAndFilterSection: some View {
        VStack(spacing: AdminSpacing.sm) {
            AdminSearchField(
                text: $viewModel.searchText,
                placeholder: Language.get("Categories_Search_Placeholder", alter: "بحث في الفصائل والسلالات والتفريعات...")
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.xs) {
                    ForEach(CategoryFilter.allCases) { filter in
                        let isSelected = viewModel.selectedFilter == filter
                        Button {
                            withAnimation(AdminAnimation.fast) {
                                viewModel.selectedFilter = filter
                            }
                        } label: {
                            Text(filter.title)
                                .font(isSelected ? AdminType.captionBold : AdminType.caption)
                                .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(
                                    isSelected ? AdminSurface.primary : AdminSurface.control,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Category Canvas Content

    @ViewBuilder
    private var categoryCanvasContent: some View {
        if viewModel.isLoading && viewModel.categories.isEmpty {
            VStack(spacing: AdminSpacing.md) {
                ProgressView()
                    .tint(AdminSurface.primary)
                    .scaleEffect(1.2)
                Text(Language.get("Categories_Loading", alter: "جارٍ تحميل تصنيفات الحيوانات..."))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else if let error = viewModel.errorMessage, viewModel.categories.isEmpty {
            VStack(spacing: AdminSpacing.md) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(Color(uiColor: .ppError))
                Text(error)
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    viewModel.startListening()
                } label: {
                    Text(Language.get("TryAgain", alter: "إعادة المحاولة"))
                        .font(AdminType.calloutBold)
                        .padding(.horizontal, 20)
                        .frame(height: 38)
                        .background(AdminSurface.primary, in: Capsule())
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else if viewModel.filteredCategories.isEmpty {
            VStack(spacing: AdminSpacing.md) {
                Image(systemName: "pawprint.circle.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                Text(Language.get("Categories_Empty_Title", alter: "لا توجد فصائل مطابقة"))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.get("Categories_Empty_Sub", alter: "جرّب تغيير عبارة البحث أو الفلتر النشط."))
                    .font(AdminType.caption1)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            if viewModel.isReorderMode {
                reorderListView
            } else {
                switch viewModel.viewMode {
                case .cards:
                    cardsGridView
                case .tree:
                    phylogeneticTreeView
                }
            }
        }
    }

    // MARK: - Reorder Mode List

    private var reorderListView: some View {
        VStack(spacing: AdminSpacing.sm) {
            HStack {
                Text(Language.get("Categories_Reorder_Notice", alter: "قم بسحب العناصر لتغيير ترتيب ظهورها بالمتجر الاستهلاكي"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.primary)
                Spacer()
            }
            .padding(.horizontal, 4)

            LazyVStack(spacing: 8) {
                ForEach(viewModel.filteredCategories) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(.system(size: 16, weight: .semibold))

                        Text("#\(item.sortingKey)")
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.control, in: Capsule())

                        Text(item.localizedName)
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)

                        Spacer()

                        Text("\(item.subKinds.count) " + Language.get("Breeds", alter: "سلالة"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(14)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                }
                .onMove { source, destination in
                    viewModel.moveCategory(from: source, to: destination)
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
                    isExpanded: expandedCategoryIDs.contains(category.id),
                    onToggleVisibility: {
                        viewModel.toggleVisibility(for: category)
                    },
                    onToggleExpand: {
                        withAnimation(AdminAnimation.standard) {
                            if expandedCategoryIDs.contains(category.id) {
                                expandedCategoryIDs.remove(category.id)
                            } else {
                                expandedCategoryIDs.insert(category.id)
                            }
                        }
                    },
                    onOpenStudio: {
                        selectedCategoryForStudio = category
                    },
                    onDelete: {
                        categoryToDelete = category
                    }
                )
            }
        }
    }

    // MARK: - Phylogenetic Interactive Tree View

    private var phylogeneticTreeView: some View {
        LazyVStack(spacing: AdminSpacing.sm) {
            ForEach(viewModel.filteredCategories) { cat in
                AdminCategoryTreeBranch(
                    category: cat,
                    viewModel: viewModel,
                    onOpenStudio: {
                        selectedCategoryForStudio = cat
                    }
                )
            }
        }
    }

    // MARK: - Toast Banner Helper

    private func toastBanner(message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
            Text(message)
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isError ? Color(uiColor: .ppError).opacity(0.4) : Color(uiColor: .ppSuccess).opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - 5. Specimen Spatial Card: AdminCategoryCardView

struct AdminCategoryCardView: View {
    let category: AdminCategoryItem
    let canManage: Bool
    let isExpanded: Bool
    let onToggleVisibility: () -> Void
    let onToggleExpand: () -> Void
    let onOpenStudio: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Main Specimen Card Header
            VStack(spacing: AdminSpacing.sm) {
                HStack(alignment: .top, spacing: 12) {
                    // Specimen Avatar Icon / Artwork
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(category.accentColor.opacity(0.16))
                            .frame(width: 58, height: 58)

                        if !category.imageUrl.isEmpty, let url = URL(string: category.imageUrl) {
                            AdminRemoteImage(url: url, contentMode: .fit, targetSize: CGSize(width: 58, height: 58)) {
                                Color.clear
                            }
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Image(systemName: category.iconName.isEmpty ? "pawprint.fill" : category.iconName)
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(category.accentColor)
                                .rotationEffect(.degrees(category.professionalAngle))
                        }
                    }

                    // Titles & Lineage
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(category.localizedName)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            Text("#\(category.numericID)")
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundColor(category.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(category.accentColor.opacity(0.12), in: Capsule())

                            Spacer()

                            // Storefront Live Visibility Switch
                            if canManage {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onToggleVisibility()
                                } label: {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(category.isVisible ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                                            .frame(width: 7, height: 7)
                                        Text(category.isVisible ? Language.get("Visible", alter: "معروض") : Language.get("Hidden", alter: "مخفي"))
                                            .font(AdminType.caption2Bold)
                                            .foregroundColor(category.isVisible ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        (category.isVisible ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.1),
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !category.secondaryName.isEmpty {
                            Text(category.secondaryName)
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }

                        // Meta Badges: Breeds count & Sorting key
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(category.subKinds.count) " + Language.get("Breeds", alter: "سلالة"))
                                    .font(AdminType.caption2Bold)
                            }
                            .foregroundColor(AdminSurface.secondaryText)

                            Text("•")
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))

                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.and.down.text.horizontal")
                                    .font(.system(size: 10))
                                Text("ترتيب: \(category.sortingKey)")
                                    .font(AdminType.caption2)
                            }
                            .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(.top, 2)
                    }
                }

                // Card Footer Actions
                HStack(spacing: 8) {
                    // Expand/Collapse Breeds Inline Preview
                    Button {
                        onToggleExpand()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                            Text(isExpanded ? Language.get("Collapse", alter: "طي السلالات") : Language.get("Categories_Explore_Breeds", alter: "استعراض السلالات"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Delete Button
                    if canManage {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(uiColor: .ppError))
                                .frame(width: 34, height: 34)
                                .background(Color(uiColor: .ppError).opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    // Open Full Studio Button
                    Button {
                        onOpenStudio()
                    } label: {
                        HStack(spacing: 5) {
                            Text(Language.get("Categories_Open_Studio", alter: "استوديو الفصيلة"))
                                .font(AdminType.captionBold)
                            Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(category.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(AdminSpacing.cardPadding)

            // Inline Expanded Breeds Drawer
            if isExpanded {
                VStack(spacing: 6) {
                    Divider().background(AdminSurface.hairline)

                    if category.subKinds.isEmpty {
                        Text(Language.get("Categories_No_Breeds_Yet", alter: "لا توجد سلالات مسجلة لهذه الفصيلة بعد."))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(category.subKinds.prefix(6)) { sub in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(category.accentColor)
                                        .frame(width: 5, height: 5)

                                    Text(sub.localizedName)
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.primaryText)

                                    if !sub.secondaryName.isEmpty {
                                        Text("(\(sub.secondaryName))")
                                            .font(AdminType.caption2)
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }

                                    Spacer()

                                    if sub.haveSubSub == 1 {
                                        Text(Language.get("Categories_Has_SubSub", alter: "تفريعات فرعية"))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Color(uiColor: .ppInfo))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(uiColor: .ppInfo).opacity(0.12), in: Capsule())
                                    }

                                    if sub.haveItems == 1 {
                                        Text(Language.get("Categories_Has_Items", alter: "مواصفات وجنس"))
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Color(uiColor: .ppSuccess))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(uiColor: .ppSuccess).opacity(0.12), in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }

                            if category.subKinds.count > 6 {
                                Button {
                                    onOpenStudio()
                                } label: {
                                    Text(String(format: Language.get("Categories_View_All_Breeds", alter: "+ %ld سلالات أخرى... اضغط للمزيد"), category.subKinds.count - 6))
                                        .font(AdminType.caption2Bold)
                                        .foregroundColor(category.accentColor)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                        .padding(.horizontal, AdminSpacing.cardPadding)
                        .padding(.vertical, 8)
                    }
                }
                .background(AdminSurface.control.opacity(0.5))
            }
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
        )
    }
}

// MARK: - 6. Phylogenetic Tree Branch Component

struct AdminCategoryTreeBranch: View {
    let category: AdminCategoryItem
    @ObservedObject var viewModel: AdminCategoriesViewModel
    let onOpenStudio: () -> Void

    @State private var isExpanded: Bool = false
    @State private var subKinds: [AdminSubKindItem] = []
    @State private var listener: (any ListenerRegistration)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Tier 1 Root Node
            HStack(spacing: 10) {
                Button {
                    withAnimation(AdminAnimation.standard) {
                        isExpanded.toggle()
                        if isExpanded && listener == nil {
                            startSubKindsListener()
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : (Language.isRTL() ? "chevron.left.circle.fill" : "chevron.right.circle.fill"))
                        .font(.system(size: 20))
                        .foregroundColor(category.accentColor)
                }
                .buttonStyle(.plain)

                Image(systemName: category.iconName.isEmpty ? "pawprint.fill" : category.iconName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(category.accentColor)

                Text(category.localizedName)
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Text("\(category.subKinds.count) " + Language.get("Breeds", alter: "سلالة"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())

                Button {
                    onOpenStudio()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
            )

            // Nested Tier 2 Children
            if isExpanded {
                VStack(spacing: 6) {
                    if subKinds.isEmpty && category.subKinds.isEmpty {
                        Text(Language.get("Categories_No_Breeds", alter: "لا توجد سلالات مسجلة."))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(8)
                    } else {
                        let displayList = subKinds.isEmpty ? category.subKinds : subKinds
                        ForEach(displayList) { breed in
                            AdminSubKindTreeLeaf(
                                mainKindDocID: category.documentID,
                                breed: breed,
                                accentColor: category.accentColor,
                                viewModel: viewModel
                            )
                        }
                    }
                }
                .padding(.leading, Language.isRTL() ? 0 : 24)
                .padding(.trailing, Language.isRTL() ? 24 : 0)
                .padding(.top, 6)
            }
        }
        .onDisappear {
            listener?.remove()
        }
    }

    private func startSubKindsListener() {
        listener = viewModel.listenToSubKinds(for: category.documentID) { items in
            self.subKinds = items
        }
    }
}

struct AdminSubKindTreeLeaf: View {
    let mainKindDocID: String
    let breed: AdminSubKindItem
    let accentColor: Color
    @ObservedObject var viewModel: AdminCategoriesViewModel

    @State private var isSubSubExpanded: Bool = false
    @State private var subSubKinds: [AdminSubSubKindItem] = []
    @State private var listener: (any ListenerRegistration)? = nil

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                if breed.haveSubSub == 1 {
                    Button {
                        withAnimation(AdminAnimation.standard) {
                            isSubSubExpanded.toggle()
                            if isSubSubExpanded && listener == nil {
                                startListener()
                            }
                        }
                    } label: {
                        Image(systemName: isSubSubExpanded ? "chevron.down" : (Language.isRTL() ? "chevron.left" : "chevron.right"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Circle()
                        .fill(accentColor.opacity(0.5))
                        .frame(width: 4, height: 4)
                }

                Text(breed.localizedName)
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                if breed.haveSubSub == 1 {
                    Text("\(subSubKinds.count) " + Language.get("Strains", alter: "تفريعات"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(uiColor: .ppInfo))
                }

                if breed.haveItems == 1 {
                    Text(Language.get("Items", alter: "مواصفات"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(uiColor: .ppSuccess))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Level 3 Children
            if isSubSubExpanded {
                VStack(spacing: 4) {
                    ForEach(subSubKinds) { s in
                        HStack {
                            Image(systemName: "circle.grid.2x1.fill")
                                .font(.system(size: 9))
                                .foregroundColor(accentColor)
                            Text(s.localizedName)
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.leading, Language.isRTL() ? 0 : 20)
                .padding(.trailing, Language.isRTL() ? 20 : 0)
            }
        }
        .onDisappear {
            listener?.remove()
        }
    }

    private func startListener() {
        listener = viewModel.listenToSubSubKinds(mainKindDocID: mainKindDocID, subKindDocID: breed.id) { list in
            self.subSubKinds = list
        }
    }
}

// MARK: - 7. Flagship Category Studio: AdminCategoryStudioView (Tier 1 & Tier 2)

struct AdminCategoryStudioView: View {
    let category: AdminCategoryItem
    @ObservedObject var viewModel: AdminCategoriesViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Editable Draft State
    @State private var draftAr: String = ""
    @State private var draftEn: String = ""
    @State private var draftNumericID: Int = 0
    @State private var draftSortingKey: Int = 0
    @State private var draftIconName: String = ""
    @State private var draftImageUrl: String = ""
    @State private var draftLighten: Double = 0.25
    @State private var draftAngle: Double = 0.0
    @State private var draftIsVisible: Bool = true
    @State private var draftColorHex: String = ""

    // SubKinds (Level 2) Stream State
    @State private var subKindsList: [AdminSubKindItem] = []
    @State private var subKindsListener: (any ListenerRegistration)? = nil
    @State private var selectedSubKindForStudio: AdminSubKindItem? = nil
    @State private var isAddingBreedSheet: Bool = false
    @State private var editingBreedItem: AdminSubKindItem? = nil
    @State private var breedToDelete: AdminSubKindItem? = nil

    @State private var selectedTab: StudioTab = .subKinds
    @State private var isSaving: Bool = false

    enum StudioTab: String, CaseIterable, Identifiable {
        case subKinds = "subkinds"
        case appearance = "appearance"
        case identity = "identity"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .subKinds: return Language.get("Categories_Tab_SubKinds", alter: "السلالات والتفريعات")
            case .appearance: return Language.get("Categories_Tab_Appearance", alter: "محاكي المتجر والمظهر")
            case .identity: return Language.get("Categories_Tab_Identity", alter: "البيانات والحوكمة")
            }
        }

        var icon: String {
            switch self {
            case .subKinds: return "point.3.connected.trianglepath.dotted"
            case .appearance: return "paintpalette.fill"
            case .identity: return "slider.horizontal.3"
            }
        }
    }

    private let popularGlyphs: [String] = [
        "pawprint.fill", "bird.fill", "hare.fill", "tortoise.fill", "fish.fill",
        "ladybug.fill", "ant.fill", "crown.fill", "star.fill", "heart.fill"
    ]

    init(category: AdminCategoryItem, viewModel: AdminCategoriesViewModel, onDismiss: @escaping () -> Void) {
        self.category = category
        self.viewModel = viewModel
        self.onDismiss = onDismiss

        _draftAr = State(initialValue: category.nameAr)
        _draftEn = State(initialValue: category.nameEn)
        _draftNumericID = State(initialValue: category.numericID)
        _draftSortingKey = State(initialValue: category.sortingKey)
        _draftIconName = State(initialValue: category.iconName.isEmpty ? "pawprint.fill" : category.iconName)
        _draftImageUrl = State(initialValue: category.imageUrl)
        _draftLighten = State(initialValue: category.lightenAmount)
        _draftAngle = State(initialValue: category.professionalAngle)
        _draftIsVisible = State(initialValue: category.isVisible)
        _draftColorHex = State(initialValue: category.colorHex)
    }

    var builtDraft: AdminCategoryItem {
        AdminCategoryItem(
            documentID: category.documentID,
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
            subKinds: subKindsList,
            colorHex: draftColorHex
        )
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                AdminSovereignNavigationBar(
                    title: draftAr.isEmpty ? category.localizedName : draftAr,
                    subtitle: String(format: Language.get("Categories_Breeds_Count", alter: "%ld سلالة موثقة"), subKindsList.count),
                    statusDotColor: Color(uiColor: .ppSuccess),
                    onBack: {
                        onDismiss()
                        dismiss()
                    }
                ) {
                    AdminPrimaryPillButton(
                        title: Language.get("Save", alter: "حفظ"),
                        systemImage: "checkmark",
                        isLoading: isSaving
                    ) {
                        saveChanges()
                    }
                }

                // Studio Tab Matrix
                tabSegmentedControl
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.xs)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        switch selectedTab {
                        case .subKinds:
                            subKindsWorkbenchSection
                        case .appearance:
                            appearanceStudioSection
                        case .identity:
                            identityGovernanceSection
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }

            // Push to SubKind Studio Link
            NavigationLink(
                destination: Group {
                    if let sub = selectedSubKindForStudio {
                        AdminSubKindStudioView(
                            mainKindDocID: category.documentID,
                            subKind: sub,
                            viewModel: viewModel,
                            onDismiss: {
                                selectedSubKindForStudio = nil
                            }
                        )
                    }
                },
                isActive: Binding(
                    get: { selectedSubKindForStudio != nil },
                    set: { if !$0 { selectedSubKindForStudio = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $isAddingBreedSheet) {
            let nextSubID = (subKindsList.map { $0.numericID }.max() ?? 0) + 1
            AdminSubKindEditorSheet(
                subKind: AdminSubKindItem(
                    id: "\(nextSubID)",
                    numericID: nextSubID,
                    mainKindID: category.numericID,
                    nameAr: "",
                    nameEn: "",
                    iconUrl: "",
                    iconName: "",
                    imageName: "",
                    adultHood: 12,
                    haveSubSub: 0,
                    haveItems: 0
                ),
                isNew: true,
                onSave: { newBreed in
                    viewModel.saveSubKind(mainKindDocID: category.documentID, subKind: newBreed, isNew: true) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            isAddingBreedSheet = false
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                }
            )
        }
        .sheet(item: $editingBreedItem) { breed in
            AdminSubKindEditorSheet(
                subKind: breed,
                isNew: false,
                onSave: { updatedBreed in
                    viewModel.saveSubKind(mainKindDocID: category.documentID, subKind: updatedBreed, isNew: false) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            editingBreedItem = nil
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                }
            )
        }
        .confirmationDialog(
            Language.get("SubKind_Delete_Confirm_Title", alter: "تأكيد حذف السلالة"),
            isPresented: Binding(get: { breedToDelete != nil }, set: { if !$0 { breedToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let breed = breedToDelete {
                Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                    viewModel.deleteSubKind(mainKindDocID: category.documentID, subKind: breed) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                        breedToDelete = nil
                    }
                }
                Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                    breedToDelete = nil
                }
            }
        } message: {
            if let breed = breedToDelete {
                Text(String(format: Language.get("SubKind_Delete_Confirm_Body", alter: "هل أنت متأكد من حذف سلالة \"%@\" نهائياً؟"), breed.localizedName))
            }
        }
        .onAppear {
            startListeningSubKinds()
        }
        .onDisappear {
            subKindsListener?.remove()
        }
    }

    private func startListeningSubKinds() {
        subKindsList = category.subKinds
        subKindsListener = viewModel.listenToSubKinds(for: category.documentID) { items in
            self.subKindsList = items
        }
    }

    private func saveChanges() {
        isSaving = true
        viewModel.saveCategory(builtDraft, isNew: false) { success, msg in
            isSaving = false
            if success {
                viewModel.showToast(msg ?? "")
            } else {
                viewModel.showToast(msg ?? "", isError: true)
            }
        }
    }

    // MARK: - Tab Segmented Matrix

    private var tabSegmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(StudioTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(AdminAnimation.fast) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        Text(tab.title)
                            .font(isSelected ? AdminType.captionBold : AdminType.caption)
                    }
                    .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        isSelected ? AdminSurface.surface : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? AdminSurface.hairline : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - SubKinds Workbench (Tab 1)

    private var subKindsWorkbenchSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Categories_SubKinds_List_Title", alter: "السلالات والأنواع الفرعية"))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Categories_SubKinds_List_Sub", alter: "اضغط على السلالة لإدارة تفريعاتها الدقيقة ومواصفاتها."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                if viewModel.canManage {
                    AdminPrimaryPillButton(
                        title: Language.get("Categories_Add_SubKind", alter: "إضافة سلالة"),
                        systemImage: "plus"
                    ) {
                        isAddingBreedSheet = true
                    }
                }
            }

            if subKindsList.isEmpty {
                VStack(spacing: AdminSpacing.sm) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                    Text(Language.get("Categories_No_Breeds_Registered", alter: "لا توجد سلالات مضافة لهذه الفصيلة بعد"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Categories_Add_First_Breed", alter: "أضف السلالة الأولى لتمكين المستهلكين من تصفحها."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(subKindsList) { breed in
                        breedRowView(breed)
                    }
                }
            }
        }
    }

    private func breedRowView(_ breed: AdminSubKindItem) -> some View {
        HStack(spacing: 12) {
            // Breed Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .ppPrimary).opacity(0.12))
                    .frame(width: 44, height: 44)

                if !breed.iconUrl.isEmpty, let url = URL(string: breed.iconUrl) {
                    AdminRemoteImage(url: url, contentMode: .fit, targetSize: CGSize(width: 44, height: 44)) {
                        Color.clear
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(uiColor: .ppPrimary))
                }
            }

            // Breed Titles & Capabilities
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(breed.localizedName)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)

                    Text("#\(breed.numericID)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AdminSurface.control, in: Capsule())
                }

                if !breed.secondaryName.isEmpty {
                    Text(breed.secondaryName)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                HStack(spacing: 6) {
                    Text(String(format: Language.get("Categories_Breed_Adulthood", alter: "سن البلوغ: %ld شهر"), breed.adultHood))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)

                    if breed.haveSubSub == 1 {
                        Text("•")
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                        Text(Language.get("Categories_Has_SubSub", alter: "تفريعات فرعية"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppInfo))
                    }

                    if breed.haveItems == 1 {
                        Text("•")
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                        Text(Language.get("Categories_Has_Items", alter: "مواصفات وجنس"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(uiColor: .ppSuccess))
                    }
                }
                .padding(.top, 2)
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                if viewModel.canManage {
                    Button {
                        editingBreedItem = breed
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 32, height: 32)
                            .background(AdminSurface.control, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        breedToDelete = breed
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(uiColor: .ppError))
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .ppError).opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    selectedSubKindForStudio = breed
                } label: {
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
        )
    }

    // MARK: - Appearance Studio (Tab 2)

    private var appearanceStudioSection: some View {
        VStack(spacing: AdminSpacing.md) {
            // Real-time Storefront Simulator Preview
            storefrontSimulatorPreview

            // Icon & SF Symbol Chooser
            iconSelectorCard

            // Professional Angle & Lighten Sliders
            visualPhysicsCard
        }
    }

    private var storefrontSimulatorPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(builtDraft.accentColor)
                Text(Language.get("Categories_Simulator_Title", alter: "محاكي المظهر بالمتجر الاستهلاكي"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text(draftIsVisible ? Language.get("Visible", alter: "معروض") : Language.get("Hidden", alter: "مخفي"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(draftIsVisible ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((draftIsVisible ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.12), in: Capsule())
            }

            // Consumer Card Replica
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(builtDraft.accentColor.opacity(draftLighten))
                        .frame(width: 80, height: 80)

                    if !draftImageUrl.isEmpty, let url = URL(string: draftImageUrl) {
                        AdminRemoteImage(url: url, contentMode: .fit, targetSize: CGSize(width: 80, height: 80)) {
                            Color.clear
                        }
                        .frame(width: 60, height: 60)
                    } else {
                        Image(systemName: draftIconName)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(builtDraft.accentColor)
                            .rotationEffect(.degrees(draftAngle))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(draftAr.isEmpty ? "اسم الفصيلة" : draftAr)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(draftEn.isEmpty ? "Species Name" : draftEn)
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.secondaryText)

                    Text(String(format: Language.get("Categories_Simulator_Breeds", alter: "يحتوي %ld سلالة موثقة"), subKindsList.count))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(builtDraft.accentColor)
                        .padding(.top, 2)
                }

                Spacer()
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }

    private var iconSelectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("Categories_Icon_And_Symbol", alter: "أيقونة ومظهر الفصيلة"))
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)

            // Preset Glyphs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(popularGlyphs, id: \.self) { glyph in
                        let isSelected = draftIconName == glyph
                        Button {
                            withAnimation(AdminAnimation.fast) {
                                draftIconName = glyph
                            }
                        } label: {
                            Image(systemName: glyph)
                                .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                .frame(width: 44, height: 44)
                                .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isSelected ? Color.clear : AdminSurface.hairline)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Categories_Custom_Symbol_Or_Url", alter: "اسم أيقونة مخصصة (SF Symbol) أو رابط صورة"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)

                HStack(spacing: 8) {
                    TextField("pawprint.fill", text: $draftIconName)
                        .font(AdminType.callout)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("https://...", text: $draftImageUrl)
                        .font(AdminType.callout)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }

    private var visualPhysicsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Language.get("Categories_Physics_Controls", alter: "معايير زاوية العرض والسطوع"))
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)

            // Professional Angle Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Language.get("Categories_Angle", alter: "زاوية الميل الاحترافية"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text("\(Int(draftAngle))°")
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                Slider(value: $draftAngle, in: -45...45, step: 1)
                    .tint(AdminSurface.primary)
            }

            // Lighten Amount Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Language.get("Categories_Lighten", alter: "درجة إضاءة الخلفية"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text("\(Int(draftLighten * 100))%")
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                }
                Slider(value: $draftLighten, in: 0.05...0.6, step: 0.05)
                    .tint(AdminSurface.primary)
            }

            // Color Hex
            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Categories_Color_Hex", alter: "كود اللون (HEX)"))
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: draftColorHex))
                        .frame(width: 24, height: 24)

                    TextField("#4A90E2", text: $draftColorHex)
                        .font(AdminType.callout)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }

    // MARK: - Identity & Governance (Tab 3)

    private var identityGovernanceSection: some View {
        VStack(spacing: AdminSpacing.md) {
            // Naming & Identification Card
            VStack(alignment: .leading, spacing: 12) {
                Text(Language.get("Categories_Identity_Title", alter: "بيانات الهوية والتسمية"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)

                VStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Category_NameAr", alter: "الاسم بالعربية"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        TextField("اسم الفصيلة", text: $draftAr)
                            .font(AdminType.callout)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Category_NameEn", alter: "الاسم بالإنجليزية"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                        TextField("Species English Name", text: $draftEn)
                            .font(AdminType.callout)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("Category_NumericID", alter: "المعرف الرقمي (ID)"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.secondaryText)
                            Text("\(draftNumericID)")
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("Category_SortingKey", alter: "مفتاح الترتيب"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.secondaryText)
                            TextField("1", value: $draftSortingKey, formatter: NumberFormatter())
                                .font(AdminType.callout)
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                        }
                    }
                }
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

            // Visibility & Consumer State Card
            VStack(alignment: .leading, spacing: 10) {
                Text(Language.get("Categories_Storefront_Governance", alter: "حوكمة الظهور بالمتجر"))
                    .font(AdminType.calloutBold)
                    .foregroundColor(AdminSurface.primaryText)

                Toggle(isOn: $draftIsVisible) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Categories_Visibility_Toggle", alter: "ظهور التصنيف للمستهلكين"))
                            .font(AdminType.callout)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("Categories_Visibility_Subtitle", alter: "عند التعطيل، يختفي التصنيف وجميع سلالاته من شاشات المستخدم."))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                .tint(AdminSurface.primary)
            }
            .padding(AdminSpacing.cardPadding)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
        }
    }
}

// MARK: - 8. Flagship Breed & SubSubKind Studio: AdminSubKindStudioView (Tier 2 & Tier 3)

@MainActor
struct AdminSubKindStudioView: View {
    let mainKindDocID: String
    let subKind: AdminSubKindItem
    @ObservedObject var viewModel: AdminCategoriesViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Editable Breed State
    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var iconUrl: String = ""
    @State private var adultMonths: Int = 12
    @State private var haveSubSub: Int = 0
    @State private var haveItems: Int = 0
    @State private var isSaving: Bool = false

    // SubSubKinds (Level 3) Stream State
    @State private var subSubKindsList: [AdminSubSubKindItem] = []
    @State private var subSubListener: (any ListenerRegistration)? = nil
    @State private var selectedSubSubForStudio: AdminSubSubKindItem? = nil
    @State private var isAddingSubSubSheet: Bool = false
    @State private var editingSubSubItem: AdminSubSubKindItem? = nil
    @State private var subSubToDelete: AdminSubSubKindItem? = nil

    init(mainKindDocID: String, subKind: AdminSubKindItem, viewModel: AdminCategoriesViewModel, onDismiss: @escaping () -> Void) {
        self.mainKindDocID = mainKindDocID
        self.subKind = subKind
        self.viewModel = viewModel
        self.onDismiss = onDismiss

        _nameAr = State(initialValue: subKind.nameAr)
        _nameEn = State(initialValue: subKind.nameEn)
        _iconUrl = State(initialValue: subKind.iconUrl)
        _adultMonths = State(initialValue: subKind.adultHood)
        _haveSubSub = State(initialValue: subKind.haveSubSub)
        _haveItems = State(initialValue: subKind.haveItems)
    }

    var builtBreed: AdminSubKindItem {
        var copy = subKind
        copy.nameAr = nameAr
        copy.nameEn = nameEn
        copy.iconUrl = iconUrl
        copy.adultHood = adultMonths
        copy.haveSubSub = haveSubSub
        copy.haveItems = haveItems
        return copy
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                AdminSovereignNavigationBar(
                    title: nameAr.isEmpty ? subKind.localizedName : nameAr,
                    subtitle: String(format: Language.get("Categories_SubSub_Count", alter: "%ld تفريع فرعي"), subSubKindsList.count),
                    statusDotColor: Color(uiColor: .ppSuccess),
                    onBack: {
                        onDismiss()
                        dismiss()
                    }
                ) {
                    AdminPrimaryPillButton(
                        title: Language.get("Save", alter: "حفظ"),
                        systemImage: "checkmark",
                        isLoading: isSaving
                    ) {
                        saveBreedChanges()
                    }
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        // Breadcrumb Indicator
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                            Text("الفصيلة: \(mainKindDocID)")
                                .font(AdminType.caption2Bold)
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                            Text("السلالة: \(subKind.localizedName)")
                                .font(AdminType.caption2Bold)
                            Spacer()
                        }
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 4)

                        // Breed Properties Card
                        breedDetailsCard

                        // SubSubKinds (Level 3) Manager
                        subSubKindsManagerSection
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }

            // Push to Level 4 Items Studio Link
            NavigationLink(
                destination: Group {
                    if let s = selectedSubSubForStudio {
                        AdminSubSubKindStudioView(
                            mainKindDocID: mainKindDocID,
                            subKindDocID: subKind.id,
                            subSubKind: s,
                            viewModel: viewModel,
                            onDismiss: {
                                selectedSubSubForStudio = nil
                            }
                        )
                    }
                },
                isActive: Binding(
                    get: { selectedSubSubForStudio != nil },
                    set: { if !$0 { selectedSubSubForStudio = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $isAddingSubSubSheet) {
            let nextID = (subSubKindsList.map { $0.numericID }.max() ?? 0) + 1
            AdminSubSubKindEditorSheet(
                subSub: AdminSubSubKindItem(
                    id: "\(nextID)",
                    numericID: nextID,
                    subKindID: subKind.numericID,
                    nameAr: "",
                    nameEn: ""
                ),
                isNew: true,
                onSave: { newSubSub in
                    viewModel.saveSubSubKind(
                        mainKindDocID: mainKindDocID,
                        subKindDocID: subKind.id,
                        subSub: newSubSub,
                        isNew: true
                    ) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            isAddingSubSubSheet = false
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                }
            )
        }
        .sheet(item: $editingSubSubItem) { item in
            AdminSubSubKindEditorSheet(
                subSub: item,
                isNew: false,
                onSave: { updated in
                    viewModel.saveSubSubKind(
                        mainKindDocID: mainKindDocID,
                        subKindDocID: subKind.id,
                        subSub: updated,
                        isNew: false
                    ) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            editingSubSubItem = nil
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                }
            )
        }
        .confirmationDialog(
            Language.get("SubSub_Delete_Confirm_Title", alter: "تأكيد حذف التفريع"),
            isPresented: Binding(get: { subSubToDelete != nil }, set: { if !$0 { subSubToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let subSub = subSubToDelete {
                Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                    viewModel.deleteSubSubKind(mainKindDocID: mainKindDocID, subKindDocID: subKind.id, subSub: subSub) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                        subSubToDelete = nil
                    }
                }
                Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                    subSubToDelete = nil
                }
            }
        } message: {
            if let s = subSubToDelete {
                Text(String(format: Language.get("SubSub_Delete_Confirm_Body", alter: "هل أنت متأكد من حذف تفريع \"%@\" نهائياً؟"), s.localizedName))
            }
        }
        .onAppear {
            startListeningSubSub()
        }
        .onDisappear {
            subSubListener?.remove()
        }
    }

    private func startListeningSubSub() {
        subSubListener = viewModel.listenToSubSubKinds(mainKindDocID: mainKindDocID, subKindDocID: subKind.id) { items in
            self.subSubKindsList = items
        }
    }

    private func saveBreedChanges() {
        isSaving = true
        viewModel.saveSubKind(mainKindDocID: mainKindDocID, subKind: builtBreed, isNew: false) { success, msg in
            isSaving = false
            if success {
                viewModel.showToast(msg ?? "")
            } else {
                viewModel.showToast(msg ?? "", isError: true)
            }
        }
    }

    // MARK: - Breed Details Card

    private var breedDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("Categories_Breed_Properties", alter: "خصائص وبيانات السلالة"))
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)

            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Categories_Breed_NameAr", alter: "اسم السلالة (عربي)"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    TextField("اسم السلالة", text: $nameAr)
                        .font(AdminType.callout)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Categories_Breed_NameEn", alter: "اسم السلالة (إنجليزي)"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)
                    TextField("Breed English Name", text: $nameEn)
                        .font(AdminType.callout)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                }

                // Adulthood Months Stepper
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Categories_Adulthood", alter: "سن البلوغ"))
                            .font(AdminType.callout)
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("Categories_Adulthood_Sub", alter: "عمر اكتمال نمو السلالة بالأشهر"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button {
                            if adultMonths > 1 { adultMonths -= 1 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(AdminSurface.control, in: Circle())
                        }

                        Text("\(adultMonths) " + Language.get("Months", alter: "شهر"))
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)

                        Button {
                            adultMonths += 1
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(AdminSurface.control, in: Circle())
                        }
                    }
                }
                .padding(.vertical, 4)

                // Capability Toggles
                VStack(spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { haveSubSub == 1 },
                        set: { haveSubSub = $0 ? 1 : 0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Categories_Enable_SubSub", alter: "تفعيل التفريعات الفرعية (SubSubKinds)"))
                                .font(AdminType.callout)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("Categories_Enable_SubSub_Sub", alter: "تتيح تقسيم السلالة إلى خطوط إنتاج أو فئات دقيقة."))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .tint(AdminSurface.primary)

                    Toggle(isOn: Binding(
                        get: { haveItems == 1 },
                        set: { haveItems = $0 ? 1 : 0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Categories_Enable_Items", alter: "تفعيل المواصفات والعناصر (Items)"))
                                .font(AdminType.callout)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("Categories_Enable_Items_Sub", alter: "تتيح إدارة خصائص الذكر والأنثى والمواصفات."))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .tint(Color(uiColor: .ppSuccess))
                }
                .padding(.top, 4)
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
    }

    // MARK: - SubSubKinds Manager Section

    private var subSubKindsManagerSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Categories_SubSub_Title", alter: "التفريعات الفرعية الدقيقة"))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Categories_SubSub_Description", alter: "المستوى الثالث في شجرة التصنيف (SubSubKinds)."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                if viewModel.canManage {
                    AdminPrimaryPillButton(
                        title: Language.get("Categories_Add_SubSub", alter: "إضافة تفريع"),
                        systemImage: "plus"
                    ) {
                        isAddingSubSubSheet = true
                    }
                }
            }

            if subSubKindsList.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "circle.grid.2x1.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                    Text(Language.get("Categories_No_SubSub_Yet", alter: "لا توجد تفريعات فرعية بعد."))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Categories_SubSub_Hint", alter: "اضغط على زر الإضافة لإنشاء تفريع جديد."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(subSubKindsList) { item in
                        subSubRowView(item)
                    }
                }
            }
        }
    }

    private func subSubRowView(_ item: AdminSubSubKindItem) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(uiColor: .ppInfo))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.localizedName)
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text("#\(item.numericID)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundColor(AdminSurface.secondaryText)
                }

                if !item.secondaryName.isEmpty {
                    Text(item.secondaryName)
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            Spacer()

            if viewModel.canManage {
                Button {
                    editingSubSubItem = item
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    subSubToDelete = item
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(uiColor: .ppError))
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .ppError).opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Drill down to Level 4 (Items)
            Button {
                selectedSubSubForStudio = item
            } label: {
                HStack(spacing: 4) {
                    Text(Language.get("Categories_Items_Traits", alter: "المواصفات"))
                        .font(AdminType.captionBold)
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color(uiColor: .ppInfo), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
    }
}

// MARK: - 9. Flagship Sub-Variety & Items Studio: AdminSubSubKindStudioView (Tier 3 & Tier 4)

@MainActor
struct AdminSubSubKindStudioView: View {
    let mainKindDocID: String
    let subKindDocID: String
    let subSubKind: AdminSubSubKindItem
    @ObservedObject var viewModel: AdminCategoriesViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var isSaving: Bool = false

    // Items (Level 4) Stream State
    @State private var itemsList: [AdminSubKindItemDetail] = []
    @State private var itemsListener: (any ListenerRegistration)? = nil
    @State private var isAddingItemSheet: Bool = false
    @State private var editingDetailItem: AdminSubKindItemDetail? = nil
    @State private var itemToDelete: AdminSubKindItemDetail? = nil

    init(mainKindDocID: String, subKindDocID: String, subSubKind: AdminSubSubKindItem, viewModel: AdminCategoriesViewModel, onDismiss: @escaping () -> Void) {
        self.mainKindDocID = mainKindDocID
        self.subKindDocID = subKindDocID
        self.subSubKind = subSubKind
        self.viewModel = viewModel
        self.onDismiss = onDismiss

        _nameAr = State(initialValue: subSubKind.nameAr)
        _nameEn = State(initialValue: subSubKind.nameEn)
    }

    var builtSubSub: AdminSubSubKindItem {
        var copy = subSubKind
        copy.nameAr = nameAr
        copy.nameEn = nameEn
        return copy
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                AdminSovereignNavigationBar(
                    title: nameAr.isEmpty ? subSubKind.localizedName : nameAr,
                    subtitle: String(format: Language.get("Categories_Items_Count", alter: "%ld مواصفة / عنصر"), itemsList.count),
                    statusDotColor: Color(uiColor: .ppSuccess),
                    onBack: {
                        onDismiss()
                        dismiss()
                    }
                ) {
                    AdminPrimaryPillButton(
                        title: Language.get("Save", alter: "حفظ"),
                        systemImage: "checkmark",
                        isLoading: isSaving
                    ) {
                        saveSubSubChanges()
                    }
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.sectionSpacing) {
                        // SubSub Names Card
                        VStack(alignment: .leading, spacing: AdminSpacing.md) {
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AdminSurface.primary)
                                Text(Language.get("Categories_SubSub_Identity", alter: "بيانات التفريع الفرعي"))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                            }

                            VStack(spacing: AdminSpacing.sm) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameAr", alter: "الاسم بالعربية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("اسم التفريع", text: $nameAr)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 14)
                                        .frame(height: 44)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameEn", alter: "الاسم بالإنجليزية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("Strain English Name", text: $nameEn)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 14)
                                        .frame(height: 44)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).stroke(AdminSurface.hairline))
                                }
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

                        // Items (Level 4) Section
                        itemsManagementSection
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $isAddingItemSheet) {
            let nextID = (itemsList.map { $0.numericID }.max() ?? 0) + 1
            AdminItemEditorSheet(
                item: AdminSubKindItemDetail(
                    id: "\(nextID)",
                    numericID: nextID,
                    subSubKindID: subSubKind.numericID,
                    itemNameAr: "",
                    itemNameEn: "",
                    male: "",
                    female: ""
                ),
                isNew: true,
                onSave: { newItem in
                    viewModel.saveItem(
                        mainKindDocID: mainKindDocID,
                        subKindDocID: subKindDocID,
                        subSubDocID: subSubKind.id,
                        item: newItem,
                        isNew: true
                    ) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            isAddingItemSheet = false
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                }
            )
        }
        .sheet(item: $editingDetailItem) { itm in
            AdminItemEditorSheet(
                item: itm,
                isNew: false,
                onSave: { updated in
                    viewModel.saveItem(
                        mainKindDocID: mainKindDocID,
                        subKindDocID: subKindDocID,
                        subSubDocID: subSubKind.id,
                        item: updated,
                        isNew: false
                    ) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                            editingDetailItem = nil
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                    }
                }
            )
        }
        .confirmationDialog(
            Language.get("Item_Delete_Confirm_Title", alter: "تأكيد حذف العنصر والمواصفة"),
            isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let itm = itemToDelete {
                Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                    viewModel.deleteItem(mainKindDocID: mainKindDocID, subKindDocID: subKindDocID, subSubDocID: subSubKind.id, item: itm) { success, msg in
                        if success {
                            viewModel.showToast(msg ?? "")
                        } else {
                            viewModel.showToast(msg ?? "", isError: true)
                        }
                        itemToDelete = nil
                    }
                }
                Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                    itemToDelete = nil
                }
            }
        } message: {
            if let itm = itemToDelete {
                Text(String(format: Language.get("Item_Delete_Confirm_Body", alter: "هل أنت متأكد من حذف مواصفة \"%@\" نهائياً؟"), itm.localizedName))
            }
        }
        .onAppear {
            startListeningItems()
        }
        .onDisappear {
            itemsListener?.remove()
        }
    }

    private func startListeningItems() {
        itemsListener = viewModel.listenToItems(mainKindDocID: mainKindDocID, subKindDocID: subKindDocID, subSubDocID: subSubKind.id) { list in
            self.itemsList = list
        }
    }

    private func saveSubSubChanges() {
        isSaving = true
        viewModel.saveSubSubKind(mainKindDocID: mainKindDocID, subKindDocID: subKindDocID, subSub: builtSubSub, isNew: false) { success, msg in
            isSaving = false
            if success {
                viewModel.showToast(msg ?? "")
            } else {
                viewModel.showToast(msg ?? "", isError: true)
            }
        }
    }

    // MARK: - Items Management Section (Level 4)

    private var itemsManagementSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Categories_Items_Traits_Title", alter: "المواصفات وخصائص الجنسين"))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Categories_Items_Traits_Sub", alter: "المستوى الرابع في شجرة التصنيف (Items: الذكر والأنثى)."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                if viewModel.canManage {
                    AdminPrimaryPillButton(
                        title: Language.get("Categories_Add_Item", alter: "إضافة مواصفة"),
                        systemImage: "plus"
                    ) {
                        isAddingItemSheet = true
                    }
                }
            }

            if itemsList.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                    Text(Language.get("Categories_No_Items_Yet", alter: "لا توجد مواصفات أو عناصر بعد."))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Categories_Items_Hint", alter: "أضف مواصفات مثل جاهزية الإنتاج، العمر، صفات الذكر والأنثى."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(itemsList) { item in
                        itemDetailCard(item)
                    }
                }
            }
        }
    }

    private func itemDetailCard(_ item: AdminSubKindItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.localizedName)
                            .font(AdminType.calloutBold)
                            .foregroundColor(AdminSurface.primaryText)
                        Text("#\(item.numericID)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    if !item.secondaryName.isEmpty {
                        Text(item.secondaryName)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                if viewModel.canManage {
                    Button {
                        editingDetailItem = item
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(width: 32, height: 32)
                            .background(AdminSurface.control, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        itemToDelete = item
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(uiColor: .ppError))
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .ppError).opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Gender Attributes Split Card
            HStack(spacing: 8) {
                // Male Traits
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(uiColor: .ppInfo))
                        Text(Language.get("Male", alter: "الذكر"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(uiColor: .ppInfo))
                    }

                    Text(item.male.isEmpty ? "—" : item.male)
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .ppInfo).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                // Female Traits
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(uiColor: .ppWarning))
                        Text(Language.get("Female", alter: "الأنثى"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(Color(uiColor: .ppWarning))
                    }

                    Text(item.female.isEmpty ? "—" : item.female)
                        .font(AdminType.caption1)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .ppWarning).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
    }
}

// MARK: - 10. Sovereign Category Create Sheet

struct AdminCategoryCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let nextNumericID: Int
    let onSave: (AdminCategoryItem) -> Void

    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var iconName: String = "pawprint.fill"
    @State private var imageUrl: String = ""
    @State private var lighten: Double = 0.25
    @State private var angle: Double = 0.0
    @State private var isVisible: Bool = true
    @State private var colorHex: String = "#4A90E2"

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                AdminSovereignNavigationBar(
                    title: Language.get("Category_New", alter: "فصيلة وتصنيف جديد"),
                    subtitle: Language.get("Category_New_Sub", alter: "المستوى الأول في شجرة التصنيف (Species)"),
                    isModal: true,
                    onBack: { dismiss() }
                ) {
                    AdminPrimaryPillButton(
                        title: Language.get("Create", alter: "إنشاء"),
                        systemImage: "plus"
                    ) {
                        let item = AdminCategoryItem(
                            documentID: "\(nextNumericID)",
                            numericID: nextNumericID,
                            sortingKey: nextNumericID,
                            nameAr: nameAr,
                            nameEn: nameEn,
                            iconName: iconName,
                            imageName: "",
                            imageUrl: imageUrl,
                            lightenAmount: lighten,
                            professionalAngle: angle,
                            isVisible: isVisible,
                            subKinds: [],
                            colorHex: colorHex
                        )
                        onSave(item)
                    }
                    .disabled(nameAr.trimmingCharacters(in: .whitespaces).isEmpty && nameEn.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // Identity Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Category_Identity", alter: "الهوية والمُعرّفات"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameAr", alter: "الاسم بالعربية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("مثال: الكلاب، القطط، الطيور", text: $nameAr)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameEn", alter: "الاسم بالإنجليزية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("e.g. Dogs, Cats, Birds", text: $nameEn)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }

                                HStack {
                                    Text(Language.get("Category_NumericID", alter: "المعرف الرقمي المقترح"))
                                        .font(AdminType.caption)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    Spacer()
                                    Text("#\(nextNumericID)")
                                        .font(AdminType.calloutBold)
                                        .foregroundColor(AdminSurface.primary)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

                        // Appearance Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Category_Appearance", alter: "المظهر والأيقونة واللون"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_IconName", alter: "أيقونة SF Symbol"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("pawprint.fill", text: $iconName)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_ImageURL", alter: "رابط الصورة (URL)"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("https://...", text: $imageUrl)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_ColorHex", alter: "لون التمييز (HEX)"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(hex: colorHex))
                                            .frame(width: 24, height: 24)
                                        TextField("#4A90E2", text: $colorHex)
                                            .font(AdminType.callout)
                                            .padding(.horizontal, 12)
                                            .frame(height: 42)
                                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                    }
                                }
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

                        // Visibility Toggle Card
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: $isVisible) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Language.get("Categories_Visibility", alter: "ظهور التصنيف بالمتجر فور الإنشاء"))
                                        .font(AdminType.calloutBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                    Text(Language.get("Categories_Visibility_Notice", alter: "سيكون متاحاً لجميع مستخدمي التطبيق الاستهلاكي."))
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                            }
                            .tint(AdminSurface.primary)
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - 11. Sovereign SubKind (Breed) Editor Sheet

@MainActor
struct AdminSubKindEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let subKind: AdminSubKindItem
    let isNew: Bool
    let onSave: (AdminSubKindItem) -> Void

    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var iconUrl: String = ""
    @State private var adultMonths: Int = 12
    @State private var haveSubSub: Int = 0
    @State private var haveItems: Int = 0

    init(subKind: AdminSubKindItem, isNew: Bool, onSave: @escaping (AdminSubKindItem) -> Void) {
        self.subKind = subKind
        self.isNew = isNew
        self.onSave = onSave

        _nameAr = State(initialValue: subKind.nameAr)
        _nameEn = State(initialValue: subKind.nameEn)
        _iconUrl = State(initialValue: subKind.iconUrl)
        _adultMonths = State(initialValue: subKind.adultHood)
        _haveSubSub = State(initialValue: subKind.haveSubSub)
        _haveItems = State(initialValue: subKind.haveItems)
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                AdminSovereignNavigationBar(
                    title: isNew ? Language.get("Categories_Add_SubKind", alter: "إضافة سلالة جديدة") : Language.get("Categories_Edit_SubKind", alter: "تعديل السلالة"),
                    subtitle: Language.get("Categories_SubKind_Level2", alter: "المستوى الثاني في شجرة التصنيف (Breeds)"),
                    isModal: true,
                    onBack: { dismiss() }
                ) {
                    AdminPrimaryPillButton(
                        title: Language.get("Save", alter: "حفظ"),
                        systemImage: "checkmark"
                    ) {
                        var copy = subKind
                        copy.nameAr = nameAr
                        copy.nameEn = nameEn
                        copy.iconUrl = iconUrl
                        copy.adultHood = adultMonths
                        copy.haveSubSub = haveSubSub
                        copy.haveItems = haveItems
                        onSave(copy)
                    }
                    .disabled(nameAr.trimmingCharacters(in: .whitespaces).isEmpty && nameEn.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // Names Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Category_Names", alter: "الأسماء واللغات"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Categories_SubKind_NameAr", alter: "اسم السلالة (عربي)"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("مثال: هاسكي سيبيري، شيواوا", text: $nameAr)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Categories_SubKind_NameEn", alter: "اسم السلالة (إنجليزي)"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("e.g. Siberian Husky", text: $nameEn)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

                        // Properties Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Categories_SubKind_Properties", alter: "خصائص السلالة ومظهرها"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 8) {
                                // Adulthood
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Language.get("Categories_SubKind_AdultMonths", alter: "سن البلوغ"))
                                            .font(AdminType.callout)
                                            .foregroundColor(AdminSurface.primaryText)
                                        Text(Language.get("Categories_Adulthood_Sub", alter: "عمر اكتمال نمو السلالة بالأشهر"))
                                            .font(AdminType.caption2)
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }

                                    Spacer()

                                    HStack(spacing: 12) {
                                        Button {
                                            if adultMonths > 1 { adultMonths -= 1 }
                                        } label: {
                                            Image(systemName: "minus")
                                                .font(.system(size: 12, weight: .bold))
                                                .frame(width: 30, height: 30)
                                                .background(AdminSurface.control, in: Circle())
                                        }

                                        Text("\(adultMonths) " + Language.get("Months", alter: "شهر"))
                                            .font(AdminType.calloutBold)
                                            .foregroundColor(AdminSurface.primaryText)

                                        Button {
                                            adultMonths += 1
                                        } label: {
                                            Image(systemName: "plus")
                                                .font(.system(size: 12, weight: .bold))
                                                .frame(width: 30, height: 30)
                                                .background(AdminSurface.control, in: Circle())
                                        }
                                    }
                                }
                                .padding(.vertical, 4)

                                // Icon URL
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Categories_SubKind_IconUrl", alter: "رابط الأيقونة (URL)"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("https://...", text: $iconUrl)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

                        // Capabilities Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Categories_SubKind_Capabilities", alter: "إمكانيات وتفريعات السلالة"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 10) {
                                Toggle(isOn: Binding(
                                    get: { haveSubSub == 1 },
                                    set: { haveSubSub = $0 ? 1 : 0 }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Language.get("Categories_Have_SubSub", alter: "تحتوي تفريعات فرعية (SubSubKinds)"))
                                            .font(AdminType.callout)
                                            .foregroundColor(AdminSurface.primaryText)
                                        Text(Language.get("Categories_Have_SubSub_Sub", alter: "تفعيل المستوى الثالث لهذه السلالة."))
                                            .font(AdminType.caption2)
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                                .tint(AdminSurface.primary)

                                Toggle(isOn: Binding(
                                    get: { haveItems == 1 },
                                    set: { haveItems = $0 ? 1 : 0 }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(Language.get("Categories_Have_Items", alter: "تحتوي مواصفات وعناصر (Items)"))
                                            .font(AdminType.callout)
                                            .foregroundColor(AdminSurface.primaryText)
                                        Text(Language.get("Categories_Have_Items_Sub", alter: "تفعيل المستوى الرابع لمواصفات الذكر والأنثى."))
                                            .font(AdminType.caption2)
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                                .tint(Color(uiColor: .ppSuccess))
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - 12. Sovereign SubSubKind (Sub-Variety) Editor Sheet

@MainActor
struct AdminSubSubKindEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let subSub: AdminSubSubKindItem
    let isNew: Bool
    let onSave: (AdminSubSubKindItem) -> Void

    @State private var nameAr: String = ""
    @State private var nameEn: String = ""

    init(subSub: AdminSubSubKindItem, isNew: Bool, onSave: @escaping (AdminSubSubKindItem) -> Void) {
        self.subSub = subSub
        self.isNew = isNew
        self.onSave = onSave

        _nameAr = State(initialValue: subSub.nameAr)
        _nameEn = State(initialValue: subSub.nameEn)
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                AdminSovereignNavigationBar(
                    title: isNew ? Language.get("Categories_Add_SubSub", alter: "تفريع فرعي جديد") : Language.get("Categories_Edit_SubSub", alter: "تعديل التفريع"),
                    subtitle: Language.get("Categories_SubSub_Level3", alter: "المستوى الثالث في شجرة التصنيف (SubSubKinds)"),
                    isModal: true,
                    onBack: { dismiss() }
                ) {
                    AdminPrimaryPillButton(
                        title: Language.get("Save", alter: "حفظ"),
                        systemImage: "checkmark"
                    ) {
                        var copy = subSub
                        copy.nameAr = nameAr
                        copy.nameEn = nameEn
                        onSave(copy)
                    }
                    .disabled(nameAr.trimmingCharacters(in: .whitespaces).isEmpty && nameEn.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Category_Names", alter: "بيانات التفريع واللغات"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameAr", alter: "الاسم بالعربية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("مثال: خط روسي نقي، قصير الشعر", text: $nameAr)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameEn", alter: "الاسم بالإنجليزية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("e.g. Pure Russian Line", text: $nameEn)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - 13. Sovereign SubKind Item (Specification / Trait) Editor Sheet

@MainActor
struct AdminItemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: AdminSubKindItemDetail
    let isNew: Bool
    let onSave: (AdminSubKindItemDetail) -> Void

    @State private var itemNameAr: String = ""
    @State private var itemNameEn: String = ""
    @State private var male: String = ""
    @State private var female: String = ""

    init(item: AdminSubKindItemDetail, isNew: Bool, onSave: @escaping (AdminSubKindItemDetail) -> Void) {
        self.item = item
        self.isNew = isNew
        self.onSave = onSave

        _itemNameAr = State(initialValue: item.itemNameAr)
        _itemNameEn = State(initialValue: item.itemNameEn)
        _male = State(initialValue: item.male)
        _female = State(initialValue: item.female)
    }

    var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                AdminSovereignNavigationBar(
                    title: isNew ? Language.get("Categories_Add_Item", alter: "مواصفة وعنصر جديد") : Language.get("Categories_Edit_Item", alter: "تعديل المواصفة"),
                    subtitle: Language.get("Categories_Items_Level4", alter: "المستوى الرابع في شجرة التصنيف (Items)"),
                    isModal: true,
                    onBack: { dismiss() }
                ) {
                    AdminPrimaryPillButton(
                        title: Language.get("Save", alter: "حفظ"),
                        systemImage: "checkmark"
                    ) {
                        var copy = item
                        copy.itemNameAr = itemNameAr
                        copy.itemNameEn = itemNameEn
                        copy.male = male
                        copy.female = female
                        onSave(copy)
                    }
                    .disabled(itemNameAr.trimmingCharacters(in: .whitespaces).isEmpty && itemNameEn.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: AdminSpacing.md) {
                        // Title Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Categories_Item_Identity", alter: "مسمى المواصفة / العنصر"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameAr", alter: "الاسم بالعربية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("مثال: جاهز للإنتاج، مدرب، صغير السن", text: $itemNameAr)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("Category_NameEn", alter: "الاسم بالإنجليزية"))
                                        .font(AdminType.captionBold)
                                        .foregroundColor(AdminSurface.secondaryText)
                                    TextField("e.g. Proven Breeder, Trained, Juvenile", text: $itemNameEn)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))

                        // Gender Characteristics Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text(Language.get("Categories_Gender_Traits", alter: "خصائص ومواصفات الجنسين"))
                                .font(AdminType.calloutBold)
                                .foregroundColor(AdminSurface.primaryText)

                            VStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(uiColor: .ppInfo))
                                            .frame(width: 8, height: 8)
                                        Text(Language.get("Male", alter: "مواصفات الذكر (Male)"))
                                            .font(AdminType.captionBold)
                                            .foregroundColor(Color(uiColor: .ppInfo))
                                    }
                                    TextField("مواصفات الذكر أو السعر أو الخصائص...", text: $male)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(uiColor: .ppWarning))
                                            .frame(width: 8, height: 8)
                                        Text(Language.get("Female", alter: "مواصفات الأنثى (Female)"))
                                            .font(AdminType.captionBold)
                                            .foregroundColor(Color(uiColor: .ppWarning))
                                    }
                                    TextField("مواصفات الأنثى أو السعر أو الخصائص...", text: $female)
                                        .font(AdminType.callout)
                                        .padding(.horizontal, 12)
                                        .frame(height: 42)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AdminSurface.hairline))
                                }
                            }
                        }
                        .padding(AdminSpacing.cardPadding)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).stroke(AdminSurface.hairline))
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.md)
                    .padding(.bottom, AdminSpacing.xxl)
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}
