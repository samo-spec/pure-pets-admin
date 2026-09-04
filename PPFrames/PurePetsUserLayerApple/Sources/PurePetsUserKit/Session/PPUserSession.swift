import Foundation

public enum PPUserSessionState: Equatable, Sendable {
  case idle
  case loading(previous: PPCurrentUserSnapshot?)
  case signedOut
  case ready(PPCurrentUserSnapshot)
  case failed(PPUserRepositoryFailure, previous: PPCurrentUserSnapshot?)

  public var snapshot: PPCurrentUserSnapshot? {
    switch self {
    case .loading(let previous), .failed(_, let previous): previous
    case .ready(let snapshot): snapshot
    case .idle, .signedOut: nil
    }
  }
}

@MainActor
public final class PPUserSession {
  public private(set) var state: PPUserSessionState = .idle

  private let repository: any PPUserRepository
  private var eventTask: Task<Void, Never>?
  private var stateContinuations: [UUID: AsyncStream<PPUserSessionState>.Continuation] = [:]
  private var generation = 0

  public init(repository: any PPUserRepository) {
    self.repository = repository
  }

  deinit {
    eventTask?.cancel()
  }

  public var snapshot: PPCurrentUserSnapshot? { state.snapshot }
  public var user: PPUser? { snapshot?.user }
  public var access: PPUserAccess { snapshot?.access ?? .unknown() }
  public var isSignedIn: Bool { user != nil }

  public func start() {
    guard eventTask == nil else { return }
    transition(to: .loading(previous: state.snapshot))
    let events = repository.events()
    eventTask = Task { [weak self] in
      for await event in events {
        guard let self, !Task.isCancelled else { return }
        self.consume(event)
      }
    }
  }

  public func stop() {
    generation += 1
    eventTask?.cancel()
    eventTask = nil
    transition(to: .idle)
  }

  public func refresh(forceTokenRefresh: Bool = true) async {
    generation += 1
    let ticket = generation
    let previous = state.snapshot
    transition(to: .loading(previous: previous))
    do {
      let snapshot = try await repository.refresh(forceTokenRefresh: forceTokenRefresh)
      guard ticket == generation else { return }
      transition(to: snapshot.map(PPUserSessionState.ready) ?? .signedOut)
    } catch let failure as PPUserRepositoryFailure {
      guard ticket == generation else { return }
      transition(to: .failed(failure, previous: previous))
    } catch {
      guard ticket == generation else { return }
      transition(
        to: .failed(.init(code: .unknown, message: String(describing: error)), previous: previous))
    }
  }

  public func updateProfile(_ patch: PPUserProfilePatch) async throws {
    try await repository.updateProfile(patch)
  }

  public func decision(for capability: PPUserCapability, at date: Date = .now)
    -> PPUserAccessDecision
  {
    access.decision(for: capability, at: date)
  }

  public func states() -> AsyncStream<PPUserSessionState> {
    let id = UUID()
    return AsyncStream { continuation in
      stateContinuations[id] = continuation
      continuation.yield(state)
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.stateContinuations.removeValue(forKey: id) }
      }
    }
  }

  private func consume(_ event: PPUserRepositoryEvent) {
    generation += 1
    switch event {
    case .signedOut:
      transition(to: .signedOut)
    case .updated(let snapshot):
      transition(
        to: snapshot.access.trust == .verified ? .ready(snapshot) : .loading(previous: snapshot))
    case .failed(let failure):
      transition(to: .failed(failure, previous: state.snapshot))
    }
  }

  private func transition(to newState: PPUserSessionState) {
    state = newState
    for continuation in stateContinuations.values {
      continuation.yield(newState)
    }
  }
}
