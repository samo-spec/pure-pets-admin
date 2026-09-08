import SwiftUI

@MainActor
struct AdminRouteDestinationView: View {
    let route: AdminRoute
    let session: AdminSession
    @ObservedObject var router: AdminRouter

    var body: some View {
        switch route {
        case .chats:
            AdminChatsView {
                router.presentedRoute = nil
            }
        case .staff:
            AdminStaffManagementView {
                router.presentedRoute = nil
            }
        case .users:
            AdminUsersListView {
                router.presentedRoute = nil
            }
        case .branches:
            AdminBranchesView {
                router.presentedRoute = nil
            }
        case .accounting:
            AdminAccountingView(session: session) {
                router.presentedRoute = nil
            }
        case .pointOfSale:
            AdminPOSFastSellView(session: session) {
                router.presentedRoute = nil
            }
        case .pointOfSaleHistory:
            AdminPOSHistoryView(session: session) {
                router.presentedRoute = nil
            }
        case .fulfillment:
            AdminFulfillmentListView(session: session) {
                router.presentedRoute = nil
            }
        case .delivery:
            AdminDeliveryListView {
                router.presentedRoute = nil
            }
        case .payments:
            AdminPaymentListView(session: session) {
                router.presentedRoute = nil
            }
        case .paymentOrder(let orderID):
            AdminPaymentDetailView(orderID: orderID, session: session) {
                router.presentedRoute = nil
            }
        case .paymentSettings:
            AdminPaymentSettingsView(session: session) {
                router.presentedRoute = nil
            }
        case .categories:
            AdminCategoriesView {
                router.presentedRoute = nil
            }
        case .hotel:
            AdminPetsHotelHubView {
                router.presentedRoute = nil
            }
        case .homeControl:
            AdminHomeControlView {
                router.presentedRoute = nil
            }
        case .moderation:
            AdminModerationView {
                router.presentedRoute = nil
            }
        case .notificationComposer:
            AdminNotificationComposerView {
                router.presentedRoute = nil
            }
        case .notificationSettings:
            AdminNotificationSettingsView {
                router.presentedRoute = nil
            }
        case .accessories:
            PPInventoryListView(kind: .typeAccessory, onDismiss: {
                router.presentedRoute = nil
            })
        case .food:
            PPInventoryListView(kind: .typeFood, onDismiss: {
                router.presentedRoute = nil
            })
        case .livePets:
            PPInventoryListView(kind: .typeLivePets, onDismiss: {
                router.presentedRoute = nil
            })
        case .providerApplications:
            AdminProvidersView(initialTab: .applications) {
                router.presentedRoute = nil
            }
        case .providerPlans:
            AdminProvidersView(initialTab: .plans) {
                router.presentedRoute = nil
            }
        case .providerFeatures:
            AdminProvidersView(initialTab: .features) {
                router.presentedRoute = nil
            }
        case .providerAccounting:
            AdminProvidersView(initialTab: .accounting) {
                router.presentedRoute = nil
            }
        case .veterinarians:
            PPVetsListView(onDismiss: {
                router.presentedRoute = nil
            })
        default:
            AdminLegacyRouteView(
                route: route,
                languageCode: Language.currentLanguageCode(),
                onDismiss: { router.presentedRoute = nil }
            )
        }
    }
}
