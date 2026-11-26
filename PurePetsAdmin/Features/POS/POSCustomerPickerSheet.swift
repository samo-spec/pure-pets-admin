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
import FirebaseAuth
import Combine

// MARK: - Customer Model

struct POSCustomerRecord: Identifiable, Hashable, Sendable, Codable {
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
    let isLinkedAppUser: Bool

    enum CodingKeys: String, CodingKey {
        case id, source, name, phone, phoneLookup, email, branchId, status, createdAt, note, isLinkedAppUser
    }

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
        note: String? = nil,
        isLinkedAppUser: Bool = false
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
        self.isLinkedAppUser = isLinkedAppUser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "directory"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        phoneLookup = try container.decodeIfPresent(String.self, forKey: .phoneLookup) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        branchId = try container.decodeIfPresent(String.self, forKey: .branchId) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        isLinkedAppUser = try container.decodeIfPresent(Bool.self, forKey: .isLinkedAppUser) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(name, forKey: .name)
        try container.encode(phone, forKey: .phone)
        try container.encode(phoneLookup, forKey: .phoneLookup)
        try container.encode(email, forKey: .email)
        try container.encode(branchId, forKey: .branchId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(isLinkedAppUser, forKey: .isLinkedAppUser)
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
        // Stable across launches, including names whose Swift hash is Int.min.
        let index = name.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
        return colors[index]
    }
}

/// Display snapshot only. The callable resolves contact data from this exact UID.
fileprivate struct POSCustomerAppAccount: Identifiable {
    let id: String
    let name: String
    let phone: String
}

// MARK: - Picker Mode

enum POSCustomerPickerPurpose {
    case posCart
    case wantedPetRequest
    case proformaInvoice
    case customerManagement
    case hotelReservation

    var isManagingCustomers: Bool { self == .customerManagement }

    var title: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_Title", alter: "دليل وربط العملاء")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_Title", alter: "دليل العملاء")
        case .proformaInvoice: return Language.get("Proforma_CustomerPicker_Title", alter: nil)
        case .customerManagement: return Language.get("POS_Customer_Management_Title", alter: nil)
        case .hotelReservation: return Language.get("Hotel_CustomerPicker_Title", alter: "دليل عملاء الفندق ونقاط البيع")
        }
    }

    func subtitle(canCreate: Bool) -> String {
        switch self {
        case .posCart:
            return canCreate
                ? Language.get("POS_Customer_Subtitle", alter: "اختر العميل المتاح أو أنشئ ملفاً جديداً فورياً للسلة.")
                : Language.get("POS_Customer_Subtitle_ReadOnly", alter: "اختر عميلاً موجوداً لإرفاقه بهذه السلة.")
        case .wantedPetRequest:
            return canCreate
                ? Language.get("WantedPets_Directory_Subtitle", alter: "اختر عميلاً أو أنشئ ملفاً جديداً لطلب الحيوان.")
                : Language.get("WantedPets_Directory_Subtitle_ReadOnly", alter: "اختر عميلاً موجوداً لطلب الحيوان.")
        case .proformaInvoice:
            return Language.get(canCreate ? "Proforma_CustomerPicker_Subtitle" : "Proforma_CustomerPicker_ReadOnly", alter: nil)
        case .customerManagement:
            return Language.get(canCreate ? "POS_Customer_Management_Subtitle" : "POS_Customer_Management_ReadOnly", alter: nil)
        case .hotelReservation:
            return canCreate
                ? Language.get("Hotel_CustomerPicker_Subtitle", alter: "اختر مالك الحيوان أو أنشئ ملفاً فورياً لربط الحجز والحيوانات.")
                : Language.get("Hotel_CustomerPicker_Subtitle_ReadOnly", alter: "اختر مالك الحيوان من الدليل لربط الحجز.")
        }
    }

    var selectTitle: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_SelectToCart", alter: "ربط العميل بهذه السلة")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_Select", alter: "استخدام هذا العميل")
        case .proformaInvoice: return Language.get("Proforma_CustomerPicker_Select", alter: nil)
        case .customerManagement: return Language.get("POS_Customer_Management_OpenProfile", alter: nil)
        case .hotelReservation: return Language.get("Hotel_CustomerPicker_Select", alter: "ربط المالك بالحجز الفندقي")
        }
    }

    var saveAndSelectTitle: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_SaveAndLink", alter: "حفظ وربط العميل بالسلة")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_SaveAndSelect", alter: "حفظ واستخدام العميل")
        case .proformaInvoice: return Language.get("Proforma_CustomerPicker_Save", alter: nil)
        case .customerManagement: return Language.get("Save", alter: nil)
        case .hotelReservation: return Language.get("Hotel_CustomerPicker_SaveAndSelect", alter: "حفظ وربط المالك بالحجز")
        }
    }

    var createTitle: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_SubmitCTA", alter: "حفظ وتحديد العميل للسلة")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_SaveAndSelect", alter: "حفظ واستخدام العميل")
        case .proformaInvoice: return Language.get("Proforma_CustomerPicker_Save", alter: nil)
        case .customerManagement: return Language.get("Save", alter: nil)
        case .hotelReservation: return Language.get("Hotel_CustomerPicker_Submit", alter: "حفظ وتحديد المالك للحجز")
        }
    }
}

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

// MARK: - POS Customer Credit Store & Summary Cache

@MainActor
final class POSCustomerCreditStore: ObservableObject {
    static let shared = POSCustomerCreditStore()

    struct CreditSummary: Sendable, Codable, Equatable {
        let customerID: String
        let branchID: String
        // A limit is displayed only after its enabled policy has been verified.
        let limitMinor: Int
        let isPolicyVerified: Bool
        let outstandingMinor: Int
        let pendingAmountMinor: Int
        let overdueMinor: Int
        let currency: String

        var availableMinor: Int {
            // Outstanding already includes money awaiting clearance.
            isPolicyVerified ? max(0, limitMinor - outstandingMinor) : 0
        }
        var hasRemainingCredit: Bool { isPolicyVerified && availableMinor > 0 }
        var hasBlockingCreditLocally: Bool {
            outstandingMinor > 0 || pendingAmountMinor > 0 || (isPolicyVerified && limitMinor > 0)
        }
        var shouldDisplayCreditView: Bool {
            (isPolicyVerified && limitMinor > 0)
                || outstandingMinor > 0
                || pendingAmountMinor > 0
                || overdueMinor > 0
        }
    }

    @Published private(set) var summaries: [String: CreditSummary] = [:]
    @Published private(set) var revision = 0
    private var requests: [String: UUID] = [:]
    private var failedKeys: Set<String> = []
    private var subscriptions = Set<AnyCancellable>()
    private nonisolated(unsafe) var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        for name in ["PPAccountingDataDidChangeNotification", "PPAdminCommandAuthorizationDidChangeNotification"] {
            NotificationCenter.default.publisher(for: Notification.Name(name))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.invalidateAll() }
                .store(in: &subscriptions)
        }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in self?.invalidateAll() }
        }
    }
    deinit { if let authListener { Auth.auth().removeStateDidChangeListener(authListener) } }

    private func key(_ customerID: String, _ branchID: String) -> String {
        // Length prefixes avoid collisions between otherwise ambiguous IDs.
        "\(customerID.utf8.count):\(customerID)\(branchID.utf8.count):\(branchID)"
    }
    private func branch(_ value: String) -> String {
        value.isEmpty ? (BranchContextStore.shared.activeBranch?.branchID ?? "") : value
    }
    func summary(for customerID: String, branchID: String) -> CreditSummary? {
        let branchID = branch(branchID)
        guard !customerID.isEmpty, POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) else { return nil }
        return summaries[key(customerID, branchID)]
    }

    func loadCreditSummary(for customerID: String, branchID: String) {
        let branchID = branch(branchID)
        let key = key(customerID, branchID)
        guard !customerID.isEmpty, POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID),
              let actor = Auth.auth().currentUser?.uid, summaries[key] == nil, requests[key] == nil, !failedKeys.contains(key) else { return }
        let ticket = UUID()
        requests[key] = ticket
        let body: [String: Any] = ["contractVersion": 1, "customerId": customerID, "branchId": branchID, "currency": "QAR", "kind": "invoices", "pageSize": 1]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            requests.removeValue(forKey: key); return
        }
        PPPOSService.shared().callCreditOperation("getCustomerReceivables", request: data, actorUID: actor) { [weak self] data, error in
            Task { @MainActor in
                guard let self, self.requests[key] == ticket, Auth.auth().currentUser?.uid == actor,
                      POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) else { return }
                guard error == nil, let data, let page = try? JSONDecoder().decode(POSCreditAccountPage<POSCreditAccountInvoice>.self, from: data),
                      page.ok, page.customerId == customerID, page.branchId == branchID, page.currency == "QAR", page.kind == "invoices",
                      page.summary.outstandingMinor >= 0, page.summary.pendingAmountMinor >= 0,
                      page.summary.pendingAmountMinor <= page.summary.outstandingMinor else {
                    self.requests.removeValue(forKey: key); self.failedKeys.insert(key); return
                }
                let balance = page.summary
                // Publish the verified debt immediately. Policy failure must never replace it with zero.
                self.summaries[key] = CreditSummary(customerID: customerID, branchID: branchID, limitMinor: 0, isPolicyVerified: false,
                    outstandingMinor: balance.outstandingMinor, pendingAmountMinor: balance.pendingAmountMinor,
                    overdueMinor: balance.overdueMinor, currency: page.currency)
                self.loadPolicy(customerID: customerID, branchID: branchID, actor: actor, key: key, ticket: ticket, balance: balance)
            }
        }
    }

    private func loadPolicy(customerID: String, branchID: String, actor: String, key: String, ticket: UUID, balance: POSCreditAccountSummary) {
        let body: [String: Any] = ["contractVersion": 1, "action": "list", "customerId": customerID, "branchId": branchID, "currency": "QAR"]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys) else {
            requests.removeValue(forKey: key); return
        }
        PPPOSService.shared().callCreditOperation("posCreditReviewCommand", request: data, actorUID: actor) { [weak self] data, error in
            Task { @MainActor in
                guard let self, self.requests[key] == ticket, Auth.auth().currentUser?.uid == actor,
                      POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID) else { return }
                self.requests.removeValue(forKey: key)
                guard error == nil, let data, let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      value["ok"] as? Bool == true, value["customerId"] as? String == customerID,
                      value["branchId"] as? String == branchID, value["currency"] as? String == "QAR",
                      let policy = value["policy"] as? [String: Any], policy["enabled"] as? Bool == true,
                      let limit = policy["limitMinor"] as? Int, limit >= 0 else { return }
                self.summaries[key] = CreditSummary(customerID: customerID, branchID: branchID, limitMinor: limit, isPolicyVerified: true,
                    outstandingMinor: balance.outstandingMinor, pendingAmountMinor: balance.pendingAmountMinor,
                    overdueMinor: balance.overdueMinor, currency: "QAR")
            }
        }
    }

    func preloadCreditSummaries(for customers: [POSCustomerRecord], branchID: String) {
        for customer in customers.prefix(25) where customer.source == "directory" {
            loadCreditSummary(for: customer.id, branchID: branchID)
        }
    }
    func invalidate(customerID: String, branchID: String) {
        let key = key(customerID, branch(branchID))
        summaries.removeValue(forKey: key); requests.removeValue(forKey: key); failedKeys.remove(key)
        revision &+= 1
    }
    func invalidateAll() {
        requests.removeAll(); failedKeys.removeAll(); summaries.removeAll()
        revision &+= 1
    }
}

// MARK: - POS Customer Cache Store & Firestore Synchronizer

final class POSCustomerCacheStore: ObservableObject, @unchecked Sendable {
    static let shared = POSCustomerCacheStore()

    private let storageKey = "purepets_pos_customers_directory_cache_v2"
    private let lastSyncKey = "purepets_pos_customers_cache_last_sync_v2"
    private let queue = DispatchQueue(label: "com.purepets.admin.pos.customercache", qos: .utility)

    private var inMemoryCache: [POSCustomerRecord] = []
    private var lastSyncTimestamp: Date? = nil

    private init() {
        loadFromDisk()
    }

    func getCachedCustomers() -> [POSCustomerRecord] {
        queue.sync { inMemoryCache }
    }

    func getLastSyncDate() -> Date? {
        queue.sync { lastSyncTimestamp }
    }

    func upsert(_ customer: POSCustomerRecord) {
        queue.async { [weak self] in
            guard let self else { return }
            var list = self.inMemoryCache
            if let idx = list.firstIndex(where: { $0.id == customer.id }) {
                list[idx] = customer
            } else {
                list.insert(customer, at: 0)
            }
            if list.count > 500 {
                list = Array(list.prefix(500))
            }
            self.inMemoryCache = list
            self.persistLocked(list)
        }
    }

    func remove(customerId: String) {
        guard !customerId.isEmpty else { return }
        queue.sync {
            var list = inMemoryCache
            let beforeCount = list.count
            list.removeAll { $0.id == customerId }
            if list.count != beforeCount {
                inMemoryCache = list
                persistLocked(list)
            }
        }
    }

    func mergeAndPersist(incoming: [POSCustomerRecord], replaceIfFewerThanPageSize pageSize: Int? = nil) -> [POSCustomerRecord] {
        queue.sync {
            if let pageSize, incoming.count < pageSize {
                var deduped: [POSCustomerRecord] = []
                var seen = Set<String>()
                for c in incoming {
                    if !seen.contains(c.id) {
                        deduped.append(c)
                        seen.insert(c.id)
                    }
                }
                self.inMemoryCache = deduped
                self.lastSyncTimestamp = Date()
                self.persistLocked(deduped)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
                return deduped
            }
            var map: [String: POSCustomerRecord] = [:]
            for c in inMemoryCache {
                map[c.id] = c
            }
            for c in incoming {
                map[c.id] = c
            }
            var result: [POSCustomerRecord] = []
            var seen = Set<String>()
            for c in incoming {
                if !seen.contains(c.id) {
                    result.append(c)
                    seen.insert(c.id)
                }
            }
            for c in inMemoryCache {
                if !seen.contains(c.id) {
                    if let updated = map[c.id] {
                        result.append(updated)
                    }
                    seen.insert(c.id)
                }
            }
            if result.count > 500 {
                result = Array(result.prefix(500))
            }
            self.inMemoryCache = result
            self.lastSyncTimestamp = Date()
            self.persistLocked(result)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)
            return result
        }
    }

    func filterLocally(term: String) -> [POSCustomerRecord] {
        let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return getCachedCustomers()
        }

        let normTerm = POSCustomerNormalization.normalize(cleaned)
        let digitMap: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        let cleanedDigits = cleaned.compactMap { digitMap[$0] ?? $0 }
            .filter { $0.isNumber }
            .map { String($0) }
            .joined()

        let list = getCachedCustomers()
        return list.filter { customer in
            if !cleanedDigits.isEmpty {
                let customerDigits = customer.phone.compactMap { digitMap[$0] ?? $0 }
                    .filter { $0.isNumber }
                    .map { String($0) }
                    .joined()
                if customerDigits.contains(cleanedDigits) || customer.phoneLookup.contains(cleanedDigits) {
                    return true
                }
            }

            let normName = POSCustomerNormalization.normalize(customer.name)
            if normName.contains(normTerm) {
                return true
            }

            if !customer.email.isEmpty && customer.email.lowercased().contains(cleaned.lowercased()) {
                return true
            }

            if let note = customer.note, !note.isEmpty {
                let normNote = POSCustomerNormalization.normalize(note)
                if normNote.contains(normTerm) {
                    return true
                }
            }

            return false
        }
    }

    private func persistLocked(_ list: [POSCustomerRecord]) {
        do {
            let data = try JSONEncoder().encode(list)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Non-fatal
        }
    }

    private func loadFromDisk() {
        if let ts = UserDefaults.standard.object(forKey: lastSyncKey) as? Double {
            lastSyncTimestamp = Date(timeIntervalSince1970: ts)
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([POSCustomerRecord].self, from: data)
            inMemoryCache = decoded
        } catch {
            // Non-fatal fallback
        }
    }
}

enum POSCustomerNormalization {
    static func normalize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        s = s.replacingOccurrences(of: "أ", with: "ا")
             .replacingOccurrences(of: "إ", with: "ا")
             .replacingOccurrences(of: "آ", with: "ا")
             .replacingOccurrences(of: "ة", with: "ه")
             .replacingOccurrences(of: "ى", with: "ي")
        return s
    }
}

// MARK: - ViewModel

@MainActor
final class POSCustomerPickerViewModel: ObservableObject {
    @Published var activeTab: POSCustomerPickerTab = .search
    @Published var searchText: String = ""
    @Published var searchResults: [POSCustomerRecord] = [] {
        didSet {
            preloadCreditsForCurrentResults()
        }
    }
    @Published var recentCustomers: [POSCustomerRecord] = []
    @Published var branches: [PPInventoryBranchOption] = []
    @Published var isLoading: Bool = false
    @Published var isSubmitting: Bool = false
    @Published var errorMessage: String? = nil
    @Published var successFeedbackMessage: String? = nil
    @Published fileprivate var attachmentCandidate: POSCustomerAppAccount? = nil
    @Published var isAttachingUser = false
    @Published var attachmentError: String? = nil

    // Cache & Firestore Verification State
    @Published var isSyncingWithFirestore: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var cachedDirectoryCount: Int = 0

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
    @Published var editPhone: String = ""
    @Published var editEmail: String = ""
    @Published var editNote: String = ""
    @Published var editBranchId: String = ""
    @Published var isEditingSubmitting: Bool = false
    @Published var isDeletingCustomer: Bool = false
    @Published var deletingCustomerId: String? = nil

    // iPad Cockpit State
    @Published var highlightedCustomer: POSCustomerRecord? = nil
    @Published var copiedPhoneId: String? = nil

    private var searchTask: Task<Void, Never>? = nil
    private var directoryGeneration = 0
    private static let recentsStorageKey = "purepets_pos_recent_customers_v1"

    init() {
        loadRecents()
        loadBranches()
        loadInitialDirectory()
    }

    private func preloadCreditsForCurrentResults() {
        let branchID = BranchContextStore.shared.activeBranch?.branchID ?? ""
        if !branchID.isEmpty {
            POSCustomerCreditStore.shared.preloadCreditSummaries(for: searchResults, branchID: branchID)
        }
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

    // MARK: - Search & Cache Verification Logic

    func handleSearchQueryChanged(_ query: String) {
        searchTask?.cancel()
        directoryGeneration += 1
        let generation = directoryGeneration
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loadInitialDirectory()
            return
        }

        // 1. Instant local filter from cache (0ms latency)
        let localMatches = POSCustomerCacheStore.shared.filterLocally(term: trimmed)
        if !localMatches.isEmpty {
            self.searchResults = localMatches
            if highlightedCustomer == nil || !localMatches.contains(where: { $0.id == highlightedCustomer?.id }) {
                highlightedCustomer = localMatches.first
            }
        }

        // 2. Debounced live Firestore verification query
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await self?.executeSearchAndVerify(term: trimmed, generation: generation)
        }
    }

    private func executeSearchAndVerify(term: String, generation: Int) async {
        if searchResults.isEmpty {
            isLoading = true
        }
        isSyncingWithFirestore = true
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
            guard !Task.isCancelled, generation == directoryGeneration else { return }
            guard let data = result.data as? [String: Any],
                  let items = data["customers"] as? [[String: Any]] else {
                isLoading = false
                isSyncingWithFirestore = false
                return
            }

            let parsed = items.compactMap(parseCustomer)
            
            // Merge newly found customers into the persistent cache
            let _ = POSCustomerCacheStore.shared.mergeAndPersist(incoming: parsed)

            // Combine remote results with any local cache results to avoid missing anything
            var combined = parsed
            let localMatches = POSCustomerCacheStore.shared.filterLocally(term: term)
            for local in localMatches {
                if !combined.contains(where: { $0.id == local.id }) {
                    combined.append(local)
                }
            }

            searchResults = combined
            if highlightedCustomer == nil || !combined.contains(where: { $0.id == highlightedCustomer?.id }) {
                highlightedCustomer = combined.first
            }
            isLoading = false
            isSyncingWithFirestore = false
            lastSyncDate = Date()
        } catch {
            guard !Task.isCancelled, generation == directoryGeneration else { return }
            isLoading = false
            isSyncingWithFirestore = false
            if searchResults.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadInitialDirectory() {
        guard searchText.isEmpty else { return }

        // 1. Immediately load and present cached customers (0ms instant presentation)
        let cached = POSCustomerCacheStore.shared.getCachedCustomers()
        if !cached.isEmpty {
            self.searchResults = cached
            self.cachedDirectoryCount = cached.count
            self.lastSyncDate = POSCustomerCacheStore.shared.getLastSyncDate()
            self.isLoading = false
            if self.highlightedCustomer == nil {
                self.highlightedCustomer = cached.first ?? self.recentCustomers.first
            }
        } else {
            self.isLoading = true
        }

        // 2. Concurrently verify and sync with Firestore
        verifyAndSyncWithFirestore()
    }

    func verifyAndSyncWithFirestore() {
        directoryGeneration += 1
        let generation = directoryGeneration
        isSyncingWithFirestore = true
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
                guard let self, generation == self.directoryGeneration else { return }
                guard let data = result.data as? [String: Any],
                      let items = data["customers"] as? [[String: Any]] else {
                    self.isLoading = false
                    self.isSyncingWithFirestore = false
                    if self.searchResults.isEmpty {
                        self.errorMessage = Language.get("POS_Customer_DirectoryLoadFailed", alter: "تعذر تحميل دليل العملاء. تحقق من الاتصال وحاول مرة أخرى.")
                    }
                    return
                }

                let parsed = items.compactMap { self.parseCustomer($0) }
                
                // Merge authoritative Firestore records into local cache (replace when authoritative list fits inside pageSize)
                let merged = POSCustomerCacheStore.shared.mergeAndPersist(incoming: parsed, replaceIfFewerThanPageSize: 25)
                
                // Update recents if any were modified or removed on Firestore
                self.syncRecentsWithUpdatedCustomers(merged, authoritativeIds: parsed.count < 25 ? Set(parsed.map(\.id)) : nil)

                // If user hasn't typed a search in the meantime, update searchResults
                if self.searchText.isEmpty {
                    self.searchResults = merged
                    if self.highlightedCustomer == nil || !merged.contains(where: { $0.id == self.highlightedCustomer?.id }) {
                        self.highlightedCustomer = merged.first ?? self.recentCustomers.first
                    }
                }
                self.cachedDirectoryCount = merged.count
                self.lastSyncDate = Date()
                self.isLoading = false
                self.isSyncingWithFirestore = false
            } catch {
                guard let self, generation == self.directoryGeneration else { return }
                self.isLoading = false
                self.isSyncingWithFirestore = false
                if self.searchResults.isEmpty {
                    self.errorMessage = Language.get("POS_Customer_DirectoryLoadFailed", alter: "تعذر تحميل دليل العملاء. تحقق من الاتصال وحاول مرة أخرى.")
                }
            }
        }
    }

    func refreshFromFirestoreAsync() async {
        POSCustomerCreditStore.shared.invalidateAll()
        isSyncingWithFirestore = true
        do {
            let callable = Functions.functions().httpsCallable("posCustomerCommand")
            callable.timeoutInterval = 20
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [String: Any] = [
                "action": "search",
                "term": trimmedSearch,
                "pageSize": 25
            ]
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any],
                  let items = data["customers"] as? [[String: Any]] else {
                isSyncingWithFirestore = false
                return
            }
            let parsed = items.compactMap { self.parseCustomer($0) }
            let isExhaustive = trimmedSearch.isEmpty && parsed.count < 25
            let merged = POSCustomerCacheStore.shared.mergeAndPersist(
                incoming: parsed,
                replaceIfFewerThanPageSize: trimmedSearch.isEmpty ? 25 : nil
            )
            self.syncRecentsWithUpdatedCustomers(merged, authoritativeIds: isExhaustive ? Set(parsed.map(\.id)) : nil)
            
            if searchText.isEmpty {
                self.searchResults = merged
            } else {
                var combined = parsed
                let local = POSCustomerCacheStore.shared.filterLocally(term: searchText)
                for l in local {
                    if !combined.contains(where: { $0.id == l.id }) {
                        combined.append(l)
                    }
                }
                self.searchResults = combined
            }
            
            self.cachedDirectoryCount = merged.count
            self.lastSyncDate = Date()
            self.isSyncingWithFirestore = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            isSyncingWithFirestore = false
        }
    }

    private func syncRecentsWithUpdatedCustomers(_ updatedList: [POSCustomerRecord], authoritativeIds: Set<String>? = nil) {
        var recentsChanged = false
        var updatedRecents = recentCustomers
        if let authoritativeIds {
            let before = updatedRecents.count
            updatedRecents.removeAll { !authoritativeIds.contains($0.id) }
            if updatedRecents.count != before {
                recentsChanged = true
            }
        }
        for updated in updatedList {
            if let idx = updatedRecents.firstIndex(where: { $0.id == updated.id }) {
                if updatedRecents[idx] != updated {
                    updatedRecents[idx] = updated
                    recentsChanged = true
                }
            }
        }
        if recentsChanged {
            recentCustomers = updatedRecents
            saveRecents()
        }
    }

    // MARK: - Verified account attachment

    var canAttachAppUser: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isActive() else { return false }
        return staff.hasPermission(kStaffPermPosSell) &&
            staff.hasAnyPermission([kStaffPermUsersView, kStaffPermUsersManage])
    }

    fileprivate func prepareAttachment(_ account: POSCustomerAppAccount) {
        attachmentError = nil
        attachmentCandidate = account
    }

    func attachSelectedAccount(overridePhone: String? = nil) {
        guard !isAttachingUser, let account = attachmentCandidate else { return }
        guard canAttachAppUser else {
            attachmentError = Language.get("POS_Customer_AttachUser_NoAccess", alter: nil)
            return
        }
        let uid = account.id
        var payload: [String: Any] = ["userUid": uid]
        let cleanPhone = (overridePhone ?? account.phone).trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPhone.isEmpty {
            payload["phone"] = cleanPhone
        }
        isAttachingUser = true
        attachmentError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.isAttachingUser = false }
            do {
                let callable = Functions.functions().httpsCallable("posCustomerCommand")
                callable.timeoutInterval = 25
                let result = try await callable.call([
                    "action": "attachUser", "payload": payload
                ])
                guard let data = result.data as? [String: Any], data["ok"] as? Bool == true,
                      let raw = data["customer"] as? [String: Any],
                      let customer = self.parseCustomer(raw), customer.isLinkedAppUser else {
                    self.attachmentError = Language.get("POS_Customer_AttachUser_Failed", alter: nil)
                    return
                }
                // Invalidate older searches before merging the authoritative result.
                self.searchTask?.cancel()
                self.directoryGeneration += 1
                self.isLoading = false
                self.searchText = customer.phone
                self.searchResults.removeAll { $0.id == customer.id }
                self.searchResults.insert(customer, at: 0)
                self.rememberCustomer(customer)
                POSCustomerCacheStore.shared.upsert(customer)
                self.lastSyncDate = Date()
                self.highlightedCustomer = customer
                self.attachmentCandidate = nil
                self.successFeedbackMessage = Language.get(
                    data["alreadyAttached"] as? Bool == true
                        ? "POS_Customer_AttachUser_AlreadyAdded" : "POS_Customer_AttachUser_Success", alter: nil
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.attachmentError = self.attachmentFailureMessage(error)
            }
        }
    }

    private func attachmentFailureMessage(_ error: Error) -> String {
        let functionError = error as NSError
        guard functionError.domain == FunctionsErrorDomain else {
            return Language.get("POS_Customer_AttachUser_Failed", alter: nil)
        }
        let code = functionError.code
        let key: String
        switch code {
        case FunctionsErrorCode.permissionDenied.rawValue, FunctionsErrorCode.unauthenticated.rawValue:
            key = "POS_Customer_AttachUser_NoAccess"
        case FunctionsErrorCode.notFound.rawValue:
            key = "POS_Customer_AttachUser_NotFound"
        case FunctionsErrorCode.failedPrecondition.rawValue, FunctionsErrorCode.alreadyExists.rawValue:
            key = "POS_Customer_AttachUser_Unavailable"
        case FunctionsErrorCode.invalidArgument.rawValue:
            key = "POS_Customer_AttachUser_InvalidContact"
        default:
            key = "POS_Customer_AttachUser_Failed"
        }
        return Language.get(key, alter: nil)
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

    /// Keeps standalone management in the existing directory after a save or
    /// duplicate lookup; selection callers continue to own their own dismissal.
    func showManagedCustomer(_ customer: POSCustomerRecord) {
        searchTask?.cancel()
        directoryGeneration += 1
        isLoading = false
        isSyncingWithFirestore = false
        errorMessage = nil
        activeTab = .search
        searchText = ""
        searchResults = POSCustomerCacheStore.shared.getCachedCustomers()
        searchResults.removeAll { $0.id == customer.id }
        searchResults.insert(customer, at: 0)
        searchResults = Array(searchResults.prefix(500))
        cachedDirectoryCount = searchResults.count
        highlightedCustomer = customer
        newName = ""
        newPhone = ""
        newEmail = ""
        newNote = ""
        selectedBranchId = ""
        duplicateMatch = nil
    }

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
                POSCustomerCacheStore.shared.upsert(customer)
                self.lastSyncDate = Date()
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
        editPhone = customer.phone
        editEmail = customer.email
        editNote = customer.note ?? ""
        editBranchId = customer.branchId
        errorMessage = nil
    }

    func cancelEditing() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        editingCustomer = nil
        editName = ""
        editPhone = ""
        editEmail = ""
        editNote = ""
        editBranchId = ""
    }

    func submitUpdateCustomer(andSelect: Bool = false, onSuccess: @escaping (POSCustomerRecord) -> Void) {
        guard let customer = editingCustomer else { return }

        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName = Language.get("POS_Customer_DefaultName", alter: "عميل نقطة بيع")
        let finalName = trimmedName.isEmpty ? defaultName : trimmedName

        let phone = editPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizePhone(phone)
        guard normalized.count >= 6 else {
            errorMessage = Language.get("POS_Customer_PhoneTooShort", alter: "يرجى إدخال رقم هاتف صحيح (٦ أرقام على الأقل).")
            return
        }

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
                    "phone": phone,
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
                if let idx = self.searchResults.firstIndex(where: { $0.id == updatedCustomer.id || $0.id == customer.id }) {
                    self.searchResults[idx] = updatedCustomer
                }

                // Update recents
                self.rememberCustomer(updatedCustomer)
                POSCustomerCacheStore.shared.upsert(updatedCustomer)
                self.lastSyncDate = Date()
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

    // MARK: - Delete Customer Lifecycle

    func removeDeletedCustomerLocally(_ customer: POSCustomerRecord) {
        let customerId = customer.id
        searchResults.removeAll { $0.id == customerId }
        if recentCustomers.contains(where: { $0.id == customerId }) {
            recentCustomers.removeAll { $0.id == customerId }
            saveRecents()
        }
        POSCustomerCacheStore.shared.remove(customerId: customerId)
        cachedDirectoryCount = searchResults.count
        POSCustomerCreditStore.shared.invalidate(customerID: customerId, branchID: customer.branchId)
        if let activeBranchId = BranchContextStore.shared.activeBranch?.branchID, !activeBranchId.isEmpty {
            POSCustomerCreditStore.shared.invalidate(customerID: customerId, branchID: activeBranchId)
        }
        if editingCustomer?.id == customerId {
            editingCustomer = nil
            editName = ""
            editPhone = ""
            editEmail = ""
            editNote = ""
            editBranchId = ""
        }
        if highlightedCustomer?.id == customerId {
            highlightedCustomer = searchResults.first ?? recentCustomers.first
        }
    }

    func deleteCustomer(_ customer: POSCustomerRecord, onSuccess: @escaping () -> Void = {}) {
        guard !isDeletingCustomer, !isSubmitting, !isEditingSubmitting, !isAttachingUser,
              customer.source == "directory", !customer.id.isEmpty else { return }

        isDeletingCustomer = true
        deletingCustomerId = customer.id
        errorMessage = nil
        successFeedbackMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let callable = Functions.functions().httpsCallable("posCustomerCommand")
                callable.timeoutInterval = 25
                let result = try await callable.call([
                    "action": "delete",
                    "payload": ["customerId": customer.id]
                ])

                guard let data = result.data as? [String: Any],
                      data["ok"] as? Bool == true,
                      data["deleted"] as? Bool == true else {
                    self.isDeletingCustomer = false
                    self.deletingCustomerId = nil
                    self.errorMessage = Language.get("POS_Customer_DeleteBlockedCredit", alter: nil)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }

                self.removeDeletedCustomerLocally(customer)
                self.lastSyncDate = Date()
                self.isDeletingCustomer = false
                self.deletingCustomerId = nil
                self.successFeedbackMessage = Language.get("POS_Customer_DeleteSuccess", alter: nil)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSuccess()

                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if self?.successFeedbackMessage == Language.get("POS_Customer_DeleteSuccess", alter: nil) {
                        self?.successFeedbackMessage = nil
                    }
                }
            } catch {
                self.isDeletingCustomer = false
                self.deletingCustomerId = nil

                let nsError = error as NSError
                let details = nsError.userInfo["details"] as? [String: Any]
                    ?? nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any]
                    ?? [:]
                let domainCode = details["domainCode"] as? String ?? ""

                if domainCode == "POS_CUSTOMER_NOT_FOUND" ||
                    (nsError.domain == FunctionsErrorDomain && nsError.code == FunctionsErrorCode.notFound.rawValue) {
                    self.removeDeletedCustomerLocally(customer)
                    self.successFeedbackMessage = Language.get("POS_Customer_DeleteAlreadyRemoved", alter: nil)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    onSuccess()
                    return
                }

                self.errorMessage = self.deletionFailureMessage(error)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func deletionFailureMessage(_ error: Error) -> String {
        let nsError = error as NSError
        let details = nsError.userInfo["details"] as? [String: Any]
            ?? nsError.userInfo["FIRFunctionsErrorDetailsKey"] as? [String: Any]
            ?? [:]
        switch details["domainCode"] as? String ?? "" {
        case "POS_CUSTOMER_HAS_CREDIT_AND_SALES":
            return Language.get("POS_Customer_DeleteBlockedCreditAndSales", alter: nil)
        case "POS_CUSTOMER_HAS_CREDIT":
            return Language.get("POS_Customer_DeleteBlockedCredit", alter: nil)
        case "POS_CUSTOMER_HAS_SALES":
            return Language.get("POS_Customer_DeleteBlockedSales", alter: nil)
        case "POS_CUSTOMER_HAS_PROFORMA":
            return Language.get("POS_Customer_DeleteBlockedProforma", alter: nil)
        case "POS_CUSTOMER_INACTIVE":
            return Language.get("POS_Customer_DeleteBlockedInactive", alter: nil)
        default:
            break
        }
        if nsError.domain == FunctionsErrorDomain,
           nsError.code == FunctionsErrorCode.permissionDenied.rawValue ||
           nsError.code == FunctionsErrorCode.unauthenticated.rawValue {
            return Language.get("POS_Customer_DeletePermissionDenied", alter: nil)
        }
        return error.localizedDescription
    }

    // MARK: - Quick Actions

    func copyPhone(customer: POSCustomerRecord) {
        copyPhone(phone: customer.phone, customerId: customer.id)
    }

    func copyPhone(phone: String, customerId: String) {
        UIPasteboard.general.string = phone
        copiedPhoneId = customerId
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self?.copiedPhoneId == customerId {
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
                "note": c.note ?? "",
                "isLinkedAppUser": c.isLinkedAppUser ? "1" : "0"
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
                note: d["note"],
                isLinkedAppUser: d["isLinkedAppUser"] == "1"
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
            note: dict["note"] as? String,
            isLinkedAppUser: dict["isLinkedAppUser"] as? Bool ?? false
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

/// A contact has one selection target and an independent editing target.
/// Technical identifiers read LTR while their physical alignment follows Arabic.
private struct POSCustomerCreditBalance: View {
    let summary: POSCustomerCreditStore.CreditSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(POSCreditAccountCopy.text("Outstanding")) · \(POSCreditAccountCopy.money(summary.outstandingMinor))")
                .font(PPBrandFont.bold(17, relativeTo: .headline))
                .foregroundStyle(summary.overdueMinor > 0 ? AdminSurface.crimson : AdminSurface.primaryText)
            if summary.isPolicyVerified {
                let available = summary.availableMinor
                Text("\(POSCreditAccountCopy.text("CollectionAvailableCredit")) · \(POSCreditAccountCopy.money(available))")
                    .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            }
            if summary.pendingAmountMinor > 0 {
                Label("\(POSCreditAccountCopy.text("CollectionAwaiting")) · \(POSCreditAccountCopy.money(summary.pendingAmountMinor))", systemImage: "clock")
                    .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            }
            if summary.overdueMinor > 0 {
                Text(POSCreditAccountCopy.text("Overdue")).font(AdminType.footnoteBold).foregroundStyle(AdminSurface.crimson)
            }
        }
        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(summary.outstandingMinor == 0 ? AdminSurface.background : AdminSurface.primarySoft,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if summary.outstandingMinor != 0 {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(AdminSurface.primary.opacity(0.16), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct POSCustomerIdentityCell: View {
    let customer: POSCustomerRecord
    let branchName: String
    let isSelected: Bool
    let selectionHint: String
    let onSelect: () -> Void
    let onEdit: (() -> Void)?
    var creditBranchID: String? = nil
    @ObservedObject private var creditStore = POSCustomerCreditStore.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction

    private var effectiveBranchID: String {
        creditBranchID ?? BranchContextStore.shared.activeBranch?.branchID ?? customer.branchId
    }

    private var creditSummary: POSCustomerCreditStore.CreditSummary? {
        creditStore.summary(for: customer.id, branchID: effectiveBranchID)
    }

    private var showsCreditAction: Bool {
        guard let branchID = creditBranchID else { return false }
        // Collection action button appears only when there is an outstanding amount owed to collect.
        return (creditSummary?.outstandingMinor ?? 0) > 0 && POSCreditAccountCopy.permitted("pos.credit.collect", branchID: branchID)
    }

    private var note: String { (customer.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isUnavailable: Bool {
        ["blocked", "banned", "disabled", "deactivated", "deleted", "suspended", "archived", "inactive"]
            .contains(customer.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            selectionButton
            if let credit = creditSummary, credit.shouldDisplayCreditView {
                remainingCreditBadge(credit)
                    .padding(.leading, typeSize.isAccessibilitySize ? AdminSpacing.base : 72)
                    .padding(.trailing, AdminSpacing.base)
                    .padding(.vertical, AdminSpacing.sm)
            }
            if showsCreditAction || onEdit != nil {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.base))
                layout {
                    if showsCreditAction, let branchID = creditBranchID {
                        POSCreditAccountLink(customerID: customer.id, branchID: branchID, compact: true, opensCollection: true)
                    }
                    if onEdit != nil { editButton }
                }
                .padding(.leading, typeSize.isAccessibilitySize ? AdminSpacing.base : 72)
                .padding(.trailing, AdminSpacing.base)
                .padding(.bottom, AdminSpacing.xs)
            }
        }
        .background(isSelected ? AdminSurface.primary.opacity(0.045) : Color.clear)
        .task(id: "\(effectiveBranchID):\(creditStore.revision)") {
            if !effectiveBranchID.isEmpty {
                creditStore.loadCreditSummary(for: customer.id, branchID: effectiveBranchID)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var selectionButton: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                if !typeSize.isAccessibilitySize {
                    Text(customer.initials)
                        .font(PPBrandFont.bold(19, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.primary.opacity(0.07), in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
                        Text(customer.name)
                            .font(PPBrandFont.bold(20, relativeTo: .headline))
                            .foregroundStyle(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: isSelected ? "checkmark" : "chevron.forward")
                            .font(.system(size: isSelected ? 16 : 11, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                            .accessibilityHidden(true)
                    }
                    if !customer.phone.isEmpty { contactLine(customer.phone, icon: "phone", isEmail: false) }
                    if !customer.email.isEmpty { contactLine(customer.email, icon: "envelope", isEmail: true) }
                    if !branchName.isEmpty { metadataLine(branchName, icon: "mappin") }
                    if customer.isLinkedAppUser {
                        metadataLine(Language.get("POS_Customer_AppUserBadge", alter: nil), icon: "person.crop.circle")
                    }
                    if isUnavailable { metadataLine(Language.get("POS_Customer_InactiveContact", alter: nil), icon: "lock") }

                    if !note.isEmpty {
                        Text(note)
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.base)
            .padding(.top, AdminSpacing.base)
            .padding(.bottom, (creditSummary?.shouldDisplayCreditView == true) || showsCreditAction || onEdit != nil ? AdminSpacing.xs : AdminSpacing.base)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(POSCustomerContactPressStyle())
        .disabled(isUnavailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(customer.name)
        .accessibilityValue([customer.phone, customer.email, branchName, note,
            customer.isLinkedAppUser ? Language.get("POS_Customer_AppUserBadge", alter: nil) : "",
            isUnavailable ? Language.get("POS_Customer_InactiveContact", alter: nil) : ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(selectionHint)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("pos.customer.select.\(customer.id)")
    }

    private func contactLine(_ value: String, icon: String, isEmail: Bool) -> some View {
        // The whole technical line reads LTR; its physical edge follows the surrounding language.
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
            if direction != .rightToLeft { Image(systemName: icon).font(.caption) }
            Text(value)
                .font(isEmail ? AdminType.footnote : AdminType.subheadline)
                .multilineTextAlignment(direction == .rightToLeft ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if direction == .rightToLeft { Image(systemName: icon).font(.caption) }
        }
        .frame(maxWidth: .infinity, alignment: direction == .rightToLeft ? .trailing : .leading)
        .environment(\.layoutDirection, .leftToRight)
        .foregroundStyle(AdminSurface.secondaryText)
    }

    private func metadataLine(_ value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
            Image(systemName: icon).font(.caption)
                .accessibilityHidden(true)
            Text(value)
                .font(AdminType.footnote)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AdminSurface.secondaryText)
    }

    private func remainingCreditBadge(_ credit: POSCustomerCreditStore.CreditSummary) -> some View {
        let collect = credit.outstandingMinor > 0 && POSCreditAccountCopy.permitted("pos.credit.collect", branchID: effectiveBranchID)
        return Button {
            guard !effectiveBranchID.isEmpty else { return }
            pushPOSCreditAccount(customerID: customer.id, branchID: effectiveBranchID, initialTab: collect ? "collect" : "invoices")
        } label: {
            POSCustomerCreditBalance(summary: credit)
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(POSCustomerContactPressStyle())
        .accessibilityHint(POSCreditAccountCopy.text(collect ? "CollectionEntryHelp" : "QuickViewSubtitle"))
        .accessibilityIdentifier("pos.customer.credit.\(customer.id)")
    }

    private var editButton: some View {
        Button { onEdit?() } label: {
            Label(Language.get("POS_Customer_EditButton", alter: nil), systemImage: "pencil.line")
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: AdminTouchTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(POSCustomerContactPressStyle())
        .disabled(isUnavailable)
        .accessibilityLabel(String(format: Language.get("POS_Customer_EditNamed", alter: nil), customer.name))
    }
}

private struct POSCustomerContactPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct POSCustomerPickerSheet: View {
    let currentSelected: POSCustomerRecord?
    let canCreateCustomer: Bool
    let purpose: POSCustomerPickerPurpose
    let onSelect: ((POSCustomerRecord) -> Void)?
    private let onDelete: ((POSCustomerRecord) -> Void)?
    private let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = POSCustomerPickerViewModel()
    @State private var isAccountPickerPresented = false
    @State private var pendingAccount: POSCustomerAppAccount?

    init(
        currentSelected: POSCustomerRecord?,
        canCreateCustomer: Bool = true,
        purpose: POSCustomerPickerPurpose = .posCart,
        onSelect: @escaping (POSCustomerRecord) -> Void,
        onDelete: ((POSCustomerRecord) -> Void)? = nil
    ) {
        self.currentSelected = currentSelected
        self.canCreateCustomer = canCreateCustomer
        self.purpose = purpose
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onDismiss = nil
    }

    /// Standalone entry from People; there is no cart or selection callback.
    init(canCreateCustomer: Bool, onDelete: ((POSCustomerRecord) -> Void)? = nil, onDismiss: @escaping () -> Void) {
        self.currentSelected = nil
        self.canCreateCustomer = canCreateCustomer
        self.purpose = .customerManagement
        self.onSelect = nil
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }

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
                        purpose: purpose,
                        canAttachAppUser: canCreateCustomer && viewModel.canAttachAppUser,
                        onAttachAppUser: showAccountPicker,
                        onSelect: onSelect,
                        onDelete: onDelete,
                        dismiss: close
                    )
                } else {
                    iPhoneCustomerSensoryDeck(
                        viewModel: viewModel,
                        currentSelected: currentSelected,
                        canCreateCustomer: canCreateCustomer,
                        purpose: purpose,
                        canAttachAppUser: canCreateCustomer && viewModel.canAttachAppUser,
                        onAttachAppUser: showAccountPicker,
                        onSelect: onSelect,
                        onDelete: onDelete,
                        dismiss: close
                    )
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $isAccountPickerPresented, onDismiss: {
            if let account = pendingAccount {
                pendingAccount = nil
                viewModel.prepareAttachment(account)
            }
        }) {
            POSCustomerAppAccountPicker(onPick: { account in
                pendingAccount = account
                isAccountPickerPresented = false
            }, onCancel: {
                pendingAccount = nil
                isAccountPickerPresented = false
            })
        }
        .sheet(item: $viewModel.attachmentCandidate) { account in
            POSCustomerAccountAttachmentSheet(viewModel: viewModel, account: account)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    private func showAccountPicker() {
        guard canCreateCustomer, viewModel.canAttachAppUser, !isAccountPickerPresented,
              viewModel.attachmentCandidate == nil else { return }
        pendingAccount = nil
        isAccountPickerPresented = true
    }

    private func close() {
        if let onDismiss { onDismiss() }
        else { dismiss() }
    }
}

// MARK: - Existing-account bridge and confirmation

private struct POSCustomerAppAccountPicker: UIViewControllerRepresentable {
    let onPick: (POSCustomerAppAccount) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let picker = UsersListVC.makePOSCustomerAttachmentPicker()
        picker.onCustomerAttachmentCancelled = onCancel
        picker.onUserPicked = { user in
            let name = (user.displayName ?? user.userName).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            onPick(POSCustomerAppAccount(
                id: user.uid,
                name: name.isEmpty ? Language.get("POS_Customer_DefaultName", alter: nil) : name,
                phone: user.mobileNo ?? ""
            ))
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.setNavigationBarHidden(true, animated: false)
        navigation.view.semanticContentAttribute = Language.semanticAttributeForCurrentLanguage()
        return navigation
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    static func dismantleUIViewController(_ controller: UINavigationController, coordinator: ()) {
        (controller.viewControllers.first as? UsersListVC)?.onUserPicked = nil
        (controller.viewControllers.first as? UsersListVC)?.onCustomerAttachmentCancelled = nil
    }
}

private struct POSCustomerAttachUserButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 17, weight: .medium))
                    .accessibilityHidden(true)
                Text(Language.get("POS_Customer_AttachUser_Title", alter: nil))
                    .font(PPBrandFont.bold(15, relativeTo: .callout))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundColor(AdminSurface.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .background(AdminSurface.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(POSCustomerContactPressStyle())
        .accessibilityHint(Language.get("POS_Customer_AttachUser_Description", alter: nil))
    }
}

private struct POSCustomerAccountAttachmentSheet: View {
    @ObservedObject var viewModel: POSCustomerPickerViewModel
    let account: POSCustomerAppAccount
    @State private var currentAccount: POSCustomerAppAccount
    @State private var phoneInput: String
    @State private var isReselectingAccount = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(viewModel: POSCustomerPickerViewModel, account: POSCustomerAppAccount) {
        self.viewModel = viewModel
        self.account = account
        _currentAccount = State(initialValue: account)
        _phoneInput = State(initialValue: account.phone)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Breathing area above title and dismiss button
                HStack(alignment: .top) {
                    Text(Language.get("POS_Customer_AttachUser_Title", alter: nil))
                        .font(PPBrandFont.bold(23, relativeTo: .title2))
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { viewModel.attachmentCandidate = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText)
                            .frame(width: 44, height: 44)
                            .background(AdminSurface.control, in: Circle())
                    }
                    .buttonStyle(POSCustomerContactPressStyle())
                    .accessibilityLabel(Language.get("Close", alter: nil))
                    .disabled(viewModel.isAttachingUser)
                }
                .padding(.top, 16)

                // Candidate card with Reselect User button directly inside
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(currentAccount.name)
                                .font(PPBrandFont.bold(21, relativeTo: .title3))
                                .foregroundColor(AdminSurface.primaryText)
                            if !currentAccount.phone.isEmpty {
                                Text(currentAccount.phone)
                                    .font(PPBrandFont.bold(15, relativeTo: .body))
                                    .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                                    .environment(\.layoutDirection, .leftToRight)
                                    .foregroundColor(AdminSurface.secondaryText)
                            } else {
                                Label(
                                    Language.get("POS_Customer_AttachUser_NoPhoneOnAccount", alter: "لا يوجد رقم هاتف مسجل في هذا الحساب"),
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(PPBrandFont.medium(13, relativeTo: .caption))
                                .foregroundColor(AdminSurface.crimson)
                            }
                        }
                        Spacer(minLength: 8)

                        // Direct reselect button
                        Button {
                            isReselectingAccount = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .bold))
                                Text(Language.get("POS_Customer_AttachUser_ChangeUser", alter: "تغيير الحساب"))
                                    .font(PPBrandFont.bold(13, relativeTo: .caption))
                            }
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(POSCustomerContactPressStyle())
                        .disabled(viewModel.isAttachingUser)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16))

                // Inline phone input if account has no phone registered
                if currentAccount.phone.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("POS_Customer_AttachUser_EnterPhone", alter: "رقم الهاتف (مطلوب لربط الحساب)"))
                            .font(PPBrandFont.bold(15, relativeTo: .subheadline))
                            .foregroundColor(AdminSurface.primaryText)

                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AdminSurface.secondaryText)

                            TextField(
                                Language.get("POS_Customer_AttachUser_EnterPhonePlaceholder", alter: "أدخل رقم هاتف العميل (مثال: 70000000)"),
                                text: $phoneInput
                            )
                            .font(PPBrandFont.regular(15, relativeTo: .body))
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                            .environment(\.layoutDirection, .leftToRight)
                        }
                        .padding(14)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    phoneInput.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
                                        ? AdminSurface.primary.opacity(0.35)
                                        : AdminSurface.control,
                                    lineWidth: 1
                                )
                        )

                        Text(Language.get("POS_Customer_AttachUser_EnterPhoneHint", alter: "هذا الحساب لا يتضمن رقم هاتف مسجل. يرجى إدخال رقم الهاتف لربطه بدليل العملاء."))
                            .font(PPBrandFont.regular(13, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                Text(Language.get("POS_Customer_AttachUser_Confirmation", alter: nil))
                    .font(PPBrandFont.regular(16, relativeTo: .body))
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = viewModel.attachmentError ?? (viewModel.canAttachAppUser ? nil : Language.get("POS_Customer_AttachUser_NoAccess", alter: nil)) {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(PPBrandFont.medium(15, relativeTo: .callout))
                        .foregroundColor(AdminSurface.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                }

                let cleanInput = phoneInput.trimmingCharacters(in: .whitespacesAndNewlines)
                let isPhoneValid = !currentAccount.phone.isEmpty || cleanInput.count >= 6
                let canSubmit = !viewModel.isAttachingUser && viewModel.canAttachAppUser && isPhoneValid

                Button {
                    let effectivePhone = currentAccount.phone.isEmpty ? cleanInput : currentAccount.phone
                    viewModel.attachSelectedAccount(overridePhone: effectivePhone)
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isAttachingUser {
                            ProgressView().tint(.white).accessibilityHidden(true)
                        } else {
                            Image(systemName: "person.badge.plus").accessibilityHidden(true)
                        }
                        Text(Language.get(viewModel.isAttachingUser
                            ? "POS_Customer_AttachUser_Pending" : "POS_Customer_AttachUser_Submit", alter: nil))
                            .font(PPBrandFont.bold(18, relativeTo: .headline))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundColor(.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(POSCustomerContactPressStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)
            }
            .padding(20)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.isAttachingUser)
        .sheet(isPresented: $isReselectingAccount) {
            POSCustomerAppAccountPicker(onPick: { newAccount in
                currentAccount = newAccount
                phoneInput = newAccount.phone
                viewModel.prepareAttachment(newAccount)
                isReselectingAccount = false
            }, onCancel: {
                isReselectingAccount = false
            })
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }
}

// MARK: - ==========================================
// MARK: - IPHONE: SENSORY DECK ARCHITECTURE
// MARK: - ==========================================

private struct iPhoneCustomerSensoryDeck: View {
    @ObservedObject var viewModel: POSCustomerPickerViewModel
    let currentSelected: POSCustomerRecord?
    let canCreateCustomer: Bool
    let purpose: POSCustomerPickerPurpose
    let canAttachAppUser: Bool
    let onAttachAppUser: () -> Void
    let onSelect: ((POSCustomerRecord) -> Void)?
    let onDelete: ((POSCustomerRecord) -> Void)?
    let dismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject private var creditStore = POSCustomerCreditStore.shared
    @FocusState private var isSearchFocused: Bool
    @State private var selectedCountry: AdminCountryCodeItem = AdminCountryCatalog.defaultCountry
    @State private var pendingDeleteCustomer: POSCustomerRecord? = nil

    private let quickNoteChips: [String] = [
        "🌟 عميل VIP",
        "💬 يفضل واتساب",
        "🚗 توصيل سريع",
        "🐾 رعاية خاصة",
        "💳 دفع آجل"
    ]

    private func toggleNoteChip(_ chip: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var current = viewModel.newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.contains(chip) {
            current = current.replacingOccurrences(of: chip, with: "")
                .replacingOccurrences(of: "•  •", with: "•")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if current.hasPrefix("•") { current = String(current.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
            if current.hasSuffix("•") { current = String(current.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            viewModel.newNote = current
        } else {
            if current.isEmpty {
                viewModel.newNote = chip
            } else {
                viewModel.newNote = "\(current) • \(chip)"
            }
        }
    }

    private func text(_ key: String) -> String { Language.get(key, alter: nil) }
    private var locale: Locale { Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA") }
    private var isBusy: Bool {
        viewModel.isSubmitting || viewModel.isEditingSubmitting || viewModel.isAttachingUser || viewModel.isDeletingCustomer
    }
    private var navigationTitle: String {
        if viewModel.activeTab == .create { return text("POS_Customer_Directory_New") }
        switch purpose {
        case .posCart: return text("POS_Customer_Directory_Heading")
        default: return purpose.title
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                navigationHeader
                switch viewModel.activeTab {
                case .search:
                    iPhoneSearchChamber
                case .create:
                    iPhoneCreateChamber
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(text("Done")) {
                        isSearchFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(AdminType.calloutBold)
                }
            }
            .interactiveDismissDisabled(isBusy)
            .sheet(item: $viewModel.editingCustomer) { customer in
                POSCustomerEditSheet(
                    viewModel: viewModel,
                    customer: customer,
                    canEdit: canCreateCustomer,
                    purpose: purpose,
                    onSelectAndDismiss: { updated in
                        onSelect?(updated)
                        dismiss()
                    },
                    onDeleted: { deleted in
                        onDelete?(deleted)
                    }
                )
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
            .alert(
                String(format: text("POS_Customer_DeleteConfirmTitle"), pendingDeleteCustomer?.name ?? ""),
                isPresented: Binding(
                    get: { pendingDeleteCustomer != nil },
                    set: { if !$0 { pendingDeleteCustomer = nil } }
                )
            ) {
                Button(text("Cancel"), role: .cancel) {
                    pendingDeleteCustomer = nil
                }
                Button(text("POS_Customer_DeleteConfirmAction"), role: .destructive) {
                    guard let target = pendingDeleteCustomer else { return }
                    pendingDeleteCustomer = nil
                    viewModel.deleteCustomer(target) {
                        onDelete?(target)
                    }
                }
            } message: {
                Text(text("POS_Customer_DeleteConfirmMessage"))
            }
        }
        .navigationViewStyle(.stack)
    }

    private var navigationHeader: some View {
        HStack(alignment: .center, spacing: AdminSpacing.md) {
            if viewModel.activeTab == .create {
                Button { switchMode(.search) } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(POSCustomerContactPressStyle())
                .foregroundStyle(AdminSurface.primary)
                .accessibilityLabel(text("POS_Customer_Directory_Back"))
                .disabled(isBusy)
            }
            Text(navigationTitle)
                .font(typeSize.isAccessibilitySize ? AdminType.headlineBold : PPBrandFont.bold(25, relativeTo: .title2))
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.surface, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(POSCustomerContactPressStyle())
            .accessibilityLabel(text("POS_Close"))
            .accessibilityIdentifier("pos.customer.close")
            .disabled(isBusy)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.md)
        .padding(.bottom, AdminSpacing.sm)
    }

    private func switchMode(_ tab: POSCustomerPickerTab) {
        guard !isBusy, tab != .create || canCreateCustomer else { return }
        isSearchFocused = false
        if tab == .create && !viewModel.searchText.isEmpty {
            let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if viewModel.isPhoneQuery && viewModel.newPhone.isEmpty {
                viewModel.newPhone = query
                viewModel.checkDuplicatePhone(query)
            } else if !viewModel.isPhoneQuery && viewModel.newName.isEmpty {
                viewModel.newName = query
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // No entrance sequence or reordering of the directory when a query changes.
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            viewModel.activeTab = tab
        }
    }

    private var iPhoneSearchChamber: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                VStack(alignment: .leading, spacing: AdminSpacing.md) {
                    Text(purpose.subtitle(canCreate: canCreateCustomer))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    searchField
                    if canCreateCustomer || canAttachAppUser { directoryActions }
                }

                feedbackMessages

                if viewModel.searchText.isEmpty && !viewModel.recentCustomers.isEmpty {
                    recentCustomers
                }

                VStack(alignment: .leading, spacing: AdminSpacing.md) {
                    directorySummary
                    if viewModel.searchResults.isEmpty {
                        if viewModel.isLoading {
                            loadingDirectory
                        } else if viewModel.errorMessage == nil {
                            iPhoneEmptySearchState
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.searchResults) { customer in
                                iPhoneCustomerResultCard(customer: customer)
                                if customer.id != viewModel.searchResults.last?.id && customer.id != currentSelected?.id {
                                    Rectangle()
                                        .fill(contrast == .increased ? AdminSurface.secondaryText : AdminSurface.hairline)
                                        .frame(height: AdminStroke.hairline)
                                        .padding(.leading, typeSize.isAccessibilitySize ? AdminSpacing.base : 72)
                                        .padding(.trailing, AdminSpacing.base)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, AdminSpacing.xs)
            .padding(.bottom, AdminSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await viewModel.refreshFromFirestoreAsync() }
    }

    private var searchField: some View {
        HStack(spacing: AdminSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSearchFocused ? AdminSurface.primary : AdminSurface.secondaryText)
                .accessibilityHidden(true)
            TextField(text("POS_Customer_DirectorySearchPlaceholder"), text: $viewModel.searchText)
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(viewModel.isPhoneQuery && direction == .rightToLeft ? .trailing : .leading)
                .environment(\.layoutDirection, viewModel.isPhoneQuery ? .leftToRight : direction)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }
                .onChange(of: viewModel.searchText) { viewModel.handleSearchQueryChanged($0) }
                .accessibilityLabel(text("POS_Customer_DirectorySearchPlaceholder"))
                .accessibilityIdentifier("pos.customer.search")
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(POSCustomerContactPressStyle())
                .accessibilityLabel(text("POS_Customer_Directory_ClearSearch"))
            }
        }
        .padding(.leading, AdminSpacing.base)
        .padding(.trailing, viewModel.searchText.isEmpty ? AdminSpacing.base : AdminSpacing.xs)
        .padding(.vertical, AdminSpacing.sm)
        .frame(minHeight: 54)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(isSearchFocused ? AdminSurface.primary :
                    (contrast == .increased ? AdminSurface.secondaryText : AdminSurface.hairline), lineWidth: isSearchFocused ? 1.5 : 1)
                .allowsHitTesting(false)
        }
    }

    private var directoryActions: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.md))
        return layout {
            if canCreateCustomer {
                Button { switchMode(.create) } label: {
                    Label(text("POS_Customer_Directory_New"), systemImage: "person.badge.plus")
                        .font(AdminType.calloutBold)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(AdminSurface.primary)
                .buttonStyle(POSCustomerContactPressStyle())
            }
            if canAttachAppUser {
                Button(action: onAttachAppUser) {
                    Label(text("POS_Customer_AttachUser_Title"), systemImage: "link")
                        .font(AdminType.footnoteBold)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(AdminSurface.secondaryText)
                .buttonStyle(POSCustomerContactPressStyle())
                .accessibilityHint(text("POS_Customer_AttachUser_Description"))
            }
        }
    }

    @ViewBuilder private var feedbackMessages: some View {
        if let error = viewModel.errorMessage {
            feedbackBanner(error, isError: true) { viewModel.errorMessage = nil }
        }
        if let success = viewModel.successFeedbackMessage {
            feedbackBanner(success, isError: false) { viewModel.successFeedbackMessage = nil }
        }
    }

    private func feedbackBanner(_ message: String, isError: Bool, dismissMessage: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? AdminSurface.crimson : AdminSurface.emerald)
                    .padding(.top, AdminSpacing.md)
                    .accessibilityHidden(true)
                Text(message)
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AdminSpacing.md)
                Button(action: dismissMessage) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(POSCustomerContactPressStyle())
                .accessibilityLabel(text("POS_Customer_Directory_DismissMessage"))
            }
            if isError && viewModel.activeTab == .search {
                Button(text("Retry")) { viewModel.handleSearchQueryChanged(viewModel.searchText) }
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primary)
                    .frame(minHeight: 44)
                    .disabled(viewModel.isSyncingWithFirestore)
            }
        }
        .padding(.horizontal, AdminSpacing.md)
        .background((isError ? AdminSurface.crimson : AdminSurface.emerald).opacity(0.06), in: RoundedRectangle(cornerRadius: AdminRadius.card))
    }

    private var directorySummary: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
                Text(text(viewModel.searchText.isEmpty ? "POS_Customer_Directory_All" : "POS_Customer_Directory_Results"))
                    .font(AdminType.headlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.searchResults.count.formatted(.number.locale(locale)))
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            if !viewModel.searchText.isEmpty {
                Text(text(viewModel.isPhoneQuery ? "POS_Customer_FilterPhoneMode" : "POS_Customer_FilterNameMode"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            syncStatusBadge
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var syncStatusBadge: some View {
        if viewModel.isSyncingWithFirestore {
            HStack(spacing: AdminSpacing.sm) {
                ProgressView().tint(AdminSurface.primary)
                Text(text("POS_Customer_Syncing"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        } else if viewModel.lastSyncDate != nil {
            Label(text("POS_Customer_Directory_Saved"), systemImage: "internaldrive")
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
        }
    }

    private var recentCustomers: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            Text(text("POS_Customer_RecentWalkIns"))
                .font(AdminType.headlineBold)
                .foregroundStyle(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
            if typeSize.isAccessibilitySize {
                VStack(spacing: AdminSpacing.sm) {
                    ForEach(viewModel.recentCustomers) { iPhoneRecentCustomerChip(customer: $0) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AdminSpacing.md) {
                        ForEach(viewModel.recentCustomers) { iPhoneRecentCustomerChip(customer: $0) }
                    }
                    .padding(.trailing, AdminSpacing.screenMargin)
                }
                .padding(.trailing, -AdminSpacing.screenMargin)
            }
        }
    }

    private func unavailable(_ customer: POSCustomerRecord) -> Bool {
        ["blocked", "banned", "disabled", "deactivated", "deleted", "suspended", "archived", "inactive"]
            .contains(customer.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func select(_ customer: POSCustomerRecord) {
        guard !unavailable(customer), !isBusy else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if purpose.isManagingCustomers {
            viewModel.startEditing(customer: customer)
            return
        }
        viewModel.rememberCustomer(customer)
        onSelect?(customer)
        dismiss()
    }

    private func iPhoneRecentCustomerChip(customer: POSCustomerRecord) -> some View {
        Button { select(customer) } label: {
            HStack(spacing: 10) {
                if !typeSize.isAccessibilitySize {
                    Text(customer.initials)
                        .font(PPBrandFont.bold(16, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.surface, in: Circle())
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name)
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                    if !customer.phone.isEmpty {
                        Text(customer.phone)
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: true)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    if unavailable(customer) {
                        Label(text("POS_Customer_InactiveContact"), systemImage: "lock")
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if currentSelected?.id == customer.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                        .accessibilityHidden(true)
                }
            }
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(
                maxWidth: typeSize.isAccessibilitySize ? .infinity : nil,
                minHeight: 64,
                alignment: .leading
            )
            .background(AdminSurface.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.card))
        }
        .buttonStyle(POSCustomerContactPressStyle())
        .disabled(unavailable(customer))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(customer.name)
        .accessibilityValue([customer.phone, unavailable(customer) ? text("POS_Customer_InactiveContact") : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(purpose.selectTitle)
        .accessibilityAddTraits(currentSelected?.id == customer.id ? [.isSelected] : [])
        .accessibilityIdentifier("pos.customer.recent.\(customer.id)")
    }

    private func iPhoneCustomerResultCard(customer: POSCustomerRecord) -> some View {
        let branchID = BranchContextStore.shared.activeBranch?.branchID ?? ""
        let effectiveBranchID = branchID.isEmpty ? customer.branchId : branchID
        let canReadCredit = customer.source == "directory" && !customer.id.isEmpty &&
            POSCreditAccountCopy.permitted("pos.credit.read", branchID: branchID)
        let hasLocalCredit = creditStore.summary(for: customer.id, branchID: effectiveBranchID)?.hasBlockingCreditLocally == true
        let canMutate = canCreateCustomer && !unavailable(customer) && customer.source == "directory"
        return POSCustomerIdentityCell(
            customer: customer,
            branchName: viewModel.branchDisplayName(for: customer.branchId),
            isSelected: currentSelected?.id == customer.id,
            selectionHint: purpose.selectTitle,
            onSelect: { select(customer) },
            onEdit: canCreateCustomer && !purpose.isManagingCustomers ? { viewModel.startEditing(customer: customer) } : nil,
            creditBranchID: canReadCredit ? branchID : nil
        )
        .contextMenu {
            if canMutate {
                Button {
                    viewModel.startEditing(customer: customer)
                } label: {
                    Label(text("POS_Customer_EditButton"), systemImage: "pencil")
                }
                if !hasLocalCredit {
                    Button(role: .destructive) {
                        pendingDeleteCustomer = customer
                    } label: {
                        Label(text("POS_Customer_DeleteButton"), systemImage: "trash")
                    }
                }
            }
        }
        .accessibilityAction(named: String(format: text("POS_Customer_DeleteNamed"), customer.name)) {
            guard canMutate, !hasLocalCredit, !isBusy else { return }
            pendingDeleteCustomer = customer
        }
    }

    private var loadingDirectory: some View {
        HStack(alignment: .center, spacing: AdminSpacing.md) {
            ProgressView().tint(AdminSurface.primary)
            Text(text("POS_Customer_Directory_Loading"))
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AdminSpacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var iPhoneEmptySearchState: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            Image(systemName: viewModel.searchText.isEmpty ? "person.crop.rectangle.stack" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AdminSurface.primary)
                .accessibilityHidden(true)
            Text(text(viewModel.searchText.isEmpty ? "POS_Customer_Directory_Empty" : "POS_Customer_NoMatchTitle"))
                .font(AdminType.title3Bold)
                .foregroundStyle(AdminSurface.primaryText)
            Text(viewModel.searchText.isEmpty
                 ? text("POS_Customer_Directory_EmptyDetail")
                 : String(format: text("POS_Customer_NoMatchSub"), viewModel.searchText))
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
            if canCreateCustomer {
                Button { switchMode(.create) } label: {
                    Label(text("POS_Customer_Directory_New"), systemImage: "plus")
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primary)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(POSCustomerContactPressStyle())
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AdminSpacing.lg)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
    }

    // MARK: - iPhone Create Chamber (Next Gen V10 Redesign)

    private var iPhoneCreateChamber: some View {
        ScrollView {
            VStack(spacing: 20) {
                feedbackMessages

                // 1. Live Persona Aura & Monogram Deck
                VStack(spacing: 8) {
                    ZStack {
                        // Ambient Breathing Aura
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AdminSurface.primary.opacity(viewModel.newName.isEmpty ? 0.08 : 0.22),
                                        Color(red: 0.85, green: 0.20, blue: 0.40).opacity(viewModel.newName.isEmpty ? 0.04 : 0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 88, height: 88)
                            .blur(radius: viewModel.newName.isEmpty ? 2 : 6)

                        // Outer Concentric Hairline Ring
                        Circle()
                            .strokeBorder(
                                viewModel.newName.isEmpty ? AdminSurface.hairline : AdminSurface.primary.opacity(0.4),
                                lineWidth: 1.5
                            )
                            .frame(width: 80, height: 80)

                        // Core Avatar Circle
                        Circle()
                            .fill(
                                viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? AnyShapeStyle(AdminSurface.surface)
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .frame(width: 72, height: 72)
                            .shadow(color: viewModel.newName.isEmpty ? Color.clear : AdminSurface.primary.opacity(0.3), radius: 8, y: 3)

                        if viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundColor(AdminSurface.primary)
                        } else {
                            Text(String(viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased())
                                .font(PPBrandFont.bold(size: 26))
                                .foregroundColor(.white)
                        }
                    }

                    // Persona Status Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 ? Color(uiColor: .systemGreen) : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(
                            viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
                                ? Language.get("POS_Customer_StatusReady", alter: "جاهز للحفظ والربط")
                                : (viewModel.newName.isEmpty
                                    ? Language.get("POS_Customer_StatusNew", alter: "تسجيل فوري لعميل جديد")
                                    : Language.get("POS_Customer_StatusNeedPhone", alter: "أكمل رقم الهاتف للربط"))
                        )
                        .font(PPBrandFont.bold(size: 11.5))
                        .foregroundStyle(viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 ? Color(uiColor: .systemGreen) : Color.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3.5)
                    .background(
                        (viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 ? Color(uiColor: .systemGreen) : Color.orange).opacity(0.1),
                        in: Capsule()
                    )
                }
                .padding(.top, 6)

                // 2. Duplicate Warning if Phone Exists
                if let match = viewModel.duplicateMatch {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if purpose.isManagingCustomers {
                            viewModel.showManagedCustomer(match)
                            viewModel.startEditing(customer: match)
                        } else {
                            viewModel.rememberCustomer(match)
                            onSelect?(match)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.system(size: 18))
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Language.get("POS_Customer_DuplicateFound", alter: "عميل مسجل مسبقاً بهذا الرقم!"))
                                    .font(PPBrandFont.bold(size: 13))
                                    .foregroundColor(AdminSurface.primaryText)
                                Text(String(format: Language.get(purpose.isManagingCustomers ? "POS_Customer_Management_Duplicate" : "POS_Customer_DuplicateSub", alter: "الاسم: %@"), match.name))
                                    .font(PPBrandFont.medium(size: 12))
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            HStack(spacing: 3) {
                                Text(Language.get("POS_Customer_UseExisting", alter: "استخدام"))
                                    .font(PPBrandFont.bold(size: 11.5))
                                Image(systemName: Language.isRTL() ? "arrowshape.turn.up.backward.fill" : "arrowshape.turn.up.right.fill")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.orange, in: Capsule())
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // 3. Elevated Form Fields Container
                VStack(spacing: 14) {
                    // Name Field
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(Language.get("POS_Customer_NameField", alter: "اسم العميل"))
                                .font(PPBrandFont.bold(size: 13))
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("Common_Optional", alter: "(اختياري)"))
                                .font(PPBrandFont.regular(size: 11))
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                                .foregroundColor(viewModel.newName.isEmpty ? AdminSurface.secondaryText : AdminSurface.primary)
                                .font(.system(size: 14))
                                .frame(width: 22)

                            TextField(Language.get("POS_Customer_NamePlaceholder", alter: "مثال: سالم الكواري"), text: $viewModel.newName)
                                .font(PPBrandFont.medium(size: 14.5))
                                .multilineTextAlignment(.leading)
                                .autocorrectionDisabled(true)

                            if !viewModel.newName.isEmpty {
                                Button {
                                    viewModel.newName = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(!viewModel.newName.isEmpty ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 0.9)
                        )
                    }

                    // Phone Field (The Essential Key)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف *"))
                                .font(PPBrandFont.bold(size: 13))
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("Common_Required", alter: "(مطلوب)"))
                                .font(PPBrandFont.bold(size: 11))
                                .foregroundColor(AdminSurface.primary)
                            Spacer()

                            if viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 {
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                    Text(Language.get("POS_Customer_PhoneValid", alter: "رقم مكتمل"))
                                        .font(PPBrandFont.bold(size: 11))
                                }
                                .foregroundColor(Color(uiColor: .systemGreen))
                            }
                        }

                        HStack(spacing: 8) {
                            // Country Flag & Code Menu (Always strictly Left-anchored for telephony)
                            Menu {
                                ForEach(AdminCountryCatalog.all) { item in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedCountry = item
                                        viewModel.newPhone = AdminCountryCatalog.formatDigits(viewModel.newPhone, for: item)
                                    } label: {
                                        HStack {
                                            Text(item.displayName)
                                            if selectedCountry.code == item.code {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(selectedCountry.flag)
                                        .font(.system(size: 16))
                                    Text(selectedCountry.code)
                                        .font(PPBrandFont.bold(size: 13.5))
                                        .foregroundColor(AdminSurface.primaryText)
                                        .monospacedDigit()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(AdminSurface.hairline, lineWidth: 0.6)
                                )
                            }

                            Rectangle()
                                .fill(AdminSurface.hairline)
                                .frame(width: 1, height: 22)

                            TextField(
                                "",
                                text: Binding(
                                    get: { viewModel.newPhone },
                                    set: { newValue in
                                        let formatted = AdminCountryCatalog.formatDigits(newValue, for: selectedCountry)
                                        viewModel.newPhone = formatted
                                        viewModel.checkDuplicatePhone(formatted)
                                    }
                                ),
                                prompt: Text(Language.get("POS_Customer_PhonePlaceholder", alter: "5512 3456"))
                                    .font(PPBrandFont.medium(size: 15))
                                    .foregroundColor(AdminSurface.secondaryText)
                            )
                            .font(PPBrandFont.bold(size: 16))
                            .foregroundColor(AdminSurface.primaryText)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if !viewModel.newPhone.isEmpty {
                                Button {
                                    viewModel.newPhone = ""
                                    viewModel.duplicateMatch = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .environment(\.layoutDirection, .leftToRight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    viewModel.duplicateMatch != nil
                                        ? Color.orange
                                        : (viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 ? Color(uiColor: .systemGreen).opacity(0.5) : AdminSurface.hairline),
                                    lineWidth: 1
                                )
                        )
                    }

                    // Email Field
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني"))
                                .font(PPBrandFont.bold(size: 13))
                                .foregroundColor(AdminSurface.primaryText)
                            Text(Language.get("Common_Optional", alter: "(اختياري)"))
                                .font(PPBrandFont.regular(size: 11))
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(viewModel.newEmail.isEmpty ? AdminSurface.secondaryText : AdminSurface.primary)
                                .font(.system(size: 14))
                                .frame(width: 22)

                            TextField(Language.get("POS_Customer_EmailPlaceholder", alter: "customer@example.com"), text: $viewModel.newEmail)
                                .font(PPBrandFont.medium(size: 14.5))
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .multilineTextAlignment(.leading)
                                .environment(\.layoutDirection, .leftToRight)

                            if !viewModel.newEmail.isEmpty {
                                Button {
                                    viewModel.newEmail = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(!viewModel.newEmail.isEmpty ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 0.9)
                        )
                    }

                    // Preferred Branch Field
                    if !viewModel.branches.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(Language.get("POS_Customer_BranchField", alter: "الفرع المفضل"))
                                    .font(PPBrandFont.bold(size: 13))
                                    .foregroundColor(AdminSurface.primaryText)
                                Spacer()
                                if !viewModel.selectedBranchId.isEmpty {
                                    Button {
                                        viewModel.selectedBranchId = ""
                                    } label: {
                                        Text(Language.get("Common_Clear", alter: "إلغاء التحديد"))
                                            .font(PPBrandFont.medium(size: 11.5))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(viewModel.branches, id: \.id) { b in
                                        let active = viewModel.selectedBranchId == b.id
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            viewModel.selectedBranchId = active ? "" : b.id
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: active ? "mappin.circle.fill" : "mappin.circle")
                                                    .font(.system(size: 12))
                                                Text(b.displayName)
                                                    .font(PPBrandFont.bold(size: 12.5))
                                            }
                                            .foregroundColor(active ? .white : AdminSurface.primaryText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                active
                                                    ? AnyShapeStyle(LinearGradient(colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    : AnyShapeStyle(AdminSurface.surface),
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .strokeBorder(active ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
                                            )
                                            .shadow(color: active ? AdminSurface.primary.opacity(0.25) : Color.clear, radius: 4, y: 2)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                        }
                    }

                    // Internal Notes & High-Velocity Quick Smart-Chips
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية وتفضيلات"))
                                .font(PPBrandFont.bold(size: 13))
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                        }

                        // Quick Smart-Chips Horizontal Scroll
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(quickNoteChips, id: \.self) { chip in
                                    let isSelected = viewModel.newNote.contains(chip)
                                    Button {
                                        toggleNoteChip(chip)
                                    } label: {
                                        Text(chip)
                                            .font(PPBrandFont.bold(size: 11.5))
                                            .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                isSelected ? AdminSurface.primary : AdminSurface.control,
                                                in: Capsule()
                                            )
                                            .overlay(Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.6))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 2)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "note.text")
                                .foregroundColor(viewModel.newNote.isEmpty ? AdminSurface.secondaryText : AdminSurface.primary)
                                .font(.system(size: 14))
                                .frame(width: 22)
                                .padding(.top, 2)

                            TextField(Language.get("POS_Customer_NotePlaceholder", alter: "ملاحظات حول التوصيل أو تفضيلات العميل…"), text: $viewModel.newNote)
                                .font(PPBrandFont.regular(size: 14))
                                .multilineTextAlignment(.leading)

                            if !viewModel.newNote.isEmpty {
                                Button {
                                    viewModel.newNote = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(AdminSurface.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(!viewModel.newNote.isEmpty ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 0.9)
                        )
                    }
                }

                // 4. Hero Primary Submit CTA
                let canSubmit = viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 && !viewModel.isSubmitting
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if selectedCountry.code != "+974" {
                        let digits = viewModel.newPhone.filter { $0.isNumber }
                        let codeDigits = selectedCountry.code.replacingOccurrences(of: "+", with: "")
                        if !digits.hasPrefix(codeDigits) {
                            viewModel.newPhone = "\(selectedCountry.code) \(viewModel.newPhone)"
                        }
                    }
                    viewModel.submitCreateCustomer { createdCustomer in
                        if purpose.isManagingCustomers {
                            viewModel.showManagedCustomer(createdCustomer)
                        } else {
                            onSelect?(createdCustomer)
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isSubmitting {
                            ProgressView().tint(.white).scaleEffect(0.9)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .bold))
                        }
                        Text(purpose.createTitle)
                            .font(PPBrandFont.bold(size: 16))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        canSubmit
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(AdminSurface.primary.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(color: canSubmit ? AdminSurface.primary.opacity(0.35) : Color.clear, radius: 10, y: 4)
                }
                .disabled(!canSubmit)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - ==========================================
// MARK: - IPHONE: CUSTOMER PROFILE EDIT SHEET
// MARK: - ==========================================

private struct POSCustomerEditSheet: View {
    @ObservedObject var viewModel: POSCustomerPickerViewModel
    let customer: POSCustomerRecord
    let canEdit: Bool
    let purpose: POSCustomerPickerPurpose
    let onSelectAndDismiss: (POSCustomerRecord) -> Void
    let onDeleted: (POSCustomerRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreditPolicySheet = false
    @State private var showsDeleteConfirmation = false
    @ObservedObject private var creditStore = POSCustomerCreditStore.shared

    private var activeBranchID: String {
        let branch = BranchContextStore.shared.activeBranch?.branchID ?? ""
        return branch.isEmpty ? customer.branchId : branch
    }

    private var creditSummary: POSCustomerCreditStore.CreditSummary? {
        creditStore.summary(for: customer.id, branchID: activeBranchID)
    }

    private var hasLocalCredit: Bool {
        creditSummary?.hasBlockingCreditLocally == true
    }

    private var isUnavailable: Bool {
        ["blocked", "banned", "disabled", "deactivated", "deleted", "suspended", "archived", "inactive"]
            .contains(customer.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private var isMutating: Bool {
        viewModel.isEditingSubmitting || viewModel.isDeletingCustomer
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header Bar
                    AdminSovereignNavigationBar(
                        title: Language.get(canEdit ? "POS_Customer_EditTitle" : "POS_Customer_CustomerDossier", alter: nil),
                        subtitle: Language.get(canEdit ? "POS_Customer_EditSubtitle" : "POS_Customer_Management_ProfileReadOnly", alter: nil),
                        statusDotColor: Color(uiColor: .ppSuccess),
                        isModal: true,
                        onBack: {
                            guard !isMutating else { return }
                            viewModel.cancelEditing()
                            dismiss()
                        }
                    ) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: canEdit ? "pencil" : "person.crop.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(AdminSurface.danger)
                                .padding(.top, 2)
                                .accessibilityHidden(true)
                            Text(error)
                                .font(AdminType.subheadline)
                                .foregroundStyle(AdminSurface.primaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(AdminSurface.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                            // Form Fields
                            VStack(spacing: 12) {
                                // Phone Field
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف *"))
                                            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                            .foregroundColor(AdminSurface.primaryText)

                                        Spacer()

                                        if !viewModel.editPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Button {
                                                viewModel.copyPhone(phone: viewModel.editPhone, customerId: customer.id)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: viewModel.copiedPhoneId == customer.id ? "checkmark" : "doc.on.doc")
                                                        .font(.system(size: 11))
                                                    Text(viewModel.copiedPhoneId == customer.id
                                                         ? Language.get("POS_Customer_QuickAction_Copied", alter: "تم النسخ")
                                                         : Language.get("POS_Customer_QuickAction_Copy", alter: "نسخ الرقم"))
                                                        .font(Font.custom("Beiruti-Bold", size: 11.5, relativeTo: .caption))
                                                }
                                                .foregroundColor(viewModel.copiedPhoneId == customer.id ? .green : AdminSurface.primary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(AdminSurface.control, in: Capsule())
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        Image(systemName: "phone.fill")
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .font(.system(size: 13))
                                            .frame(width: 20)

                                        TextField(Language.get("POS_Customer_PhonePlaceholder", alter: "5512 3456"), text: $viewModel.editPhone)
                                            .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .body))
                                            .keyboardType(.phonePad)
                                            .disabled(!canEdit)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                                }
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
                                            .disabled(!canEdit)
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
                                            .disabled(!canEdit)
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
                                                    .disabled(!canEdit)
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
                                            .disabled(!canEdit)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))
                                }

                                // Credit Policy & Terms Section
                                if canEdit {
                                    let activeBranchID = BranchContextStore.shared.activeBranch?.branchID ?? customer.branchId
                                    let credit = creditStore.summary(for: customer.id, branchID: activeBranchID)

                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(Language.get("POS_Customer_CreditSectionTitle", alter: "سياسة وتسهيلات البيع الآجل"))
                                                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                                .foregroundColor(AdminSurface.primaryText)
                                            Spacer()
                                        }

                                        if let credit {
                                            POSCustomerCreditBalance(summary: credit)
                                        } else {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: "checkmark.shield.fill")
                                                .foregroundColor(AdminSurface.primary)
                                                .font(.system(size: 16))
                                                .padding(.top, 2)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(Language.get("POS_Credit_NeedsVerification", alter: "تعذّر التحقق من شروط العميل"))
                                                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .subheadline))
                                                    .foregroundColor(AdminSurface.primaryText)
                                                Text(Language.get("POS_Credit_PolicyRequired", alter: "يحتاج العميل إلى سياسة ائتمان معتمدة لهذا الفرع قبل البيع على الحساب."))
                                                    .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                                                    .foregroundColor(AdminSurface.secondaryText)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }

                                            Spacer(minLength: 0)
                                        }
                                        .padding(12)
                                        .background(AdminSurface.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))

                                        }
                                        Button {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            showsCreditPolicySheet = true
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "slider.horizontal.3")
                                                Text(Language.get("POS_Customer_ManageCreditCTA", alter: "إعداد سياسة وسقف الائتمان"))
                                                    .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .callout))
                                            }
                                            .foregroundColor(AdminSurface.primary)
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }

                            // Action Buttons
                            if canEdit {
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
                                    .disabled(isMutating)

                                    // Save and Link CTA
                                    if !purpose.isManagingCustomers {
                                        Button {
                                            viewModel.submitUpdateCustomer(andSelect: true) { updated in
                                                onSelectAndDismiss(updated)
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrowshape.turn.up.backward.fill")
                                                    .font(.system(size: 13))
                                                Text(purpose.saveAndSelectTitle)
                                                    .font(Font.custom("Beiruti-Bold", size: 14.5, relativeTo: .callout))
                                            }
                                            .foregroundColor(AdminSurface.primary)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                        .disabled(isMutating)
                                    }

                                    // Delete Customer Section
                                    if customer.source == "directory" && !customer.id.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Button(role: .destructive) {
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                showsDeleteConfirmation = true
                                            } label: {
                                                HStack(spacing: 8) {
                                                    if viewModel.isDeletingCustomer {
                                                        ProgressView().tint(AdminSurface.danger).scaleEffect(0.9)
                                                    } else {
                                                        Image(systemName: "trash")
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .accessibilityHidden(true)
                                                    }
                                                    Text(Language.get(viewModel.isDeletingCustomer ? "POS_Customer_Deleting" : "POS_Customer_DeleteButton", alter: nil))
                                                        .font(AdminType.calloutBold)
                                                        .multilineTextAlignment(.leading)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                                .foregroundStyle(AdminSurface.danger)
                                                .frame(maxWidth: .infinity, minHeight: 48)
                                                .background(AdminSurface.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .strokeBorder(AdminSurface.danger.opacity(0.24), lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(POSCustomerContactPressStyle())
                                            .disabled(isMutating || isUnavailable || hasLocalCredit)
                                            .opacity((isMutating || isUnavailable || hasLocalCredit) ? 0.5 : 1)
                                            .accessibilityLabel(String(format: Language.get("POS_Customer_DeleteNamed", alter: nil), customer.name))
                                            .accessibilityIdentifier("pos.customer.delete")

                                            Text(Language.get(hasLocalCredit ? "POS_Customer_DeleteCreditHint" : "POS_Customer_DeleteEligibilityHint", alter: nil))
                                                .font(AdminType.caption)
                                                .foregroundStyle(hasLocalCredit ? AdminSurface.crimson : AdminSurface.secondaryText)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 24)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationBarHidden(true)
            .interactiveDismissDisabled(isMutating)
            .task(id: "\(customer.id):\(activeBranchID):\(creditStore.revision)") {
                if !activeBranchID.isEmpty, customer.source == "directory" {
                    creditStore.loadCreditSummary(for: customer.id, branchID: activeBranchID)
                }
            }
            .sheet(isPresented: $showsCreditPolicySheet) {
                let branchID = BranchContextStore.shared.activeBranch?.branchID ?? ""
                let branchName = BranchContextStore.shared.activeBranch?.localizedName() ?? ""
                POSCustomerCreditPolicySheet(
                    customerID: customer.id,
                    customerName: customer.name,
                    customerPhone: customer.phone,
                    branchID: branchID,
                    branchName: branchName
                ) {
                    POSCustomerCreditStore.shared.invalidate(customerID: customer.id, branchID: branchID)
                    POSCustomerCreditStore.shared.loadCreditSummary(for: customer.id, branchID: branchID)
                }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
            .alert(
                String(format: Language.get("POS_Customer_DeleteConfirmTitle", alter: nil), customer.name),
                isPresented: $showsDeleteConfirmation
            ) {
                Button(Language.get("Cancel", alter: nil), role: .cancel) {}
                Button(Language.get("POS_Customer_DeleteConfirmAction", alter: nil), role: .destructive) {
                    viewModel.deleteCustomer(customer) {
                        onDeleted(customer)
                        dismiss()
                    }
                }
            } message: {
                Text(Language.get("POS_Customer_DeleteConfirmMessage", alter: nil))
            }
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
    let purpose: POSCustomerPickerPurpose
    let canAttachAppUser: Bool
    let onAttachAppUser: () -> Void
    let onSelect: ((POSCustomerRecord) -> Void)?
    let onDelete: ((POSCustomerRecord) -> Void)?
    let dismiss: () -> Void

    @ObservedObject private var creditStore = POSCustomerCreditStore.shared
    @FocusState private var isSearchFocused: Bool
    @State private var selectedCountry: AdminCountryCodeItem = AdminCountryCatalog.defaultCountry
    @State private var pendingDeleteCustomer: POSCustomerRecord? = nil

    private var isBusy: Bool {
        viewModel.isSubmitting || viewModel.isEditingSubmitting || viewModel.isAttachingUser || viewModel.isDeletingCustomer
    }

    private func isUnavailable(_ customer: POSCustomerRecord) -> Bool {
        ["blocked", "banned", "disabled", "deactivated", "deleted", "suspended", "archived", "inactive"]
            .contains(customer.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private func hasLocalBlockingCredit(_ customer: POSCustomerRecord) -> Bool {
        let activeBranch = BranchContextStore.shared.activeBranch?.branchID ?? ""
        let effectiveBranchID = activeBranch.isEmpty ? customer.branchId : activeBranch
        return creditStore.summary(for: customer.id, branchID: effectiveBranchID)?.hasBlockingCreditLocally == true
    }

    private let quickNoteChips: [String] = [
        "🌟 عميل VIP",
        "💬 يفضل واتساب",
        "🚗 توصيل سريع",
        "🐾 رعاية خاصة",
        "💳 دفع آجل"
    ]

    private func toggleNoteChip(_ chip: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var current = viewModel.newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.contains(chip) {
            current = current.replacingOccurrences(of: chip, with: "")
                .replacingOccurrences(of: "•  •", with: "•")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if current.hasPrefix("•") { current = String(current.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
            if current.hasSuffix("•") { current = String(current.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            viewModel.newNote = current
        } else {
            if current.isEmpty {
                viewModel.newNote = chip
            } else {
                viewModel.newNote = "\(current) • \(chip)"
            }
        }
    }
    @State private var showsCreditPolicySheet = false

    var body: some View {
        ZStack {
            // Soft Dimming Backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    guard !isBusy else { return }
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
            .sheet(isPresented: $showsCreditPolicySheet) {
                if let customer = viewModel.editingCustomer ?? viewModel.highlightedCustomer {
                    let branchID = BranchContextStore.shared.activeBranch?.branchID ?? ""
                    let branchName = BranchContextStore.shared.activeBranch?.localizedName() ?? ""
                    POSCustomerCreditPolicySheet(
                        customerID: customer.id,
                        customerName: customer.name,
                        customerPhone: customer.phone,
                        branchID: branchID,
                        branchName: branchName
                    ) {
                        POSCustomerCreditStore.shared.invalidate(customerID: customer.id, branchID: branchID)
                        POSCustomerCreditStore.shared.loadCreditSummary(for: customer.id, branchID: branchID)
                    }
                    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
                }
            }
            .alert(
                String(format: Language.get("POS_Customer_DeleteConfirmTitle", alter: nil), pendingDeleteCustomer?.name ?? ""),
                isPresented: Binding(
                    get: { pendingDeleteCustomer != nil },
                    set: { if !$0 { pendingDeleteCustomer = nil } }
                )
            ) {
                Button(Language.get("Cancel", alter: nil), role: .cancel) {
                    pendingDeleteCustomer = nil
                }
                Button(Language.get("POS_Customer_DeleteConfirmAction", alter: nil), role: .destructive) {
                    guard let target = pendingDeleteCustomer else { return }
                    pendingDeleteCustomer = nil
                    viewModel.deleteCustomer(target) {
                        onDelete?(target)
                    }
                }
            } message: {
                Text(Language.get("POS_Customer_DeleteConfirmMessage", alter: nil))
            }
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
                    Text(purpose.title)
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

                Text(purpose.subtitle(canCreate: canCreateCustomer))
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
                        .frame(width: 44, height: 44)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
    }

    // MARK: - Feedback Banner

    private func iPadFeedbackBanner(text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(isError ? AdminSurface.danger : .green)
                .font(.system(size: 13))
                .padding(.top, 2)
            Text(text)
                .font(AdminType.subheadline)
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                if isError { viewModel.errorMessage = nil }
                else { viewModel.successFeedbackMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AdminSurface.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background((isError ? AdminSurface.danger : Color.green).opacity(0.1))
    }

    // MARK: - Left Directory Column

    private var iPadLeftDirectoryColumn: some View {
        VStack(spacing: 12) {
            if canAttachAppUser && viewModel.activeTab == .search {
                POSCustomerAttachUserButton(action: onAttachAppUser)
            }
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
                        syncStatusBadge
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
                                            .fixedSize(horizontal: true, vertical: true)
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

            // Search Results Header & Sync Status (when search is active or recents empty)
            if !viewModel.searchText.isEmpty || viewModel.recentCustomers.isEmpty {
                HStack {
                    if !viewModel.searchText.isEmpty {
                        Text(String(format: Language.get("POS_Catalog_ResultCount_Format", alter: "%ld نتيجة"), viewModel.searchResults.count))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption2))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    Spacer()
                    syncStatusBadge
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
                            let branchID = BranchContextStore.shared.activeBranch?.branchID ?? ""
                            let credit = creditStore.summary(for: customer.id, branchID: branchID)
                            let showsCreditAction = (credit?.outstandingMinor ?? 0) > 0 && POSCreditAccountCopy.permitted("pos.credit.collect", branchID: branchID)
                            VStack(spacing: 4) {
                                iPadCustomerListCard(customer: customer)
                                if customer.source == "directory", showsCreditAction {
                                    POSCreditAccountLink(customerID: customer.id, branchID: branchID, compact: true, opensCollection: true)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .refreshable {
                await viewModel.refreshFromFirestoreAsync()
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        if viewModel.isSyncingWithFirestore {
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text(Language.get("POS_Customer_Syncing", alter: "جارٍ التحقق والتحديث..."))
                    .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AdminSurface.control, in: Capsule())
            .transition(.opacity)
        } else if viewModel.lastSyncDate != nil {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(uiColor: .ppSuccess))
                Text(Language.get("POS_Customer_CacheSynced", alter: "محدث ومحفوظ محلياً"))
                    .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AdminSurface.control, in: Capsule())
            .transition(.opacity)
        }
    }

    // MARK: - Customer Card in Left Stream

    private func iPadCustomerListCard(customer: POSCustomerRecord) -> some View {
        let isHighlighted = viewModel.highlightedCustomer?.id == customer.id
        let isCurrentPOS = currentSelected?.id == customer.id
        let activeBranchID = BranchContextStore.shared.activeBranch?.branchID ?? customer.branchId
        let credit = creditStore.summary(for: customer.id, branchID: activeBranchID)

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
                                    .font(PPBrandFont.medium(12, relativeTo: .caption2))
                            }
                            .foregroundColor(AdminSurface.secondaryText)

                            if let note = customer.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Image(systemName: "note.text")
                                    .font(.system(size: 9))
                                    .foregroundColor(AdminSurface.primary)
                            }
                        }

                        if let credit, credit.shouldDisplayCreditView {
                            POSCustomerCreditBalance(summary: credit)
                        }
                    }

                    Spacer(minLength: 2)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if canCreateCustomer {
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
        }
        .padding(10)
        .background(isHighlighted ? AdminSurface.primary.opacity(0.08) : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHighlighted ? AdminSurface.primary : (isCurrentPOS ? Color.clear : AdminSurface.hairline), lineWidth: isHighlighted ? 1.5 : (isCurrentPOS ? 0 : 1))
        )
        .task(id: "\(activeBranchID):\(creditStore.revision)") {
            if !activeBranchID.isEmpty {
                creditStore.loadCreditSummary(for: customer.id, branchID: activeBranchID)
            }
        }
        .contextMenu {
            if canCreateCustomer && !isUnavailable(customer) && customer.source == "directory" {
                Button {
                    viewModel.highlightedCustomer = customer
                    viewModel.startEditing(customer: customer)
                } label: {
                    Label(Language.get("POS_Customer_EditButton", alter: nil), systemImage: "pencil")
                }
                if !hasLocalBlockingCredit(customer) {
                    Button(role: .destructive) {
                        pendingDeleteCustomer = customer
                    } label: {
                        Label(Language.get("POS_Customer_DeleteButton", alter: nil), systemImage: "trash")
                    }
                }
            }
        }
        .accessibilityAction(named: String(format: Language.get("POS_Customer_DeleteNamed", alter: nil), customer.name)) {
            guard canCreateCustomer, !isUnavailable(customer), customer.source == "directory",
                  !hasLocalBlockingCredit(customer), !isBusy else { return }
            pendingDeleteCustomer = customer
        }
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

                            // Credit & Terms Card in Dossier
                            let activeBranchID = BranchContextStore.shared.activeBranch?.branchID ?? customer.branchId
                            let credit = creditStore.summary(for: customer.id, branchID: activeBranchID)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "creditcard.fill")
                                            .foregroundColor(credit?.isPolicyVerified == true ? Color(red: 0.05, green: 0.58, blue: 0.38) : AdminSurface.primary)
                                            .font(.system(size: 13))
                                        Text(Language.get("POS_Customer_CreditSectionTitle", alter: "سياسة وتسهيلات البيع الآجل"))
                                            .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                            .foregroundColor(AdminSurface.primaryText)
                                    }
                                    Spacer()
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        showsCreditPolicySheet = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 11))
                                            Text(Language.get("POS_Customer_ManageCreditCTA", alter: "إعداد الائتمان"))
                                                .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                        }
                                        .foregroundColor(AdminSurface.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }

                                if let credit, credit.shouldDisplayCreditView {
                                    POSCustomerCreditBalance(summary: credit)
                                } else {
                                    Text(Language.get("POS_Credit_PolicyRequired", alter: "This customer needs an approved credit policy for this branch before selling on credit."))
                                        .font(Font.custom("Beiruti-Regular", size: 11.5, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(10)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 16)
                }

                Divider().background(AdminSurface.hairline)

                // Dock Action Controls
                VStack(alignment: .leading, spacing: 8) {
                    if canCreateCustomer && customer.source == "directory" && hasLocalBlockingCredit(customer) {
                        Text(Language.get("POS_Customer_DeleteCreditHint", alter: nil))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.crimson)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        if canCreateCustomer {
                            if customer.source == "directory" && !customer.id.isEmpty {
                                let localCredit = hasLocalBlockingCredit(customer)
                                let disabledDelete = isBusy || isUnavailable(customer) || localCredit
                                Button(role: .destructive) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    pendingDeleteCustomer = customer
                                } label: {
                                    HStack(spacing: 6) {
                                        if viewModel.isDeletingCustomer && viewModel.deletingCustomerId == customer.id {
                                            ProgressView().tint(AdminSurface.danger).scaleEffect(0.85)
                                        } else {
                                            Image(systemName: "trash")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        if purpose.isManagingCustomers {
                                            Text(Language.get("POS_Customer_DeleteButton", alter: nil))
                                                .font(AdminType.calloutBold)
                                        }
                                    }
                                    .foregroundStyle(AdminSurface.danger)
                                    .padding(.horizontal, purpose.isManagingCustomers ? 14 : 0)
                                    .frame(minWidth: 46, minHeight: 46)
                                    .background(AdminSurface.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(AdminSurface.danger.opacity(0.22), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(disabledDelete)
                                .opacity(disabledDelete ? 0.45 : 1)
                                .accessibilityLabel(String(format: Language.get("POS_Customer_DeleteNamed", alter: nil), customer.name))
                                .accessibilityIdentifier("pos.customer.ipad.delete")
                            }

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
                                .frame(maxWidth: purpose.isManagingCustomers ? .infinity : nil, minHeight: 46)
                                .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isBusy)
                        }

                        // Primary Link To Cart Button
                        if !purpose.isManagingCustomers {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                viewModel.rememberCustomer(customer)
                                onSelect?(customer)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 15, weight: .bold))
                                    Text(purpose.selectTitle)
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
                            .disabled(isBusy)
                        }
                    }
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
                    Text(canCreateCustomer
                         ? Language.get("POS_Customer_InspectorHint", alter: "اختر عميلاً من القائمة لمعاينة التفاصيل أو تعديل الملف.")
                         : Language.get("POS_Customer_InspectorHint_ReadOnly", alter: "اختر عميلاً لمعاينة التفاصيل."))
                        .font(Font.custom("Beiruti-Regular", size: 13, relativeTo: .caption))
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AdminSurface.surface.opacity(0.5))
        .onAppear {
            if let customer = viewModel.highlightedCustomer {
                let branchID = BranchContextStore.shared.activeBranch?.branchID ?? customer.branchId
                if !branchID.isEmpty {
                    creditStore.loadCreditSummary(for: customer.id, branchID: branchID)
                }
            }
        }
        .onChange(of: viewModel.highlightedCustomer?.id) { newID in
            if let customer = viewModel.highlightedCustomer, let newID = newID, !newID.isEmpty {
                let branchID = BranchContextStore.shared.activeBranch?.branchID ?? customer.branchId
                if !branchID.isEmpty {
                    creditStore.loadCreditSummary(for: newID, branchID: branchID)
                }
            }
        }
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
                        .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .caption))
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

                    // Phone Field
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف *"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                            if !viewModel.editPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    if let id = viewModel.editingCustomer?.id {
                                        viewModel.copyPhone(phone: viewModel.editPhone, customerId: id)
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: viewModel.copiedPhoneId == viewModel.editingCustomer?.id ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10))
                                        Text(viewModel.copiedPhoneId == viewModel.editingCustomer?.id
                                             ? Language.get("POS_Customer_QuickAction_Copied", alter: "تم النسخ")
                                             : Language.get("POS_Customer_QuickAction_Copy", alter: "نسخ"))
                                            .font(Font.custom("Beiruti-Bold", size: 11, relativeTo: .caption2))
                                    }
                                    .foregroundColor(viewModel.copiedPhoneId == viewModel.editingCustomer?.id ? .green : AdminSurface.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(AdminSurface.control, in: Capsule())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AdminSurface.secondaryText)
                                .frame(width: 18)
                            TextField(Language.get("POS_Customer_PhonePlaceholder", alter: "5512 3456"), text: $viewModel.editPhone)
                                .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
                                .keyboardType(.phonePad)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }

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

                    // Credit Policy & Terms Section
                    let editingCustomer = viewModel.editingCustomer
                    let editBranchID = !viewModel.editBranchId.isEmpty ? viewModel.editBranchId : (BranchContextStore.shared.activeBranch?.branchID ?? editingCustomer?.branchId ?? "")
                    let credit = editingCustomer.flatMap { creditStore.summary(for: $0.id, branchID: editBranchID) }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Language.get("POS_Customer_CreditSectionTitle", alter: "سياسة وتسهيلات البيع الآجل"))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.primaryText)
                            Spacer()
                        }

                        if let credit, credit.shouldDisplayCreditView {
                            POSCustomerCreditBalance(summary: credit)
                        } else {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(AdminSurface.primary)
                                    .font(.system(size: 15))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Language.get("POS_Credit_NeedsVerification", alter: "Customer terms need verification"))
                                        .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .subheadline))
                                        .foregroundColor(AdminSurface.primaryText)
                                    Text(Language.get("POS_Credit_PolicyRequired", alter: "This customer needs an approved credit policy for this branch before selling on credit."))
                                        .font(Font.custom("Beiruti-Regular", size: 11, relativeTo: .caption))
                                        .foregroundColor(AdminSurface.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(AdminSurface.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
                        }

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showsCreditPolicySheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                Text(Language.get("POS_Customer_ManageCreditCTA", alter: "إعداد سياسة وسقف الائتمان"))
                                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .callout))
                            }
                            .foregroundColor(AdminSurface.primary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if let editingCustomer, editingCustomer.source == "directory", !editingCustomer.id.isEmpty {
                        let localCredit = hasLocalBlockingCredit(editingCustomer)
                        let disabledDelete = isBusy || isUnavailable(editingCustomer) || localCredit
                        VStack(alignment: .leading, spacing: 6) {
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                pendingDeleteCustomer = editingCustomer
                            } label: {
                                HStack(spacing: 8) {
                                    if viewModel.isDeletingCustomer && viewModel.deletingCustomerId == editingCustomer.id {
                                        ProgressView().tint(AdminSurface.danger).scaleEffect(0.85)
                                    } else {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    Text(Language.get(viewModel.isDeletingCustomer ? "POS_Customer_Deleting" : "POS_Customer_DeleteButton", alter: nil))
                                        .font(AdminType.calloutBold)
                                }
                                .foregroundStyle(AdminSurface.danger)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(AdminSurface.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(AdminSurface.danger.opacity(0.22), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(disabledDelete)
                            .opacity(disabledDelete ? 0.45 : 1)
                            .accessibilityLabel(String(format: Language.get("POS_Customer_DeleteNamed", alter: nil), editingCustomer.name))

                            Text(Language.get(localCredit ? "POS_Customer_DeleteCreditHint" : "POS_Customer_DeleteEligibilityHint", alter: nil))
                                .font(AdminType.caption)
                                .foregroundStyle(localCredit ? AdminSurface.crimson : AdminSurface.secondaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
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
                .disabled(isBusy)

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
                .disabled(isBusy)
                .buttonStyle(PlainButtonStyle())

                if !purpose.isManagingCustomers {
                    Button {
                        viewModel.submitUpdateCustomer(andSelect: true) { updated in
                            onSelect?(updated)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.backward.fill").font(.system(size: 11))
                            Text(purpose.saveAndSelectTitle)
                                .font(Font.custom("Beiruti-Bold", size: 13.5, relativeTo: .callout))
                        }
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isBusy)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(14)
            .background(AdminSurface.surface)
        }
    }

    // MARK: - State 2: Walk-In Registration Studio (iPad Next Gen V10 Redesign)

    private var iPadInPlaceCreateChamber: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .foregroundColor(AdminSurface.primary)
                            .font(.system(size: 16, weight: .bold))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("POS_Customer_TabCreate", alter: "تسجيل عميل جديد فوري"))
                            .font(PPBrandFont.bold(size: 16))
                            .foregroundColor(AdminSurface.primaryText)
                        Text(Language.get("POS_Customer_TabCreate_Sub", alter: "إضافة ملف عميل فوري إلى سجلات بيور بيتس الموحدة"))
                            .font(PPBrandFont.regular(size: 11.5))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
                Spacer()

                // Persona Ready Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 ? Color(uiColor: .systemGreen) : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(
                        viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
                            ? Language.get("POS_Customer_StatusReady", alter: "جاهز للحفظ والربط")
                            : (viewModel.newName.isEmpty
                                ? Language.get("POS_Customer_StatusNew", alter: "تسجيل فوري")
                                : Language.get("POS_Customer_StatusNeedPhone", alter: "أكمل رقم الهاتف"))
                    )
                    .font(PPBrandFont.bold(size: 11.5))
                    .foregroundStyle(viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 ? Color(uiColor: .systemGreen) : Color.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    (viewModel.newPhone.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 ? Color(uiColor: .systemGreen) : Color.orange).opacity(0.1),
                    in: Capsule()
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(AdminSurface.surface)

            Divider().background(AdminSurface.hairline)

            ScrollView {
                VStack(spacing: 18) {
                    // Live Persona Aura & Monogram Deck
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            AdminSurface.primary.opacity(viewModel.newName.isEmpty ? 0.08 : 0.22),
                                            Color(red: 0.85, green: 0.20, blue: 0.40).opacity(viewModel.newName.isEmpty ? 0.04 : 0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .blur(radius: viewModel.newName.isEmpty ? 2 : 5)

                            Circle()
                                .strokeBorder(
                                    viewModel.newName.isEmpty ? AdminSurface.hairline : AdminSurface.primary.opacity(0.4),
                                    lineWidth: 1.5
                                )
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(
                                    viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? AnyShapeStyle(AdminSurface.surface)
                                        : AnyShapeStyle(
                                            LinearGradient(
                                                colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .frame(width: 64, height: 64)
                                .shadow(color: viewModel.newName.isEmpty ? Color.clear : AdminSurface.primary.opacity(0.3), radius: 6, y: 2)

                            if viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(AdminSurface.primary)
                            } else {
                                Text(String(viewModel.newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased())
                                    .font(PPBrandFont.bold(size: 22))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Duplicate Warning if Phone Exists
                    if let match = viewModel.duplicateMatch {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if purpose.isManagingCustomers {
                                viewModel.showManagedCustomer(match)
                                viewModel.startEditing(customer: match)
                            } else {
                                viewModel.rememberCustomer(match)
                                onSelect?(match)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .font(.system(size: 18))
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Language.get("POS_Customer_DuplicateFound", alter: "عميل مسجل مسبقاً بهذا الرقم!"))
                                        .font(PPBrandFont.bold(size: 13))
                                        .foregroundColor(AdminSurface.primaryText)
                                    Text(String(format: Language.get(purpose.isManagingCustomers ? "POS_Customer_Management_Duplicate" : "POS_Customer_DuplicateSub", alter: "الاسم: %@"), match.name))
                                        .font(PPBrandFont.medium(size: 12))
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                                HStack(spacing: 3) {
                                    Text(Language.get("POS_Customer_UseExisting", alter: "استخدام"))
                                        .font(PPBrandFont.bold(size: 11.5))
                                    Image(systemName: Language.isRTL() ? "arrowshape.turn.up.backward.fill" : "arrowshape.turn.up.right.fill")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.orange, in: Capsule())
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange.opacity(0.3), lineWidth: 0.8))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Form Fields
                    VStack(spacing: 12) {
                        // 1. Name Field
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Language.get("POS_Customer_NameField", alter: "اسم العميل (اختياري)"))
                                .font(PPBrandFont.bold(size: 12.5))
                                .foregroundColor(AdminSurface.primaryText)

                            HStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .frame(width: 18)

                                TextField(Language.get("POS_Customer_NamePlaceholder", alter: "مثال: سالم الكواري"), text: $viewModel.newName)
                                    .font(PPBrandFont.medium(size: 14))

                                if !viewModel.newName.isEmpty {
                                    Button {
                                        viewModel.newName = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }

                        // 2. Phone Field with Qatar/GCC Country Code Picker
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف *"))
                                    .font(PPBrandFont.bold(size: 12.5))
                                    .foregroundColor(AdminSurface.primaryText)
                                Spacer()
                                Text(Language.get("POS_Customer_PhoneRequired", alter: "مطلوب للربط وحفظ السجل"))
                                    .font(PPBrandFont.regular(size: 10.5))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }

                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(AdminCountryCatalog.all) { item in
                                        Button {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedCountry = item
                                            viewModel.newPhone = AdminCountryCatalog.formatDigits(viewModel.newPhone, for: item)
                                            viewModel.checkDuplicatePhone(viewModel.newPhone)
                                        } label: {
                                            HStack {
                                                Text(item.displayName)
                                                if selectedCountry.code == item.code {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(selectedCountry.flag)
                                            .font(.system(size: 16))
                                        Text(selectedCountry.code)
                                            .font(PPBrandFont.bold(size: 13))
                                            .foregroundColor(AdminSurface.primaryText)
                                            .monospacedDigit()
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(AdminSurface.hairline, lineWidth: 0.6)
                                    )
                                }

                                Rectangle()
                                    .fill(AdminSurface.hairline)
                                    .frame(width: 1, height: 22)

                                TextField(
                                    "",
                                    text: Binding(
                                        get: { viewModel.newPhone },
                                        set: { newValue in
                                            let formatted = AdminCountryCatalog.formatDigits(newValue, for: selectedCountry)
                                            viewModel.newPhone = formatted
                                            viewModel.checkDuplicatePhone(formatted)
                                        }
                                    ),
                                    prompt: Text(Language.get("POS_Customer_PhonePlaceholder", alter: "5512 3456"))
                                        .font(PPBrandFont.medium(size: 14))
                                        .foregroundColor(AdminSurface.secondaryText)
                                )
                                .keyboardType(.phonePad)
                                .font(PPBrandFont.bold(size: 15))
                                .foregroundColor(AdminSurface.primaryText)
                                .monospacedDigit()

                                if !viewModel.newPhone.isEmpty {
                                    Button {
                                        viewModel.newPhone = ""
                                        viewModel.checkDuplicatePhone("")
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(viewModel.duplicateMatch != nil ? Color.orange : AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }

                        // 3. Email Field
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Language.get("POS_Customer_EmailField", alter: "البريد الإلكتروني (اختياري)"))
                                .font(PPBrandFont.bold(size: 12.5))
                                .foregroundColor(AdminSurface.primaryText)

                            HStack(spacing: 10) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .frame(width: 18)

                                TextField("customer@example.com", text: $viewModel.newEmail)
                                    .font(PPBrandFont.regular(size: 14))
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()

                                if !viewModel.newEmail.isEmpty {
                                    Button {
                                        viewModel.newEmail = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }

                        // 4. Preferred Branch Selector
                        if !viewModel.branches.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 11))
                                        .foregroundColor(AdminSurface.primary)
                                    Text(Language.get("POS_Customer_BranchField", alter: "الفرع المفضل"))
                                        .font(PPBrandFont.bold(size: 12.5))
                                        .foregroundColor(AdminSurface.primaryText)
                                    Spacer()
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(viewModel.branches, id: \.id) { b in
                                            let active = viewModel.selectedBranchId == b.id
                                            Button {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                                    viewModel.selectedBranchId = active ? "" : b.id
                                                }
                                            } label: {
                                                HStack(spacing: 5) {
                                                    if active {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 10, weight: .bold))
                                                    }
                                                    Text(b.displayName)
                                                        .font(PPBrandFont.bold(size: 12.5))
                                                }
                                                .foregroundColor(active ? .white : AdminSurface.primaryText)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(
                                                    active
                                                        ? AnyShapeStyle(LinearGradient(colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                        : AnyShapeStyle(AdminSurface.surface),
                                                    in: Capsule()
                                                )
                                                .overlay(Capsule().stroke(active ? Color.clear : AdminSurface.hairline, lineWidth: 0.8))
                                                .shadow(color: active ? AdminSurface.primary.opacity(0.25) : Color.clear, radius: 4, y: 1.5)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            }
                        }

                        // 5. Internal Notes with Smart Chips
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(Language.get("POS_Customer_NoteField", alter: "ملاحظات داخلية"))
                                    .font(PPBrandFont.bold(size: 12.5))
                                    .foregroundColor(AdminSurface.primaryText)
                                Spacer()
                                Text(Language.get("POS_Customer_NoteOptional", alter: "اختياري"))
                                    .font(PPBrandFont.regular(size: 10.5))
                                    .foregroundColor(AdminSurface.secondaryText)
                            }

                            // Quick chips for velocity
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(quickNoteChips, id: \.self) { chip in
                                        Button {
                                            toggleNoteChip(chip)
                                        } label: {
                                            Text(chip)
                                                .font(PPBrandFont.medium(size: 11))
                                                .foregroundColor(viewModel.newNote.contains(chip) ? AdminSurface.primary : AdminSurface.secondaryText)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    viewModel.newNote.contains(chip) ? AdminSurface.primary.opacity(0.1) : AdminSurface.control,
                                                    in: Capsule()
                                                )
                                                .overlay(
                                                    Capsule().stroke(
                                                        viewModel.newNote.contains(chip) ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline,
                                                        lineWidth: 0.6
                                                    )
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 13))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .padding(.top, 2)
                                    .frame(width: 18)

                                TextField(Language.get("POS_Customer_NotePlaceholder", alter: "ملاحظات حول التوصيل أو تفضيلات العميل…"), text: $viewModel.newNote)
                                    .font(PPBrandFont.regular(size: 13.5))

                                if !viewModel.newNote.isEmpty {
                                    Button {
                                        viewModel.newNote = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(AdminSurface.secondaryText)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }
                    }
                }
                .padding(18)
            }

            Divider().background(AdminSurface.hairline)

            // Submit Button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.submitCreateCustomer { createdCustomer in
                    if purpose.isManagingCustomers {
                        viewModel.showManagedCustomer(createdCustomer)
                    } else {
                        onSelect?(createdCustomer)
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white).scaleEffect(0.9)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(purpose.createTitle)
                        .font(PPBrandFont.bold(size: 15.5))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
            }
            .disabled(viewModel.isSubmitting)
            .padding(16)
            .background(AdminSurface.surface)
        }
    }
}
