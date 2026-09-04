import Foundation

public struct PPCurrentUserSnapshot: Codable, Equatable, Sendable {
  public let user: PPUser
  public let access: PPUserAccess
  public let profile: PPDocument

  public init(user: PPUser, access: PPUserAccess, profile: PPDocument = [:]) {
    self.user = user
    self.access = access
    self.profile = profile
  }

  public func cachedCopy(at date: Date = .now) -> Self {
    Self(user: user, access: access.cachedCopy(at: date), profile: profile)
  }
}

public struct PPUserRepositoryFailure: Error, Codable, Equatable, Sendable {
  public enum Code: String, Codable, Sendable {
    case authentication
    case token
    case profile
    case permissions
    case staleOperation
    case persistence
    case unknown
  }

  public let code: Code
  public let message: String

  public init(code: Code, message: String) {
    self.code = code
    self.message = message
  }
}

public enum PPUserRepositoryEvent: Equatable, Sendable {
  case signedOut
  case updated(PPCurrentUserSnapshot)
  case failed(PPUserRepositoryFailure)
}

public protocol PPUserRepository: Sendable {
  func events() -> AsyncStream<PPUserRepositoryEvent>
  func refresh(forceTokenRefresh: Bool) async throws -> PPCurrentUserSnapshot?
  func updateProfile(_ patch: PPUserProfilePatch) async throws
}

public struct PPAuthUser: Equatable, Sendable {
  public let id: PPUserID
  public let email: String?
  public let displayName: String?
  public let photoURL: URL?

  public init(id: PPUserID, email: String? = nil, displayName: String? = nil, photoURL: URL? = nil)
  {
    self.id = id
    self.email = email?.ppNilIfBlank
    self.displayName = displayName?.ppNilIfBlank
    self.photoURL = photoURL
  }
}

public struct PPTokenClaims: Equatable, Sendable {
  public let role: PPUserRole
  public let isAdmin: Bool
  public let isSuperAdmin: Bool
  public let isBlocked: Bool
  public let issuedAt: Date
  public let expiresAt: Date

  public init(
    role: PPUserRole = .user,
    isAdmin: Bool = false,
    isSuperAdmin: Bool = false,
    isBlocked: Bool = false,
    issuedAt: Date,
    expiresAt: Date
  ) {
    self.role = role
    self.isAdmin = isAdmin || isSuperAdmin || role == .admin || role == .superAdmin
    self.isSuperAdmin = isSuperAdmin || role == .superAdmin
    self.isBlocked = isBlocked
    self.issuedAt = issuedAt
    self.expiresAt = expiresAt
  }
}

public struct PPRemoteUserState: Equatable, Sendable {
  public let profile: PPDocument
  public let permissions: [String: Bool]

  public init(profile: PPDocument, permissions: [String: Bool]) {
    self.profile = profile
    self.permissions = permissions
  }
}

public protocol PPAuthSource: Sendable {
  func events() async -> AsyncStream<PPAuthUser?>
  func token(for userID: PPUserID, forceRefresh: Bool) async throws -> PPTokenClaims
}

public protocol PPUserStore: Sendable {
  func states(for userID: PPUserID) async -> AsyncThrowingStream<PPRemoteUserState, Error>
  func fetchState(for userID: PPUserID) async throws -> PPRemoteUserState
  func updateProfile(for userID: PPUserID, patch: PPUserProfilePatch) async throws
}

public protocol PPUserCache: Sendable {
  func load(for userID: PPUserID) async throws -> PPCurrentUserSnapshot?
  func save(_ snapshot: PPCurrentUserSnapshot) async throws
  func remove(for userID: PPUserID) async throws
}
