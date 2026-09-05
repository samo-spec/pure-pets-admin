import SwiftUI

@MainActor
struct AdminRouteDestinationView: View {
    let route: AdminRoute
    let session: AdminSession
    @ObservedObject var router: AdminRouter

    var body: some View {
        switch route {
        case .notificationComposer:
            AdminNotificationComposerView {
                router.presentedRoute = nil
            }
        case .notificationSettings:
            AdminNotificationSettingsView {
                router.presentedRoute = nil
            }
        default:
            AdminLegacyRouteView(
                route: route,
                languageCode: Language.currentLanguageCode(),
                onDismiss: { router.presentedRoute = nil }
            )
        }
    }
}
