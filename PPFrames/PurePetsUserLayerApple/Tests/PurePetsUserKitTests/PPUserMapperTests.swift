import XCTest

@testable import PurePetsUserKit

final class PPUserMapperTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000)
  private let mapper = PPUserMapper(permissionCatalog: testCatalog)

  func testAuthIdentityOverridesProfileIdentity() throws {
    let auth = PPAuthUser(
      id: PPUserID("auth-id")!,
      email: "auth@example.com",
      displayName: "Auth Name",
      photoURL: URL(string: "https://example.com/auth.jpg")
    )
    let remote = activeRemoteState(extra: [
      "ID": .string("forged-id"),
      "UserEmail": .string("profile@example.com"),
      "UserName": .string("Profile Name"),
      "UserImageUrl": .string("https://example.com/profile.jpg"),
      "claims": .object(["isAdmin": .bool(true)]),
    ])

    let snapshot = mapper.map(
      authUser: auth, remote: remote, token: testToken(now: now), fetchedAt: now)
    XCTAssertEqual(snapshot.user.id.rawValue, "auth-id")
    XCTAssertEqual(snapshot.user.email, "auth@example.com")
    XCTAssertEqual(snapshot.user.username, "Auth Name")
    XCTAssertEqual(snapshot.user.avatarURL?.absoluteString, "https://example.com/auth.jpg")
    XCTAssertFalse(snapshot.access.isAdmin)
  }

  func testCanonicalChatBlockWinsOverLegacyAllow() throws {
    let remote = activeRemoteState(
      features: ["canUseChat": .bool(false)],
      restrictions: ["chatBlocked": .bool(true)],
      extra: ["canReceiveMessages": .bool(true)]
    )

    let snapshot = mapper.map(
      authUser: testUser("u1"), remote: remote, token: testToken(now: now), fetchedAt: now)
    XCTAssertEqual(snapshot.access.decision(for: .useChat, at: now).denial, .explicitlyRestricted)
  }

  func testLegacyChatIsUsedOnlyWhenCanonicalFieldsAreAbsent() throws {
    let remote = activeRemoteState(
      features: [:],
      restrictions: [:],
      extra: ["canReceiveMessages": .bool(true)]
    )

    let snapshot = mapper.map(
      authUser: testUser("u1"), remote: remote, token: testToken(now: now), fetchedAt: now)
    XCTAssertTrue(snapshot.access.decision(for: .useChat, at: now).isAllowed)
  }

  func testExplicitPermissionDenialWinsOverFeatureFallback() throws {
    let remote = activeRemoteState(
      features: ["canVet": .bool(true)],
      permissions: [testCatalog.manageVet: false]
    )

    let snapshot = mapper.map(
      authUser: testUser("u1"), remote: remote, token: testToken(now: now), fetchedAt: now)
    XCTAssertEqual(snapshot.access.decision(for: .manageVet, at: now).denial, .permissionMissing)
  }

  func testRootLevelBlockIsDenyOnlyCompatibility() throws {
    let remote = activeRemoteState(extra: ["isBlocked": .bool(true)])
    let snapshot = mapper.map(
      authUser: testUser("u1"), remote: remote, token: testToken(now: now), fetchedAt: now)

    XCTAssertTrue(snapshot.access.isBlocked)
    XCTAssertEqual(snapshot.access.decision(for: .useChat, at: now).denial, .accountBlocked)
  }

  func testProfileClaimsCanNeverGrantPrivilegedRole() throws {
    let remote = activeRemoteState(extra: [
      "claims": .object([
        "role": .string("super_admin"),
        "isSuperAdmin": .bool(true),
      ])
    ])
    let snapshot = mapper.map(
      authUser: testUser("u1"), remote: remote, token: testToken(now: now), fetchedAt: now)

    XCTAssertEqual(snapshot.access.role, .user)
    XCTAssertFalse(snapshot.access.isAdmin)
    XCTAssertFalse(snapshot.access.isSuperAdmin)
  }
}
