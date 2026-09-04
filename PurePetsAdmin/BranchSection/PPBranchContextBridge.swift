//
//  PPBranchContextBridge.swift
//  PurePetsAdmin
//
//  SwiftUI ObservableObject bridging PPBranchContextManager.
//

import SwiftUI
import Combine

@MainActor
public final class BranchContextStore: ObservableObject {
    public static let shared = BranchContextStore()

    @Published public private(set) var activeBranch: PPBranchModel?
    @Published public private(set) var availableBranches: [PPBranchModel] = []
    @Published public private(set) var isGlobal: Bool = false
    public var isGlobalAccess: Bool { isGlobal }
    @Published public private(set) var needsBranchSelection: Bool = false
    @Published public private(set) var currentBranchDisplayName: String = ""
    @Published public private(set) var currentStaff: PPStaffDoc?
    @Published public private(set) var isSyncingBackend: Bool = false

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
