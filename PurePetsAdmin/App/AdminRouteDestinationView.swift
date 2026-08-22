import SwiftUI

@MainActor
struct AdminRouteDestinationView: View {
    let route: AdminRoute
    let session: AdminSession
    @ObservedObject var router: AdminRouter

    var body: some View {
        AdminLegacyRouteView(
            route: route,
            languageCode: Language.currentLanguageCode(),
            onDismiss: { router.presentedRoute = nil }
        )
    }
}
