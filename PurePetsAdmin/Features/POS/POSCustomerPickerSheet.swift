//
//  POSCustomerPickerSheet.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles for iPhone and iPad separately:
//  Category-defining Customer Directory & Instant Walk-In Registration Cockpit
//  with full-lifecycle Customer Profile Editing and POS Cart Binding.
//

import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

// MARK: - Customer Model

struct POSCustomerRecord: Identifiable, Hashable, Sendable {
    let id: String
    let source: String
    let name: String
    let phone: String
    let phoneLookup: String
    let email: String
    let branchId: String
    let status: String
    let createdAt: String?
    let note: String?

    init(
        id: String,
        source: String = "directory",
        name: String,
        phone: String,
        phoneLookup: String = "",
        email: String = "",
        branchId: String = "",
        status: String = "active",
        createdAt: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.source = source
        self.name = name
        self.phone = phone
        self.phoneLookup = phoneLookup
        self.email = email
        self.branchId = branchId
        self.status = status
        self.createdAt = createdAt
        self.note = note
    }

    var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2, let first = parts.first?.first, let second = parts.last?.first {
            return "\(first)\(second)".uppercased()
        }
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "PP"
    }

    var avatarColor: Color {
        let colors: [Color] = [
            Color(red: 0.49, green: 0.06, blue: 0.20), // PurePets Crimson
            Color(red: 0.12, green: 0.53, blue: 0.90), // Sapphire
            Color(red: 0.06, green: 0.65, blue: 0.45), // Emerald
            Color(red: 0.85, green: 0.45, blue: 0.08), // Amber
            Color(red: 0.55, green: 0.20, blue: 0.75), // Amethyst
            Color(red: 0.18, green: 0.68, blue: 0.70)  // Teal
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Picker Mode

enum POSCustomerPickerTab: Int, CaseIterable, Identifiable {
    case search = 0
    case create = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .search:
            return Language.get("POS_Customer_TabSearch", alter: "بحث في الدليل")
        case .create:
            return Language.get("POS_Customer_TabCreate", alter: "عميل جديد سريع")
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .create: return "person.badge.plus"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class POSCustomerPickerViewModel: ObservableObject {
    @Published var activeTab: POSCustomerPickerTab = .search
    @Published var searchText: String = ""
    @Published var searchResults: [POSCustomerRecord] = []
    @Published var recentCustomers: [POSCustomerRecord] = []
    @Published var branches: [PPInventoryBranchOption] = []
    @Published var isLoading: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String? = nil
    @Published var successFeedbackMessage: String? = nil

    // Create Form Fields
    @Published var newName: String = ""
    @Published var newPhone: String = ""
    @Published var newEmail: String = ""
    @Published var newNote: String = ""
    @Published var selectedBranchId: String = ""
    @Published var duplicateMatch: POSCustomerRecord? = nil

    // Edit Form Fields & State
    @Published var editingCustomer: POSCustomerRecord? = nil
    @Published var editName: String = ""
    @Published var editEmail: String = ""
    @Published var editNote: String = ""
    @Published var editBranchId: String = ""
    @Published var isEditingSubmitting: Bool = false

    // iPad Cockpit State
    @Published var highlightedCustomer: POSCustomerRecord? = nil
    @Published var copiedPhoneId: String? = nil

    private var searchTask: Task<Void, Never>? = nil
    private static let recentsStorageKey = "purepets_pos_recent_customers_v1"

    init() {
        loadRecents()
        loadBranches()
        loadInitialDirectory()
    }

    // MARK: - Query Type Detector

    var isPhoneQuery: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0.isNumber || $0 == "+" || $0 == "-" || $0.isWhitespace || "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".contains($0) }
    }

    // MARK: - Phone Normalization Helper

    func normalizePhone(_ input: String) -> String {
        let digitMap: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        return input.compactMap { digitMap[$0] ?? $0 }
            .filter { $0.isNumber }
            .map { String($0) }
            .joined()
    }

    // MARK: - Search Logic

    func handleSearchQueryChanged(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loadInitialDirectory()
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await self?.executeSearch(term: trimmed)
        }
    }

    private func executeSearch(term: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let callable = Functions.functions().httpsCallable("posCustomerCommand")
            callable.timeoutInterval = 20
            let payload: [String: Any] = [
                "action": "search",
                "term": term,
                "pageSize": 25
            ]
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any],
                  let items = data["customers"] as? [[String: Any]] else {
                isLoading = false
                return
            }

            let parsed = items.compactMap(parseCustomer)
            searchResults = parsed
            if highlightedCustomer == nil || !parsed.contains(where: { $0.id == highlightedCustomer?.id }) {
                highlightedCustomer = parsed.first
            }
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func loadInitialDirectory() {
        guard searchText.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            do {
                let callable = Functions.functions().httpsCallable("posCustomerCommand")
                callable.timeoutInterval = 20
                let result = try await callable.call([
                    "action": "search",
                    "term": "",
                    "pageSize": 25
                ])
                guard let data = result.data as? [String: Any],
                      let items = data["customers"] as? [[String: Any]] else {
                    self?.isLoading = false
                    self?.errorMessage = Language.get("POS_Customer_DirectoryLoadFailed", alter: "تعذر تحميل دليل العملاء. تحقق من الاتصال وحاول مرة أخرى.")
                    return
                }
                if let self {
                    let parsed = items.compactMap { self.parseCustomer($0) }
                    self.searchResults = parsed
                    if self.highlightedCustomer == nil {
                        self.highlightedCustomer = parsed.first ?? self.recentCustomers.first
                    }
                }
                self?.isLoading = false
            } catch {
                self?.isLoading = false
                self?.errorMessage = Language.get("POS_Customer_DirectoryLoadFailed", alter: "تعذر تحميل دليل العملاء. تحقق من الاتصال وحاول مرة أخرى.")
            }
        }
    }

    // MARK: - Duplicate Phone Checking

    func checkDuplicatePhone(_ phoneInput: String) {
        let normalized = normalizePhone(phoneInput)
        guard normalized.count >= 6 else {
            duplicateMatch = nil
            return
        }

        Task { [weak self] in
            do {
                let callable = Functions.functions().httpsCallable("posCustomerCommand")
                callable.timeoutInterval = 10
                let result = try await callable.call([
                    "action": "search",
                    "term": normalized,
                    "pageSize": 2
                ])
                guard let data = result.data as? [String: Any],
                      let items = data["customers"] as? [[String: Any]],
                      let first = items.first else {
                    self?.duplicateMatch = nil
                    return
                }
                let customer = self?.parseCustomer(first)
                if customer?.phoneLookup == normalized {
                    self?.duplicateMatch = customer
                } else {
                    self?.duplicateMatch = nil
                }
            } catch {
                // Non-fatal
            }
        }
    }

    // MARK: - Create Customer

    func submitCreateCustomer(onSuccess: @escaping (POSCustomerRecord) -> Void) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = newPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizePhone(phone)

        guard normalized.count >= 6 else {
            errorMessage = Language.get("POS_Customer_PhoneTooShort", alter: "يرجى إدخال رقم هاتف صحيح (٦ أرقام على الأقل).")
            return
        }

        isSubmitting = true
        errorMessage = nil

        let defaultName = Language.get("POS_Customer_DefaultName", alter: "عميل نقطة بيع")
        let finalName = name.isEmpty ? defaultName : name

        Task { [weak self] in
            guard let self else { return }
            do {
                let callable = Functions.functions().httpsCallable("posCustomerCommand")
                callable.timeoutInterval = 25
                var payload: [String: Any] = [
                    "name": finalName,
                    "phone": phone
                ]
                if !self.newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    payload["email"] = self.newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !self.newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    payload["note"] = self.newNote.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !self.selectedBranchId.isEmpty {
                    payload["branchId"] = self.selectedBranchId
                }

                let result = try await callable.call([
                    "action": "create",
                    "payload": payload
                ])

                guard let data = result.data as? [String: Any],
                      let customerDict = data["customer"] as? [String: Any],
                      let customer = self.parseCustomer(customerDict) else {
                    self.isSubmitting = false
                    self.errorMessage = Language.get("POS_Customer_CreateFailed", alter: "تعذر حفظ بيانات العميل. تأكد من البيانات وحاول مرة أخرى.")
                    return
                }

                self.rememberCustomer(customer)
                self.highlightedCustomer = customer
                self.isSubmitting = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSuccess(customer)
            } catch {
                self.isSubmitting = false
                self.errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Edit Customer Lifecycle

    func startEditing(customer: POSCustomerRecord) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        editingCustomer = customer
        editName = customer.name
        editEmail = customer.email
        editNote = customer.note ?? ""
        editBranchId = customer.branchId
        errorMessage = nil
    }

    func cancelEditing() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editingCustomer = nil
        editName = ""
        editEmail = ""
        editNote = ""
        editBranchId = ""
    }

    func submitUpdateCustomer(andSelect: Bool = false, onSuccess: @escaping (POSCustomerRecord) -> Void) {
        guard let customer = editingCustomer else { return }

        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName = Language.get("POS_Customer_DefaultName", alter: "عميل نقطة بيع")
        let finalName = trimmedName.isEmpty ? defaultName : trimmedName

        isEditingSubmitting = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let callable = Functions.functions().httpsCallable("posCustomerCommand")
                callable.timeoutInterval = 25
                let payload: [String: Any] = [
                    "customerId": customer.id,
                    "name": finalName,
                    "email": self.editEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                    "note": self.editNote.trimmingCharacters(in: .whitespacesAndNewlines),
                    "branchId": self.editBranchId
                ]

                let result = try await callable.call([
                    "action": "update",
                    "payload": payload
                ])

                guard let data = result.data as? [String: Any],
                      let customerDict = data["customer"] as? [String: Any],
                      let updatedCustomer = self.parseCustomer(customerDict) else {
                    self.isEditingSubmitting = false
                    self.errorMessage = Language.get("POS_Customer_CreateFailed", alter: "تعذر تحديث بيانات العميل. تأكد من البيانات وحاول مرة أخرى.")
                    return
                }

                // Update local search results
                if let idx = self.searchResults.firstIndex(where: { $0.id == updatedCustomer.id }) {
                    self.searchResults[idx] = updatedCustomer
                }

                // Update recents
                self.rememberCustomer(updatedCustomer)
                self.highlightedCustomer = updatedCustomer
                self.editingCustomer = nil
                self.isEditingSubmitting = false

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.successFeedbackMessage = Language.get("POS_Customer_EditSuccess", alter: "تم تحديث بيانات العميل بنجاح.")

                // Auto dismiss success toast after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if self.successFeedbackMessage != nil {
                        self.successFeedbackMessage = nil
                    }
                }

                if andSelect {
                    onSuccess(updatedCustomer)
                }
            } catch {
                self.isEditingSubmitting = false
                self.errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Quick Actions

    func copyPhone(customer: POSCustomerRecord) {
        UIPasteboard.general.string = customer.phone
        copiedPhoneId = customer.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self?.copiedPhoneId == customer.id {
                self?.copiedPhoneId = nil
            }
        }
    }

    // MARK: - Recents & Persistence

    func rememberCustomer(_ customer: POSCustomerRecord) {
        var updated = recentCustomers.filter { $0.id != customer.id }
        updated.insert(customer, at: 0)
        if updated.count > 10 {
            updated = Array(updated.prefix(10))
        }
        recentCustomers = updated
        saveRecents()
    }

    private func saveRecents() {
        let serialized = recentCustomers.map { c -> [String: String] in
            [
                "id": c.id,
                "name": c.name,
                "phone": c.phone,
                "phoneLookup": c.phoneLookup,
                "email": c.email,
                "branchId": c.branchId,
                "status": c.status,
                "note": c.note ?? ""
            ]
        }
        UserDefaults.standard.set(serialized, forKey: Self.recentsStorageKey)
    }

    private func loadRecents() {
        guard let list = UserDefaults.standard.array(forKey: Self.recentsStorageKey) as? [[String: String]] else { return }
        recentCustomers = list.compactMap { d -> POSCustomerRecord? in
            guard let id = d["id"], !id.isEmpty,
                  let phone = d["phone"], !phone.isEmpty else { return nil }
            let nameRaw = (d["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = nameRaw.isEmpty ? Language.get("POS_Customer_DefaultName", alter: "عميل نقطة بيع") : nameRaw
            return POSCustomerRecord(
                id: id,
                source: "directory",
                name: name,
                phone: phone,
                phoneLookup: d["phoneLookup"] ?? "",
                email: d["email"] ?? "",
                branchId: d["branchId"] ?? "",
                status: d["status"] ?? "active",
                createdAt: nil,
                note: d["note"]
            )
        }
    }

    private func loadBranches() {
        Task { [weak self] in
            do {
                let snapshot = try await Firestore.firestore().collection("branches").getDocuments()
                let list = snapshot.documents.compactMap { doc -> PPInventoryBranchOption? in
                    let data = doc.data()
                    if data["isActive"] as? Bool == false { return nil }
                    var nameAr = (data["nameAr"] as? String) ?? ""
                    var nameEn = (data["nameEn"] as? String) ?? ""
                    if let nameMap = data["name"] as? [String: Any] {
                        if nameAr.isEmpty { nameAr = (nameMap["ar"] as? String) ?? "" }
                        if nameEn.isEmpty { nameEn = (nameMap["en"] as? String) ?? "" }
                    } else if let nameStr = data["name"] as? String, nameAr.isEmpty {
                        if nameStr.lowercased().contains("reservation") {
                            nameAr = Language.get("ReservationBranch", alter: "فرع الحجوزات")
                            nameEn = "Reservation Branch"
                        } else {
                            nameAr = nameStr
                        }
                    }
                    if let branchName = data["branchName"] as? String, nameAr.isEmpty {
                        nameAr = branchName
                    }
                    let code = (data["code"] as? String) ?? ""
                    let address = (data["address"] as? String) ?? ""
                    let phone = (data["phone"] as? String) ?? ""
                    let isDefault = (data["isDefault"] as? Bool) ?? false
                    let stockMode = (data["stockMode"] as? String) ?? ""
                    return PPInventoryBranchOption(
                        id: doc.documentID,
                        code: code,
                        nameAr: nameAr,
                        nameEn: nameEn,
                        address: address,
                        phone: phone,
                        isDefault: isDefault,
                        stockMode: stockMode
                    )
                }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                self?.branches = list
            } catch {
                // Non-critical
            }
        }
    }

    func parseCustomer(_ dict: [String: Any]) -> POSCustomerRecord? {
        let id = (dict["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawName = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = (dict["phone"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }

        let name = rawName.isEmpty ? Language.get("POS_Customer_DefaultName", alter: "عميل نقطة بيع") : rawName

        return POSCustomerRecord(
            id: id,
            source: (dict["source"] as? String) ?? "directory",
            name: name,
            phone: phone,
            phoneLookup: (dict["phoneLookup"] as? String) ?? "",
            email: (dict["email"] as? String) ?? "",
            branchId: (dict["branchId"] as? String) ?? "",
            status: (dict["status"] as? String) ?? "active",
            createdAt: dict["createdAt"] as? String,
            note: dict["note"] as? String
        )
    }

    func branchDisplayName(for branchId: String) -> String {
        guard !branchId.isEmpty else { return "" }
        if let branch = branches.first(where: { $0.id == branchId }) {
            return branch.displayName
        }
        return branchId
    }
}

// MARK: - Root Entry Sheet

struct POSCustomerPickerSheet: View {
    let currentSelected: POSCustomerRecord?
    var canCreateCustomer: Bool = true
    let onSelect: (POSCustomerRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = POSCustomerPickerViewModel()

    var body: some View {
        GeometryReader { geometry in
            let isPad = UIDevice.current.userInterfaceIdiom == .pad && geometry.size.width > 600

            ZStack {
                AdminSurface.background.ignoresSafeArea()

                if isPad {
                    iPadCustomerSpatialCockpit(
                        viewModel: viewModel,
                        currentSelected: currentSelected,
                        canCreateCustomer: canCreateCustomer,
                        onSelect: onSelect,
                        dismiss: { dismiss() }
                    )
                } else {
                    iPhoneCustomerSensoryDeck(
                        viewModel: viewModel,
                        currentSelected: currentSelected,
                        canCreateCustomer: canCreateCustomer,
                        onSelect: onSelect,
                        dismiss: { dismiss() }
                    )
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - ==========================================
// MARK: - IPHONE: SENSORY DECK ARCHITECTURE
// MARK: - ==========================================

private struct iPhoneCustomerSensoryDeck: View {
    @ObservedObject var viewModel: POSCustomerPickerViewModel
    let currentSelected: POSCustomerRecord?
    let canCreateCustomer: Bool
    let onSelect: (POSCustomerRecord) -> Void
    let dismiss: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header Bar
                    AdminSovereignNavigationBar(
                        title: Language.get("POS_Customer_Title", alter: "دليل وربط العملاء"),
                        subtitle: canCreateCustomer
                            ? Language.get("POS_Customer_Subtitle", alter: "اختر العميل المتاح أو أنشئ ملفاً جديداً فورياً للسلة.")
                            : Language.get("POS_Customer_Subtitle_ReadOnly", alter: "اختر عميلاً موجوداً لإرفاقه بهذه السلة."),
                        statusDotColor: Color(uiColor: .ppSuccess),
                        isModal: true,
                        onBack: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        }
                    ) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "person.2.badge.gearshape.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }

                    // Mode Switcher Tabs
                    tabSwitcher
                    Divider().background(AdminSurface.hairline)

                    // Error & Success Banners
                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }
                    if let success = viewModel.successFeedbackMessage {
                        successBanner(success)
                    }

                    // Dynamic Sensory Body
                    switch viewModel.activeTab {
                    case .search:
                        iPhoneSearchChamber
                    case .create:
                        iPhoneCreateChamber
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $viewModel.editingCustomer) { customer in
                POSCustomerEditSheet(
                    viewModel: viewModel,
                    customer: customer,
                    onSelectAndDismiss: { updated in
                        onSelect(updated)
                        dismiss()
                    }
                )
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
        }
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(canCreateCustomer ? POSCustomerPickerTab.allCases : [.search]) { tab in
                let selected = viewModel.activeTab == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        viewModel.activeTab = tab
                        if tab == .create && !viewModel.searchText.isEmpty {
                            let trimmedSearch = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if viewModel.isPhoneQuery && viewModel.newPhone.isEmpty {
                                viewModel.newPhone = trimmedSearch
                                viewModel.checkDuplicatePhone(trimmedSearch)
                            } else if !viewModel.isPhoneQuery && viewModel.newName.isEmpty {
                                viewModel.newName = trimmedSearch
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(Font.custom(selected ? "Beiruti-Bold" : "Beiruti-Medium", size: 14, relativeTo: .subheadline))
                    }
                    .foregroundColor(selected ? .white : AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        selected ? AdminSurface.primary : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Feedback Banners

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(Font.custom("Beiruti-Medium", size: 12.5, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func successBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
            Button {
                viewModel.successFeedbackMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - iPhone Search Chamber

    private var iPhoneSearchChamber: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Search Input Capsule
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AdminSurface.secondaryText)
                        .font(.system(size: 16, weight: .medium))

                    TextField(Language.get("POS_Customer_DirectorySearchPlaceholder", alter: "ابحث بالاسم أو رقم الهاتف..."), text: $viewModel.searchText)
                        .font(Font.custom("Beiruti-Regular", size: 15, relativeTo: .body))
                        .foregroundColor(AdminSurface.primaryText)
                        .focused($isSearchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: viewModel.searchText, perform: { newValue in
                            viewModel.handleSearchQueryChanged(newValue)
                        })

                    // Query Mode Intelligence Badge
                    if !viewModel.searchText.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isPhoneQuery ? "phone.badge.waveform" : "person.text.rectangle")
                                .font(.system(size: 10))
                            Text(viewModel.isPhoneQuery
                                 ? Language.get("POS_Customer_FilterPhoneMode", alter: "رقم هاتف")
                                 : Language.get("POS_Customer_FilterNameMode", alter: "اسم العميل"))
                                .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                        }
                        .foregroundColor(viewModel.isPhoneQuery ? .orange : AdminSurface.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            (viewModel.isPhoneQuery ? Color.orange : AdminSurface.primary).opacity(0.12),
                            in: Capsule()
                        )

                        Button {
                            viewModel.searchText = ""
                            viewModel.handleSearchQueryChanged("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AdminSurface.secondaryText)
                                .font(.system(size: 15))
                        }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(AdminSurface.primary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSearchFocused ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSearchFocused ? 1.5 : 1)
                )

                // Recent Walk-Ins Shelf
                if viewModel.searchText.isEmpty && !viewModel.recentCustomers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                                .foregroundColor(AdminSurface.secondaryText)
                            Text(Language.get("POS_Customer_RecentWalkIns", alter: "عملاء حديثون"))
                                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.recentCustomers) { customer in
                                    iPhoneRecentCustomerChip(customer: customer)
                                }
                            }
                        }
                    }
                }

                // Customer Results Stream
                if viewModel.searchResults.isEmpty && !viewModel.isLoading {
                    iPhoneEmptySearchState
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.searchResults) { customer in
                            iPhoneCustomerResultCard(customer: customer)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Recent Chip

    private func iPhoneRecentCustomerChip(customer: POSCustomerRecord) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            viewModel.rememberCustomer(customer)
            onSelect(customer)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(customer.avatarColor)
                        .frame(width: 28, height: 28)
                    Text(customer.initials)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(customer.name)
                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)
                    Text(customer.phone)
                        .font(.system(size: 10))
                        .foregroundColor(AdminSurface.secondaryText)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - iPhone Customer Card with Edit Button

    private func iPhoneCustomerResultCard(customer: POSCustomerRecord) -> some View {
        let isSelected = currentSelected?.id == customer.id

        return HStack(spacing: 10) {
            // Main Tap Area: Selects customer and dismisses
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.rememberCustomer(customer)
                onSelect(customer)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    // Avatar Squircle
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(customer.avatarColor.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(customer.initials)
                            .font(Font.custom("Beiruti-Bold", size: 17, relativeTo: .headline))
                            .foregroundColor(customer.avatarColor)
                    }

                    // Information Stack
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(customer.name)
                                .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .body))
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            if isSelected {
                                Text(Language.get("POS_Customer_SelectedBadge", alter: "المحدد حالياً"))
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green, in: Capsule())
                            }
                        }

                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 9))
                                Text(customer.phone)
                                    .font(.system(size: 12, weight: .medium))
                                    .monospacedDigit()
                            }
                            .foregroundColor(AdminSurface.secondaryText)

                            if !customer.email.isEmpty {
                                Text("•")
                                    .foregroundColor(AdminSurface.hairline)
                                Text(customer.email)
                                    .font(.system(size: 11))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        // Branch & Notes Pill row
                        HStack(spacing: 6) {
                            if !customer.branchId.isEmpty {
                                let branchTitle = viewModel.branchDisplayName(for: customer.branchId)
                                if !branchTitle.isEmpty {
                                    HStack(spacing: 3) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 9))
                                        Text(branchTitle)
                                            .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                                    }
                                    .foregroundColor(AdminSurface.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                                }
                            }

                            if let note = customer.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 9))
                                    Text(note)
                                        .font(Font.custom("Beiruti-Regular", size: 10.5, relativeTo: .caption2))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AdminSurface.control, in: Capsule())
                            }
                        }
                    }

                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Dedicated EDIT Button
            Button {
                viewModel.startEditing(customer: customer)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.10))
                        .frame(width: 38, height: 38)
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Language.get("POS_Customer_EditButton", alter: "تعديل"))

            // Select Chevron Indicator
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.rememberCustomer(customer)
                onSelect(customer)
                dismiss()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? .green : AdminSurface.secondaryText.opacity(0.6))
                    .frame(width: 24, height: 38)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color.green : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
        )
    }

    // MARK: - iPhone Empty Search State

    private var iPhoneEmptySearchState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 42, weight: .light))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                .padding(.top, 24)

            VStack(spacing: 4) {
                Text(Language.get("POS_Customer_NoMatchTitle", alter: "لا توجد نتائج مطابقة"))
                    .font(Font.custom("Beiruti-Bold", size: 16.5, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
                if !viewModel.searchText.isEmpty {
                    Text(String(format: Language.get("POS_Customer_NoMatchSub", alter: "لم نجد عميلاً باسم أو هاتف '%@'."), viewModel.searchText))
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }

            if canCreateCustomer && !viewModel.searchText.isEmpty {
                Button {
                    let trimmedSearch = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if viewModel.isPhoneQuery {
                        viewModel.newPhone = trimmedSearch
                        viewModel.checkDuplicatePhone(trimmedSearch)
                    } else {
                        viewModel.newName = trimmedSearch
                    }
                    viewModel.activeTab = .create
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(format: Language.get("POS_Customer_CreateInstantCTA", alter: "إضافة «%@» كعميل جديد"), viewModel.searchText))
                            .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AdminSurface.primary, in: Capsule())
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - iPhone Create Chamber

    private var iPhoneCreateChamber: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Live Monogram Hero Preview
                ZStack {
                    Circle()
                        .fill(viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.12) : AdminSurface.primary.opacity(0.15))
                        .frame(width: 70, height: 70)

                    if viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 26))
                            .foregroundColor(AdminSurface.secondaryText)
                    } else {
                        Text(String(viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased())
                            .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title))
                            .foregroundColor(AdminSurface.primary)
                    }
                }
                .padding(.top, 8)

                // Duplicate Warning if Phone Exists
                if let match = viewModel.duplicateMatch {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.rememberCustomer(match)
                        onSelect(match)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("POS_Customer_DuplicateFound", alter: "عميل مسجل مسبقاً بهذا الرقم!"))
                                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(String(format: Language.get("POS_Customer_DuplicateSub", alter: "اضغط هنا لاختيار '%@' مباشرة."), match.name))
                                    .font(Font.custom("Beiruti-Regular", size: 12, relativeTo: .caption2))
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            Image(systemName: "arrowshape.turn.up.right.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Form Container
                VStack(spacing: 12) {
                    // Name Field
                    iPhoneFormField(
                        title: Language.get("POS_Customer_NameField", alter: "اسم العميل (اختياري)"),
                        placeholder: Language.get("POS_Customer_NamePlaceholder", alter: "مثال: سالم الكواري"),
                        icon: "person.fill",
                        text: $viewModel.newName
                    )

                    // Phone Field
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف *"))
                            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                            .foregroundColor(AdminSurface.primaryText)

                        HStack(spacing: 8) {
                            Text("🇶🇦 +974")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AdminSurface.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            TextField(Language.get("POS_Customer_PhonePlaceholder", alter: "5512 3456"), text: $viewModel.newPhone)
                                .font(.system(size: 15, weight: .semibold))
                                .monospacedDigit()
                                .keyboardType(.phonePad)
                                .onChange(of: viewModel.newPhone, perform: { newValue in
                                    viewModel.checkDuplicatePhone(newValue)
                                })
                        }
                        .padding(6)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Email Field
                    iPhoneFormField(
                        title: Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني (اختياري)"),
                        placeholder: Language.get("POS_Customer_EmailPlaceholder", alter: "customer@example.com"),
                        icon: "envelope.fill",
                        text: $viewModel.newEmail,
                        keyboardType: .emailAddress
                    )

                    // Branch Selector
                    if !viewModel.branches.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Language.get("POS_Customer_BranchField", alter: "الفرع المفضل"))
                                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(viewModel.branches, id: \.id) { b in
                                        let active = viewModel.selectedBranchId == b.id
                                        Button {
                                            viewModel.selectedBranchId = active ? "" : b.id
                                        } label: {
                                            Text(b.displayName)
                                                .font(Font.custom(active ? "Beiruti-Bold" : "Beiruti-Regular", size: 12.5, relativeTo: .caption))
                                                .foregroundColor(active ? .white : AdminSurface.primaryText)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(active ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                                                .overlay(Capsule().stroke(AdminSurface.hairline))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }
                    }

                    // Notes Field
                    iPhoneFormField(
                        title: Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية"),
                        placeholder: Language.get("POS_Customer_NotePlaceholder", alter: "ملاحظات حول التوصيل أو تفضيلات العميل…"),
                        icon: "note.text",
                        text: $viewModel.newNote
                    )
                }

                // Submit Button
                Button {
                    viewModel.submitCreateCustomer { createdCustomer in
                        onSelect(createdCustomer)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.white).scaleEffect(0.9)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(Language.get("POS_Customer_SubmitCTA", alter: "حفظ وتحديد العميل للسلة"))
                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.24), radius: 8, y: 3)
                }
                .disabled(viewModel.isSubmitting)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .padding(16)
        }
    }

    private func iPhoneFormField(
        title: String,
        placeholder: String,
        icon: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 13))
                    .frame(width: 20)

                TextField(placeholder, text: text)
                    .font(Font.custom("Beiruti-Regular", size: 14.5, relativeTo: .body))
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
        }
    }
}

// MARK: - ==========================================
// MARK: - IPHONE: CUSTOMER PROFILE EDIT SHEET
// MARK: - ==========================================

private struct POSCustomerEditSheet: View {
    @ObservedObject var viewModel: POSCustomerPickerViewModel
    let customer: POSCustomerRecord
    let onSelectAndDismiss: (POSCustomerRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header Bar
                    AdminSovereignNavigationBar(
                        title: Language.get("POS_Customer_EditTitle", alter: "تعديل ملف العميل"),
                        subtitle: Language.get("POS_Customer_EditSubtitle", alter: "تحديث بيانات الاتصال والفرع والملاحظات التشغيلية."),
                        statusDotColor: Color(uiColor: .ppSuccess),
                        isModal: true,
                        onBack: {
                            viewModel.cancelEditing()
                            dismiss()
                        }
                    ) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "pencil")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                            Text(error)
                                .font(Font.custom("Beiruti-Medium", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }

                    ScrollView {
                        VStack(spacing: 16) {
                            // Avatar Monogram Preview with Live Initials
                            ZStack {
                                Circle()
                                    .fill(customer.avatarColor)
                                    .frame(width: 72, height: 72)
                                let initials = viewModel.editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? customer.initials
                                    : String(viewModel.editName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
                                Text(initials)
                                    .font(Font.custom("Beiruti-Bold", size: 26, relativeTo: .title))
                                    .foregroundColor(.white)
                            }
                            .padding(.top, 12)

                            // Phone Identity Locked Badge
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 13))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف (معرف الحساب الثابت)"))
                                        .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption2))
                                        .foregroundColor(AdminSurface.secondaryText)
                                    Text(customer.phone)
                                        .font(.system(size: 14, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundColor(AdminSurface.primaryText)
                                }

                                Spacer()

                                Button {
                                    viewModel.copyPhone(customer: customer)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: viewModel.copiedPhoneId == customer.id ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 11))
                                        Text(viewModel.copiedPhoneId == customer.id
                                             ? Language.get("POS_Customer_QuickAction_Copied", alter: "تم النسخ")
                                             : Language.get("POS_Customer_QuickAction_Copy", alter: "نسخ"))
                                            .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                                    }
                                    .foregroundColor(viewModel.copiedPhoneId == customer.id ? .green : AdminSurface.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(AdminSurface.control, in: Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(12)
                            .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))

                            // Form Fields
                            VStack(spacing: 12) {
                                // Name Field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("POS_Customer_NameField", alter: "اسم العميل"))
                                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.primaryText)
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .font(.system(size: 13))
                                            .frame(width: 20)
                                        TextField(Language.get("POS_Customer_NamePlaceholder", alter: "الاسم الكامل"), text: $viewModel.editName)
                                            .font(Font.custom("Beiruti-Regular", size: 14.5, relativeTo: .body))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                                }

                                // Email Field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني"))
                                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.primaryText)
                                    HStack(spacing: 8) {
                                        Image(systemName: "envelope.fill")
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .font(.system(size: 13))
                                            .frame(width: 20)
                                        TextField("customer@example.com", text: $viewModel.editEmail)
                                            .font(Font.custom("Beiruti-Regular", size: 14.5, relativeTo: .body))
                                            .keyboardType(.emailAddress)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                                }

                                // Branch Selector
                                if !viewModel.branches.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(Language.get("POS_Customer_BranchField", alter: "الفرع المفضل"))
                                            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                            .foregroundColor(AdminSurface.primaryText)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(viewModel.branches, id: \.id) { b in
                                                    let active = viewModel.editBranchId == b.id
                                                    Button {
                                                        viewModel.editBranchId = active ? "" : b.id
                                                    } label: {
                                                        Text(b.displayName)
                                                            .font(Font.custom(active ? "Beiruti-Bold" : "Beiruti-Regular", size: 12.5, relativeTo: .caption))
                                                            .foregroundColor(active ? .white : AdminSurface.primaryText)
                                                            .padding(.horizontal, 10)
                                                            .padding(.vertical, 6)
                                                            .background(active ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                                                            .overlay(Capsule().stroke(AdminSurface.hairline))
                                                    }
                                                    .buttonStyle(PlainButtonStyle())
                                                }
                                            }
                                        }
                                    }
                                }

                                // Notes Field
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية"))
                                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.primaryText)
                                    HStack(spacing: 8) {
                                        Image(systemName: "note.text")
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .font(.system(size: 13))
                                            .frame(width: 20)
                                        TextField(Language.get("POS_Customer_NotePlaceholder", alter: "ملاحظات تشغيلية..."), text: $viewModel.editNote)
                                            .font(Font.custom("Beiruti-Regular", size: 14.5, relativeTo: .body))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                                }
                            }

                            // Action Buttons
                            VStack(spacing: 10) {
                                // Primary Save Button
                                Button {
                                    viewModel.submitUpdateCustomer(andSelect: false) { _ in
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        if viewModel.isEditingSubmitting {
                                            ProgressView().tint(.white).scaleEffect(0.9)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 15, weight: .bold))
                                        }
                                        Text(Language.get("POS_Customer_EditCTA", alter: "حفظ وتحديث ملف العميل"))
                                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .disabled(viewModel.isEditingSubmitting)

                                // Save and Link CTA
                                Button {
                                    viewModel.submitUpdateCustomer(andSelect: true) { updated in
                                        onSelectAndDismiss(updated)
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrowshape.turn.up.backward.fill")
                                            .font(.system(size: 13))
                                        Text(Language.get("POS_Customer_SaveAndLink", alter: "حفظ وربط العميل بالسلة"))
                                            .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .callout))
                                    }
                                    .foregroundColor(AdminSurface.primary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .disabled(viewModel.isEditingSubmitting)
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                        .padding(16)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - ==========================================
// MARK: - IPAD: SPATIAL COCKPIT ARCHITECTURE
// MARK: - ==========================================

private struct iPadCustomerSpatialCockpit: View {
    @ObservedObject var viewModel: POSCustomerPickerViewModel
    let currentSelected: POSCustomerRecord?
    let canCreateCustomer: Bool
    let onSelect: (POSCustomerRecord) -> Void
    let dismiss: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            // Soft Dimming Backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Central Floating Cockpit Vessel
            VStack(spacing: 0) {
                // Top Vessel Command Bar
                iPadTopCommandBar

                Divider().background(AdminSurface.hairline)

                // Feedback Strip
                if let error = viewModel.errorMessage {
                    iPadFeedbackBanner(text: error, isError: true)
                }
                if let success = viewModel.successFeedbackMessage {
                    iPadFeedbackBanner(text: success, isError: false)
                }

                // Two-Column Cockpit Engine
                HStack(spacing: 0) {
                    // Left Column (52%): Directory Stream & Search Engine
                    iPadLeftDirectoryColumn
                        .frame(maxWidth: .infinity)

                    // Vertical Separation Hairline
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(width: 1)

                    // Right Column (48%): Dynamic Inspector / Studio Chamber
                    iPadRightStudioColumn
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 880, maxHeight: 720)
            .background(AdminSurface.background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 30, y: 12)
            .padding(24)
        }
    }

    // MARK: - Top Command Bar

    private var iPadTopCommandBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: "person.2.badge.gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Language.get("POS_Customer_Title", alter: "دليل وربط العملاء"))
                        .font(Font.custom("Beiruti-Bold", size: 19, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)

                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(Language.get("POS_Customer_StatsTotal", alter: "متصل بالدليل الموحد"))
                            .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())
                }

                Text(canCreateCustomer
                     ? Language.get("POS_Customer_Subtitle", alter: "البحث السريع، ربط السلة وتحديث الملفات التشغيلية فورياً.")
                     : Language.get("POS_Customer_Subtitle_ReadOnly", alter: "اختر عميلاً موجوداً لإرفاقه بهذه السلة."))
                    .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            // Close Vessel Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 36, height: 36)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
    }

    // MARK: - Feedback Banner

    private func iPadFeedbackBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? .red : .green)
                .font(.system(size: 13))
            Text(text)
                .font(Font.custom("Beiruti-Medium", size: 13, relativeTo: .caption))
                .foregroundColor(AdminSurface.primaryText)
            Spacer()
            Button {
                if isError { viewModel.errorMessage = nil }
                else { viewModel.successFeedbackMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background((isError ? Color.red : Color.green).opacity(0.1))
    }

    // MARK: - Left Directory Column

    private var iPadLeftDirectoryColumn: some View {
        VStack(spacing: 12) {
            // Mode Switcher Tabs
            HStack(spacing: 4) {
                ForEach(canCreateCustomer ? POSCustomerPickerTab.allCases : [.search]) { tab in
                    let isSelected = viewModel.activeTab == tab
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            viewModel.activeTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon).font(.system(size: 12, weight: .semibold))
                            Text(tab.title)
                                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 13.5, relativeTo: .callout))
                        }
                        .foregroundColor(isSelected ? .white : AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isSelected ? AdminSurface.primary : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(3)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Search Bar Capsule
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AdminSurface.secondaryText)
                    .font(.system(size: 14))

                TextField(Language.get("POS_Customer_DirectorySearchPlaceholder", alter: "ابحث بالاسم أو رقم الهاتف..."), text: $viewModel.searchText)
                    .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .onChange(of: viewModel.searchText, perform: { newValue in
                        viewModel.handleSearchQueryChanged(newValue)
                    })

                if !viewModel.searchText.isEmpty {
                    // Mode Badge
                    Text(viewModel.isPhoneQuery
                         ? Language.get("POS_Customer_FilterPhoneMode", alter: "هاتف")
                         : Language.get("POS_Customer_FilterNameMode", alter: "اسم"))
                        .font(Font.custom("Beiruti-Bold", size: 10.5, relativeTo: .caption2))
                        .foregroundColor(viewModel.isPhoneQuery ? .orange : AdminSurface.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((viewModel.isPhoneQuery ? Color.orange : AdminSurface.primary).opacity(0.12), in: Capsule())

                    Button {
                        viewModel.searchText = ""
                        viewModel.handleSearchQueryChanged("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AdminSurface.secondaryText)
                            .font(.system(size: 13))
                    }
                }

                if viewModel.isLoading {
                    ProgressView().scaleEffect(0.7).tint(AdminSurface.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSearchFocused ? AdminSurface.primary : AdminSurface.hairline)
            )

            // Recents Runway
            if viewModel.searchText.isEmpty && !viewModel.recentCustomers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 10)).foregroundColor(AdminSurface.secondaryText)
                        Text(Language.get("POS_Customer_RecentWalkIns", alter: "عملاء حديثون"))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                        Spacer()
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.recentCustomers) { c in
                                Button {
                                    viewModel.highlightedCustomer = c
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(c.avatarColor).frame(width: 20, height: 20)
                                            .overlay(Text(c.initials).font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                                        Text(c.name)
                                            .font(Font.custom("Beiruti-Medium", size: 12, relativeTo: .caption))
                                            .foregroundColor(AdminSurface.primaryText)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AdminSurface.surface, in: Capsule())
                                    .overlay(Capsule().stroke(viewModel.highlightedCustomer?.id == c.id ? AdminSurface.primary : AdminSurface.hairline))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }

            // Customer Stream
            ScrollView {
                if viewModel.searchResults.isEmpty && !viewModel.isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                            .padding(.top, 30)
                        Text(Language.get("POS_Customer_NoMatchTitle", alter: "لا توجد نتائج مطابقة"))
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.searchResults) { customer in
                            iPadCustomerListCard(customer: customer)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Customer Card in Left Stream

    private func iPadCustomerListCard(customer: POSCustomerRecord) -> some View {
        let isHighlighted = viewModel.highlightedCustomer?.id == customer.id
        let isCurrentPOS = currentSelected?.id == customer.id

        return HStack(spacing: 10) {
            // Main Touch Target: Highlights customer in Right Inspector
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.highlightedCustomer = customer
                    if viewModel.editingCustomer != nil {
                        viewModel.startEditing(customer: customer)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    // Avatar
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(customer.avatarColor.opacity(0.18))
                            .frame(width: 42, height: 42)
                        Text(customer.initials)
                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                            .foregroundColor(customer.avatarColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(customer.name)
                                .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .body))
                                .foregroundColor(AdminSurface.primaryText)
                                .lineLimit(1)

                            if isCurrentPOS {
                                Text(Language.get("POS_Customer_SelectedBadge", alter: "المحدد"))
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.green, in: Capsule())
                            }
                        }

                        HStack(spacing: 8) {
                            HStack(spacing: 3) {
                                Image(systemName: "phone.fill").font(.system(size: 8.5))
                                Text(customer.phone)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .monospacedDigit()
                            }
                            .foregroundColor(AdminSurface.secondaryText)

                            if let note = customer.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Image(systemName: "note.text")
                                    .font(.system(size: 9))
                                    .foregroundColor(AdminSurface.primary)
                            }
                        }
                    }

                    Spacer(minLength: 2)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Dedicated EDIT Button
            Button {
                viewModel.highlightedCustomer = customer
                viewModel.startEditing(customer: customer)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.10))
                        .frame(width: 34, height: 34)
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Language.get("POS_Customer_EditButton", alter: "تعديل"))
        }
        .padding(10)
        .background(isHighlighted ? AdminSurface.primary.opacity(0.08) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHighlighted ? AdminSurface.primary : (isCurrentPOS ? Color.green.opacity(0.6) : AdminSurface.hairline), lineWidth: isHighlighted ? 1.5 : 1)
        )
    }

    // MARK: - Right Column: Morphing Studio

    @ViewBuilder
    private var iPadRightStudioColumn: some View {
        if viewModel.editingCustomer != nil {
            // STATE 1: In-Place Customer Profile Editor
            iPadInPlaceEditorChamber
        } else if viewModel.activeTab == .create {
            // STATE 2: Walk-In Registration Studio
            iPadInPlaceCreateChamber
        } else {
            // STATE 3: Customer Live Dossier Inspector
            iPadCustomerDossierInspector
        }
    }

    // MARK: - State 3: Customer Dossier Inspector

    private var iPadCustomerDossierInspector: some View {
        VStack(spacing: 0) {
            if let customer = viewModel.highlightedCustomer {
                ScrollView {
                    VStack(spacing: 16) {
                        // Dossier Header with Big Avatar
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(customer.avatarColor)
                                    .frame(width: 68, height: 68)
                                    .shadow(color: customer.avatarColor.opacity(0.3), radius: 10, y: 4)
                                Text(customer.initials)
                                    .font(Font.custom("Beiruti-Bold", size: 26, relativeTo: .title))
                                    .foregroundColor(.white)
                            }

                            Text(customer.name)
                                .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .title3))
                                .foregroundColor(AdminSurface.primaryText)
                                .multilineTextAlignment(.center)

                            HStack(spacing: 6) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text(Language.get("POS_Customer_StatusActive", alter: "عضو نشط • دليل نقاط البيع"))
                                    .font(Font.custom("Beiruti-Medium", size: 12, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }
                        }
                        .padding(.top, 16)

                        // Quick Action Pills Strip
                        HStack(spacing: 12) {
                            // Call Action
                            Button {
                                if let url = URL(string: "tel://\(viewModel.normalizePhone(customer.phone))") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "phone.fill").font(.system(size: 12))
                                    Text(Language.get("POS_Customer_QuickAction_Call", alter: "اتصال"))
                                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                }
                                .foregroundColor(AdminSurface.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Copy Phone Action
                            Button {
                                viewModel.copyPhone(customer: customer)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: viewModel.copiedPhoneId == customer.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 12))
                                    Text(viewModel.copiedPhoneId == customer.id
                                         ? Language.get("POS_Customer_QuickAction_Copied", alter: "تم النسخ")
                                         : Language.get("POS_Customer_QuickAction_Copy", alter: "نسخ الرقم"))
                                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                }
                                .foregroundColor(viewModel.copiedPhoneId == customer.id ? .green : AdminSurface.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 16)

                        // Details Stack
                        VStack(spacing: 10) {
                            // Phone Card
                            dossierInfoRow(
                                title: Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف"),
                                value: customer.phone,
                                icon: "phone.circle.fill",
                                isMonospaced: true
                            )

                            // Email Card
                            dossierInfoRow(
                                title: Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني"),
                                value: customer.email.isEmpty ? "—" : customer.email,
                                icon: "envelope.circle.fill"
                            )

                            // Branch Card
                            let branchTitle = viewModel.branchDisplayName(for: customer.branchId)
                            dossierInfoRow(
                                title: Language.get("POS_Customer_BranchField", alter: "الفرع المفضل"),
                                value: branchTitle.isEmpty ? Language.get("POS_Customer_AnyBranch", alter: "كافة الفروع") : branchTitle,
                                icon: "mappin.circle.fill"
                            )

                            // Notes Card
                            if let note = customer.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                dossierInfoRow(
                                    title: Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية"),
                                    value: note,
                                    icon: "note.text"
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 16)
                }

                Divider().background(AdminSurface.hairline)

                // Dock Action Controls
                HStack(spacing: 10) {
                    // Edit Profile Trigger
                    Button {
                        viewModel.startEditing(customer: customer)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                            Text(Language.get("POS_Customer_EditButton", alter: "تعديل الملف"))
                                .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .callout))
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Primary Link To Cart Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.rememberCustomer(customer)
                        onSelect(customer)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text(Language.get("POS_Customer_SelectToCart", alter: "ربط العميل بهذه السلة"))
                                .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.2), radius: 6, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(14)
                .background(AdminSurface.surface)

            } else {
                // Empty Inspector Placeholder
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.square.filled.and.at.rectangle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                    Text(Language.get("POS_Customer_CustomerDossier", alter: "بطاقة العميل"))
                        .font(Font.custom("Beiruti-Bold", size: 18, relativeTo: .headline))
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("POS_Customer_InspectorHint", alter: "اختر عميلاً من القائمة لمعاينة التفاصيل أو تعديل الملف."))
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AdminSurface.surface.opacity(0.5))
    }

    private func dossierInfoRow(title: String, value: String, icon: String, isMonospaced: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AdminSurface.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
                if isMonospaced {
                    Text(value)
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(AdminSurface.primaryText)
                } else {
                    Text(value)
                        .font(Font.custom("Beiruti-Medium", size: 13.5, relativeTo: .caption))
                        .foregroundColor(AdminSurface.primaryText)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
    }

    // MARK: - State 1: In-Place Profile Editor (iPad)

    private var iPadInPlaceEditorChamber: some View {
        VStack(spacing: 0) {
            // Editor Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(AdminSurface.primary)
                        .font(.system(size: 16))
                    Text(Language.get("POS_Customer_EditTitle", alter: "تعديل ملف العميل"))
                        .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                        .foregroundColor(AdminSurface.primaryText)
                }

                Spacer()

                Button {
                    viewModel.cancelEditing()
                } label: {
                    Text(Language.get("POS_Customer_CancelEdit", alter: "إلغاء التعديل"))
                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.control, in: Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AdminSurface.surface)

            Divider().background(AdminSurface.hairline)

            ScrollView {
                VStack(spacing: 14) {
                    // Monogram Preview
                    ZStack {
                        Circle()
                            .fill(viewModel.editingCustomer?.avatarColor ?? AdminSurface.primary)
                            .frame(width: 60, height: 60)
                        let initials = viewModel.editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? (viewModel.editingCustomer?.initials ?? "PP")
                            : String(viewModel.editName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
                        Text(initials)
                            .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title2))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    // Phone Identity Locked
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف:"))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(viewModel.editingCustomer?.phone ?? "")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(AdminSurface.primaryText)
                        Spacer()
                    }
                    .padding(10)
                    .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Name Field
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("POS_Customer_NameField", alter: "اسم العميل"))
                            .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                            .foregroundColor(AdminSurface.primaryText)
                        TextField(Language.get("POS_Customer_NamePlaceholder", alter: "الاسم الكامل"), text: $viewModel.editName)
                            .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Email Field
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني"))
                            .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                            .foregroundColor(AdminSurface.primaryText)
                        TextField("customer@example.com", text: $viewModel.editEmail)
                            .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                            .keyboardType(.emailAddress)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Branch Selector
                    if !viewModel.branches.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get("POS_Customer_BranchField", alter: "الفرع المفضل"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(viewModel.branches, id: \.id) { b in
                                        let active = viewModel.editBranchId == b.id
                                        Button {
                                            viewModel.editBranchId = active ? "" : b.id
                                        } label: {
                                            Text(b.displayName)
                                                .font(Font.custom(active ? "Beiruti-Bold" : "Beiruti-Regular", size: 12, relativeTo: .caption))
                                                .foregroundColor(active ? .white : AdminSurface.primaryText)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(active ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                                                .overlay(Capsule().stroke(AdminSurface.hairline))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }
                    }

                    // Notes Field
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية"))
                            .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                            .foregroundColor(AdminSurface.primaryText)
                        TextField(Language.get("POS_Customer_NotePlaceholder", alter: "ملاحظات تشغيلية…"), text: $viewModel.editNote)
                            .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }
                }
                .padding(16)
            }

            Divider().background(AdminSurface.hairline)

            // Editor Bottom Dock
            HStack(spacing: 10) {
                Button {
                    viewModel.cancelEditing()
                } label: {
                    Text(Language.get("POS_Customer_CancelEdit", alter: "إلغاء"))
                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())

                Button {
                    viewModel.submitUpdateCustomer(andSelect: false) { _ in }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isEditingSubmitting {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .bold))
                        }
                        Text(Language.get("POS_Customer_EditCTA", alter: "حفظ التعديلات"))
                            .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .headline))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(viewModel.isEditingSubmitting)
                .buttonStyle(PlainButtonStyle())

                Button {
                    viewModel.submitUpdateCustomer(andSelect: true) { updated in
                        onSelect(updated)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.backward.fill").font(.system(size: 11))
                        Text(Language.get("POS_Customer_SaveAndLink", alter: "حفظ وربط"))
                            .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .callout))
                    }
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(viewModel.isEditingSubmitting)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(14)
            .background(AdminSurface.surface)
        }
    }

    // MARK: - State 2: Walk-In Registration Studio (iPad)

    private var iPadInPlaceCreateChamber: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(AdminSurface.primary)
                        .font(.system(size: 16))
                    Text(Language.get("POS_Customer_TabCreate", alter: "تسجيل عميل جديد فوري"))
                        .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                        .foregroundColor(AdminSurface.primaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AdminSurface.surface)

            Divider().background(AdminSurface.hairline)

            ScrollView {
                VStack(spacing: 14) {
                    // Live Monogram Hero Preview
                    ZStack {
                        Circle()
                            .fill(viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.12) : AdminSurface.primary.opacity(0.15))
                            .frame(width: 60, height: 60)

                        if viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 22))
                                .foregroundColor(AdminSurface.secondaryText)
                        } else {
                            Text(String(viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased())
                                .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title2))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }
                    .padding(.top, 8)

                    // Duplicate Warning if Phone Exists
                    if let match = viewModel.duplicateMatch {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            viewModel.rememberCustomer(match)
                            onSelect(match)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Language.get("POS_Customer_DuplicateFound", alter: "عميل مسجل مسبقاً بهذا الرقم!"))
                                        .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.primaryText)
                                    Text(String(format: Language.get("POS_Customer_DuplicateSub", alter: "اضغط هنا لاختيار '%@' مباشرة."), match.name))
                                        .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption2))
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                Image(systemName: "arrowshape.turn.up.right.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Form Fields
                    VStack(spacing: 10) {
                        // Name
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Language.get("POS_Customer_NameField", alter: "اسم العميل"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            TextField(Language.get("POS_Customer_NamePlaceholder", alter: "مثال: سالم الكواري"), text: $viewModel.newName)
                                .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                        }

                        // Phone
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف *"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            HStack(spacing: 6) {
                                Text("🇶🇦 +974")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 8)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                TextField("5512 3456", text: $viewModel.newPhone)
                                    .font(.system(size: 14, weight: .semibold))
                                    .monospacedDigit()
                                    .keyboardType(.phonePad)
                                    .onChange(of: viewModel.newPhone, perform: { newValue in
                                        viewModel.checkDuplicatePhone(newValue)
                                    })
                            }
                            .padding(4)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                        }

                        // Email
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            TextField("customer@example.com", text: $viewModel.newEmail)
                                .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                                .keyboardType(.emailAddress)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                        }

                        // Branch Selector
                        if !viewModel.branches.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("POS_Customer_BranchField", alter: "الفرع المفضل"))
                                    .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.primaryText)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 5) {
                                        ForEach(viewModel.branches, id: \.id) { b in
                                            let active = viewModel.selectedBranchId == b.id
                                            Button {
                                                viewModel.selectedBranchId = active ? "" : b.id
                                            } label: {
                                                Text(b.displayName)
                                                    .font(Font.custom(active ? "Beiruti-Bold" : "Beiruti-Regular", size: 12, relativeTo: .caption))
                                                    .foregroundColor(active ? .white : AdminSurface.primaryText)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 5)
                                                    .background(active ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                                                    .overlay(Capsule().stroke(AdminSurface.hairline))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            }
                        }

                        // Notes
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            TextField(Language.get("POS_Customer_NotePlaceholder", alter: "ملاحظات حول التوصيل أو تفضيلات العميل…"), text: $viewModel.newNote)
                                .font(Font.custom("Beiruti-Regular", size: 14, relativeTo: .body))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                        }
                    }
                }
                .padding(16)
            }

            Divider().background(AdminSurface.hairline)

            // Submit Button
            Button {
                viewModel.submitCreateCustomer { createdCustomer in
                    onSelect(createdCustomer)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white).scaleEffect(0.9)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                    }
                    Text(Language.get("POS_Customer_SubmitCTA", alter: "حفظ وتحديد العميل للسلة"))
                        .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .headline))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: AdminSurface.primary.opacity(0.2), radius: 6, y: 2)
            }
            .disabled(viewModel.isSubmitting)
            .padding(14)
            .background(AdminSurface.surface)
        }
    }
}
