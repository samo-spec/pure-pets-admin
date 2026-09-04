//
//  PPBranchContextBridge.swift
//  PurePetsAdmin
//
//  SwiftUI ObservableObject bridging PPBranchContextManager.
//

import SwiftUI
import Combine

// MARK: - Branch Session Model

public struct PPBranchSession: Identifiable, Hashable, Sendable {
    public let id: String
    public let branchId: String
    public let branchCode: String
    public let branchName: String
    public let userId: String
    public let userName: String
    public let openedAt: Date
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        branchId: String,
        branchCode: String = "",
        branchName: String = "",
        userId: String = "",
        userName: String = "",
        openedAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.id = id
        self.branchId = branchId
        self.branchCode = branchCode
        self.branchName = branchName
        self.userId = userId
        self.userName = userName
        self.openedAt = openedAt
        self.isActive = isActive
    }
}

@MainActor
public final class BranchContextStore: ObservableObject {
    public static let shared = BranchContextStore()

    @Published public private(set) var activeBranch: PPBranchModel?
    @Published public private(set) var activeSession: PPBranchSession?
    @Published public private(set) var availableBranches: [PPBranchModel] = []
    @Published public private(set) var isGlobal: Bool = false
    public var isGlobalAccess: Bool { isGlobal }
    @Published public private(set) var needsBranchSelection: Bool = false
    @Published public private(set) var currentBranchDisplayName: String = ""
    @Published public private(set) var currentStaff: PPStaffDoc?
    @Published public private(set) var isSyncingBackend: Bool = false

    public var currentSessionId: String {
        activeSession?.id ?? ""
    }

    private var cancellables = Set<AnyCancellable>()

    public init() {
        syncFromManager()

        NotificationCenter.default.publisher(for: NSNotification.Name.PPActiveBranchDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncFromManager()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name.PPAvailableBranchesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncFromManager()
            }
            .store(in: &cancellables)
    }

    public func syncFromManager() {
        let manager = PPBranchContextManager.shared()
        self.activeBranch = manager.activeBranch
        self.availableBranches = (manager.availableBranches as? [PPBranchModel]) ?? []
        self.currentStaff = manager.currentStaff
        self.isGlobal = manager.isGlobalAccess
        self.needsBranchSelection = manager.needsBranchSelection
        self.currentBranchDisplayName = manager.currentBranchDisplayName

        // Maintain operational branch session
        if let branch = manager.activeBranch, !branch.branchID.isEmpty {
            let branchId = branch.branchID
            if activeSession == nil || activeSession?.branchId != branchId {
                let staffId = manager.currentStaff?.uid ?? ""
                let staffName = manager.currentStaff?.displayName ?? "Staff"
                let session = PPBranchSession(
                    branchId: branchId,
                    branchCode: branch.code ?? "",
                    branchName: branch.localizedName(),
                    userId: staffId,
                    userName: staffName
                )
                self.activeSession = session
                UserDefaults.standard.set(session.id, forKey: "PPActiveBranchSessionID")
            }
        } else {
            self.activeSession = nil
            UserDefaults.standard.removeObject(forKey: "PPActiveBranchSessionID")
        }
    }

    @discardableResult
    public func selectBranch(_ branch: PPBranchModel) -> Bool {
        let success = PPBranchContextManager.shared().selectBranch(branch)
        syncFromManager()
        return success
    }

    @discardableResult
    public func selectBranch(id: String) -> Bool {
        let success = PPBranchContextManager.shared().selectBranch(withID: id)
        syncFromManager()
        return success
    }

    public func syncWorkingBranchToBackend(branchID: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        isSyncingBackend = true
        PPBranchContextManager.shared().syncWorkingBranch(toBackend: branchID) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.isSyncingBackend = false
                completion?(success)
            }
        }
    }

    public func reload() {
        PPBranchContextManager.shared().reloadAvailableBranches { [weak self] _ in
            DispatchQueue.main.async {
                self?.syncFromManager()
            }
        }
    }

    public func branch(for id: String) -> PPBranchModel? {
        PPBranchContextManager.shared().branch(withID: id)
    }

    public func localizedBranchName(for id: String?, fallback: String? = nil) -> String {
        PPBranchContextManager.shared().localizedBranchName(forID: id, fallback: fallback)
    }

    public func clear() {
        PPBranchContextManager.shared().clearContext()
        syncFromManager()
    }
}
