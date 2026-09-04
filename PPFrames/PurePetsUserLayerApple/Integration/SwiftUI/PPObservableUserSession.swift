#if canImport(Observation)
  import Foundation
  import Observation
  import PurePetsUserKit

  /// SwiftUI-facing observation adapter. `PPUserSession` remains the single source of truth.
  @available(iOS 17.0, macOS 14.0, *)
  @Observable
  @MainActor
  public final class PPObservableUserSession {
    public private(set) var state: PPUserSessionState

    @ObservationIgnored private let session: PPUserSession
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    public init(session: PPUserSession) {
      self.session = session
      state = session.state
    }

    deinit {
      observationTask?.cancel()
    }

    public var snapshot: PPCurrentUserSnapshot? { state.snapshot }
    public var user: PPUser? { snapshot?.user }
    public var access: PPUserAccess { snapshot?.access ?? .unknown() }
    public var isSignedIn: Bool { user != nil }

    public func start() {
      guard observationTask == nil else { return }
      session.start()
      let states = session.states()
      observationTask = Task { [weak self] in
        for await state in states {
          guard let self, !Task.isCancelled else { return }
          self.state = state
        }
      }
    }

    public func stop() {
      observationTask?.cancel()
      observationTask = nil
      session.stop()
      state = session.state
    }

    public func refresh(forceTokenRefresh: Bool = true) async {
      await session.refresh(forceTokenRefresh: forceTokenRefresh)
    }

    public func updateProfile(_ patch: PPUserProfilePatch) async throws {
      try await session.updateProfile(patch)
    }

    public func decision(for capability: PPUserCapability, at date: Date = .now)
      -> PPUserAccessDecision
    {
      session.decision(for: capability, at: date)
    }
  }
#endif
