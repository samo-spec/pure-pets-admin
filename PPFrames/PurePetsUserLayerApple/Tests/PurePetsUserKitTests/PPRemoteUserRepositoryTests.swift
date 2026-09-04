import XCTest

@testable import PurePetsUserKit

final class PPRemoteUserRepositoryTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_000)

  func testVerifiedSnapshotIsPublishedFromAuthTokenAndRemoteState() async throws {
    let auth = TestAuthSource()
    let store = TestUserStore()
    let repository = PPRemoteUserRepository(
      auth: auth,
      store: store,
      cache: PPMemoryUserCache(),
      mapper: PPUserMapper(permissionCatalog: testCatalog),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    var iterator = repository.events().makeAsyncIterator()
    let user = testUser("u1", name: "Youssef")
    await auth.setToken(testToken(now: now), for: user.id)
    await store.setState(activeRemoteState(), for: user.id)
    await auth.emit(user)

    let event = await iterator.next()
    guard case .updated(let snapshot) = event else {
      return XCTFail("Expected an updated snapshot, received \(String(describing: event))")
    }
    XCTAssertEqual(snapshot.user.id, user.id)
    XCTAssertEqual(snapshot.user.displayName, "Youssef")
    XCTAssertEqual(snapshot.access.trust, .verified)
  }

  func testCrossAccountStaleTokenCannotPublishOldUser() async throws {
    let auth = TestAuthSource()
    let store = TestUserStore()
    let repository = PPRemoteUserRepository(
      auth: auth,
      store: store,
      cache: PPMemoryUserCache(),
      mapper: PPUserMapper(permissionCatalog: testCatalog),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    var iterator = repository.events().makeAsyncIterator()
    let first = testUser("first")
    let second = testUser("second")

    await auth.setToken(testToken(now: now), for: first.id, delay: .milliseconds(300))
    await auth.setToken(
      testToken(role: .admin, admin: true, now: now), for: second.id, delay: .milliseconds(10))
    await store.setState(activeRemoteState(name: "First"), for: first.id)
    await store.setState(activeRemoteState(name: "Second"), for: second.id)

    await auth.emit(first)
    try await Task.sleep(for: .milliseconds(20))
    await auth.emit(second)

    let event = await iterator.next()
    guard case .updated(let snapshot) = event else {
      return XCTFail("Expected second user snapshot")
    }
    XCTAssertEqual(snapshot.user.id, second.id)
    XCTAssertTrue(snapshot.access.isAdmin)

    try await Task.sleep(for: .milliseconds(350))
    let refreshed = try await repository.refresh(forceTokenRefresh: false)
    XCTAssertEqual(refreshed?.user.id, second.id)
    XCTAssertNotEqual(refreshed?.user.id, first.id)
  }

  func testIDTokenEventRefreshesClaimsForSameUser() async throws {
    let auth = TestAuthSource()
    let store = TestUserStore()
    let repository = PPRemoteUserRepository(
      auth: auth,
      store: store,
      cache: PPMemoryUserCache(),
      mapper: PPUserMapper(permissionCatalog: testCatalog),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    var iterator = repository.events().makeAsyncIterator()
    let user = testUser("u1")
    await store.setState(activeRemoteState(), for: user.id)
    await auth.setToken(testToken(role: .admin, admin: true, now: now), for: user.id)
    await auth.emit(user)

    guard case .updated(let first)? = await iterator.next() else {
      return XCTFail("Expected initial update")
    }
    XCTAssertTrue(first.access.isAdmin)

    await auth.setToken(testToken(now: now), for: user.id)
    await auth.emit(user)
    guard case .updated(let second)? = await iterator.next() else {
      return XCTFail("Expected token refresh update")
    }
    XCTAssertFalse(second.access.isAdmin)
  }

  func testSignOutClearsSessionAndEmitsSignedOut() async throws {
    let auth = TestAuthSource()
    let store = TestUserStore()
    let repository = PPRemoteUserRepository(
      auth: auth,
      store: store,
      cache: PPMemoryUserCache(),
      mapper: PPUserMapper(permissionCatalog: testCatalog),
      now: { Date(timeIntervalSince1970: 1_000) }
    )
    var iterator = repository.events().makeAsyncIterator()
    let user = testUser("u1")
    await auth.setToken(testToken(now: now), for: user.id)
    await store.setState(activeRemoteState(), for: user.id)
    await auth.emit(user)
    _ = await iterator.next()

    await auth.emit(nil)
    let event = await iterator.next()
    XCTAssertEqual(event, .signedOut)
  }
}
