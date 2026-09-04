#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
  import FirebaseAuth
  import FirebaseFirestore
  import PurePetsUserKit

  @available(iOS 15.0, *)
  @MainActor
  public enum PPFirebaseUserLayerAssembly {
    public static func makeSession(
      usersCollection: String,
      permissionCollections: [String],
      permissionCatalog: PPPermissionCatalog,
      auth: Auth = .auth(),
      firestore: Firestore = .firestore()
    ) throws -> PPUserSession {
      let authSource = PPFirebaseAuthSource(auth: auth)
      let store = PPFirebaseUserStore(
        auth: auth,
        firestore: firestore,
        configuration: .init(
          usersCollection: usersCollection,
          permissionCollections: permissionCollections
        )
      )
      let cache = try PPFileUserCache()
      let repository = PPRemoteUserRepository(
        auth: authSource,
        store: store,
        cache: cache,
        mapper: PPUserMapper(permissionCatalog: permissionCatalog)
      )
      return PPUserSession(repository: repository)
    }
  }
#endif
