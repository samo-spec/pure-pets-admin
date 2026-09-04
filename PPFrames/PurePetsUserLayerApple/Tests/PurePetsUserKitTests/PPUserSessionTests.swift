import XCTest

@testable import PurePetsUserKit

@MainActor
final class PPUserSessionTests: XCTestCase {
  func testSessionPublishesOneSourceOfTruth() async {
    let repository = TestRepository()
    let session = PPUserSession(repository: repository)
    var states = session.states().makeAsyncIterator()
    _ = await states.next()  // idle
    session.start()
    _ = await states.next()  // loading without a snapshot

    let snapshot = PPCurrentUserSnapshot(
      user: PPUser(id: PPUserID("u1")!, username: "Pure Pets"),
      access: .unknown()
    )
    await repository.emit(.updated(snapshot))

    guard case .loading(let previous)? = await states.next() else {
      return XCTFail("Cached/unverified access must remain loading")
    }
    XCTAssertEqual(previous?.user.id.rawValue, "u1")
  }

  func testSessionForwardsCapabilityDecisions() async {
    let repository = TestRepository()
    let session = PPUserSession(repository: repository)
    XCTAssertEqual(session.decision(for: .useChat).denial, .accessUnverified)
  }
}

private actor TestRepository: PPUserRepository {
  private let stream: AsyncStream<PPUserRepositoryEvent>
  private let continuation: AsyncStream<PPUserRepositoryEvent>.Continuation

  init() {
    let pair = AsyncStream<PPUserRepositoryEvent>.makeStream(bufferingPolicy: .bufferingNewest(20))
    stream = pair.stream
    continuation = pair.continuation
  }

  nonisolated func events() -> AsyncStream<PPUserRepositoryEvent> {
    stream
  }

  func refresh(forceTokenRefresh: Bool) async throws -> PPCurrentUserSnapshot? { nil }
  func updateProfile(_ patch: PPUserProfilePatch) async throws {}
  func emit(_ event: PPUserRepositoryEvent) { continuation.yield(event) }
}
