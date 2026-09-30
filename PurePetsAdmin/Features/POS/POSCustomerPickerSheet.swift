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

    var title: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_Title", alter: "دليل وربط العملاء")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_Title", alter: "دليل العملاء")
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
        }
    }

    var selectTitle: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_SelectToCart", alter: "ربط العميل بهذه السلة")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_Select", alter: "استخدام هذا العميل")
        }
    }

    var saveAndSelectTitle: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_SaveAndLink", alter: "حفظ وربط العميل بالسلة")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_SaveAndSelect", alter: "حفظ واستخدام العميل")
        }
    }

    var createTitle: String {
        switch self {
        case .posCart: return Language.get("POS_Customer_SubmitCTA", alter: "حفظ وتحديد العميل للسلة")
        case .wantedPetRequest: return Language.get("WantedPets_Directory_SaveAndSelect", alter: "حفظ واستخدام العميل")
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

    func mergeAndPersist(incoming: [POSCustomerRecord]) -> [POSCustomerRecord] {
        queue.sync {
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
    @Published var searchResults: [POSCustomerRecord] = []
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
    @Published var editEmail: String = ""
    @Published var editNote: String = ""
    @Published var editBranchId: String = ""
    @Published var isEditingSubmitting: Bool = false

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
                
                // Merge authoritative Firestore records into local cache
                let merged = POSCustomerCacheStore.shared.mergeAndPersist(incoming: parsed)
                
                // Update recents if any were modified on Firestore
                self.syncRecentsWithUpdatedCustomers(merged)

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
        isSyncingWithFirestore = true
        do {
            let callable = Functions.functions().httpsCallable("posCustomerCommand")
            callable.timeoutInterval = 20
            let payload: [String: Any] = [
                "action": "search",
                "term": searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                "pageSize": 25
            ]
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any],
                  let items = data["customers"] as? [[String: Any]] else {
                isSyncingWithFirestore = false
                return
            }
            let parsed = items.compactMap { self.parseCustomer($0) }
            let merged = POSCustomerCacheStore.shared.mergeAndPersist(incoming: parsed)
            self.syncRecentsWithUpdatedCustomers(merged)
            
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

    private func syncRecentsWithUpdatedCustomers(_ updatedList: [POSCustomerRecord]) {
        var recentsChanged = false
        var updatedRecents = recentCustomers
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
private struct POSCustomerIdentityCell: View {
    let customer: POSCustomerRecord
    let branchName: String
    let isSelected: Bool
    let selectionHint: String
    let onSelect: () -> Void
    let onEdit: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    private var note: String { (customer.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isUnavailable: Bool {
        ["blocked", "banned", "disabled", "deactivated", "deleted", "suspended", "archived", "inactive"]
            .contains(customer.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    selectionButton
                    if onEdit != nil {
                        Divider().padding(.horizontal, 16)
                        editButton
                    }
                }
            } else {
                HStack(spacing: 0) {
                    selectionButton
                    if onEdit != nil {
                        Rectangle().fill(AdminSurface.hairline).frame(width: 1, height: 28)
                            .accessibilityHidden(true)
                        editButton.padding(.horizontal, 6)
                    }
                }
            }
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? AdminSurface.primary :
                    (contrast == .increased ? AdminSurface.secondaryText : AdminSurface.hairline),
                    lineWidth: isSelected ? 1.5 : 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }

    private var selectionButton: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 11) {
                if !typeSize.isAccessibilitySize {
                    Text(customer.initials)
                        .font(PPBrandFont.bold(15, relativeTo: .caption))
                        .foregroundColor(AdminSurface.primary)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(customer.name)
                            .font(PPBrandFont.bold(20, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.forward")
                            .font(.system(size: isSelected ? 17 : 11, weight: .semibold))
                            .foregroundColor(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if !customer.phone.isEmpty { contactLine(customer.phone, icon: "phone", isEmail: false) }
                        if !customer.email.isEmpty { contactLine(customer.email, icon: "envelope", isEmail: true) }
                    }
                    if customer.isLinkedAppUser {
                        metadataLine(Language.get("POS_Customer_AppUserBadge", alter: nil), icon: "person.crop.circle")
                    }
                    if isUnavailable { metadataLine(Language.get("POS_Customer_InactiveContact", alter: nil), icon: "lock") }
                    if !branchName.isEmpty { metadataLine(branchName, icon: "mappin") }
                    if !note.isEmpty {
                        Text(note)
                            .font(PPBrandFont.regular(13, relativeTo: .footnote))
                            .foregroundColor(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
    }

    private func contactLine(_ value: String, icon: String, isEmail: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if !Language.isRTL() { Image(systemName: icon).font(.system(size: 10, weight: .medium)) }
            Text(value)
                .font(isEmail ? PPBrandFont.medium(13.5, relativeTo: .footnote) : PPBrandFont.bold(15, relativeTo: .subheadline))
                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if Language.isRTL() { Image(systemName: icon).font(.system(size: 10, weight: .medium)) }
        }
        .frame(maxWidth: .infinity, alignment: Language.isRTL() ? .trailing : .leading)
        .environment(\.layoutDirection, .leftToRight)
        .foregroundColor(AdminSurface.secondaryText)
    }

    private func metadataLine(_ value: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .medium))
            Text(value).font(PPBrandFont.medium(13, relativeTo: .footnote))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(AdminSurface.secondaryText)
    }

    private var editButton: some View {
        Button { onEdit?() } label: {
            HStack(spacing: 7) {
                Image(systemName: "pencil.line").font(.system(size: 16, weight: .medium))
                if typeSize.isAccessibilitySize {
                    Text(Language.get("POS_Customer_EditButton", alter: nil))
                        .font(PPBrandFont.bold(16, relativeTo: .callout))
                }
            }
            .foregroundColor(AdminSurface.primary)
            .frame(minWidth: 44, maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 44)
            .padding(.vertical, typeSize.isAccessibilitySize ? 4 : 0)
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
    let onSelect: (POSCustomerRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = POSCustomerPickerViewModel()
    @State private var isAccountPickerPresented = false
    @State private var pendingAccount: POSCustomerAppAccount?

    init(
        currentSelected: POSCustomerRecord?,
        canCreateCustomer: Bool = true,
        purpose: POSCustomerPickerPurpose = .posCart,
        onSelect: @escaping (POSCustomerRecord) -> Void
    ) {
        self.currentSelected = currentSelected
        self.canCreateCustomer = canCreateCustomer
        self.purpose = purpose
        self.onSelect = onSelect
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
                        dismiss: { dismiss() }
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
                        dismiss: { dismiss() }
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
                        title: purpose.title,
                        subtitle: purpose.subtitle(canCreate: canCreateCustomer),
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
                    purpose: purpose,
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

                if canAttachAppUser {
                    POSCustomerAttachUserButton(action: onAttachAppUser)
                }

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
                            syncStatusBadge
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

                // Search Results Header & Sync Status (when search is active or recents empty)
                if !viewModel.searchText.isEmpty || viewModel.recentCustomers.isEmpty {
                    HStack {
                        if !viewModel.searchText.isEmpty {
                            Text(String(format: Language.get("POS_Catalog_ResultCount_Format", alter: "%ld نتيجة"), viewModel.searchResults.count))
                                .font(Font.custom("Beiruti-Bold", size: 12.5, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        Spacer()
                        syncStatusBadge
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
        .refreshable {
            await viewModel.refreshFromFirestoreAsync()
        }
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
                        .font(PPBrandFont.medium(11, relativeTo: .caption2))
                        .foregroundColor(AdminSurface.secondaryText)
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
        POSCustomerIdentityCell(
            customer: customer,
            branchName: viewModel.branchDisplayName(for: customer.branchId),
            isSelected: currentSelected?.id == customer.id,
            selectionHint: purpose.selectTitle,
            onSelect: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.rememberCustomer(customer)
                onSelect(customer)
                dismiss()
            },
            onEdit: canCreateCustomer ? { viewModel.startEditing(customer: customer) } : nil
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
                                .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                .foregroundColor(AdminSurface.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            TextField(Language.get("POS_Customer_PhonePlaceholder", alter: "5512 3456"), text: $viewModel.newPhone)
                                .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .body))
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
                        Text(purpose.createTitle)
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
    let purpose: POSCustomerPickerPurpose
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
                                        .font(PPBrandFont.bold(14, relativeTo: .callout))
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
                                        Text(purpose.saveAndSelectTitle)
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
    let purpose: POSCustomerPickerPurpose
    let canAttachAppUser: Bool
    let onAttachAppUser: () -> Void
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
                            iPadCustomerListCard(customer: customer)
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
                    if canCreateCustomer {
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
                    }

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

                    // Phone Identity Locked
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(Language.get("POS_Customer_PhoneField", alter: "رقم الهاتف:"))
                            .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                            .foregroundColor(AdminSurface.secondaryText)
                        Text(viewModel.editingCustomer?.phone ?? "")
                            .font(PPBrandFont.bold(14, relativeTo: .callout))
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
                        Text(purpose.saveAndSelectTitle)
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
                                    .font(Font.custom("Beiruti-Bold", size: 12, relativeTo: .caption))
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 8)
                                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                TextField("5512 3456", text: $viewModel.newPhone)
                                    .font(Font.custom("Beiruti-Bold", size: 14, relativeTo: .body))
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
                    Text(purpose.createTitle)
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
