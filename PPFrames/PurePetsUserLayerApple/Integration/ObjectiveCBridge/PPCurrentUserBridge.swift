#if canImport(ObjectiveC)
  import Foundation
  import PurePetsUserKit

  @objc(PPCurrentUserBridgeState)
  public enum PPCurrentUserBridgeState: Int {
    case idle
    case loading
    case signedOut
    case ready
    case failed
  }

  @objc(PPObjCUserCapability)
  public enum PPObjCUserCapability: Int, CaseIterable {
    case postPetAd
    case postAdoption
    case sellAccessories
    case useStories
    case useChat
    case purchase
    case withdraw
    case accessPremiumMarketplace
    case accessProviderMarketplace
    case accessPartnerApp
    case manageDelivery
    case manageServiceProvider
    case manageVet
    case postVetProfile
    case editVetInfo
    case managePetMedicines

    fileprivate var swiftValue: PPUserCapability {
      switch self {
      case .postPetAd: .postPetAd
      case .postAdoption: .postAdoption
      case .sellAccessories: .sellAccessories
      case .useStories: .useStories
      case .useChat: .useChat
      case .purchase: .purchase
      case .withdraw: .withdraw
      case .accessPremiumMarketplace: .accessPremiumMarketplace
      case .accessProviderMarketplace: .accessProviderMarketplace
      case .accessPartnerApp: .accessPartnerApp
      case .manageDelivery: .manageDelivery
      case .manageServiceProvider: .manageServiceProvider
      case .manageVet: .manageVet
      case .postVetProfile: .postVetProfile
      case .editVetInfo: .editVetInfo
      case .managePetMedicines: .managePetMedicines
      }
    }
  }

  @available(iOS 15.0, *)
  @MainActor
  @objcMembers
  public final class PPCurrentUserBridge: NSObject {
    public static let didChangeNotification = Notification.Name(
      "PPCurrentUserBridgeDidChangeNotification")

    public dynamic private(set) var state: PPCurrentUserBridgeState = .idle
    public dynamic private(set) var userID: String?
    public dynamic private(set) var displayName: String?
    public dynamic private(set) var email: String?
    public dynamic private(set) var avatarURL: URL?
    public dynamic private(set) var role: String = PPUserRole.user.rawValue
    public dynamic private(set) var isAdmin = false
    public dynamic private(set) var isSuperAdmin = false
    public dynamic private(set) var failureCode: String?

    private let session: PPUserSession
    private var observationTask: Task<Void, Never>?

    public init(session: PPUserSession) {
      self.session = session
      super.init()
      synchronize(with: session.state)
    }

    deinit {
      observationTask?.cancel()
    }

    public func start() {
      guard observationTask == nil else { return }
      session.start()
      let states = session.states()
      observationTask = Task { [weak self] in
        for await state in states {
          guard let self, !Task.isCancelled else { return }
          self.synchronize(with: state)
        }
      }
    }

    public func stop() {
      observationTask?.cancel()
      observationTask = nil
      session.stop()
      synchronize(with: session.state)
    }

    public func refresh(_ completion: @escaping (NSError?) -> Void) {
      Task {
        await session.refresh(forceTokenRefresh: true)
        if case .failed(let failure, _) = session.state {
          completion(
            NSError(
              domain: "PPCurrentUserBridge",
              code: 1,
              userInfo: [
                NSLocalizedDescriptionKey: failure.message,
                "failureCode": failure.code.rawValue,
              ]
            ))
        } else {
          completion(nil)
        }
      }
    }

    public func isAllowed(_ capability: PPObjCUserCapability) -> Bool {
      session.decision(for: capability.swiftValue).isAllowed
    }

    public func denialReasonCode(for capability: PPObjCUserCapability) -> String? {
      session.decision(for: capability.swiftValue).denial?.rawValue
    }

    /// Explicit profile fields only. Authorization, role, claims and permissions are not writable here.
    public func updateProfile(
      username: String?,
      firstName: String?,
      lastName: String?,
      phoneNumber: String?,
      about: String?,
      avatarURL: URL?,
      completion: @escaping (NSError?) -> Void
    ) {
      let patch = PPUserProfilePatch(
        username: username.map(PPFieldUpdate.set) ?? .unchanged,
        firstName: firstName.map(PPFieldUpdate.set) ?? .unchanged,
        lastName: lastName.map(PPFieldUpdate.set) ?? .unchanged,
        phoneNumber: phoneNumber.map(PPFieldUpdate.set) ?? .unchanged,
        about: about.map(PPFieldUpdate.set) ?? .unchanged,
        avatarURL: avatarURL.map(PPFieldUpdate.set) ?? .unchanged
      )
      Task {
        do {
          try await session.updateProfile(patch)
          completion(nil)
        } catch {
          completion(error as NSError)
        }
      }
    }

    private func synchronize(with state: PPUserSessionState) {
      switch state {
      case .idle:
        self.state = .idle
        failureCode = nil
      case .loading:
        self.state = .loading
        failureCode = nil
      case .signedOut:
        self.state = .signedOut
        failureCode = nil
      case .ready:
        self.state = .ready
        failureCode = nil
      case .failed(let failure, _):
        self.state = .failed
        failureCode = failure.code.rawValue
      }

      let snapshot = state.snapshot
      userID = snapshot?.user.id.rawValue
      displayName = snapshot?.user.displayName
      email = snapshot?.user.email
      avatarURL = snapshot?.user.avatarURL
      role = snapshot?.access.role.rawValue ?? PPUserRole.user.rawValue
      isAdmin = snapshot?.access.isAdmin ?? false
      isSuperAdmin = snapshot?.access.isSuperAdmin ?? false

      NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
  }
#endif
