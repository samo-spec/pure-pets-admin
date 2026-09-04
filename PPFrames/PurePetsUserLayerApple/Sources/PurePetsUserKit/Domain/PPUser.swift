import Foundation

public struct PPUserID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init?(rawValue: String) {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    self.rawValue = value
  }

  public init?(_ rawValue: String) {
    self.init(rawValue: rawValue)
  }

  public var description: String { rawValue }
}

public struct PPUser: Identifiable, Codable, Equatable, Sendable {
  public struct Name: Codable, Equatable, Sendable {
    public var first: String?
    public var last: String?

    public init(first: String? = nil, last: String? = nil) {
      self.first = first?.ppNilIfBlank
      self.last = last?.ppNilIfBlank
    }

    public var formatted: String? {
      [first, last]
        .compactMap { $0?.ppNilIfBlank }
        .joined(separator: " ")
        .ppNilIfBlank
    }
  }

  public struct Presence: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
      case unknown
      case offline
      case online
    }

    public var status: Status
    public var lastSeenAt: Date?

    public init(status: Status = .unknown, lastSeenAt: Date? = nil) {
      self.status = status
      self.lastSeenAt = lastSeenAt
    }
  }

  public struct Reputation: Codable, Equatable, Sendable {
    public var rating: Double
    public var reviewCount: Int

    public init(rating: Double, reviewCount: Int) {
      self.rating = min(max(rating, 0), 5)
      self.reviewCount = max(reviewCount, 0)
    }
  }

  public let id: PPUserID
  public var username: String?
  public var email: String?
  public var name: Name
  public var phoneNumber: String?
  public var about: String?
  public var avatarURL: URL?
  public var presence: Presence
  public var countryID: Int?
  public var reputation: Reputation?
  public var coverImageURLs: [URL]
  public var createdAt: Date?
  public var updatedAt: Date?

  public init(
    id: PPUserID,
    username: String? = nil,
    email: String? = nil,
    name: Name = .init(),
    phoneNumber: String? = nil,
    about: String? = nil,
    avatarURL: URL? = nil,
    presence: Presence = .init(),
    countryID: Int? = nil,
    reputation: Reputation? = nil,
    coverImageURLs: [URL] = [],
    createdAt: Date? = nil,
    updatedAt: Date? = nil
  ) {
    self.id = id
    self.username = username?.ppNilIfBlank
    self.email = email?.ppNilIfBlank
    self.name = name
    self.phoneNumber = phoneNumber?.ppNilIfBlank
    self.about = about?.ppNilIfBlank
    self.avatarURL = avatarURL
    self.presence = presence
    self.countryID = countryID
    self.reputation = reputation
    self.coverImageURLs = coverImageURLs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  public var displayName: String {
    username?.ppNilIfBlank
      ?? name.formatted
      ?? email?.split(separator: "@").first.map(String.init)?.ppNilIfBlank
      ?? id.rawValue
  }
}

extension String {
  package var ppNilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
