import Foundation
import FirebaseAuth
import FirebaseFirestore
import PurePetsUserKit

@objcMembers
public final class PPUserKitUserModel: NSObject, NSSecureCoding {
  public static var supportsSecureCoding: Bool { true }

  private var permissionChange: ((NSDictionary) -> Void)?
  private var permissionObserver: NSObjectProtocol?
  private var isApplyingProjection = false

  public var onlineStatus: OnlineStatus = .offline
  public var lastSeen: Date?
  public var ID: String = ""
  public var UserName: String = "" {
    didSet { queueProfilePatch(username: UserName) }
  }
  public var UserEmail: String = ""
  public var FirstName: String? {
    didSet { queueProfilePatch(firstName: FirstName) }
  }
  public var LastName: String? {
    didSet { queueProfilePatch(lastName: LastName) }
  }
  public var MobileNo: String? {
    didSet { queueProfilePatch(phoneNumber: MobileNo) }
  }
  public var UserAbout: String? {
    didSet { queueProfilePatch(about: UserAbout) }
  }
  public var UserImageName: String?
  public var UserImageUrl: URL? {
    didSet { queueProfilePatch(avatarURL: UserImageUrl) }
  }
  public var isOnline: Bool = false
  public var loginDate: Date?
  public var updatedAt: Date?
  public var CountryID: Int = 0 {
    didSet { queueProfilePatch(countryID: CountryID) }
  }
  public var PPUserTokenID: String = ""
  public var PPAdminTokenID: String = ""
  public var PPProTokenID: String = ""
  public var role: UserRole = .user
  public var isAdmin = false
  public var isSuperAdmin = false
  public var isBlocked = false
  public var accountStatus = "unknown"
  public var prodectionStatus = "inactive"
  public var canPostPetAdsFeature = false
  public var canPostAdoptionFeature = false
  public var canSellAccessoriesFeature = false
  public var canOfferServicesFeature = false
  public var canDeliveryFeature = false
  public var canPharmacyFeature = false
  public var canVetFeature = false
  public var canUseStoriesFeature = false
  public var canUseChatFeature = false
  public var canAccessPremiumMarketplaceFeature = false
  public var canAccessProviderMarketplaceFeature = false
  public var partnerOnboardingVisible = false
  public var partnerApplicationStatus = "not_started"
  public var selectedPartnerType: String?
  public var canAccessPartnerAppPermission = false
  public var canManageDeliveryPermission = false
  public var canManageServiceProviderPermission = false
  public var canManageVetPermission = false
  public var canPostVetProfilePermission = false
  public var canEditVetInfoPermission = false
  public var canManagePetMedicinesPermission = false
  public var subscriptionPlan = "free"
  public var subscriptionStatus = "active"
  public var subscriptionSource = "manual"
  public var postingBlocked = false
  public var chatBlocked = false
  public var purchaseBlocked = false
  public var withdrawalBlocked = false
  public var permissions: NSDictionary = [:]
  public var permissionsListener: AnyObject?
  public var verified = false
  public var plan: String?
  public var providerRatingValue = 0.0
  public var providerReviewCount = 0
  public var coverImageUrls: NSArray?
  public var loginSource: UserLoginSource = .unknown
  public var Addresses = NSMutableArray()
  public var SelectedInstrument: AnyObject?

  public override init() {
    super.init()
  }

  @objc(initWithDict:)
  public convenience init(dict: NSDictionary) {
    self.init()
    apply(dictionary: dict)
  }

  @objc(initWithSnapshot:)
  public convenience init(snapshot: DocumentSnapshot) {
    self.init(dict: snapshot.data() as NSDictionary? ?? [:])
  }

  public required init?(coder: NSCoder) {
    super.init()
    ID = coder.decodeObject(of: NSString.self, forKey: "ID") as String? ?? ""
    UserName = coder.decodeObject(of: NSString.self, forKey: "UserName") as String? ?? ""
    UserEmail = coder.decodeObject(of: NSString.self, forKey: "UserEmail") as String? ?? ""
    FirstName = coder.decodeObject(of: NSString.self, forKey: "FirstName") as String?
    LastName = coder.decodeObject(of: NSString.self, forKey: "LastName") as String?
    MobileNo = coder.decodeObject(of: NSString.self, forKey: "MobileNo") as String?
    UserAbout = coder.decodeObject(of: NSString.self, forKey: "UserAbout") as String?
    UserImageUrl = coder.decodeObject(of: NSURL.self, forKey: "UserImageUrl") as URL?
    CountryID = coder.decodeInteger(forKey: "CountryID")
    role = UserRole(rawValue: coder.decodeInteger(forKey: "role")) ?? .user
    isAdmin = coder.decodeBool(forKey: "isAdmin")
    isSuperAdmin = coder.decodeBool(forKey: "isSuperAdmin")
    isBlocked = coder.decodeBool(forKey: "isBlocked")
    permissions = coder.decodeObject(of: NSDictionary.self, forKey: "permissions") ?? [:]
    accountStatus = coder.decodeObject(of: NSString.self, forKey: "accountStatus") as String? ?? "unknown"
    prodectionStatus = coder.decodeObject(of: NSString.self, forKey: "prodectionStatus") as String? ?? "inactive"
    subscriptionPlan = coder.decodeObject(of: NSString.self, forKey: "subscriptionPlan") as String? ?? "free"
    subscriptionStatus = coder.decodeObject(of: NSString.self, forKey: "subscriptionStatus") as String? ?? "active"
    subscriptionSource = coder.decodeObject(of: NSString.self, forKey: "subscriptionSource") as String? ?? "manual"
    verified = coder.decodeBool(forKey: "verified")
  }

  public func encode(with coder: NSCoder) {
    coder.encode(ID, forKey: "ID")
    coder.encode(UserName, forKey: "UserName")
    coder.encode(UserEmail, forKey: "UserEmail")
    coder.encode(FirstName, forKey: "FirstName")
    coder.encode(LastName, forKey: "LastName")
    coder.encode(MobileNo, forKey: "MobileNo")
    coder.encode(UserAbout, forKey: "UserAbout")
    coder.encode(UserImageUrl, forKey: "UserImageUrl")
    coder.encode(CountryID, forKey: "CountryID")
    coder.encode(role.rawValue, forKey: "role")
    coder.encode(isAdmin, forKey: "isAdmin")
    coder.encode(isSuperAdmin, forKey: "isSuperAdmin")
    coder.encode(isBlocked, forKey: "isBlocked")
    coder.encode(permissions, forKey: "permissions")
    coder.encode(accountStatus, forKey: "accountStatus")
    coder.encode(prodectionStatus, forKey: "prodectionStatus")
    coder.encode(subscriptionPlan, forKey: "subscriptionPlan")
    coder.encode(subscriptionStatus, forKey: "subscriptionStatus")
    coder.encode(subscriptionSource, forKey: "subscriptionSource")
    coder.encode(verified, forKey: "verified")
  }

  public var isEffectivelyBlocked: Bool {
    isBlocked || accountStatus == "blocked" || accountStatus == "disabled"
  }

  public var isPostingEffectivelyBlocked: Bool {
    isEffectivelyBlocked || postingBlocked
  }

  public var isChatEffectivelyBlocked: Bool {
    isEffectivelyBlocked || chatBlocked
  }

  public var isPurchaseEffectivelyBlocked: Bool {
    isEffectivelyBlocked || purchaseBlocked
  }

  public var canPostAds: Bool { hasPermissionNamed(kPermPostAds) }
  public var canSellNew: Bool { hasPermissionNamed(kPermSellNew) }
  public var canSellUsed: Bool { hasPermissionNamed(kPermSellUsed) }
  public var canAdoption: Bool { hasPermissionNamed(kPermAdoption) }
  public var canManageStore: Bool { hasPermissionNamed(kPermManageStore) }
  public var canModeration: Bool { hasPermissionNamed(kPermModeration) }
  public var canManageFood: Bool { hasPermissionNamed(kPermManageFood) }
  public var canManageServices: Bool { hasPermissionNamed(kPermManageServices) }
  public var canProduction: Bool { hasPermissionNamed(kPermProduction) }
  public var isAdminAll: Bool { hasPermissionNamed(kPermAdminAll) }
  public var isStoreManager: Bool { role == .storeManager }
  public var isFoodManager: Bool { role == .foodManager }
  public var isModerator: Bool { role == .moderator }
  public var isOwner: Bool { role == .owner }
  public var isVet: Bool { role == .vet }

  public func toDictionary() -> NSDictionary {
    var values: [String: Any] = ["ID": ID]
    put(UserName, key: "UserName", into: &values)
    put(UserEmail, key: "UserEmail", into: &values)
    put(FirstName, key: "FirstName", into: &values)
    put(LastName, key: "LastName", into: &values)
    put(MobileNo, key: "MobileNo", into: &values)
    put(UserAbout, key: "UserAbout", into: &values)
    put(UserImageName, key: "UserImageName", into: &values)
    if let UserImageUrl { values["UserImageUrl"] = UserImageUrl.absoluteString }
    if CountryID != 0 { values["CountryID"] = CountryID }
    if PPUserTokenID.isEmpty == false { values["PPUserTokenID"] = PPUserTokenID }
    if let coverImageUrls { values["coverImageUrls"] = coverImageUrls }
    return values as NSDictionary
  }

  public func syncToFirestore(completion: @escaping (NSError?) -> Void) {
    updateProfile(completion: completion)
  }

  public func SYNC(completion: @escaping (NSError?) -> Void) {
    syncToFirestore(completion: completion)
  }

  public func fetchPermissions(
    completion: ((NSDictionary, NSError?) -> Void)?
  ) {
    guard let completion else { return }
    Task { @MainActor in
      PPUserKitRuntime.shared.start()
      PPUserKitRuntime.shared.refresh { [weak self] error in
        guard let self else {
          completion([:], error)
          return
        }
        if let error {
          completion(self.permissions, error)
          return
        }
        guard PPUserKitRuntime.shared.isCurrentUser(id: self.ID) else {
          completion(
            self.permissions,
            NSError(
              domain: "PPUserKit",
              code: 403,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Only the authenticated user's permissions are available through PurePetsUserKit."
              ]
            ))
          return
        }
        completion(self.permissions, nil)
      }
    }
  }

  public func startListeningPermissions(withChange change: @escaping (NSDictionary) -> Void) {
    permissionChange = change
    permissionObserver = NotificationCenter.default.addObserver(
      forName: PPUserKitRuntime.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self,
        let snapshot = PPUserKitRuntime.shared.currentSnapshot,
        snapshot.user.id.rawValue == self.ID
      else { return }
      self.apply(snapshot: snapshot)
      change(self.permissions)
    }
    Task { @MainActor in PPUserKitRuntime.shared.start() }
    change(permissions)
  }

  public func stopListeningPermissions() {
    if let permissionObserver {
      NotificationCenter.default.removeObserver(permissionObserver)
    }
    permissionObserver = nil
    permissionChange = nil
  }

  public func setPermissionNamed(
    _ permName: String,
    allowed: Bool,
    completion: @escaping (NSError?) -> Void
  ) {
    completion(
      NSError(
        domain: "PPUserKit",
        code: 403,
        userInfo: [NSLocalizedDescriptionKey: "Permissions are managed by the platform authority."]
      ))
  }

  public func hasPermissionNamed(_ permName: String) -> Bool {
    let cleanPermission = PPCanonicalPermissionName(permName)
    guard cleanPermission.isEmpty == false else { return false }

    if let explicitPermission = explicitPermission(for: cleanPermission) {
      return explicitPermission.boolValue
    }

    if cleanPermission != kPermAdminAll,
      let adminAllPermission = explicitPermission(for: kPermAdminAll)
    {
      return adminAllPermission.boolValue
    }

    return roleHasDefaultPermission(cleanPermission)
  }

  public func hasAnyPermission(inKeys keys: [String]) -> Bool {
    keys.contains(where: hasPermissionNamed)
  }

  public func bestDisplayName() -> String {
    if UserName.isEmpty == false { return UserName }
    if let FirstName, FirstName.isEmpty == false { return FirstName }
    if UserEmail.isEmpty == false { return UserEmail }
    return ID
  }

  public func PPBestDisplayName() -> String {
    bestDisplayName()
  }

  public func userName() -> String { UserName }
  public func userEmail() -> String { UserEmail }
  public func firstName() -> String? { FirstName }
  public func lastName() -> String? { LastName }
  public func mobileNo() -> String? { MobileNo }
  public func userAbout() -> String? { UserAbout }
  public func userImageName() -> String? { UserImageName }
  public func userImageUrl() -> URL? { UserImageUrl }
  public func countryID() -> Int { CountryID }
  public func ppUserTokenID() -> String { PPUserTokenID }
  public func addresses() -> NSMutableArray { Addresses }
  public func selectedInstrument() -> AnyObject? { SelectedInstrument }

  @nonobjc public func apply(snapshot: PPCurrentUserSnapshot) {
    isApplyingProjection = true
    ID = snapshot.user.id.rawValue
    UserName = snapshot.user.username ?? snapshot.user.displayName
    UserEmail = snapshot.user.email ?? ""
    FirstName = snapshot.user.name.first
    LastName = snapshot.user.name.last
    MobileNo = snapshot.user.phoneNumber
    UserAbout = snapshot.user.about
    UserImageUrl = snapshot.user.avatarURL
    onlineStatus = snapshot.user.presence.status == .online ? .online : .offline
    isOnline = snapshot.user.presence.status == .online
    lastSeen = snapshot.user.presence.lastSeenAt
    CountryID = snapshot.user.countryID ?? 0
    updatedAt = snapshot.user.updatedAt
    loginDate = snapshot.user.createdAt
    providerRatingValue = snapshot.user.reputation?.rating ?? 0
    providerReviewCount = snapshot.user.reputation?.reviewCount ?? 0
    coverImageUrls = snapshot.user.coverImageURLs.map(\.absoluteString) as NSArray
    UserImageName = string(in: snapshot.profile, keys: ["UserImageName", "imageName"])

    role = compatibilityRole(snapshot.access.role)
    isAdmin = snapshot.access.isAdmin
    isSuperAdmin = snapshot.access.isSuperAdmin
    isBlocked = snapshot.access.isBlocked
    accountStatus = snapshot.access.accountStatus.rawValue
    prodectionStatus = snapshot.access.protectionStatus
    subscriptionPlan = snapshot.access.subscription.plan
    subscriptionStatus = snapshot.access.subscription.status
    subscriptionSource = snapshot.access.subscription.source
    plan = string(in: snapshot.profile, keys: ["plan"]) ?? subscriptionPlan
    permissions = snapshot.access.permissionValues.reduce(into: NSMutableDictionary()) {
      $0[$1.key] = NSNumber(value: $1.value)
    }

    let features = snapshot.access.featureFlags
    canPostPetAdsFeature = features["canPostPetAds"] ?? false
    canPostAdoptionFeature = features["canPostAdoption"] ?? false
    canSellAccessoriesFeature = features["canSellAccessories"] ?? false
    canOfferServicesFeature = features["canOfferServices"] ?? false
    canDeliveryFeature = features["canDelivery"] ?? false
    canPharmacyFeature = features["canPharmacy"] ?? false
    canVetFeature = features["canVet"] ?? false
    canUseStoriesFeature = features["canUseStories"] ?? false
    canUseChatFeature = features["canUseChat"] ?? false
    canAccessPremiumMarketplaceFeature = features["canAccessPremiumMarketplace"] ?? false
    canAccessProviderMarketplaceFeature = features["canAccessProviderMarketplace"] ?? false

    let restrictions = snapshot.access.restrictions
    postingBlocked = restrictions["postingBlocked"] ?? false
    chatBlocked = restrictions["chatBlocked"] ?? false
    purchaseBlocked = restrictions["purchaseBlocked"] ?? false
    withdrawalBlocked = restrictions["withdrawalBlocked"] ?? false
    canAccessPartnerAppPermission = snapshot.access.isCapabilityEnabled(.accessPartnerApp)
    canManageDeliveryPermission = snapshot.access.isCapabilityEnabled(.manageDelivery)
    canManageServiceProviderPermission = snapshot.access.isCapabilityEnabled(.manageServiceProvider)
    canManageVetPermission = snapshot.access.isCapabilityEnabled(.manageVet)
    canPostVetProfilePermission = snapshot.access.isCapabilityEnabled(.postVetProfile)
    canEditVetInfoPermission = snapshot.access.isCapabilityEnabled(.editVetInfo)
    canManagePetMedicinesPermission = snapshot.access.isCapabilityEnabled(.managePetMedicines)

    let partnerProfile =
      snapshot.profile["onboarding"]?.objectValue
      ?? snapshot.profile["partnerOnboarding"]?.objectValue
      ?? snapshot.profile
    partnerOnboardingVisible =
      bool(in: partnerProfile, keys: ["partnerOnboardingVisible", "visible"]) ?? false
    partnerApplicationStatus =
      string(in: partnerProfile, keys: ["partnerApplicationStatus", "status"]) ?? "not_started"
    selectedPartnerType = normalizedPartnerType(
      string(in: partnerProfile, keys: ["selectedPartnerType", "selectedType"]))
    verified = bool(in: snapshot.profile, keys: ["verified"]) ?? false
    PPUserTokenID = string(in: snapshot.profile, keys: ["PPUserTokenID", "ppUserTokenID"]) ?? PPUserTokenID
    PPAdminTokenID = string(in: snapshot.profile, keys: ["PPAdminTokenID", "ppAdminTokenID"]) ?? PPAdminTokenID
    PPProTokenID = string(in: snapshot.profile, keys: ["PPProTokenID", "ppProTokenID"]) ?? PPProTokenID
    loginSource = UserLoginSource(rawValue: int(in: snapshot.profile, keys: ["loginSource"]) ?? 0) ?? .unknown
    isApplyingProjection = false
  }

  private func apply(dictionary: NSDictionary) {
    isApplyingProjection = true
    ID = string(in: dictionary, keys: ["ID", "uid", "id"]) ?? ""
    UserName = string(in: dictionary, keys: ["UserName", "username", "displayName"]) ?? ""
    UserEmail = string(in: dictionary, keys: ["UserEmail", "email"]) ?? ""
    FirstName = string(in: dictionary, keys: ["FirstName", "firstName"])
    LastName = string(in: dictionary, keys: ["LastName", "lastName"])
    MobileNo = string(in: dictionary, keys: ["MobileNo", "phoneNumber", "mobile"])
    UserAbout = string(in: dictionary, keys: ["UserAbout", "about", "bio"])
    UserImageName = string(in: dictionary, keys: ["UserImageName", "imageName"])
    if let image = string(
      in: dictionary,
      keys: [
        "UserImageUrl", "UserImageURL", "photoURL", "photoUrl", "avatarURL", "avatarUrl",
        "avatar", "userImageUrl", "userImageURL", "profileImageUrl", "profileImageURL",
        "photo", "picture", "image",
      ])
    {
      UserImageUrl = URL(string: image)
    }
    CountryID = int(in: dictionary, keys: ["CountryID", "countryID"]) ?? 0
    role = PPParseRoleFromUserDoc(dictionary as? [AnyHashable: Any] ?? [:])
    isAdmin = bool(in: dictionary, keys: ["isAdmin", "admin"]) ?? false
    isSuperAdmin = bool(in: dictionary, keys: ["isSuperAdmin", "superAdmin", "superadmin"]) ?? false
    isBlocked = bool(in: dictionary, keys: ["isBlocked", "blocked"]) ?? false
    accountStatus = string(in: dictionary, keys: ["accountStatus"]) ?? "unknown"
    prodectionStatus = string(in: dictionary, keys: ["prodectionStatus", "protectionStatus"]) ?? "inactive"
    let subscription = nested(dictionary, key: "subscription")
    subscriptionPlan =
      string(in: subscription, keys: ["plan"])
      ?? string(in: dictionary, keys: ["subscriptionPlan", "plan"])
      ?? "free"
    subscriptionStatus =
      string(in: subscription, keys: ["status"])
      ?? string(in: dictionary, keys: ["subscriptionStatus"])
      ?? "active"
    subscriptionSource =
      string(in: subscription, keys: ["source"])
      ?? string(in: dictionary, keys: ["subscriptionSource"])
      ?? "manual"
    plan = string(in: dictionary, keys: ["plan"]) ?? subscriptionPlan
    postingBlocked = bool(in: nested(dictionary, key: "restrictions"), keys: ["postingBlocked"]) ?? bool(in: dictionary, keys: ["postingBlocked"]) ?? false
    chatBlocked = bool(in: nested(dictionary, key: "restrictions"), keys: ["chatBlocked"]) ?? bool(in: dictionary, keys: ["chatBlocked"]) ?? false
    purchaseBlocked = bool(in: nested(dictionary, key: "restrictions"), keys: ["purchaseBlocked"]) ?? bool(in: dictionary, keys: ["purchaseBlocked"]) ?? false
    withdrawalBlocked = bool(in: nested(dictionary, key: "restrictions"), keys: ["withdrawalBlocked"]) ?? bool(in: dictionary, keys: ["withdrawalBlocked"]) ?? false
    let featureValues = nested(dictionary, key: "features")
    canPostPetAdsFeature = bool(in: featureValues, keys: ["canPostPetAds"]) ?? true
    canPostAdoptionFeature = bool(in: featureValues, keys: ["canPostAdoption"]) ?? true
    canSellAccessoriesFeature = bool(in: featureValues, keys: ["canSellAccessories"]) ?? false
    canOfferServicesFeature = bool(in: featureValues, keys: ["canOfferServices", "service_provider"]) ?? false
    canDeliveryFeature = bool(in: featureValues, keys: ["canDelivery", "delivery"]) ?? false
    canPharmacyFeature = bool(in: featureValues, keys: ["canPharmacy", "pharmacy"]) ?? bool(in: dictionary, keys: ["canPharmacy"]) ?? false
    canVetFeature = bool(in: featureValues, keys: ["canVet", "vet"]) ?? false
    canUseStoriesFeature = bool(in: featureValues, keys: ["canUseStories"]) ?? true
    canUseChatFeature = bool(in: featureValues, keys: ["canUseChat"]) ?? true
    canAccessPremiumMarketplaceFeature = bool(in: featureValues, keys: ["canAccessPremiumMarketplace"]) ?? false
    canAccessProviderMarketplaceFeature = bool(in: featureValues, keys: ["canAccessProviderMarketplace"]) ?? false
    let partnerProfile = nested(dictionary, key: "onboarding")
    let partnerSource = partnerProfile.count > 0 ? partnerProfile : dictionary
    partnerOnboardingVisible =
      bool(in: partnerSource, keys: ["partnerOnboardingVisible", "visible"]) ?? false
    partnerApplicationStatus =
      string(in: partnerSource, keys: ["partnerApplicationStatus", "status"]) ?? "not_started"
    selectedPartnerType = normalizedPartnerType(
      string(in: partnerSource, keys: ["selectedPartnerType", "selectedType"]))
    verified = bool(in: dictionary, keys: ["verified"]) ?? false
    PPUserTokenID = string(in: dictionary, keys: ["PPUserTokenID", "ppUserTokenID"]) ?? ""
    PPAdminTokenID = string(in: dictionary, keys: ["PPAdminTokenID", "ppAdminTokenID"]) ?? ""
    PPProTokenID = string(in: dictionary, keys: ["PPProTokenID", "ppProTokenID"]) ?? ""
    loginSource = UserLoginSource(rawValue: int(in: dictionary, keys: ["loginSource"]) ?? 0) ?? .unknown
    onlineStatus = resolvedOnlineStatus(in: dictionary)
    isOnline = onlineStatus == .online
    lastSeen = date(in: dictionary, keys: ["lastSeen"])
    loginDate = date(in: dictionary, keys: ["loginDate", "createdAt"])
    updatedAt = date(in: dictionary, keys: ["updatedAt"])
    providerRatingValue = min(
      5,
      max(0, double(in: dictionary, keys: ["providerRatingValue", "providerRating"]) ?? 0))
    providerReviewCount = max(
      0,
      int(in: dictionary, keys: ["providerReviewCount", "reviewCount"]) ?? 0)
    if let coverImages = strings(in: dictionary, keys: ["coverImageUrls"]) {
      coverImageUrls = coverImages as NSArray
    }
    if let rawPermissions = dictionary["permissions"] as? NSDictionary {
      permissions = rawPermissions
    }
    isApplyingProjection = false
  }

  private func updateProfile(completion: @escaping (NSError?) -> Void) {
    let patch = PPUserProfilePatch(
      username: UserName.isEmpty ? .unchanged : .set(UserName),
      firstName: FirstName.map(PPFieldUpdate.set) ?? .unchanged,
      lastName: LastName.map(PPFieldUpdate.set) ?? .unchanged,
      phoneNumber: MobileNo.map(PPFieldUpdate.set) ?? .unchanged,
      about: UserAbout.map(PPFieldUpdate.set) ?? .unchanged,
      avatarURL: UserImageUrl.map(PPFieldUpdate.set) ?? .unchanged,
      countryID: CountryID == 0 ? .unchanged : .set(CountryID)
    )
    Task { @MainActor in PPUserKitRuntime.shared.updateProfile(patch, completion: completion) }
  }

  private func queueProfilePatch(
    username: String? = nil,
    firstName: String? = nil,
    lastName: String? = nil,
    phoneNumber: String? = nil,
    about: String? = nil,
    avatarURL: URL? = nil,
    countryID: Int? = nil
  ) {
    guard !isApplyingProjection, !ID.isEmpty else { return }
    let patch = PPUserProfilePatch(
      username: username.map(PPFieldUpdate.set) ?? .unchanged,
      firstName: firstName.map(PPFieldUpdate.set) ?? .unchanged,
      lastName: lastName.map(PPFieldUpdate.set) ?? .unchanged,
      phoneNumber: phoneNumber.map(PPFieldUpdate.set) ?? .unchanged,
      about: about.map(PPFieldUpdate.set) ?? .unchanged,
      avatarURL: avatarURL.map(PPFieldUpdate.set) ?? .unchanged,
      countryID: countryID.map(PPFieldUpdate.set) ?? .unchanged
    )
    Task { @MainActor in
      guard PPUserKitRuntime.shared.isCurrentUser(id: ID) else { return }
      PPUserKitRuntime.shared.updateProfile(patch) { error in
        if let error { NSLog("[PPUserKitUserModel] profile update failed: %@", error.localizedDescription) }
      }
    }
  }

  private func put(_ value: String?, key: String, into values: inout [String: Any]) {
    guard let value, value.isEmpty == false else { return }
    values[key] = value
  }

  private func explicitPermission(for canonicalName: String) -> NSNumber? {
    var keys = [canonicalName]
    if canonicalName == kPermAdoption {
      keys.append("ManageUsers")
    } else if canonicalName == kPermModeration {
      keys.append(contentsOf: ["ManageNotificatiuons", "ManageNotifications"])
    } else if canonicalName == kPermPostAds {
      keys.append("ManageBanners")
    } else if canonicalName == kPermProduction {
      keys.append("Prodection")
    }

    for key in keys {
      if let value = permissions[key] as? NSNumber {
        return value
      }
    }
    return nil
  }

  private func roleHasDefaultPermission(_ permissionKey: String) -> Bool {
    var defaults: Set<String> = [
      kPermPostAds, kPermProduction, kPermAdoption, kPermSellUsed
    ]

    switch role {
    case .owner:
      defaults.formUnion([kPermSellNew, kPermManageServices])
    case .vet:
      defaults.insert(kPermManageServices)
    case .moderator:
      defaults.insert(kPermModeration)
    case .admin:
      defaults.formUnion([
        kPermSellNew, kPermModeration, kPermManageStore,
        kPermManageServices, kPermAdminAll
      ])
    case .storeManager:
      defaults.formUnion([kPermSellNew, kPermManageStore, kPermManageServices])
    case .foodManager:
      defaults.formUnion([
        kPermSellNew, kPermManageStore, kPermManageFood, kPermManageServices
      ])
    case .superAdmin:
      defaults = [
        kPermPostAds, kPermSellNew, kPermSellUsed, kPermAdoption,
        kPermModeration, kPermManageStore, kPermManageFood,
        kPermManageServices, kPermProduction, kPermAdminAll
      ]
    case .unknown, .user:
      break
    @unknown default:
      break
    }

    return defaults.contains(permissionKey)
  }

  private func compatibilityRole(_ role: PPUserRole) -> UserRole {
    switch role {
    case .owner: return .owner
    case .vet: return .vet
    case .moderator: return .moderator
    case .admin: return .admin
    case .storeManager: return .storeManager
    case .foodManager: return .foodManager
    case .superAdmin: return .superAdmin
    default: return .user
    }
  }

  private func string(in dictionary: NSDictionary, keys: [String]) -> String? {
    for key in keys {
      if let value = dictionary[key] as? String, value.isEmpty == false { return value }
    }
    return nil
  }

  private func string(in document: PPDocument, keys: [String]) -> String? {
    for key in keys {
      if let value = document[key]?.stringValue, value.isEmpty == false { return value }
    }
    return nil
  }

  private func int(in dictionary: NSDictionary, keys: [String]) -> Int? {
    for key in keys {
      if let value = dictionary[key] as? NSNumber { return value.intValue }
      if let value = dictionary[key] as? String, let result = Int(value) { return result }
    }
    return nil
  }

  private func int(in document: PPDocument, keys: [String]) -> Int? {
    for key in keys {
      if let value = document[key]?.intValue { return value }
    }
    return nil
  }

  private func double(in dictionary: NSDictionary, keys: [String]) -> Double? {
    for key in keys {
      if let value = dictionary[key] as? NSNumber { return value.doubleValue }
      if let value = dictionary[key] as? String, let result = Double(value) { return result }
    }
    return nil
  }

  private func strings(in dictionary: NSDictionary, keys: [String]) -> [String]? {
    for key in keys {
      if let values = dictionary[key] as? [String] {
        return values.filter { $0.isEmpty == false }
      }
      if let values = dictionary[key] as? NSArray {
        let strings = values.compactMap { $0 as? String }.filter { $0.isEmpty == false }
        if strings.isEmpty == false { return strings }
      }
    }
    return nil
  }

  private func date(in dictionary: NSDictionary, keys: [String]) -> Date? {
    for key in keys {
      if let value = dictionary[key] as? Date { return value }
      if let value = dictionary[key] as? Timestamp { return value.dateValue() }
      if let value = dictionary[key] as? NSNumber {
        return Date(timeIntervalSince1970: value.doubleValue)
      }
    }
    return nil
  }

  private func resolvedOnlineStatus(in dictionary: NSDictionary) -> OnlineStatus {
    if let status = int(in: dictionary, keys: ["onlineStatus"]) {
      return status == OnlineStatus.online.rawValue ? .online : .offline
    }
    if let online = bool(in: dictionary, keys: ["isOnline", "online"]) {
      return online ? .online : .offline
    }
    if let raw = string(in: dictionary, keys: ["onlineStatus"])?.lowercased() {
      return raw == "online" || raw == "1" ? .online : .offline
    }
    return .offline
  }

  private func normalizedPartnerType(_ value: String?) -> String? {
    guard let value else { return nil }
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "delivery_subscription", "delivery":
      return "delivery"
    case "service", "serviceprovider", "service_provider":
      return "service_provider"
    case "vet":
      return "vet"
    case "pharmacy":
      return "pharmacy"
    default:
      return nil
    }
  }

  private func bool(in dictionary: NSDictionary, keys: [String]) -> Bool? {
    for key in keys {
      if let value = dictionary[key] as? NSNumber { return value.boolValue }
      if let value = dictionary[key] as? String {
        switch value.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: break
        }
      }
    }
    return nil
  }

  private func bool(in document: PPDocument, keys: [String]) -> Bool? {
    for key in keys {
      if let value = document[key]?.boolValue { return value }
    }
    return nil
  }

  private func nested(_ dictionary: NSDictionary, key: String) -> NSDictionary {
    dictionary[key] as? NSDictionary ?? [:]
  }
}
