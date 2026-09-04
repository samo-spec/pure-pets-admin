import Foundation

public actor PPMemoryUserCache: PPUserCache {
  private var snapshots: [PPUserID: PPCurrentUserSnapshot] = [:]

  public init() {}

  public func load(for userID: PPUserID) -> PPCurrentUserSnapshot? {
    snapshots[userID]?.cachedCopy()
  }

  public func save(_ snapshot: PPCurrentUserSnapshot) {
    snapshots[snapshot.user.id] = snapshot
  }

  public func remove(for userID: PPUserID) {
    snapshots.removeValue(forKey: userID)
  }
}
