import Foundation

enum AdminTab: String, CaseIterable, Identifiable {
    case command
    case work
    case operations
    case customers
    case more

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .command: return "CommandCenter_Tab_Command"
        case .work: return "CommandCenter_Tab_Work"
        case .operations: return "CommandCenter_Tab_Operations"
        // Keep the persisted tab identifier stable while naming the mixed
        // users, staff, and conversations lane for what it actually contains.
        case .customers: return "CommandCenter_Tab_People"
        case .more: return "CommandCenter_Tab_More"
        }
    }

    var symbol: String {
        switch self {
        case .command: return "square.grid.2x2"
        case .work: return "briefcase"
        case .operations: return "slider.horizontal.3"
        case .customers: return "person.2"
        case .more: return "ellipsis.circle"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .command: return "square.grid.2x2.fill"
        case .work: return "briefcase.fill"
        case .operations: return "slider.horizontal.3"
        case .customers: return "person.2.fill"
        case .more: return "ellipsis.circle.fill"
        }
    }
}

extension AdminTab {
    func routes(for session: AdminSession) -> [AdminRoute] {
        switch self {
        case .command:
            return []
        case .work:
            return [
                .payments, .paymentSettings, .fulfillment,
                .pointOfSale, .pointOfSaleHistory,
                .accessories, .food, .livePets
            ].filter { $0.isAuthorized(for: session) }
        case .operations:
            return [
                .delivery, .providerApplications, .providerPlans,
                .providerFeatures, .providerAccounting, .branches,
                .agents, .homeControl, .services, .veterinarians,
                .moderation
            ].filter { $0.isAuthorized(for: session) }
        case .customers:
            return [
                .users, .staff, .chats
            ].filter { $0.isAuthorized(for: session) }
        case .more:
            return [
                .account, .notifications, .notificationComposer,
                .notificationSettings, .accounting, .audit,
                .categories, .banners, .listings
            ].filter { $0.isAuthorized(for: session) }
        }
    }

    func isAuthorized(for session: AdminSession) -> Bool {
        switch self {
        case .command:
            return session.hasAnyPermission(["admin.all", "command.center", "dashboard.view"]) ||
                   session.grantsAllPermissions ||
                   session.roleIdentifier == "super_admin" ||
                   session.roleIdentifier == "owner" ||
                   session.roleIdentifier == "operations_manager"
        case .work:
            return !routes(for: session).isEmpty
        case .operations:
            return !routes(for: session).isEmpty
        case .customers:
            return !routes(for: session).isEmpty
        case .more:
            return true
        }
    }
}
