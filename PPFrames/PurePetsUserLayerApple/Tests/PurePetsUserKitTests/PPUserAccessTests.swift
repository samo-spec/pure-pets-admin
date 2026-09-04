import XCTest

@testable import PurePetsUserKit

final class PPUserAccessTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000)

  func testUnknownAccessFailsClosed() {
    let decision = PPUserAccess.unknown(at: now).decision(for: .useChat, at: now)
    XCTAssertFalse(decision.isAllowed)
    XCTAssertEqual(decision.denial, .accessUnverified)
  }

  func testExpiredAccessFailsClosed() throws {
    let mapper = PPUserMapper(permissionCatalog: testCatalog)
    let snapshot = mapper.map(
      authUser: testUser("u1"),
      remote: activeRemoteState(),
      token: PPTokenClaims(
        issuedAt: now.addingTimeInterval(-7_200), expiresAt: now.addingTimeInterval(-1)),
      fetchedAt: now
    )

    XCTAssertEqual(snapshot.access.decision(for: .useChat, at: now).denial, .accessExpired)
  }

  func testCachedSnapshotCannotGrantAdminOrPermissions() throws {
    let mapper = PPUserMapper(permissionCatalog: testCatalog)
    let verified = mapper.map(
      authUser: testUser("u1"),
      remote: activeRemoteState(permissions: ["manage_store": true]),
      token: testToken(role: .superAdmin, superAdmin: true, now: now),
      fetchedAt: now
    )

    let cached = verified.cachedCopy(at: now)
    XCTAssertEqual(cached.access.trust, .cached)
    XCTAssertFalse(cached.access.isAdmin)
    XCTAssertFalse(cached.access.isSuperAdmin)
    XCTAssertFalse(cached.access.hasPermission("manage_store", at: now))
    XCTAssertEqual(cached.access.decision(for: .useChat, at: now).denial, .accessUnverified)
  }

  func testEveryCapabilityHasAnExplicitRule() throws {
    let mapper = PPUserMapper(permissionCatalog: testCatalog)
    let snapshot = mapper.map(
      authUser: testUser("u1"),
      remote: activeRemoteState(),
      token: testToken(now: now),
      fetchedAt: now
    )

    XCTAssertEqual(Set(snapshot.access.rules.keys), Set(PPUserCapability.allCases))
  }
}
