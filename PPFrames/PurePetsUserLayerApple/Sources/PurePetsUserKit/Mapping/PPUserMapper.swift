import Foundation

public struct PPPermissionCatalog: Equatable, Sendable {
  public let postPetAd: String
  public let postAdoption: String
  public let sellAccessories: String
  public let accessPartnerApp: String
  public let manageDelivery: String
  public let manageServiceProvider: String
  public let manageVet: String
  public let postVetProfile: String
  public let editVetInfo: String
  public let managePetMedicines: String

  public init(
    postPetAd: String,
    postAdoption: String,
    sellAccessories: String,
    accessPartnerApp: String = "canAccessPartnerApp",
    manageDelivery: String = "canManageDelivery",
    manageServiceProvider: String = "canManageServiceProvider",
    manageVet: String = "canManageVet",
    postVetProfile: String = "canPostVetProfile",
    editVetInfo: String = "canEditVetInfo",
    managePetMedicines: String = "canManagePetMedicines"
  ) {
    self.postPetAd = postPetAd
    self.postAdoption = postAdoption
    self.sellAccessories = sellAccessories
    self.accessPartnerApp = accessPartnerApp
    self.manageDelivery = manageDelivery
    self.manageServiceProvider = manageServiceProvider
    self.manageVet = manageVet
    self.postVetProfile = postVetProfile
    self.editVetInfo = editVetInfo
    self.managePetMedicines = managePetMedicines
  }
}

public struct PPUserMapper: Sendable {
  public let permissionCatalog: PPPermissionCatalog

  public init(permissionCatalog: PPPermissionCatalog) {
    self.permissionCatalog = permissionCatalog
  }

  public func map(
    authUser: PPAuthUser,
    remote: PPRemoteUserState,
    token: PPTokenClaims,
    fetchedAt: Date
  ) -> PPCurrentUserSnapshot {
    let profile = remote.profile
    let user = PPUser(
      id: authUser.id,
      username: authUser.displayName ?? profile.ppString(["UserName", "displayName", "username"]),
      email: authUser.email ?? profile.ppString(["UserEmail", "email"]),
      name: .init(
        first: profile.ppString(["FirstName", "firstName"]),
        last: profile.ppString(["LastName", "lastName"])
      ),
      phoneNumber: profile.ppString(["MobileNo", "phoneNumber", "mobile"]),
      about: profile.ppString(["UserAbout", "about", "bio"]),
      avatarURL: authUser.photoURL
        ?? profile.ppString([
          "UserImageUrl", "UserImageURL", "photoURL", "photoUrl", "avatarURL", "avatarUrl",
          "avatar", "userImageUrl", "userImageURL", "profileImageUrl", "profileImageURL",
          "photo", "picture", "image",
        ]).flatMap(URL.init(string:)),
      presence: mapPresence(profile),
      countryID: profile.ppInt(["CountryID", "countryID"]),
      reputation: mapReputation(profile),
      coverImageURLs: mapCoverURLs(profile),
      createdAt: profile.ppDate(["createdAt", "loginDate"]),
      updatedAt: profile.ppDate(["updatedAt"])
    )

    let access = mapAccess(
      profile: profile, permissions: remote.permissions, token: token, fetchedAt: fetchedAt)
    return PPCurrentUserSnapshot(user: user, access: access, profile: profile)
  }

  private func mapPresence(_ profile: PPDocument) -> PPUser.Presence {
    let status: PPUser.Presence.Status
    if let rawStatus = profile.ppInt(["onlineStatus"]) {
      status = rawStatus == 1 ? .online : .offline
    } else if let online = profile.ppBool(["isOnline", "online"]) {
      status = online ? .online : .offline
    } else if let raw = profile.ppString(["onlineStatus"])?.lowercased() {
      status = raw == "online" || raw == "1" ? .online : .offline
    } else {
      status = .unknown
    }
    return .init(status: status, lastSeenAt: profile.ppDate(["lastSeen"]))
  }

  private func mapReputation(_ profile: PPDocument) -> PPUser.Reputation? {
    let rating = profile.ppDouble(["providerRatingValue", "providerRating"])
    let count = profile.ppInt(["providerReviewCount", "reviewCount"])
    guard rating != nil || count != nil else { return nil }
    return .init(rating: rating ?? 0, reviewCount: count ?? 0)
  }

  private func mapCoverURLs(_ profile: PPDocument) -> [URL] {
    profile["coverImageUrls"]?.arrayValue?
      .compactMap(\.stringValue)
      .compactMap(URL.init(string:)) ?? []
  }

  private func mapAccess(
    profile: PPDocument,
    permissions: [String: Bool],
    token: PPTokenClaims,
    fetchedAt: Date
  ) -> PPUserAccess {
    let featureDocument = profile.ppObject("features")
    let restrictionDocument = profile.ppObject("restrictions")
    let subscriptionDocument = profile.ppObject("subscription")

    var features: [String: Bool] = [
      "canPostPetAds": true,
      "canPostAdoption": true,
      "canSellAccessories": false,
      "canOfferServices": false,
      "canDelivery": false,
      "canPharmacy": false,
      "canVet": false,
      "canUseStories": true,
      "canUseChat": true,
      "canAccessPremiumMarketplace": false,
      "canAccessProviderMarketplace": false,
    ]
    features.merge(featureDocument.compactMapValues(\.boolValue)) { _, current in current }
    applyFeatureAlias(
      "canOfferServices", aliases: ["service_provider", "serviceProvider"],
      document: featureDocument, to: &features)
    applyFeatureAlias(
      "canDelivery", aliases: ["delivery"], document: featureDocument, to: &features)
    applyFeatureAlias(
      "canPharmacy", aliases: ["pharmacy"], document: featureDocument, to: &features)
    applyFeatureAlias("canVet", aliases: ["vet"], document: featureDocument, to: &features)

    if features["canPharmacy"] == nil, let value = profile.ppBool(["canPharmacy"]) {
      features["canPharmacy"] = value
    }

    var restrictions = restrictionDocument.compactMapValues(\.boolValue)
    let canonicalChatFeatureExists = features["canUseChat"] != nil
    let canonicalChatRestrictionExists = restrictions["chatBlocked"] != nil
    let legacyChat = profile.ppBool(["canReceiveMessages", "isChatEnabled"])

    if !canonicalChatFeatureExists, let legacyChat {
      features["canUseChat"] = legacyChat
    }
    if !canonicalChatRestrictionExists, let legacyChat {
      restrictions["chatBlocked"] = !legacyChat
    }

    let accountStatus =
      PPUserAccountStatus(
        rawValue: profile.ppString(["accountStatus"])?.lowercased() ?? "unknown"
      ) ?? .unknown
    let rootBlocked = profile.ppBool(["isBlocked", "blocked"]) ?? false
    let blocked =
      token.isBlocked || rootBlocked || accountStatus == .blocked || accountStatus == .disabled

    let grantedPermissions = Set(
      permissions.compactMap { key, value in value ? key : nil }
    )

    var rules: [PPUserCapability: PPUserCapabilityRule] = [:]
    rules[.postPetAd] = featureAndPermissionRule(
      feature: features["canPostPetAds"] ?? false,
      permission: permissionCatalog.postPetAd,
      permissions: permissions,
      restricted: restrictions["postingBlocked"] ?? false
    )
    rules[.postAdoption] = featureAndPermissionRule(
      feature: features["canPostAdoption"] ?? false,
      permission: permissionCatalog.postAdoption,
      permissions: permissions,
      restricted: restrictions["postingBlocked"] ?? false
    )
    rules[.sellAccessories] = featureAndPermissionRule(
      feature: features["canSellAccessories"] ?? false,
      permission: permissionCatalog.sellAccessories,
      permissions: permissions,
      restricted: restrictions["postingBlocked"] ?? false
    )
    rules[.useStories] = featureRule(features["canUseStories"] ?? false)
    rules[.useChat] = restrictedRule(
      allowed: features["canUseChat"] ?? false,
      restricted: restrictions["chatBlocked"] ?? false
    )
    rules[.purchase] = restrictionOnlyRule(restrictions["purchaseBlocked"] ?? false)
    rules[.withdraw] = restrictionOnlyRule(restrictions["withdrawalBlocked"] ?? false)
    rules[.accessPremiumMarketplace] = featureRule(features["canAccessPremiumMarketplace"] ?? false)
    rules[.accessProviderMarketplace] = featureRule(
      features["canAccessProviderMarketplace"] ?? false)

    let deliveryFallback = resolvePermission(
      permissions, key: permissionCatalog.manageDelivery, fallback: features["canDelivery"] ?? false
    )
    let serviceFallback = resolvePermission(
      permissions, key: permissionCatalog.manageServiceProvider,
      fallback: features["canOfferServices"] ?? false)
    let vetFallback = resolvePermission(
      permissions, key: permissionCatalog.manageVet, fallback: features["canVet"] ?? false)
    let pharmacyFallback = features["canPharmacy"] ?? false
    let providerMarketplaceFallback = features["canAccessProviderMarketplace"] ?? false

    rules[.manageDelivery] = permissionRule(
      permissions, key: permissionCatalog.manageDelivery, fallback: features["canDelivery"] ?? false
    )
    rules[.manageServiceProvider] = permissionRule(
      permissions, key: permissionCatalog.manageServiceProvider,
      fallback: features["canOfferServices"] ?? false)
    rules[.manageVet] = permissionRule(
      permissions, key: permissionCatalog.manageVet, fallback: features["canVet"] ?? false)
    rules[.postVetProfile] = permissionRule(
      permissions, key: permissionCatalog.postVetProfile, fallback: vetFallback)
    rules[.editVetInfo] = permissionRule(
      permissions, key: permissionCatalog.editVetInfo, fallback: vetFallback)
    rules[.managePetMedicines] = permissionRule(
      permissions, key: permissionCatalog.managePetMedicines, fallback: pharmacyFallback)
    rules[.accessPartnerApp] = permissionRule(
      permissions,
      key: permissionCatalog.accessPartnerApp,
      fallback: deliveryFallback || serviceFallback || vetFallback || pharmacyFallback
        || providerMarketplaceFallback
    )

    return PPUserAccess(
      role: token.role,
      isAdmin: token.isAdmin,
      isSuperAdmin: token.isSuperAdmin,
      isBlocked: blocked,
      accountStatus: accountStatus,
      protectionStatus: profile.ppString(["prodectionStatus", "protectionStatus"])?.lowercased()
        ?? "inactive",
      subscription: .init(
        plan: subscriptionDocument.ppString(["plan"]) ?? "free",
        status: subscriptionDocument.ppString(["status"]) ?? "inactive",
        source: subscriptionDocument.ppString(["source"]) ?? "unknown"
      ),
      featureFlags: features,
      restrictions: restrictions,
      permissionValues: permissions,
      permissions: grantedPermissions,
      trust: .verified,
      fetchedAt: fetchedAt,
      expiresAt: token.expiresAt,
      rules: rules
    )
  }

  private func applyFeatureAlias(
    _ canonical: String,
    aliases: [String],
    document: PPDocument,
    to features: inout [String: Bool]
  ) {
    guard features[canonical] == nil else { return }
    features[canonical] = document.ppBool(aliases)
  }

  private func featureRule(_ enabled: Bool) -> PPUserCapabilityRule {
    enabled ? .allowed : .featureDisabled
  }

  private func restrictionOnlyRule(_ restricted: Bool) -> PPUserCapabilityRule {
    restricted ? .explicitlyRestricted : .allowed
  }

  private func restrictedRule(allowed: Bool, restricted: Bool) -> PPUserCapabilityRule {
    if restricted { return .explicitlyRestricted }
    return allowed ? .allowed : .featureDisabled
  }

  private func featureAndPermissionRule(
    feature: Bool,
    permission: String,
    permissions: [String: Bool],
    restricted: Bool
  ) -> PPUserCapabilityRule {
    if restricted { return .explicitlyRestricted }
    if !feature { return .featureDisabled }
    return permissionRule(permissions, key: permission, fallback: false)
  }

  private func permissionRule(_ permissions: [String: Bool], key: String, fallback: Bool)
    -> PPUserCapabilityRule
  {
    resolvePermission(permissions, key: key, fallback: fallback) ? .allowed : .permissionMissing
  }

  private func resolvePermission(_ permissions: [String: Bool], key: String, fallback: Bool) -> Bool
  {
    if let explicit = permissions[key] { return explicit }
    return fallback
  }
}
