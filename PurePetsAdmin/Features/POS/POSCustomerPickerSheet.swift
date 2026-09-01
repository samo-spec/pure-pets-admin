//
//  POSCustomerPickerSheet.swift
//  PurePetsAdmin
//
//  Reimagined from absolute first principles: Category-defining Customer Directory
//  & Instant Walk-In Registration Chamber for POS Fast Sell operations.
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

    var initials: String {
        let parts = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts.last?.first {
            return "\(first)\(second)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
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

    // Create Form Fields
    @Published var newName: String = ""
    @Published var newPhone: String = ""
    @Published var newEmail: String = ""
    @Published var newNote: String = ""
    @Published var selectedBranchId: String = ""
    @Published var duplicateMatch: POSCustomerRecord? = nil

    private var searchTask: Task<Void, Never>? = nil
    private static let recentsStorageKey = "purepets_pos_recent_customers_v1"

    init() {
        loadRecents()
        loadBranches()
        loadInitialDirectory()
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
                "pageSize": 20
            ]
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any],
                  let items = data["customers"] as? [[String: Any]] else {
                isLoading = false
                return
            }

            searchResults = items.compactMap(parseCustomer)
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
                    "pageSize": 15
                ])
                guard let data = result.data as? [String: Any],
                      let items = data["customers"] as? [[String: Any]] else {
                    self?.isLoading = false
                    return
                }
                if let self { self.searchResults = items.compactMap { self.parseCustomer($0) } }
                self?.isLoading = false
            } catch {
                self?.isLoading = false
            }
        }
    }

    // MARK: - Create Customer

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
                // Ignore transient lookup check errors
            }
        }
    }

    func submitCreateCustomer(onSuccess: @escaping (POSCustomerRecord) -> Void) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = newPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizePhone(phone)

        guard name.count >= 2 else {
            errorMessage = Language.get("POS_Customer_NameTooShort", alter: "يرجى كتابة اسم العميل بالكامل (حرفين على الأقل).")
            return
        }
        guard normalized.count >= 6 else {
            errorMessage = Language.get("POS_Customer_PhoneTooShort", alter: "يرجى إدخال رقم هاتف صحيح (٦ أرقام على الأقل).")
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let callable = Functions.functions().httpsCallable("posCustomerCommand")
                callable.timeoutInterval = 25
                var payload: [String: Any] = [
                    "name": name,
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

    // MARK: - Recents & Persistence

    func rememberCustomer(_ customer: POSCustomerRecord) {
        var updated = recentCustomers.filter { $0.id != customer.id }
        updated.insert(customer, at: 0)
        if updated.count > 8 {
            updated = Array(updated.prefix(8))
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
                "status": c.status
            ]
        }
        UserDefaults.standard.set(serialized, forKey: Self.recentsStorageKey)
    }

    private func loadRecents() {
        guard let list = UserDefaults.standard.array(forKey: Self.recentsStorageKey) as? [[String: String]] else { return }
        recentCustomers = list.compactMap { d -> POSCustomerRecord? in
            guard let id = d["id"], !id.isEmpty,
                  let name = d["name"], !name.isEmpty,
                  let phone = d["phone"], !phone.isEmpty else { return nil }
            return POSCustomerRecord(
                id: id,
                source: "directory",
                name: name,
                phone: phone,
                phoneLookup: d["phoneLookup"] ?? "",
                email: d["email"] ?? "",
                branchId: d["branchId"] ?? "",
                status: d["status"] ?? "active",
                createdAt: nil
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
                    let name = (data["name"] as? String) ?? (data["nameAr"] as? String) ?? (data["branchName"] as? String) ?? doc.documentID
                    return PPInventoryBranchOption(id: doc.documentID, name: name)
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self?.branches = list
            } catch {
                // Non-critical
            }
        }
    }

    private func parseCustomer(_ dict: [String: Any]) -> POSCustomerRecord? {
        let id = (dict["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = (dict["phone"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, !name.isEmpty else { return nil }

        return POSCustomerRecord(
            id: id,
            source: (dict["source"] as? String) ?? "directory",
            name: name,
            phone: phone,
            phoneLookup: (dict["phoneLookup"] as? String) ?? "",
            email: (dict["email"] as? String) ?? "",
            branchId: (dict["branchId"] as? String) ?? "",
            status: (dict["status"] as? String) ?? "active",
            createdAt: dict["createdAt"] as? String
        )
    }
}

// MARK: - Main Sheet View

struct POSCustomerPickerSheet: View {
    let currentSelected: POSCustomerRecord?
    let onSelect: (POSCustomerRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = POSCustomerPickerViewModel()
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar
                    tabSwitcher
                    Divider().background(AdminSurface.hairline)

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    switch viewModel.activeTab {
                    case .search:
                        searchChamber
                    case .create:
                        createChamber
                    }
                }
            }
            .navigationBarHidden(true)
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.2.badge.gearshape.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("POS_Customer_Title", alter: "دليل وربط العملاء"))
                    .font(Font.custom("Beiruti-Bold", size: 20, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
                Text(Language.get("POS_Customer_Subtitle", alter: "اختر العميل المتاح أو أنشئ ملفاً جديداً فورياً للسلة."))
                    .font(Font.custom("Beiruti-Regular", size: 12.5, relativeTo: .caption))
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.control, in: Circle())
            }
            .accessibilityLabel(Language.get("Close", alter: "إغلاق"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(AdminSurface.surface)
    }

    // MARK: - Tab Switcher

    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(POSCustomerPickerTab.allCases) { tab in
                let selected = viewModel.activeTab == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        viewModel.activeTab = tab
                        if tab == .create && viewModel.newName.isEmpty && !viewModel.searchText.isEmpty {
                            viewModel.newName = viewModel.searchText
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

    // MARK: - Error Banner

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

    // MARK: - Search Chamber

    private var searchChamber: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Search Input Island
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AdminSurface.secondaryText)
                        .font(.system(size: 16, weight: .medium))

                    TextField(Language.get("POS_Customer_SearchPlaceholder", alter: "ابحث بالاسم أو رقم الهاتف..."), text: $viewModel.searchText)
                        .font(Font.custom("Beiruti-Regular", size: 15, relativeTo: .body))
                        .foregroundColor(AdminSurface.primaryText)
                        .focused($isSearchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: viewModel.searchText, perform: { newValue in
                            viewModel.handleSearchQueryChanged(newValue)
                        })

                    if !viewModel.searchText.isEmpty {
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

                // Recent Walk-Ins Carousel
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
                                    recentCustomerChip(customer)
                                }
                            }
                        }
                    }
                }

                // Results List
                if viewModel.searchResults.isEmpty && !viewModel.isLoading {
                    emptySearchState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.searchResults) { customer in
                            customerResultCard(customer)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Recent Chip

    private func recentCustomerChip(_ customer: POSCustomerRecord) -> some View {
        Button {
            selectAndDismiss(customer)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(customer.avatarColor)
                        .frame(width: 26, height: 26)
                    Text(customer.initials)
                        .font(.system(size: 10, weight: .bold))
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

    // MARK: - Customer Card

    private func customerResultCard(_ customer: POSCustomerRecord) -> some View {
        let isSelected = currentSelected?.id == customer.id

        return Button {
            selectAndDismiss(customer)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(customer.avatarColor.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Text(customer.initials)
                        .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                        .foregroundColor(customer.avatarColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(customer.name)
                            .font(Font.custom("Beiruti-Bold", size: 15.5, relativeTo: .body))
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

                    HStack(spacing: 10) {
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
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? .green : AdminSurface.secondaryText.opacity(0.7))
            }
            .padding(12)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.green : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Empty State

    private var emptySearchState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                .padding(.top, 24)

            VStack(spacing: 4) {
                Text(Language.get("POS_Customer_NoMatchTitle", alter: "لا توجد نتائج مطابقة"))
                    .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
                if !viewModel.searchText.isEmpty {
                    Text(String(format: Language.get("POS_Customer_NoMatchSub", alter: "لم نجد عميلاً باسم أو هاتف '%@'."), viewModel.searchText))
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }

            if !viewModel.searchText.isEmpty {
                Button {
                    withAnimation(.spring()) {
                        viewModel.newName = viewModel.searchText
                        viewModel.activeTab = .create
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(format: Language.get("POS_Customer_CreateInstantCTA", alter: "إضافة '%@' كعميل جديد"), viewModel.searchText))
                            .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .callout))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(AdminSurface.primary, in: Capsule())
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Create Chamber

    private var createChamber: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Live Monogram Hero Preview
                ZStack {
                    Circle()
                        .fill(viewModel.newName.isEmpty ? Color.gray.opacity(0.15) : AdminSurface.primary.opacity(0.15))
                        .frame(width: 68, height: 68)

                    Text(viewModel.newName.isEmpty ? "؟" : String(viewModel.newName.prefix(2)).uppercased())
                        .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title))
                        .foregroundColor(viewModel.newName.isEmpty ? AdminSurface.secondaryText : AdminSurface.primary)
                }
                .padding(.top, 8)

                // Duplicate Warning if Phone Exists
                if let match = viewModel.duplicateMatch {
                    Button {
                        selectAndDismiss(match)
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
                    formField(
                        title: Language.get("POS_Customer_NameField", alter: "اسم العميل بالكامل *"),
                        placeholder: "مثال: سالم الكواري",
                        icon: "person.fill",
                        text: $viewModel.newName
                    )
                    .focused($isNameFocused)

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

                            TextField("5512 3456", text: $viewModel.newPhone)
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

                    // Email Field (Optional)
                    formField(
                        title: Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني (اختياري)"),
                        placeholder: "customer@example.com",
                        icon: "envelope.fill",
                        text: $viewModel.newEmail,
                        keyboardType: .emailAddress
                    )

                    // Branch Selector (Optional)
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
                                            Text(b.name)
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

                    // Note Field (Optional)
                    formField(
                        title: Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية"),
                        placeholder: "ملاحظات حول التوصيل أو تفضيلات العميل...",
                        icon: "note.text",
                        text: $viewModel.newNote
                    )
                }

                // Submit Button
                Button {
                    viewModel.submitCreateCustomer { createdCustomer in
                        selectAndDismiss(createdCustomer)
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

    // MARK: - Form Field Component

    private func formField(
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

    // MARK: - Selection Handler

    private func selectAndDismiss(_ customer: POSCustomerRecord) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        viewModel.rememberCustomer(customer)
        onSelect(customer)
        dismiss()
    }
}
