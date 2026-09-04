import Foundation

public enum PPFieldUpdate<Value: Sendable>: Sendable {
  case unchanged
  case set(Value)
  case remove
}

public struct PPUserProfilePatch: Sendable {
  public var username: PPFieldUpdate<String>
  public var firstName: PPFieldUpdate<String>
  public var lastName: PPFieldUpdate<String>
  public var phoneNumber: PPFieldUpdate<String>
  public var about: PPFieldUpdate<String>
  public var avatarURL: PPFieldUpdate<URL>
  public var countryID: PPFieldUpdate<Int>
  public var coverImageURLs: PPFieldUpdate<[URL]>

  public init(
    username: PPFieldUpdate<String> = .unchanged,
    firstName: PPFieldUpdate<String> = .unchanged,
    lastName: PPFieldUpdate<String> = .unchanged,
    phoneNumber: PPFieldUpdate<String> = .unchanged,
    about: PPFieldUpdate<String> = .unchanged,
    avatarURL: PPFieldUpdate<URL> = .unchanged,
    countryID: PPFieldUpdate<Int> = .unchanged,
    coverImageURLs: PPFieldUpdate<[URL]> = .unchanged
  ) {
    self.username = username
    self.firstName = firstName
    self.lastName = lastName
    self.phoneNumber = phoneNumber
    self.about = about
    self.avatarURL = avatarURL
    self.countryID = countryID
    self.coverImageURLs = coverImageURLs
  }

  public var isEmpty: Bool {
    [
      username.isUnchanged,
      firstName.isUnchanged,
      lastName.isUnchanged,
      phoneNumber.isUnchanged,
      about.isUnchanged,
      avatarURL.isUnchanged,
      countryID.isUnchanged,
      coverImageURLs.isUnchanged,
    ].allSatisfy { $0 }
  }
}

extension PPFieldUpdate {
  package var isUnchanged: Bool {
    if case .unchanged = self { return true }
    return false
  }
}
