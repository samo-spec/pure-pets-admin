import Foundation
import PurePetsUserKit

public actor PPFileUserCache: PPUserCache {
  private let directory: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(directory: URL? = nil) throws {
    let fileManager = FileManager.default
    let base =
      try directory
      ?? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    self.directory = base.appendingPathComponent("PurePets/UserCache", isDirectory: true)
    try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    #if os(iOS)
      try? fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: self.directory.path
      )
    #endif
    encoder = JSONEncoder()
    decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    decoder.dateDecodingStrategy = .millisecondsSince1970
  }

  public func load(for userID: PPUserID) throws -> PPCurrentUserSnapshot? {
    let url = fileURL(for: userID)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let data = try Data(contentsOf: url)
      return try decoder.decode(PPCurrentUserSnapshot.self, from: data).cachedCopy()
    } catch {
      try? FileManager.default.removeItem(at: url)
      throw PPUserRepositoryFailure(
        code: .persistence, message: "The cached user snapshot was invalid and was removed.")
    }
  }

  public func save(_ snapshot: PPCurrentUserSnapshot) throws {
    let data = try encoder.encode(snapshot)
    try data.write(to: fileURL(for: snapshot.user.id), options: .atomic)
    #if os(iOS)
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: fileURL(for: snapshot.user.id).path
      )
    #endif
  }

  public func remove(for userID: PPUserID) throws {
    let url = fileURL(for: userID)
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  private func fileURL(for userID: PPUserID) -> URL {
    let key = Data(userID.rawValue.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
    return directory.appendingPathComponent("\(key).json", isDirectory: false)
  }
}
