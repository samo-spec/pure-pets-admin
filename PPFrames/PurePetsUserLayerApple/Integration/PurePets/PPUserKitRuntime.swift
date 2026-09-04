import Foundation
import PurePetsUserKit

@available(iOS 15.0, *)
@MainActor
@objcMembers
public final class PPUserKitRuntime: NSObject {
  public static let shared = PPUserKitRuntime()
  public static let didChangeNotification = Notification.Name("PPUserKitRuntimeDidChangeNotification")

  public private(set) var lastError: NSError?
  public private(set) var isStarted = false
  public private(set) var currentUserID: String?
  @nonobjc public private(set) var currentSnapshot: PPCurrentUserSnapshot?

  private var session: PPUserSession?
  private var stateTask: Task<Void, Never>?
  private var projection: PPUserKitUserModel?

  private override init() {
    super.init()
  }

  deinit {
    stateTask?.cancel()
  }

  public func start() {
    do {
      let session = try ensureSession()
      guard !isStarted else { return }
      isStarted = true
      session.start()
      let states = session.states()
      stateTask = Task { @MainActor [weak self] in
        for await state in states {
          guard let self, !Task.isCancelled else { return }
          self.consume(state)
        }
      }
    } catch {
      lastError = error as NSError
      NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
  }

  public func stop() {
    stateTask?.cancel()
    stateTask = nil
    session?.stop()
    isStarted = false
    projection = nil
    currentUserID = nil
    lastError = nil
    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
  }

  public func refresh(completion: @escaping (NSError?) -> Void) {
    do {
      let session = try ensureSession()
      start()
      Task { @MainActor [weak self, session] in
        await session.refresh(forceTokenRefresh: true)
        guard let self else { return }
        self.consume(session.state)
        let error = self.error(from: session.state)
        completion(error)
      }
    } catch {
      let nsError = error as NSError
      lastError = nsError
      completion(nsError)
    }
  }

  public func currentUserModel() -> PPUserKitUserModel? {
    projection
  }

  public func loadCurrentUserModel(
    completion: @escaping (PPUserKitUserModel?, NSError?) -> Void
  ) {
    start()
    if let projection, currentUserID != nil {
      completion(projection, nil)
      return
    }
    refresh { [weak self] error in
      completion(self?.projection, error)
    }
  }

  public func isCurrentUser(id: String) -> Bool {
    currentUserID == id && projection != nil
  }

  @nonobjc public func updateProfile(
    _ patch: PPUserProfilePatch,
    completion: ((NSError?) -> Void)? = nil
  ) {
    do {
      let session = try ensureSession()
      start()
      Task { @MainActor [weak self, session] in
        do {
          try await session.updateProfile(patch)
          completion?(nil)
        } catch {
          completion?(error as NSError)
        }
        self?.consume(session.state)
      }
    } catch {
      completion?(error as NSError)
    }
  }

  public func updateProfileValues(
    _ values: NSDictionary,
    completion: @escaping (NSError?) -> Void
  ) {
    let patch = PPUserProfilePatch(
      username: field(values, keys: ["UserName", "username", "displayName"]),
      firstName: field(values, keys: ["FirstName", "firstName"]),
      lastName: field(values, keys: ["LastName", "lastName"]),
      phoneNumber: field(values, keys: ["MobileNo", "phoneNumber", "mobile"]),
      about: field(values, keys: ["UserAbout", "about", "bio"]),
      avatarURL: urlField(values, keys: ["UserImageUrl", "photoURL", "avatarURL"]),
      countryID: number(values, keys: ["CountryID", "countryID"])
    )
    updateProfile(patch, completion: completion)
  }

  public func loadCachedUserModel(
    for uid: String,
    completion: @escaping (PPUserKitUserModel?, NSError?) -> Void
  ) {
    Task { @MainActor in
      do {
        guard let userID = PPUserID(uid) else {
          throw NSError(
            domain: "PPUserKit",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: "A valid user ID is required."]
          )
        }
        let cache = try PPFileUserCache()
        let snapshot = try await cache.load(for: userID)
        let model = snapshot.map { value -> PPUserKitUserModel in
          let result = PPUserKitUserModel()
          result.apply(snapshot: value)
          return result
        }
        completion(model, nil)
      } catch {
        completion(nil, error as NSError)
      }
    }
  }

  public func loadCachedUserModelSynchronously(for uid: String) -> PPUserKitUserModel? {
    guard let userID = PPUserID(uid),
      let data = try? Data(contentsOf: cachedFileURL(for: userID))
    else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    guard let snapshot = try? decoder.decode(PPCurrentUserSnapshot.self, from: data) else {
      return nil
    }
    let model = PPUserKitUserModel()
    model.apply(snapshot: snapshot.cachedCopy())
    return model
  }

  public func removeCachedUser(for uid: String, completion: ((NSError?) -> Void)? = nil) {
    Task { @MainActor in
      do {
        guard let userID = PPUserID(uid) else {
          throw NSError(
            domain: "PPUserKit",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: "A valid user ID is required."]
          )
        }
        let cache = try PPFileUserCache()
        try await cache.remove(for: userID)
        completion?(nil)
      } catch {
        completion?(error as NSError)
      }
    }
  }

  private func ensureSession() throws -> PPUserSession {
    if let session { return session }
    do {
      let session = try PPPurePetsUserLayer.makeSession()
      self.session = session
      return session
    } catch {
      lastError = error as NSError
      throw error
    }
  }

  private func consume(_ state: PPUserSessionState) {
    let snapshot = state.snapshot
    currentSnapshot = snapshot
    currentUserID = snapshot?.user.id.rawValue
    if let snapshot {
      if let projection {
        projection.apply(snapshot: snapshot)
      } else {
        let model = PPUserKitUserModel()
        model.apply(snapshot: snapshot)
        projection = model
      }
    } else {
      projection = nil
    }
    if case .failed(let failure, _) = state {
      lastError = NSError(
        domain: "PPUserKit",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: failure.message,
          "failureCode": failure.code.rawValue,
        ]
      )
    } else {
      lastError = nil
    }
    NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
  }

  private func error(from state: PPUserSessionState) -> NSError? {
    guard case .failed(let failure, _) = state else { return nil }
    return NSError(
      domain: "PPUserKit",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: failure.message, "failureCode": failure.code.rawValue]
    )
  }

  private func field(_ values: NSDictionary, keys: [String]) -> PPFieldUpdate<String> {
    for key in keys {
      if let value = values[key] as? String {
        return value.isEmpty ? .remove : .set(value)
      }
    }
    return .unchanged
  }

  private func urlField(_ values: NSDictionary, keys: [String]) -> PPFieldUpdate<URL> {
    for key in keys {
      if let value = values[key] as? String, let url = URL(string: value) {
        return .set(url)
      }
    }
    return .unchanged
  }

  private func number(_ values: NSDictionary, keys: [String]) -> PPFieldUpdate<Int> {
    for key in keys {
      if let value = values[key] as? NSNumber { return .set(value.intValue) }
      if let value = values[key] as? String, let int = Int(value) { return .set(int) }
    }
    return .unchanged
  }

  private func cachedFileURL(for userID: PPUserID) -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let directory = base.appendingPathComponent("PurePets/UserCache", isDirectory: true)
    let key = Data(userID.rawValue.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
    return directory.appendingPathComponent("\(key).json", isDirectory: false)
  }
}
