import Foundation

public typealias AuthStateDidChangeListenerHandle = NSObjectProtocol
public final class Auth: @unchecked Sendable {
  public static func auth() -> Auth { Auth() }
  public var currentUser: User?
  public func addIDTokenDidChangeListener(_ listener: @escaping @Sendable (Auth, User?) -> Void)
    -> AuthStateDidChangeListenerHandle
  { NSObject() }
  public func removeIDTokenDidChangeListener(_ handle: AuthStateDidChangeListenerHandle) {}
}
public final class User: @unchecked Sendable {
  public var uid: String = ""
  public var email: String?
  public var displayName: String?
  public var photoURL: URL?
  public func getIDTokenResult(
    forcingRefresh: Bool, completion: @escaping @Sendable (AuthTokenResult?, Error?) -> Void
  ) {}
}
public final class AuthTokenResult: @unchecked Sendable {
  public var claims: [String: Any] = [:]
  public var issuedAtDate: Date = .now
  public var expirationDate: Date = .now
}
