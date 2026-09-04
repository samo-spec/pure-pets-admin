#if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
  import FirebaseAuth
  import FirebaseFirestore
  import PurePetsUserKit

  @available(iOS 15.0, *)
  @MainActor
  enum PPPurePetsUserLayer {
    static func makeSession() throws -> PPUserSession {
      let permissionCatalog = PPPermissionCatalog(
        postPetAd: "PostAds",
        postAdoption: "Adoption",
        sellAccessories: "SellNew"
      )

      return try PPFirebaseUserLayerAssembly.makeSession(
        usersCollection: "UsersCol",
        permissionCollections: [
          "PermisstionsCol",
          "PermissionsCol",
          "permissions",
        ],
        permissionCatalog: permissionCatalog
      )
    }
  }
#endif
