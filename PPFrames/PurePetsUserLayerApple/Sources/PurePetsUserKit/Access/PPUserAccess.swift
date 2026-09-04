import Foundation

public struct PPUserRole: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue =
      rawValue
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
      .ppNilIfBlank ?? Self.user.rawValue
  }

  public init(stringLiteral value: String) {
    self.init(rawValue: value)
  }

  public static let user: Self = "user"
  public static let admin: Self = "admin"
  public static let superAdmin: Self = "super_admin"
  public static let owner: Self = "owner"
  public static let moderator: Self = "moderator"
  public static let storeManager: Self = "store_manager"
  public static let foodManager: Self = "food_manager"
  public static let vet: Self = "vet"
}

public enum PPUserAccountStatus: String, Codable, Sendable {
  case unknown
  case active
  case pendingReview = "pending_review"
  case blocked
  case disabled
}

public enum PPUserAccessTrust: String, Codable, Sendable {
  case unknown
  case cached
  case verified
}

public enum PPUserCapability: String, Codable, CaseIterable, Hashable, Sendable {
  case postPetAd
  case postAdoption
  case sellAccessories
  case useStories
  case useChat
  case purchase
  case withdraw
  case accessPremiumMarketplace
  case accessProviderMarketplace
  case accessPartnerApp
  case manageDelivery
  case manageServiceProvider
  case manageVet
  case postVetProfile
  case editVetInfo
  case managePetMedicines
}

public enum PPUserAccessDenial: String, Codable, Error, Sendable {
  case accessUnverified
  case accessExpired
  case accountBlocked
  case accountDisabled
  case accountNotActive
  case featureDisabled
  case explicitlyRestricted
  case permissionMissing
  case unsupportedCapability
}

public struct PPUserAccessDecision: Codable, Equatable, Sendable {
  public let isAllowed: Bool
  public let denial: PPUserAccessDenial?

  package static let allowed = Self(isAllowed: true, denial: nil)

  package static func denied(_ denial: PPUserAccessDenial) -> Self {
    Self(isAllowed: false, denial: denial)
  }
}

public struct PPUserSubscription: Codable, Equatable, Sendable {
  public var plan: String
  public var status: String
  public var source: String

  public init(plan: String = "free", status: String = "inactive", source: String = "unknown") {
    self.plan = plan.ppNilIfBlank?.lowercased() ?? "free"
    self.status = status.ppNilIfBlank?.lowercased() ?? "inactive"
    self.source = source.ppNilIfBlank?.lowercased() ?? "unknown"
  }
}

package enum PPUserCapabilityRule: String, Codable, Sendable {
  case allowed
  case featureDisabled
  case explicitlyRestricted
  case permissionMissing
}

public struct PPUserAccess: Codable, Equatable, Sendable {
  public let role: PPUserRole
  public let isAdmin: Bool
  public let isSuperAdmin: Bool
  public let isBlocked: Bool
  public let accountStatus: PPUserAccountStatus
  public let protectionStatus: String
  public let subscription: PPUserSubscription
  public let featureFlags: [String: Bool]
  public let restrictions: [String: Bool]
  public let permissionValues: [String: Bool]
  public let permissions: Set<String>
  public let trust: PPUserAccessTrust
  public let fetchedAt: Date
  public let expiresAt: Date?

  package let rules: [PPUserCapability: PPUserCapabilityRule]

  package init(
    role: PPUserRole,
    isAdmin: Bool,
    isSuperAdmin: Bool,
    isBlocked: Bool,
    accountStatus: PPUserAccountStatus,
    protectionStatus: String,
    subscription: PPUserSubscription,
    featureFlags: [String: Bool],
    restrictions: [String: Bool],
    permissionValues: [String: Bool],
    permissions: Set<String>,
    trust: PPUserAccessTrust,
    fetchedAt: Date,
    expiresAt: Date?,
    rules: [PPUserCapability: PPUserCapabilityRule]
  ) {
    self.role = role
    self.isAdmin = isAdmin
    self.isSuperAdmin = isSuperAdmin
    self.isBlocked = isBlocked
    self.accountStatus = accountStatus
    self.protectionStatus = protectionStatus
    self.subscription = subscription
    self.featureFlags = featureFlags
    self.restrictions = restrictions
    self.permissionValues = permissionValues
    self.permissions = permissions
    self.trust = trust
    self.fetchedAt = fetchedAt
    self.expiresAt = expiresAt
    self.rules = rules
  }

  public static func unknown(at date: Date = .now) -> Self {
    Self(
      role: .user,
      isAdmin: false,
      isSuperAdmin: false,
      isBlocked: false,
      accountStatus: .unknown,
      protectionStatus: "inactive",
      subscription: .init(),
      featureFlags: [:],
      restrictions: [:],
      permissionValues: [:],
      permissions: [],
      trust: .unknown,
      fetchedAt: date,
      expiresAt: nil,
      rules: [:]
    )
  }

  public func isExpired(at date: Date = .now) -> Bool {
    guard let expiresAt else { return false }
    return expiresAt <= date
  }

  public func decision(for capability: PPUserCapability, at date: Date = .now)
    -> PPUserAccessDecision
  {
    guard trust == .verified else {
      return .denied(.accessUnverified)
    }
    guard !isExpired(at: date) else {
      return .denied(.accessExpired)
    }
    if accountStatus == .disabled {
      return .denied(.accountDisabled)
    }
    if isBlocked || accountStatus == .blocked {
      return .denied(.accountBlocked)
    }
    guard accountStatus == .active else {
      return .denied(.accountNotActive)
    }

    guard let rule = rules[capability] else {
      return .denied(.unsupportedCapability)
    }

    switch rule {
    case .allowed:
      return .allowed
    case .featureDisabled:
      return .denied(.featureDisabled)
    case .explicitlyRestricted:
      return .denied(.explicitlyRestricted)
    case .permissionMissing:
      return .denied(.permissionMissing)
    }
  }

  public func hasPermission(_ permission: String, at date: Date = .now) -> Bool {
    guard permission.ppNilIfBlank != nil else { return false }
    guard decisionEnvironmentAllowsAccess(at: date) else { return false }
    return permissions.contains(permission)
  }

  public func isCapabilityEnabled(_ capability: PPUserCapability) -> Bool {
    rules[capability] == .allowed
  }

  public func capabilityRuleCode(_ capability: PPUserCapability) -> String {
    rules[capability]?.rawValue ?? PPUserCapabilityRule.permissionMissing.rawValue
  }

  package func cachedCopy(at date: Date = .now) -> Self {
    Self(
      role: role,
      isAdmin: false,
      isSuperAdmin: false,
      isBlocked: isBlocked,
      accountStatus: accountStatus,
      protectionStatus: protectionStatus,
      subscription: subscription,
      featureFlags: featureFlags,
      restrictions: restrictions,
      permissionValues: permissionValues,
      permissions: [],
      trust: .cached,
      fetchedAt: date,
      expiresAt: nil,
      rules: rules.mapValues { rule in
        rule == .explicitlyRestricted ? .explicitlyRestricted : .featureDisabled
      }
    )
  }

  private func decisionEnvironmentAllowsAccess(at date: Date) -> Bool {
    trust == .verified
      && !isExpired(at: date)
      && !isBlocked
      && accountStatus == .active
  }
}
