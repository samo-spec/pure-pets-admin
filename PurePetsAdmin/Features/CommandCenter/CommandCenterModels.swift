import Foundation

enum AttentionSeverity: Int, Equatable, Comparable {
    case critical = 0
    case actionRequired = 1
    case watch = 2
    case normal = 3

    static func < (lhs: AttentionSeverity, rhs: AttentionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum OperationalHealth: Equatable {
    case stable
    case attention(Int)
    case partial(Int)
}

struct AttentionItem: Identifiable, Equatable {
    let id: String
    let domain: String
    let severity: AttentionSeverity
    let titleKey: String
    let detailKey: String
    let count: Int
    let symbol: String
    let route: AdminRoute
    let occurredAt: Date?
    let entityID: String?
    let requiredPermissions: [String]
}

struct OperationsSnapshot: Equatable {
    let activeOrders: Int?
    let awaitingFulfillment: Int?
    let activeDeliveries: Int?
    let pendingProviderApplications: Int?
}

struct BusinessSnapshot: Equatable {
    let listings: Int?
    let users: Int?
    let accessories: Int?
}

struct AdminCommandSnapshot: Equatable {
    let generatedAt: Date
    let health: OperationalHealth
    let attentionItems: [AttentionItem]
    let operations: OperationsSnapshot
    let business: BusinessSnapshot
    let requestedAreas: [String]
    let failedAreas: [String]

    var hasAvailableData: Bool {
        [
            operations.activeOrders,
            operations.awaitingFulfillment,
            operations.activeDeliveries,
            operations.pendingProviderApplications,
            business.listings,
            business.users,
            business.accessories,
        ].contains { $0 != nil }
    }
}

struct CommandMetric: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let value: Int?
    let symbol: String
    let route: AdminRoute?
}
