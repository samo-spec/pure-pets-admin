#if canImport(FirebaseAuth)
  import Foundation
  import FirebaseAuth
  import PurePetsUserKit

  public final class PPFirebaseAuthSource: PPAuthSource, @unchecked Sendable {
    private let auth: Auth

    public init(auth: Auth = .auth()) {
      self.auth = auth
    }

    public func events() async -> AsyncStream<PPAuthUser?> {
      AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let handle = auth.addIDTokenDidChangeListener { _, user in
          continuation.yield(user.flatMap(Self.mapUser))
        }
        let cancellation = PPFirebaseAuthCancellation { [auth] in
          auth.removeIDTokenDidChangeListener(handle)
        }
        continuation.onTermination = { _ in cancellation.cancel() }
      }
    }

    public func token(for userID: PPUserID, forceRefresh: Bool) async throws -> PPTokenClaims {
      guard let user = auth.currentUser, user.uid == userID.rawValue else {
        throw PPUserRepositoryFailure(
          code: .authentication,
          message: "The authenticated Firebase user changed before token verification."
        )
      }

      let result: AuthTokenResult = try await withCheckedThrowingContinuation { continuation in
        user.getIDTokenResult(forcingRefresh: forceRefresh) { result, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let result {
            continuation.resume(returning: result)
          } else {
            continuation.resume(
              throwing: PPUserRepositoryFailure(
                code: .token,
                message: "Firebase returned no token result."
              ))
          }
        }
      }

      guard auth.currentUser?.uid == userID.rawValue else {
        throw PPUserRepositoryFailure(
          code: .staleOperation,
          message: "The authenticated Firebase user changed during token verification."
        )
      }

      let claims = result.claims
      let role = Self.role(from: claims)
      return PPTokenClaims(
        role: role,
        isAdmin: Self.bool(in: claims, keys: ["isAdmin", "admin"]) || role == .admin,
        isSuperAdmin: Self.bool(in: claims, keys: ["isSuperAdmin", "superAdmin", "superadmin"])
          || role == .superAdmin,
        isBlocked: Self.bool(in: claims, keys: ["isBlocked", "blocked"]),
        issuedAt: result.issuedAtDate,
        expiresAt: result.expirationDate
      )
    }

    private static func mapUser(_ user: FirebaseAuth.User) -> PPAuthUser? {
      guard let id = PPUserID(user.uid) else { return nil }
      return PPAuthUser(
        id: id,
        email: user.email,
        displayName: user.displayName,
        photoURL: user.photoURL
      )
    }

    private static func role(from claims: [String: Any]) -> PPUserRole {
      let raw = firstValue(in: claims, keys: ["role", "roleName", "userRole"])
      if let string = raw as? String {
        return role(from: string)
      }
      if let number = raw as? NSNumber {
        return role(from: number.stringValue)
      }
      return .user
    }

    private static func role(from raw: String) -> PPUserRole {
      switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "2", "owner": return .owner
      case "3", "vet": return .vet
      case "4", "moderator": return .moderator
      case "5", "admin": return .admin
      case "6", "storemanager", "store_manager": return .storeManager
      case "7", "foodmanager", "food_manager": return .foodManager
      case "8", "superadmin", "super_admin": return .superAdmin
      default: return PPUserRole(rawValue: raw)
      }
    }

    private static func bool(in dictionary: [String: Any], keys: [String]) -> Bool {
      guard let value = firstValue(in: dictionary, keys: keys) else { return false }
      if let value = value as? Bool { return value }
      if let value = value as? NSNumber { return value.boolValue }
      if let value = value as? String {
        return ["true", "yes", "1"].contains(value.lowercased())
      }
      return false
    }

    private static func firstValue(in dictionary: [String: Any], keys: [String]) -> Any? {
      keys.lazy.compactMap { dictionary[$0] }.first
    }
  }

  private final class PPFirebaseAuthCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (() -> Void)?

    init(action: @escaping () -> Void) {
      self.action = action
    }

    func cancel() {
      lock.lock()
      let current = action
      action = nil
      lock.unlock()
      current?()
    }
  }
#endif
