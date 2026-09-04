import Foundation

@testable import PurePetsUserKit

let testCatalog = PPPermissionCatalog(
  postPetAd: "post_ads",
  postAdoption: "adoption",
  sellAccessories: "sell_new"
)

func testUser(_ rawID: String, name: String? = nil) -> PPAuthUser {
  PPAuthUser(id: PPUserID(rawID)!, email: "\(rawID)@example.com", displayName: name)
}

func testToken(
  role: PPUserRole = .user,
  admin: Bool = false,
  superAdmin: Bool = false,
  blocked: Bool = false,
  now: Date = Date(timeIntervalSince1970: 1_000)
) -> PPTokenClaims {
  PPTokenClaims(
    role: role,
    isAdmin: admin,
    isSuperAdmin: superAdmin,
    isBlocked: blocked,
    issuedAt: now,
    expiresAt: now.addingTimeInterval(3_600)
  )
}

func activeRemoteState(
  name: String = "Pure Pets",
  features: PPDocument = ["canUseChat": .bool(true)],
  restrictions: PPDocument = [:],
  permissions: [String: Bool] = [:],
  extra: PPDocument = [:]
) -> PPRemoteUserState {
  var profile: PPDocument = [
    "UserName": .string(name),
    "accountStatus": .string("active"),
    "features": .object(features),
    "restrictions": .object(restrictions),
  ]
  profile.merge(extra) { _, new in new }
  return PPRemoteUserState(profile: profile, permissions: permissions)
}

actor TestAuthSource: PPAuthSource {
  private let stream: AsyncStream<PPAuthUser?>
  private let continuation: AsyncStream<PPAuthUser?>.Continuation
  private var tokens: [PPUserID: PPTokenClaims] = [:]
  private var delays: [PPUserID: Duration] = [:]

  init() {
    let pair = AsyncStream<PPAuthUser?>.makeStream(bufferingPolicy: .bufferingNewest(20))
    stream = pair.stream
    continuation = pair.continuation
  }

  func events() -> AsyncStream<PPAuthUser?> { stream }

  func token(for userID: PPUserID, forceRefresh: Bool) async throws -> PPTokenClaims {
    if let delay = delays[userID] {
      try await Task.sleep(for: delay)
    }
    guard let token = tokens[userID] else {
      throw PPUserRepositoryFailure(code: .token, message: "Missing token")
    }
    return token
  }

  func setToken(_ token: PPTokenClaims, for userID: PPUserID, delay: Duration = .zero) {
    tokens[userID] = token
    delays[userID] = delay
  }

  func emit(_ user: PPAuthUser?) {
    continuation.yield(user)
  }
}

actor TestUserStore: PPUserStore {
  private struct Channel {
    let stream: AsyncThrowingStream<PPRemoteUserState, Error>
    let continuation: AsyncThrowingStream<PPRemoteUserState, Error>.Continuation
  }

  private var channels: [PPUserID: Channel] = [:]
  private var latest: [PPUserID: PPRemoteUserState] = [:]
  private(set) var updates: [(PPUserID, PPUserProfilePatch)] = []

  func states(for userID: PPUserID) -> AsyncThrowingStream<PPRemoteUserState, Error> {
    let channel = channel(for: userID)
    if let latest = latest[userID] {
      channel.continuation.yield(latest)
    }
    return channel.stream
  }

  func fetchState(for userID: PPUserID) async throws -> PPRemoteUserState {
    guard let latest = latest[userID] else {
      throw PPUserRepositoryFailure(code: .profile, message: "Missing remote state")
    }
    return latest
  }

  func updateProfile(for userID: PPUserID, patch: PPUserProfilePatch) {
    updates.append((userID, patch))
  }

  func setState(_ state: PPRemoteUserState, for userID: PPUserID) {
    latest[userID] = state
    channel(for: userID).continuation.yield(state)
  }

  private func channel(for userID: PPUserID) -> Channel {
    if let existing = channels[userID] { return existing }
    let pair = AsyncThrowingStream<PPRemoteUserState, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(20))
    let value = Channel(stream: pair.stream, continuation: pair.continuation)
    channels[userID] = value
    return value
  }
}
