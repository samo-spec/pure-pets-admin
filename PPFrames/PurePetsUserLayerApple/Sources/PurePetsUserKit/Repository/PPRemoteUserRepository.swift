import Foundation

public actor PPRemoteUserRepository: PPUserRepository {
  private let auth: any PPAuthSource
  private let store: any PPUserStore
  private let cache: any PPUserCache
  private let mapper: PPUserMapper
  private let now: @Sendable () -> Date

  private var subscribers: [UUID: AsyncStream<PPUserRepositoryEvent>.Continuation] = [:]
  private var authTask: Task<Void, Never>?
  private var storeTask: Task<Void, Never>?
  private var tokenTask: Task<Void, Never>?

  private var generation = 0
  private var tokenRevision = 0
  private var currentAuthUser: PPAuthUser?
  private var currentRemoteState: PPRemoteUserState?
  private var currentToken: PPTokenClaims?
  private var currentSnapshot: PPCurrentUserSnapshot?
  private var authInitialized = false

  public init(
    auth: any PPAuthSource,
    store: any PPUserStore,
    cache: any PPUserCache,
    mapper: PPUserMapper,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.auth = auth
    self.store = store
    self.cache = cache
    self.mapper = mapper
    self.now = now
  }

  deinit {
    authTask?.cancel()
    storeTask?.cancel()
    tokenTask?.cancel()
  }

  public nonisolated func events() -> AsyncStream<PPUserRepositoryEvent> {
    let id = UUID()
    return AsyncStream { continuation in
      Task { await self.attach(id: id, continuation: continuation) }
      continuation.onTermination = { _ in
        Task { await self.detach(id: id) }
      }
    }
  }

  public func refresh(forceTokenRefresh: Bool = true) async throws -> PPCurrentUserSnapshot? {
    guard let user = currentAuthUser else { return nil }
    let ticket = generation

    async let token = auth.token(for: user.id, forceRefresh: forceTokenRefresh)
    async let remote = store.fetchState(for: user.id)
    let (resolvedToken, resolvedRemote) = try await (token, remote)

    guard generation == ticket, currentAuthUser?.id == user.id else {
      throw PPUserRepositoryFailure(
        code: .staleOperation, message: "The authenticated user changed during refresh.")
    }

    let snapshot = mapper.map(
      authUser: user,
      remote: resolvedRemote,
      token: resolvedToken,
      fetchedAt: now()
    )
    currentToken = resolvedToken
    currentRemoteState = resolvedRemote
    currentSnapshot = snapshot
    publish(.updated(snapshot))
    try? await cache.save(snapshot)
    return snapshot
  }

  public func updateProfile(_ patch: PPUserProfilePatch) async throws {
    guard !patch.isEmpty else { return }
    guard let user = currentAuthUser else {
      throw PPUserRepositoryFailure(code: .authentication, message: "A signed-in user is required.")
    }
    let ticket = generation
    try await store.updateProfile(for: user.id, patch: patch)
    guard generation == ticket, currentAuthUser?.id == user.id else {
      throw PPUserRepositoryFailure(
        code: .staleOperation, message: "The authenticated user changed during profile update.")
    }
  }

  private func attach(id: UUID, continuation: AsyncStream<PPUserRepositoryEvent>.Continuation) async
  {
    subscribers[id] = continuation
    if let currentSnapshot {
      continuation.yield(.updated(currentSnapshot))
    } else if authInitialized, currentAuthUser == nil {
      continuation.yield(.signedOut)
    }
    startIfNeeded()
  }

  private func detach(id: UUID) {
    subscribers.removeValue(forKey: id)
    guard subscribers.isEmpty else { return }
    authTask?.cancel()
    storeTask?.cancel()
    tokenTask?.cancel()
    authTask = nil
    storeTask = nil
    tokenTask = nil
    generation += 1
    tokenRevision += 1
    authInitialized = false
    currentAuthUser = nil
    currentRemoteState = nil
    currentToken = nil
    currentSnapshot = nil
  }

  private func startIfNeeded() {
    guard authTask == nil else { return }
    authTask = Task { [auth] in
      let events = await auth.events()
      for await user in events {
        if Task.isCancelled { break }
        await self.handleAuthEvent(user)
      }
    }
  }

  private func handleAuthEvent(_ user: PPAuthUser?) async {
    authInitialized = true
    let previousID = currentAuthUser?.id
    let nextID = user?.id

    if previousID != nextID {
      generation += 1
      tokenRevision += 1
      storeTask?.cancel()
      tokenTask?.cancel()
      storeTask = nil
      tokenTask = nil
      currentAuthUser = user
      currentRemoteState = nil
      currentToken = nil
      currentSnapshot = nil

      if let previousID {
        try? await cache.remove(for: previousID)
      }

      guard let user else {
        publish(.signedOut)
        return
      }

      if let cached = try? await cache.load(for: user.id) {
        currentSnapshot = cached
        publish(.updated(cached))
      }
      startStoreStream(for: user, ticket: generation)
    }

    guard let user else { return }
    refreshToken(for: user, ticket: generation)
  }

  private func startStoreStream(for user: PPAuthUser, ticket: Int) {
    storeTask = Task { [store] in
      do {
        let states = await store.states(for: user.id)
        for try await state in states {
          if Task.isCancelled { break }
          await self.commitRemoteState(state, userID: user.id, ticket: ticket)
        }
      } catch is CancellationError {
        return
      } catch {
        self.publishFailure(
          .init(code: .profile, message: String(describing: error)), userID: user.id, ticket: ticket
        )
      }
    }
  }

  private func refreshToken(for user: PPAuthUser, ticket: Int) {
    tokenRevision += 1
    let revision = tokenRevision
    tokenTask?.cancel()
    tokenTask = Task { [auth] in
      do {
        let token = try await auth.token(for: user.id, forceRefresh: false)
        await self.commitToken(token, userID: user.id, ticket: ticket, revision: revision)
      } catch is CancellationError {
        return
      } catch {
        self.publishFailure(
          .init(code: .token, message: String(describing: error)), userID: user.id, ticket: ticket)
      }
    }
  }

  private func commitRemoteState(_ state: PPRemoteUserState, userID: PPUserID, ticket: Int) async {
    guard generation == ticket, currentAuthUser?.id == userID else { return }
    currentRemoteState = state
    await publishIfReady()
  }

  private func commitToken(_ token: PPTokenClaims, userID: PPUserID, ticket: Int, revision: Int)
    async
  {
    guard generation == ticket,
      tokenRevision == revision,
      currentAuthUser?.id == userID
    else { return }
    currentToken = token
    await publishIfReady()
  }

  private func publishIfReady() async {
    guard let user = currentAuthUser,
      let remote = currentRemoteState,
      let token = currentToken
    else { return }
    let snapshot = mapper.map(authUser: user, remote: remote, token: token, fetchedAt: now())
    currentSnapshot = snapshot
    publish(.updated(snapshot))
    try? await cache.save(snapshot)
  }

  private func publishFailure(_ failure: PPUserRepositoryFailure, userID: PPUserID, ticket: Int) {
    guard generation == ticket, currentAuthUser?.id == userID else { return }
    publish(.failed(failure))
  }

  private func publish(_ event: PPUserRepositoryEvent) {
    for continuation in subscribers.values {
      continuation.yield(event)
    }
  }
}
