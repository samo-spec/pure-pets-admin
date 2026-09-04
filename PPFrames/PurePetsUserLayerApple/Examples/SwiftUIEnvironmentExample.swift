#if canImport(SwiftUI)
  import SwiftUI
  import PurePetsUserKit

  @available(iOS 17.0, *)
  struct PurePetsRootView: View {
    @State private var currentUser: PPObservableUserSession

    init(session: PPUserSession) {
      _currentUser = State(initialValue: PPObservableUserSession(session: session))
    }

    var body: some View {
      ContentView()
        .environment(currentUser)
        .task { currentUser.start() }
    }
  }

  @available(iOS 17.0, *)
  private struct ContentView: View {
    @Environment(PPObservableUserSession.self) private var currentUser

    var body: some View {
      Text(currentUser.user?.displayName ?? "")
    }
  }
#endif
