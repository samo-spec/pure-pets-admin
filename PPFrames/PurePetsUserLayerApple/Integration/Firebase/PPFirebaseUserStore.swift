#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
  import Foundation
  import FirebaseAuth
  import FirebaseFirestore
  import PurePetsUserKit

  public struct PPFirebaseUserStoreConfiguration: Sendable {
    public let usersCollection: String
    /// Ordered from lowest to highest precedence. The last collection is canonical.
    public let permissionCollections: [String]

    public init(usersCollection: String, permissionCollections: [String]) {
      precondition(!usersCollection.isEmpty)
      precondition(!permissionCollections.isEmpty)
      self.usersCollection = usersCollection
      self.permissionCollections = permissionCollections
    }
  }

  public final class PPFirebaseUserStore: PPUserStore, @unchecked Sendable {
    private let auth: Auth
    private let firestore: Firestore
    private let configuration: PPFirebaseUserStoreConfiguration

    public init(
      auth: Auth = .auth(),
      firestore: Firestore = .firestore(),
      configuration: PPFirebaseUserStoreConfiguration
    ) {
      self.auth = auth
      self.firestore = firestore
      self.configuration = configuration
    }

    public func states(for userID: PPUserID) async -> AsyncThrowingStream<PPRemoteUserState, Error>
    {
      let reference = userReference(for: userID)
      return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
        let accumulator = PPFirebaseUserStateAccumulator(
          permissionLayerCount: configuration.permissionCollections.count,
          continuation: continuation
        )
        let listeners = PPFirebaseListenerBag()

        listeners.append(
          reference.addSnapshotListener { snapshot, error in
            if let error {
              Task { await accumulator.fail(error) }
              return
            }
            let profile = PPFirebaseDocumentConverter.document(from: snapshot?.data() ?? [:])
            Task { await accumulator.updateProfile(profile) }
          })

        for (index, name) in configuration.permissionCollections.enumerated() {
          listeners.append(
            reference.collection(name).addSnapshotListener { snapshot, error in
              if let error {
                Task {
                  await accumulator.updatePermissionLayer(
                    index: index, permissions: [:], error: error)
                }
                return
              }
              let permissions = Self.decodePermissions(snapshot?.documents ?? [])
              Task {
                await accumulator.updatePermissionLayer(
                  index: index, permissions: permissions, error: nil)
              }
            })
        }

        continuation.onTermination = { _ in listeners.removeAll() }
      }
    }

    public func fetchState(for userID: PPUserID) async throws -> PPRemoteUserState {
      let reference = userReference(for: userID)
      let profileSnapshot = try await getDocument(reference)
      var merged: [String: Bool] = [:]

      for (index, name) in configuration.permissionCollections.enumerated() {
        do {
          let snapshot = try await getDocuments(reference.collection(name))
          merged.merge(Self.decodePermissions(snapshot.documents)) { _, higherPriority in
            higherPriority
          }
        } catch {
          let isCanonical = index == configuration.permissionCollections.count - 1
          if isCanonical { throw error }
        }
      }

      return PPRemoteUserState(
        profile: PPFirebaseDocumentConverter.document(from: profileSnapshot.data() ?? [:]),
        permissions: merged
      )
    }

    public func updateProfile(for userID: PPUserID, patch: PPUserProfilePatch) async throws {
      guard auth.currentUser?.uid == userID.rawValue else {
        throw PPUserRepositoryFailure(
          code: .authentication,
          message: "A profile can only be updated by its authenticated owner."
        )
      }

      var payload = Self.payload(from: patch)
      guard !payload.isEmpty else { return }
      payload["updatedAt"] = FieldValue.serverTimestamp()

      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        userReference(for: userID).setData(payload, merge: true) { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }
    }

    private func userReference(for userID: PPUserID) -> DocumentReference {
      firestore.collection(configuration.usersCollection).document(userID.rawValue)
    }

    private func getDocument(_ reference: DocumentReference) async throws -> DocumentSnapshot {
      try await withCheckedThrowingContinuation { continuation in
        reference.getDocument { snapshot, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let snapshot {
            continuation.resume(returning: snapshot)
          } else {
            continuation.resume(
              throwing: PPUserRepositoryFailure(
                code: .profile, message: "Missing profile snapshot."))
          }
        }
      }
    }

    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
      try await withCheckedThrowingContinuation { continuation in
        query.getDocuments { snapshot, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let snapshot {
            continuation.resume(returning: snapshot)
          } else {
            continuation.resume(
              throwing: PPUserRepositoryFailure(
                code: .permissions, message: "Missing permissions snapshot."))
          }
        }
      }
    }

    private static func decodePermissions(_ documents: [QueryDocumentSnapshot]) -> [String: Bool] {
      var result: [String: Bool] = [:]
      for document in documents {
        let data = document.data()
        let documentKey = canonicalPermissionName(document.documentID)
        if let allowed = boolValue(data["allowed"] ?? data["enabled"] ?? data["value"]) {
          if documentKey.isEmpty == false {
            result[documentKey] = allowed
          }
        }
        for (key, value) in data where key != "allowed" && key != "enabled" && key != "value" {
          let permissionKey = canonicalPermissionName(key)
          if let allowed = boolValue(value), permissionKey.isEmpty == false {
            result[permissionKey] = allowed
          }
        }
      }
      return result
    }

    private static func canonicalPermissionName(_ rawName: String) -> String {
      let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
      switch name {
      case "ManageUsers": return "Adoption"
      case "ManageNotificatiuons", "ManageNotifications": return "Moderation"
      case "ManageBanners": return "PostAds"
      case "Prodection": return "production"
      default: return name
      }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
      if let value = value as? Bool { return value }
      if let value = value as? NSNumber { return value.boolValue }
      if let value = value as? String {
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
      }
      return nil
    }

    private static func payload(from patch: PPUserProfilePatch) -> [String: Any] {
      var payload: [String: Any] = [:]
      apply(patch.username, key: "UserName", to: &payload)
      apply(patch.firstName, key: "FirstName", to: &payload)
      apply(patch.lastName, key: "LastName", to: &payload)
      apply(patch.phoneNumber, key: "MobileNo", to: &payload)
      apply(patch.about, key: "UserAbout", to: &payload)
      apply(patch.avatarURL, key: "UserImageUrl", transform: \.absoluteString, to: &payload)
      apply(patch.countryID, key: "CountryID", to: &payload)
      apply(
        patch.coverImageURLs, key: "coverImageUrls", transform: { $0.map(\.absoluteString) },
        to: &payload)
      return payload
    }

    private static func apply<Value>(
      _ update: PPFieldUpdate<Value>,
      key: String,
      transform: (Value) -> Any = { $0 },
      to payload: inout [String: Any]
    ) {
      switch update {
      case .unchanged: break
      case .set(let value): payload[key] = transform(value)
      case .remove: payload[key] = FieldValue.delete()
      }
    }
  }

  private actor PPFirebaseUserStateAccumulator {
    private let permissionLayerCount: Int
    private let continuation: AsyncThrowingStream<PPRemoteUserState, Error>.Continuation
    private var profile: PPDocument?
    private var layers: [Int: [String: Bool]] = [:]
    private var initializedLayers: Set<Int> = []
    private var finished = false

    init(
      permissionLayerCount: Int,
      continuation: AsyncThrowingStream<PPRemoteUserState, Error>.Continuation
    ) {
      self.permissionLayerCount = permissionLayerCount
      self.continuation = continuation
    }

    func updateProfile(_ profile: PPDocument) {
      guard !finished else { return }
      self.profile = profile
      emitIfReady()
    }

    func updatePermissionLayer(index: Int, permissions: [String: Bool], error: Error?) {
      guard !finished else { return }
      let isCanonical = index == permissionLayerCount - 1
      if let error, isCanonical {
        fail(error)
        return
      }
      layers[index] = permissions
      initializedLayers.insert(index)
      emitIfReady()
    }

    func fail(_ error: Error) {
      guard !finished else { return }
      finished = true
      continuation.finish(throwing: error)
    }

    private func emitIfReady() {
      guard let profile, initializedLayers.count == permissionLayerCount else { return }
      var permissions: [String: Bool] = [:]
      for index in 0..<permissionLayerCount {
        permissions.merge(layers[index] ?? [:]) { _, higherPriority in higherPriority }
      }
      continuation.yield(.init(profile: profile, permissions: permissions))
    }
  }

  private final class PPFirebaseListenerBag: @unchecked Sendable {
    private let lock = NSLock()
    private var listeners: [ListenerRegistration] = []

    func append(_ listener: ListenerRegistration) {
      lock.lock()
      listeners.append(listener)
      lock.unlock()
    }

    func removeAll() {
      lock.lock()
      let current = listeners
      listeners.removeAll()
      lock.unlock()
      for listener in current {
        listener.remove()
      }
    }
  }
#endif
