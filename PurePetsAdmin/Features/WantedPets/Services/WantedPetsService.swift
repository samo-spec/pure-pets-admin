//
//  WantedPetsService.swift
//  Pure Pets Admin
//
//  Created for Pure Pets Platform.
//  Category-defining, resilient operational service for Wanted Pets.
//

import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Filter Enum

public enum WantedPetsFilter: String, CaseIterable, Identifiable {
    case byPet = "byPet"
    case all = "all"
    case waiting = "waiting"
    case contacted = "contacted"
    case interested = "interested"
    case fulfilled = "fulfilled"
    case closed = "closed"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .byPet: return Language.get("WantedPets_Filter_ByPet", alter: "حسب الحيوان")
        case .all: return Language.get("WantedPets_Filter_All", alter: "الكل")
        case .waiting: return Language.get("WantedPets_Filter_Waiting", alter: "انتظار")
        case .contacted: return Language.get("WantedPets_Filter_Contacted", alter: "تواصل")
        case .interested: return Language.get("WantedPets_Filter_Interested", alter: "مهتم")
        case .fulfilled: return Language.get("WantedPets_Filter_Fulfilled", alter: "مكتمل")
        case .closed: return Language.get("WantedPets_Filter_Closed", alter: "مغلق")
        }
    }
}

// MARK: - Pet Category Group

public struct WantedPetCategoryGroup: Identifiable, Hashable {
    public var id: String { "\(mainKindId)_\(subkindId ?? 0)" }
    public let mainKindId: Int
    public let mainKindName: String
    public let subkindId: Int?
    public let subkindName: String?
    public var items: [CustomerWantedPet]

    public var displayName: String {
        if let sub = subkindName, !sub.isEmpty {
            return sub
        }
        if !mainKindName.isEmpty {
            return mainKindName
        }
        return Language.get("WantedPet_UnknownCategory", alter: "فئة غير محددة")
    }

    public var waitingCount: Int {
        items.filter { $0.status == .waiting }.count
    }

    public var totalActiveCount: Int {
        items.filter { $0.status.isActive }.count
    }

    public var oldestWaitingDurationText: String? {
        let waitingItems = items.filter { $0.status == .waiting }.sorted { $0.createdAt < $1.createdAt }
        return waitingItems.first?.waitingDurationText
    }
}

// MARK: - Service Implementation

@MainActor
public final class WantedPetsService: ObservableObject {
    public static let shared = WantedPetsService()

    @Published public private(set) var items: [CustomerWantedPet] = []
    @Published public var isLoading: Bool = false
    @Published public var isMutating: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var successMessage: String? = nil
    @Published public var searchQuery: String = ""
    @Published public var selectedFilter: WantedPetsFilter = .byPet

    private var listener: PPFirestoreListenerToken?
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    public init() {
        startLiveListener()
    }

    deinit {
        listener?.remove()
    }

    // MARK: - Live Firestore Synchronization

    public func startLiveListener() {
        listener?.remove()
        isLoading = true
        errorMessage = nil

        let query = db.collection("CustomerWantedPets")
            .order(by: "createdAt", descending: true)
            .limit(to: 200)

        let registration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            self.isLoading = false

            if let error = error {
                self.errorMessage = error.localizedDescription
                return
            }

            guard let docs = snapshot?.documents else { return }
            let parsed = docs.compactMap { CustomerWantedPet(documentId: $0.documentID, data: $0.data()) }
            self.items = parsed
            self.errorMessage = nil
        }
        listener = PPFirestoreListenerToken(registration)
    }

    public func stopLiveListener() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Computed Properties

    public var waitingCount: Int {
        items.filter { $0.status == .waiting }.count
    }

    public var contactedCount: Int {
        items.filter { $0.status == .contacted }.count
    }

    public var interestedCount: Int {
        items.filter { $0.status == .interested }.count
    }

    public var fulfilledCount: Int {
        items.filter { $0.status == .fulfilled }.count
    }

    public var closedCount: Int {
        items.filter { $0.status == .closed }.count
    }

    public var totalActiveCount: Int {
        items.filter { $0.status.isActive }.count
    }

    public func waitingCountFor(mainKindId: Int, subkindId: Int?) -> Int {
        guard mainKindId > 0 else { return 0 }
        return items.filter { item in
            guard item.status == .waiting && item.mainKindId == mainKindId else { return false }
            if let targetSub = subkindId, targetSub > 0, let itemSub = item.subkindId, itemSub > 0 {
                return itemSub == targetSub
            }
            return true
        }.count
    }

    public var filteredItems: [CustomerWantedPet] {
        var base = items

        switch selectedFilter {
        case .byPet, .all:
            break
        case .waiting:
            base = base.filter { $0.status == .waiting }
        case .contacted:
            base = base.filter { $0.status == .contacted }
        case .interested:
            base = base.filter { $0.status == .interested }
        case .fulfilled:
            base = base.filter { $0.status == .fulfilled }
        case .closed:
            base = base.filter { $0.status == .closed }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            base = base.filter { item in
                item.customerName.lowercased().contains(query) ||
                item.phoneNumber.contains(query) ||
                item.normalizedPhoneNumber.contains(query) ||
                (item.notes?.lowercased().contains(query) ?? false) ||
                (item.mainKindName?.lowercased().contains(query) ?? false) ||
                (item.subkindName?.lowercased().contains(query) ?? false)
            }
        }

        return base
    }

    public var categoryGroups: [WantedPetCategoryGroup] {
        var groupDict: [String: WantedPetCategoryGroup] = [:]

        for item in filteredItems {
            let key = "\(item.mainKindId)_\(item.subkindId ?? 0)"
            if var existing = groupDict[key] {
                existing.items.append(item)
                groupDict[key] = existing
            } else {
                groupDict[key] = WantedPetCategoryGroup(
                    mainKindId: item.mainKindId,
                    mainKindName: item.mainKindName ?? "",
                    subkindId: item.subkindId,
                    subkindName: item.subkindName,
                    items: [item]
                )
            }
        }

        return groupDict.values.sorted {
            if $0.waitingCount != $1.waitingCount {
                return $0.waitingCount > $1.waitingCount
            }
            return $0.displayName < $1.displayName
        }
    }

    // MARK: - Callable Server Commands

    public struct CreateWantedPetResult {
        public let ok: Bool
        public let duplicateDetected: Bool
        public let existingRequest: CustomerWantedPet?
        public let message: String?
        public let id: String?
    }

    public func createRequest(
        customerName: String,
        phoneNumber: String,
        contactSource: WantedPetContactSource,
        mainKindId: Int,
        mainKindName: String?,
        subkindId: Int?,
        subkindName: String?,
        sexPreference: WantedPetSexPreference,
        colorPreference: String?,
        budgetMin: Double?,
        budgetMax: Double?,
        notes: String?,
        addAnyway: Bool = false
    ) async throws -> CreateWantedPetResult {
        isMutating = true
        defer { isMutating = false }

        var payload: [String: Any] = [
            "customerName": customerName,
            "phoneNumber": phoneNumber,
            "contactSource": contactSource.rawValue,
            "mainKindId": mainKindId,
            "sexPreference": sexPreference.rawValue,
            "addAnyway": addAnyway
        ]

        if let mName = mainKindName, !mName.isEmpty { payload["mainKindName"] = mName }
        if let sId = subkindId { payload["subkindId"] = sId }
        if let sName = subkindName, !sName.isEmpty { payload["subkindName"] = sName }
        if let color = colorPreference, !color.isEmpty { payload["colorPreference"] = color }
        if let bMin = budgetMin { payload["budgetMin"] = bMin }
        if let bMax = budgetMax { payload["budgetMax"] = bMax }
        if let n = notes, !n.isEmpty { payload["notes"] = n }

        let result = try await functions.httpsCallable("createWantedPetRequest").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw NSError(domain: "WantedPets", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }

        let isOk = (data["ok"] as? Bool) ?? false
        let isDuplicate = (data["duplicateDetected"] as? Bool) ?? false

        if isDuplicate {
            var existing: CustomerWantedPet? = nil
            if let existingDict = data["existingRequest"] as? [String: Any],
               let existingId = existingDict["id"] as? String {
                existing = CustomerWantedPet(documentId: existingId, data: existingDict)
            }
            return CreateWantedPetResult(
                ok: false,
                duplicateDetected: true,
                existingRequest: existing,
                message: data["message"] as? String,
                id: nil
            )
        }

        let newId = data["id"] as? String
        return CreateWantedPetResult(ok: isOk, duplicateDetected: false, existingRequest: nil, message: nil, id: newId)
    }

    public func transitionStatus(
        id: String,
        targetStatus: WantedPetStatus,
        contactChannel: String? = nil,
        linkedLivePetId: String? = nil,
        interestedPetId: String? = nil,
        fulfilledPetId: String? = nil,
        closeReason: String? = nil
    ) async throws {
        isMutating = true
        defer { isMutating = false }

        var payload: [String: Any] = [
            "id": id,
            "targetStatus": targetStatus.rawValue
        ]

        if let channel = contactChannel { payload["contactChannel"] = channel }
        if let petId = linkedLivePetId { payload["linkedLivePetId"] = petId }
        if let intPet = interestedPetId { payload["interestedPetId"] = intPet }
        if let fulPet = fulfilledPetId { payload["fulfilledPetId"] = fulPet }
        if let reason = closeReason { payload["closeReason"] = reason }

        _ = try await functions.httpsCallable("transitionWantedPetStatus").call(payload)
    }

    public func batchMarkContacted(ids: [String], channel: String = "whatsapp") async throws -> Int {
        isMutating = true
        defer { isMutating = false }

        let payload: [String: Any] = [
            "ids": ids,
            "channel": channel
        ]

        let result = try await functions.httpsCallable("batchMarkWantedPetsContacted").call(payload)
        guard let data = result.data as? [String: Any], let count = data["updatedCount"] as? Int else {
            return ids.count
        }
        return count
    }

    public func findMatchesForPet(
        mainKindId: Int,
        subkindId: Int?,
        gender: String?,
        color: String?,
        price: Double?
    ) async throws -> [WantedPetMatchResult] {
        var payload: [String: Any] = [
            "mainKindId": mainKindId
        ]
        if let sId = subkindId { payload["subkindId"] = sId }
        if let g = gender { payload["gender"] = g }
        if let c = color { payload["color"] = c }
        if let p = price { payload["sellingPrice"] = p }

        let result = try await functions.httpsCallable("findWantedCustomersForPet").call(payload)
        guard let data = result.data as? [String: Any],
              let matchesRaw = data["matches"] as? [[String: Any]] else {
            return []
        }

        var results: [WantedPetMatchResult] = []
        for raw in matchesRaw {
            guard let wantedDict = raw["wantedPet"] as? [String: Any],
                  let wantedId = raw["id"] as? String ?? wantedDict["id"] as? String,
                  let wantedPet = CustomerWantedPet(documentId: wantedId, data: wantedDict) else {
                continue
            }
            let levelStr = (raw["matchLevel"] as? String) ?? "compatible"
            let level = WantedPetMatchLevel(rawValue: levelStr) ?? .compatible
            let reason = (raw["matchReason"] as? String) ?? ""
            results.append(WantedPetMatchResult(wantedPet: wantedPet, matchLevel: level, matchReason: reason))
        }

        return results
    }

    public struct CustomerPhoneLookupResult {
        public let found: Bool
        public let customerName: String?
        public let activeWantedPetsCount: Int
    }

    public func lookupCustomerByPhone(phoneNumber: String) async throws -> CustomerPhoneLookupResult {
        let payload: [String: Any] = ["phoneNumber": phoneNumber]
        let result = try await functions.httpsCallable("lookupWantedPetCustomerByPhone").call(payload)

        guard let data = result.data as? [String: Any] else {
            return CustomerPhoneLookupResult(found: false, customerName: nil, activeWantedPetsCount: 0)
        }

        let found = (data["found"] as? Bool) ?? false
        var name: String? = nil
        if let customerDict = data["customer"] as? [String: Any] {
            name = customerDict["name"] as? String
        }
        let activeCount = (data["activeWantedPetsCount"] as? Int) ?? 0

        return CustomerPhoneLookupResult(found: found, customerName: name, activeWantedPetsCount: activeCount)
    }
}
