//
//  AdminRoleRankSecurityLevelsView.swift
//  PurePetsAdmin
//
//  NextGen V6 Sovereign Role Rank & Security Clearance Matrix.
//  Category-defining access governance, numerical command hierarchy,
//  multi-tier clearance levels, live staff distribution, and audit logging.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - 1. Security Clearance Tier Definition

public enum SecurityClearanceTier: String, CaseIterable, Identifiable, Sendable {
    case tier1 = "tier_1"
    case tier2 = "tier_2"
    case tier3 = "tier_3"
    case tier4 = "tier_4"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tier1:
            return Language.get("RoleRank_Tier_1", alter: "الرتبة السيادية العليا • Tier 1")
        case .tier2:
            return Language.get("RoleRank_Tier_2", alter: "قيادة العمليات التنفيذية • Tier 2")
        case .tier3:
            return Language.get("RoleRank_Tier_3", alter: "الخدمات والدعم الميداني • Tier 3")
        case .tier4:
            return Language.get("RoleRank_Tier_4", alter: "الرصد والمراقبة المقيدة • Tier 4")
        }
    }

    public var shortName: String {
        switch self {
        case .tier1: return "Tier 1 — Sovereign"
        case .tier2: return "Tier 2 — Directorate"
        case .tier3: return "Tier 3 — Field Ops"
        case .tier4: return "Tier 4 — Observers"
        }
    }

    public var localizedDescription: String {
        switch self {
        case .tier1:
            return Language.isRTL()
                ? "سلطة سيادية عليا تشمل الهيكلة المالية وإدارة النظام والسياسات الأمنية"
                : "Supreme sovereign authority, financial root control, and core platform governance"
        case .tier2:
            return Language.isRTL()
                ? "قيادة وإشراف تنفيذي على العمليات المتعددة والمخزون والخزينة والتوصيل"
                : "Directorate leadership over operations, branch stores, inventory & payments"
        case .tier3:
            return Language.isRTL()
                ? "تنفيذ الخدمات التشغيلية المباشرة والدعم الفني ونقاط البيع ومناولة المستودع"
                : "Direct customer service, POS cashier desks, logistics, and field support"
        case .tier4:
            return Language.isRTL()
                ? "رصد القياسات التشغيلية والتقارير دون أي صلاحيات لإجراء تعديلات"
                : "Read-only telemetry, operational observation, and restricted audit view"
        }
    }

    public var defaultRankFloor: Int {
        switch self {
        case .tier1: return 90
        case .tier2: return 65
        case .tier3: return 30
        case .tier4: return 1
        }
    }

    public var primaryColor: Color {
        switch self {
        case .tier1: return Color(red: 0.82, green: 0.12, blue: 0.28) // Royal Crimson
        case .tier2: return Color(red: 0.12, green: 0.52, blue: 0.88) // Electric Sapphire
        case .tier3: return Color(red: 0.12, green: 0.72, blue: 0.52) // Vivid Emerald
        case .tier4: return Color(red: 0.48, green: 0.54, blue: 0.64) // Steel Slate
        }
    }

    public var secondaryColor: Color {
        switch self {
        case .tier1: return Color(red: 0.95, green: 0.75, blue: 0.25) // Imperial Gold
        case .tier2: return Color(red: 0.25, green: 0.72, blue: 0.98) // Cyan Frost
        case .tier3: return Color(red: 0.55, green: 0.35, blue: 0.92) // Purple Orchid
        case .tier4: return Color(red: 0.65, green: 0.70, blue: 0.78) // Muted Ash
        }
    }

    public var iconName: String {
        switch self {
        case .tier1: return "crown.fill"
        case .tier2: return "shield.checkered"
        case .tier3: return "person.badge.shield.checkmark.fill"
        case .tier4: return "eye.fill"
        }
    }

    public static func tierForRank(_ rank: Int) -> SecurityClearanceTier {
        if rank >= 90 { return .tier1 }
        if rank >= 65 { return .tier2 }
        if rank >= 30 { return .tier3 }
        return .tier4
    }
}

// MARK: - 2. Canonical Platform Permission Catalog (18 Modules)

public struct SecurityPermissionItem: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let titleAr: String
    public let titleEn: String
    public let moduleKey: String
    public let isHighRisk: Bool

    public var localizedTitle: String {
        Language.isRTL() ? titleAr : titleEn
    }
}

public struct SecurityPermissionModule: Identifiable, Hashable, Sendable {
    public var id: String { key }
    public let key: String
    public let titleAr: String
    public let titleEn: String
    public let icon: String
    public let permissions: [SecurityPermissionItem]

    public var localizedTitle: String {
        Language.isRTL() ? titleAr : titleEn
    }
}

public final class SecurityPermissionCatalog: @unchecked Sendable {
    public static let shared = SecurityPermissionCatalog()

    public let modules: [SecurityPermissionModule]
    public let allPermissions: [SecurityPermissionItem]
    public let totalPermissionsCount: Int

    private init() {
        let list: [SecurityPermissionModule] = [
            SecurityPermissionModule(
                key: "dashboard",
                titleAr: "لوحة التحكم المركزية",
                titleEn: "Central Dashboard",
                icon: "gauge.with.dots.needle.50percent",
                permissions: [
                    SecurityPermissionItem(key: "dashboard.view", titleAr: "عرض مؤشرات لوحة التحكم", titleEn: "View Dashboard Metrics", moduleKey: "dashboard", isHighRisk: false)
                ]
            ),
            SecurityPermissionModule(
                key: "staff",
                titleAr: "إدارة فريق العمل والصلاحيات",
                titleEn: "Staff & Access Control",
                icon: "person.2.badge.gearshape.fill",
                permissions: [
                    SecurityPermissionItem(key: "staff.view", titleAr: "عرض سجلات الموظفين", titleEn: "View Staff Roster", moduleKey: "staff", isHighRisk: false),
                    SecurityPermissionItem(key: "staff.manage", titleAr: "إدارة وتعيين وتعديل الموظفين والرتب", titleEn: "Manage Staff, Roles & Ranks", moduleKey: "staff", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "users",
                titleAr: "حسابات العملاء والملفات",
                titleEn: "Customer Profiles & Accounts",
                icon: "person.crop.circle.badge.checkmark",
                permissions: [
                    SecurityPermissionItem(key: "users.view", titleAr: "عرض قائمة العملاء", titleEn: "View Customers", moduleKey: "users", isHighRisk: false),
                    SecurityPermissionItem(key: "users.manage", titleAr: "تعديل وتوثيق حسابات العملاء", titleEn: "Manage & Verify Customers", moduleKey: "users", isHighRisk: false),
                    SecurityPermissionItem(key: "users.block", titleAr: "حظر وإلغاء حظر العملاء", titleEn: "Block / Unblock Customers", moduleKey: "users", isHighRisk: true),
                    SecurityPermissionItem(key: "users.features.manage", titleAr: "إدارة ميزات الحسابات التجريبية", titleEn: "Manage Account Feature Flags", moduleKey: "users", isHighRisk: false),
                    SecurityPermissionItem(key: "users.restrictions.manage", titleAr: "فرض قيود أمنية على العملاء", titleEn: "Manage Security Restrictions", moduleKey: "users", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "stock",
                titleAr: "المخزون والمنتجات والمستلزمات",
                titleEn: "Stock, Products & Inventory",
                icon: "cube.box.fill",
                permissions: [
                    SecurityPermissionItem(key: "stock.view", titleAr: "عرض مستويات المخزون والأسعار", titleEn: "View Stock & Pricing", moduleKey: "stock", isHighRisk: false),
                    SecurityPermissionItem(key: "stock.manage", titleAr: "تعديل الكميات والباركود والأسعار", titleEn: "Manage Quantities & Barcodes", moduleKey: "stock", isHighRisk: false),
                    SecurityPermissionItem(key: "stock.create", titleAr: "إضافة منتجات ومستلزمات جديدة", titleEn: "Create New Products", moduleKey: "stock", isHighRisk: false),
                    SecurityPermissionItem(key: "stock.delete", titleAr: "حذف المنتجات من الكتالوج", titleEn: "Delete Products", moduleKey: "stock", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "listings",
                titleAr: "إعلانات البيع والتبني والحيوانات",
                titleEn: "Pet Listings & Adoptions",
                icon: "pawprint.fill",
                permissions: [
                    SecurityPermissionItem(key: "listings.view", titleAr: "عرض إعلانات المجتمع والتبني", titleEn: "View Pet Listings", moduleKey: "listings", isHighRisk: false),
                    SecurityPermissionItem(key: "listings.manage", titleAr: "تعديل وتفعيل إعلانات الحيوانات", titleEn: "Manage Pet Listings", moduleKey: "listings", isHighRisk: false),
                    SecurityPermissionItem(key: "listings.moderate", titleAr: "إجازة أو رفض وحذف الإعلانات المخالفة", titleEn: "Moderate & Remove Listings", moduleKey: "listings", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "payments",
                titleAr: "الخزينة والمدفوعات والاسترداد",
                titleEn: "Treasury, Payments & Refunds",
                icon: "creditcard.fill",
                permissions: [
                    SecurityPermissionItem(key: "payments.view", titleAr: "عرض حركات الدفع والفواتير", titleEn: "View Transactions & Invoices", moduleKey: "payments", isHighRisk: false),
                    SecurityPermissionItem(key: "payments.manage", titleAr: "تسوية الحسابات المالية ونقاط البيع", titleEn: "Manage Financial Settlements", moduleKey: "payments", isHighRisk: true),
                    SecurityPermissionItem(key: "payments.refund", titleAr: "إصدار وتفويض استرداد المبالغ", titleEn: "Authorize & Issue Refunds", moduleKey: "payments", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "delivery",
                titleAr: "العمليات اللوجستية والتوصيل",
                titleEn: "Logistics & Delivery Dispatch",
                icon: "box.truck.fill",
                permissions: [
                    SecurityPermissionItem(key: "delivery.view", titleAr: "عرض رحلات وتتبع الشحنات", titleEn: "View Delivery Shipments", moduleKey: "delivery", isHighRisk: false),
                    SecurityPermissionItem(key: "delivery.dispatch", titleAr: "جدولة وتعيين السائقين والمناديب", titleEn: "Dispatch & Assign Drivers", moduleKey: "delivery", isHighRisk: false),
                    SecurityPermissionItem(key: "delivery.override", titleAr: "التدخل السيادي وإعادة التوجيه", titleEn: "Sovereign Delivery Override", moduleKey: "delivery", isHighRisk: true),
                    SecurityPermissionItem(key: "delivery.cod.reconcile", titleAr: "تسوية مبالغ الدفع عند الاستلام (COD)", titleEn: "Reconcile Cash on Delivery", moduleKey: "delivery", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "pos",
                titleAr: "نقاط البيع والمبيعات المباشرة",
                titleEn: "Point of Sale (POS)",
                icon: "cart.fill",
                permissions: [
                    SecurityPermissionItem(key: "pos.view", titleAr: "عرض شاشات البيع المباشر", titleEn: "View POS Screen", moduleKey: "pos", isHighRisk: false),
                    SecurityPermissionItem(key: "pos.sell", titleAr: "إجراء عمليات البيع وإصدار الفواتير", titleEn: "Execute Sales & Receipts", moduleKey: "pos", isHighRisk: false),
                    SecurityPermissionItem(key: "pos.history", titleAr: "استعراض سجل مبيعات الصندوق", titleEn: "Review Register History", moduleKey: "pos", isHighRisk: false)
                ]
            ),
            SecurityPermissionModule(
                key: "branches",
                titleAr: "الفروع ومواقع العمليات",
                titleEn: "Store Branches & Hubs",
                icon: "building.2.fill",
                permissions: [
                    SecurityPermissionItem(key: "branches.view", titleAr: "عرض بيانات وسجلات الفروع", titleEn: "View Branches", moduleKey: "branches", isHighRisk: false),
                    SecurityPermissionItem(key: "branches.manage", titleAr: "تعديل وإضافة الفروع وساعات العمل", titleEn: "Manage Branch Hubs", moduleKey: "branches", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "support",
                titleAr: "محادثات الدعم الفني والشكاوى",
                titleEn: "Support Chats & Tickets",
                icon: "headphones",
                permissions: [
                    SecurityPermissionItem(key: "support.view", titleAr: "عرض محادثات واستفسارات العملاء", titleEn: "View Support Inquiries", moduleKey: "support", isHighRisk: false),
                    SecurityPermissionItem(key: "support.manage", titleAr: "الرد وحل النزاعات وإغلاق التذاكر", titleEn: "Reply & Resolve Tickets", moduleKey: "support", isHighRisk: false)
                ]
            ),
            SecurityPermissionModule(
                key: "services",
                titleAr: "الخدمات والمواعيد والعيادات",
                titleEn: "Services, Clinics & Bookings",
                icon: "cross.case.fill",
                permissions: [
                    SecurityPermissionItem(key: "services.view", titleAr: "عرض مواعيد العيادات والخدمات", titleEn: "View Booked Appointments", moduleKey: "services", isHighRisk: false),
                    SecurityPermissionItem(key: "services.manage", titleAr: "إدارة أسعار وباقات الخدمات", titleEn: "Manage Service Packages", moduleKey: "services", isHighRisk: false)
                ]
            ),
            SecurityPermissionModule(
                key: "accounting",
                titleAr: "المحاسبة والدفاتر المالية والضرائب",
                titleEn: "Accounting, Ledgers & Tax",
                icon: "chart.line.uptrend.xyaxis",
                permissions: [
                    SecurityPermissionItem(key: "accounting.view", titleAr: "عرض القيود المحاسبية وميزان المراجعة", titleEn: "View Accounting Books", moduleKey: "accounting", isHighRisk: false),
                    SecurityPermissionItem(key: "accounting.manage", titleAr: "إقفال الفترات وإجراء القيود اليومية", titleEn: "Post Journals & Close Fiscal Periods", moduleKey: "accounting", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "hotel",
                titleAr: "فندق الحيوانات الأليفة والإقامة",
                titleEn: "Pets Hotel & Boarding",
                icon: "bed.double.fill",
                permissions: [
                    SecurityPermissionItem(key: "hotel.view", titleAr: "عرض حجوزات وغرف الفندق", titleEn: "View Hotel Stays", moduleKey: "hotel", isHighRisk: false),
                    SecurityPermissionItem(key: "hotel.manage", titleAr: "إدارة الحجوزات وخطط الرعاية والتغذية", titleEn: "Manage Hotel Care Plans", moduleKey: "hotel", isHighRisk: false),
                    SecurityPermissionItem(key: "hotel.checkin", titleAr: "تسجيل دخول وخروج النزلاء", titleEn: "Check-in & Check-out Guests", moduleKey: "hotel", isHighRisk: false)
                ]
            ),
            SecurityPermissionModule(
                key: "categories",
                titleAr: "شجرة التصنيفات والأنواع",
                titleEn: "Taxonomy & Categories",
                icon: "folder.fill.badge.gearshape",
                permissions: [
                    SecurityPermissionItem(key: "categories.view", titleAr: "عرض الأنواع والتصنيفات", titleEn: "View Categories", moduleKey: "categories", isHighRisk: false),
                    SecurityPermissionItem(key: "categories.manage", titleAr: "إضافة وتعديل التصنيفات وسلالات الحيوانات", titleEn: "Manage Breeds & Taxonomies", moduleKey: "categories", isHighRisk: false)
                ]
            ),
            SecurityPermissionModule(
                key: "audit",
                titleAr: "سجل التدقيق الرقابي والعمليات",
                titleEn: "Immutable Audit Trail",
                icon: "shield.lefthalf.filled",
                permissions: [
                    SecurityPermissionItem(key: "audit.view", titleAr: "مراجعة وفحص السجل الأمني والرقابي", titleEn: "Inspect Security Audit Trail", moduleKey: "audit", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "moderation",
                titleAr: "الرقابة وفحص المحتوى والبلاغات",
                titleEn: "Content Moderation & Reports",
                icon: "exclamationmark.shield.fill",
                permissions: [
                    SecurityPermissionItem(key: "moderation.view", titleAr: "عرض بلاغات المحتوى غير الملائم", titleEn: "View Flagged Reports", moduleKey: "moderation", isHighRisk: false),
                    SecurityPermissionItem(key: "moderation.manage", titleAr: "اتخاذ إجراءات الحظر والإزالة الفورية", titleEn: "Enforce Content Takedowns", moduleKey: "moderation", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "notifications",
                titleAr: "الإشعارات والتنبيهات المباشرة",
                titleEn: "Broadcast Notifications",
                icon: "bell.badge.fill",
                permissions: [
                    SecurityPermissionItem(key: "notifications.view", titleAr: "عرض سجل الإشعارات المرسلة", titleEn: "View Push Notification History", moduleKey: "notifications", isHighRisk: false),
                    SecurityPermissionItem(key: "notifications.send", titleAr: "إرسال إشعارات جماعية للعملاء", titleEn: "Broadcast Push Notifications", moduleKey: "notifications", isHighRisk: true)
                ]
            ),
            SecurityPermissionModule(
                key: "settings",
                titleAr: "إعدادات المنصة والسياسات",
                titleEn: "Platform System Settings",
                icon: "gearshape.2.fill",
                permissions: [
                    SecurityPermissionItem(key: "settings.view", titleAr: "عرض سياسات وإعدادات النظام", titleEn: "View Platform Settings", moduleKey: "settings", isHighRisk: false),
                    SecurityPermissionItem(key: "settings.manage", titleAr: "تعديل إعدادات بوابات الدفع والتوصيل", titleEn: "Configure Gateway & System Rules", moduleKey: "settings", isHighRisk: true)
                ]
            )
        ]

        self.modules = list
        var flat: [SecurityPermissionItem] = []
        for m in list {
            flat.append(contentsOf: m.permissions)
        }
        self.allPermissions = flat
        self.totalPermissionsCount = flat.count
    }
}

// MARK: - 3. Unified Platform Role Model

public struct PlatformRoleModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let key: String
    public let titleAr: String
    public let titleEn: String
    public let descAr: String
    public let descEn: String
    public let rank: Int
    public let clearanceTier: SecurityClearanceTier
    public let isBuiltIn: Bool
    public let iconName: String
    public let accentHex: String?
    public let permissions: Set<String>
    public let assignedStaffUids: Set<String>

    public var localizedTitle: String {
        Language.isRTL() ? titleAr : titleEn
    }

    public var localizedDesc: String {
        Language.isRTL() ? descAr : descEn
    }

    public var accentColor: Color {
        if let hex = accentHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return clearanceTier.primaryColor
    }

    public var coveragePercentage: Double {
        let total = Double(SecurityPermissionCatalog.shared.totalPermissionsCount)
        guard total > 0 else { return 0 }
        return Double(permissions.count) / total
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(rank)
        hasher.combine(permissions)
        hasher.combine(assignedStaffUids)
    }

    public static func == (lhs: PlatformRoleModel, rhs: PlatformRoleModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.rank == rhs.rank &&
        lhs.permissions == rhs.permissions &&
        lhs.assignedStaffUids == rhs.assignedStaffUids
    }
}

// MARK: - 4. ViewModel (Reactive Firestore IAM Stream & Mutations)

@MainActor
public final class AdminRoleRankViewModel: ObservableObject {
    @Published public private(set) var allRoles: [PlatformRoleModel] = []
    @Published public private(set) var filteredRoles: [PlatformRoleModel] = []
    @Published public private(set) var staffMembers: [PPStaffDoc] = []
    @Published public var selectedTierFilter: String = "all"
    @Published public var searchText: String = ""
    @Published public private(set) var isLoading: Bool = true
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var canManage: Bool = false

    // Sheets & Dialogs State
    @Published public var inspectingMatrixRole: PlatformRoleModel? = nil
    @Published public var inspectingStaffRole: PlatformRoleModel? = nil
    @Published public var editingRole: PlatformRoleModel? = nil
    @Published public var isShowingEditor: Bool = false
    @Published public var roleToDelete: PlatformRoleModel? = nil
    @Published public var deletionErrorMessage: String? = nil
    @Published public var toastMessage: String? = nil

    private nonisolated(unsafe) var staffListener: (any ListenerRegistration)?
    private nonisolated(unsafe) var customRolesListener: (any ListenerRegistration)?

    public init() {
        evaluatePermissions()
    }

    deinit {
        staffListener?.remove()
        customRolesListener?.remove()
    }

    public func evaluatePermissions() {
        let staff = PPStaffAuth.shared().cachedCurrentStaff
        self.canManage = staff?.hasPermission(kStaffPermStaffManage) ?? false
    }

    public func startListening() {
        evaluatePermissions()
        isLoading = true
        errorMessage = nil

        // Listen to Staff Roster for live role assignment counts
        staffListener?.remove()
        staffListener = PPStaffAuth.shared().listenAllStaff { [weak self] docs, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let docs {
                    self.staffMembers = docs
                    self.recomputeRoles()
                }
            }
        }

        // Listen to Firestore `staff_roles` collection
        customRolesListener?.remove()
        let db = Firestore.firestore()
        customRolesListener = db.collection("staff_roles").addSnapshotListener { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.parseCustomRoles(snapshot?.documents ?? [])
            }
        }
    }

    public func stopListening() {
        staffListener?.remove()
        customRolesListener?.remove()
    }

    private var rawCustomRoleDocs: [QueryDocumentSnapshot] = []

    private func parseCustomRoles(_ docs: [QueryDocumentSnapshot]) {
        self.rawCustomRoleDocs = docs
        recomputeRoles()
    }

    private func recomputeRoles() {
        var roles: [PlatformRoleModel] = []

        // Map assigned staff by role identifier
        var staffRoleMap: [String: Set<String>] = [:]
        for member in staffMembers {
            let roleId = (member.roleIdentifier ?? member.role.rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !roleId.isEmpty else { continue }
            staffRoleMap[roleId, default: []].insert(member.uid)
            if roleId.hasPrefix("custom_") {
                let stripped = String(roleId.dropFirst(7))
                staffRoleMap[stripped, default: []].insert(member.uid)
            }
        }

        // 1. Built-in System Foundation Roles
        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.superAdmin.rawValue,
                key: PPStaffRole.superAdmin.rawValue,
                titleAr: "مدير النظام السيادي",
                titleEn: "Super Administrator",
                descAr: "تحكّم كامل في جميع وحدات المنصة وإدارة الموظفين والسياسات الأمنية الحاكمة",
                descEn: "Supreme platform control, cryptographic authority, IAM and policy governance",
                rank: 100,
                clearanceTier: .tier1,
                isBuiltIn: true,
                iconName: "crown.fill",
                accentHex: "#B81430",
                permissions: Set(SecurityPermissionCatalog.shared.allPermissions.map { $0.key }),
                assignedStaffUids: staffRoleMap[PPStaffRole.superAdmin.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.owner.rawValue,
                key: PPStaffRole.owner.rawValue,
                titleAr: "المالك السيادي",
                titleEn: "Platform Owner",
                descAr: "صلاحيات سيادية مطلقة تشمل الهيكلة المالية وإدارة النظام وتراخيص الكيانات",
                descEn: "Absolute enterprise authority, banking settlement, entity ownership",
                rank: 95,
                clearanceTier: .tier1,
                isBuiltIn: true,
                iconName: "star.fill",
                accentHex: "#D4AF37",
                permissions: Set(SecurityPermissionCatalog.shared.allPermissions.map { $0.key }),
                assignedStaffUids: staffRoleMap[PPStaffRole.owner.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.operationsManager.rawValue,
                key: PPStaffRole.operationsManager.rawValue,
                titleAr: "مدير العمليات التنفيذية",
                titleEn: "Operations Director",
                descAr: "إشراف شامل على تدفق الطلبات، مراقبة المخزون، التوصيل، والتدخل السيادي",
                descEn: "Executive director of fulfillment, branch workflows, dispatch and inventory",
                rank: 85,
                clearanceTier: .tier2,
                isBuiltIn: true,
                iconName: "gearshape.2.fill",
                accentHex: "#1472B8",
                permissions: Set([
                    "dashboard.view", "staff.view", "users.view", "users.manage", "stock.view", "stock.manage", "stock.create",
                    "listings.view", "listings.manage", "listings.moderate", "payments.view", "delivery.view", "delivery.dispatch",
                    "delivery.override", "delivery.cod.reconcile", "pos.view", "pos.sell", "pos.history", "branches.view",
                    "support.view", "support.manage", "services.view", "services.manage", "hotel.view", "hotel.manage",
                    "categories.view", "categories.manage", "moderation.view", "moderation.manage", "notifications.view", "notifications.send"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.operationsManager.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.branchManager.rawValue,
                key: PPStaffRole.branchManager.rawValue,
                titleAr: "مدير الفرع الميداني",
                titleEn: "Branch General Manager",
                descAr: "حوكمة وإدارة الفرع ومخزون المستودع وصندوق المبيعات وفريق الصالة",
                descEn: "Full management of local branch hub, stock transfers, registers and local staff",
                rank: 78,
                clearanceTier: .tier2,
                isBuiltIn: true,
                iconName: "building.2.fill",
                accentHex: "#2563EB",
                permissions: Set([
                    "dashboard.view", "staff.view", "users.view", "stock.view", "stock.manage", "payments.view",
                    "pos.view", "pos.sell", "pos.history", "branches.view", "hotel.view", "hotel.manage",
                    "hotel.checkin", "services.view", "support.view"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.branchManager.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.inventoryManager.rawValue,
                key: PPStaffRole.inventoryManager.rawValue,
                titleAr: "مدير سلاسل الإمداد والمخزون",
                titleEn: "Inventory & Supply Director",
                descAr: "إدارة كتالوج المنتجات والمستلزمات، توليد الباركود، التسعير، والتوريدات",
                descEn: "Catalog management, wholesale pricing, barcode generation, inventory transfers",
                rank: 72,
                clearanceTier: .tier2,
                isBuiltIn: true,
                iconName: "cube.box.fill",
                accentHex: "#EA580C",
                permissions: Set([
                    "dashboard.view", "stock.view", "stock.manage", "stock.create", "stock.delete",
                    "categories.view", "categories.manage", "branches.view"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.inventoryManager.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.paymentsManager.rawValue,
                key: PPStaffRole.paymentsManager.rawValue,
                titleAr: "مدير الخزينة والمدفوعات",
                titleEn: "Treasury & Payments Director",
                descAr: "إدارة نقاط البيع، تسوية الحسابات، تفويض استرداد المبالغ، والتدقيق المالي",
                descEn: "Payment gateways, POS settlements, transaction disputes, refund authorization",
                rank: 70,
                clearanceTier: .tier2,
                isBuiltIn: true,
                iconName: "creditcard.fill",
                accentHex: "#0D9488",
                permissions: Set([
                    "dashboard.view", "payments.view", "payments.manage", "payments.refund",
                    "accounting.view", "pos.view", "pos.history", "delivery.cod.reconcile"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.paymentsManager.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.accountant.rawValue,
                key: PPStaffRole.accountant.rawValue,
                titleAr: "المحاسب المالي القانوني",
                titleEn: "Certified Accountant",
                descAr: "مراجعة الدفاتر، القيود اليومية، ميزان المراجعة، والإقرارات الضريبية",
                descEn: "Ledger posting, journal auditing, tax filing, balance reconciliation",
                rank: 65,
                clearanceTier: .tier2,
                isBuiltIn: true,
                iconName: "chart.line.uptrend.xyaxis",
                accentHex: "#4F46E5",
                permissions: Set([
                    "dashboard.view", "accounting.view", "accounting.manage", "payments.view",
                    "reports.view", "reports.export"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.accountant.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.supportAgent.rawValue,
                key: PPStaffRole.supportAgent.rawValue,
                titleAr: "أخصائي الدعم وخدمة العملاء",
                titleEn: "Customer Care Specialist",
                descAr: "الرد على محادثات العملاء، متابعة الشكاوى، وتقديم حلول الخدمة المباشرة",
                descEn: "Live customer chat handling, dispute mediation, ticket escalations",
                rank: 45,
                clearanceTier: .tier3,
                isBuiltIn: true,
                iconName: "headphones",
                accentHex: "#7C3AED",
                permissions: Set([
                    "support.view", "support.manage", "users.view", "listings.view", "hotel.view", "services.view"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.supportAgent.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.warehouse.rawValue,
                key: PPStaffRole.warehouse.rawValue,
                titleAr: "أخصائي مناولة المستودع والتجهيز",
                titleEn: "Warehouse Fulfillment Officer",
                descAr: "تجهيز الشحنات، الفرز والتعبئة، مسح الباركود، وتسليم مناديب التوصيل",
                descEn: "Order pick-pack, barcode scan verification, courier dispatch handover",
                rank: 35,
                clearanceTier: .tier3,
                isBuiltIn: true,
                iconName: "shippingbox.fill",
                accentHex: "#059669",
                permissions: Set([
                    "stock.view", "stock.manage", "delivery.view", "delivery.dispatch"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.warehouse.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.sales.rawValue,
                key: PPStaffRole.sales.rawValue,
                titleAr: "أمين صندوق ومبيعات الصالة",
                titleEn: "POS Cashier & Retail Floor",
                descAr: "إتمام عمليات البيع السريع وإصدار الفواتير وتسجيل بيانات الحيوانات المباعة",
                descEn: "POS cashier checkout, receipt printing, customer order intake",
                rank: 30,
                clearanceTier: .tier3,
                isBuiltIn: true,
                iconName: "cart.fill",
                accentHex: "#10B981",
                permissions: Set([
                    "pos.view", "pos.sell", "pos.history", "stock.view", "users.view"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.sales.rawValue] ?? []
            )
        )

        roles.append(
            PlatformRoleModel(
                id: PPStaffRole.viewer.rawValue,
                key: PPStaffRole.viewer.rawValue,
                titleAr: "مراقب قياسات الأداء والتقارير",
                titleEn: "Telemetry & Performance Observer",
                descAr: "اطلاع ورصد فقط على المؤشرات التشغيلية والتقارير دون إمكانية التعديل",
                descEn: "Restricted read-only operational telemetry and business dashboard observer",
                rank: 10,
                clearanceTier: .tier4,
                isBuiltIn: true,
                iconName: "eye.fill",
                accentHex: "#64748B",
                permissions: Set([
                    "dashboard.view", "reports.view"
                ]),
                assignedStaffUids: staffRoleMap[PPStaffRole.viewer.rawValue] ?? []
            )
        )

        // 2. Custom Roles Parsed from Firestore
        for doc in rawCustomRoleDocs {
            let data = doc.data()
            let nameMap = data["name"] as? [String: String] ?? [:]
            let descMap = data["description"] as? [String: String] ?? [:]
            let perms = data["permissions"] as? [String] ?? []
            let rankNum = (data["rank"] as? NSNumber)?.intValue ?? 50
            let icon = data["iconName"] as? String ?? "shield.lefthalf.filled"
            let accent = data["accentHex"] as? String ?? "#E11D48"
            let tierRaw = data["securityLevel"] as? String ?? ""
            let tier = SecurityClearanceTier(rawValue: tierRaw) ?? SecurityClearanceTier.tierForRank(rankNum)

            let titleAr = nameMap["ar"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? nameMap["ar"]!
                : (nameMap["en"] ?? doc.documentID)
            let titleEn = nameMap["en"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? nameMap["en"]!
                : titleAr

            let descAr = descMap["ar"] ?? ""
            let descEn = descMap["en"] ?? descAr

            let staffUids = staffRoleMap[doc.documentID] ?? staffRoleMap["custom_\(doc.documentID)"] ?? []

            roles.append(
                PlatformRoleModel(
                    id: doc.documentID,
                    key: "custom_\(doc.documentID)",
                    titleAr: titleAr,
                    titleEn: titleEn,
                    descAr: descAr,
                    descEn: descEn,
                    rank: rankNum,
                    clearanceTier: tier,
                    isBuiltIn: false,
                    iconName: icon,
                    accentHex: accent,
                    permissions: Set(perms),
                    assignedStaffUids: staffUids
                )
            )
        }

        // Sort descending by Numerical Rank
        roles.sort { $0.rank > $1.rank }
        self.allRoles = roles
        applyFilter()
    }

    public func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        self.filteredRoles = allRoles.filter { role in
            if selectedTierFilter == "custom_only" {
                if role.isBuiltIn { return false }
            } else if selectedTierFilter != "all" {
                if role.clearanceTier.rawValue != selectedTierFilter { return false }
            }

            if query.isEmpty { return true }

            let matchesTitle = role.titleAr.lowercased().contains(query) || role.titleEn.lowercased().contains(query)
            let matchesDesc = role.descAr.lowercased().contains(query) || role.descEn.lowercased().contains(query)
            let matchesRank = "\(role.rank)".contains(query)
            let matchesPermission = role.permissions.contains { $0.lowercased().contains(query) }

            return matchesTitle || matchesDesc || matchesRank || matchesPermission
        }
    }

    // MARK: - Mutations with Audit Logging

    public func saveCustomRole(
        existingId: String?,
        titleAr: String,
        titleEn: String,
        descAr: String,
        descEn: String,
        rank: Int,
        tier: SecurityClearanceTier,
        iconName: String,
        accentHex: String,
        permissions: Set<String>,
        completion: @escaping (Bool) -> Void
    ) {
        guard canManage else {
            completion(false)
            return
        }

        let db = Firestore.firestore()
        let payload: [String: Any] = [
            "name": [
                "ar": titleAr.trimmingCharacters(in: .whitespacesAndNewlines),
                "en": titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
            ],
            "description": [
                "ar": descAr.trimmingCharacters(in: .whitespacesAndNewlines),
                "en": descEn.trimmingCharacters(in: .whitespacesAndNewlines)
            ],
            "rank": rank,
            "securityLevel": tier.rawValue,
            "iconName": iconName,
            "accentHex": accentHex,
            "permissions": Array(permissions),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let existingId, !existingId.isEmpty {
            db.collection("staff_roles").document(existingId).setData(payload, merge: true) { [weak self] error in
                guard let self = self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }

                self.writeAuditTrail(
                    action: "update_staff_role",
                    targetId: existingId,
                    metadata: [
                        "rank": rank,
                        "tier": tier.rawValue,
                        "permissionsCount": permissions.count
                    ]
                )
                self.toastMessage = Language.get("RoleRank_Save_Success", alter: "تم حفظ وتطبيق الدور بنجاح")
                completion(true)
            }
        } else {
            var newPayload = payload
            newPayload["createdAt"] = FieldValue.serverTimestamp()
            var ref: DocumentReference? = nil
            ref = db.collection("staff_roles").addDocument(data: newPayload) { [weak self] error in
                guard let self = self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    completion(false)
                    return
                }
                let newId = ref?.documentID ?? "unknown"
                self.writeAuditTrail(
                    action: "create_staff_role",
                    targetId: newId,
                    metadata: [
                        "rank": rank,
                        "tier": tier.rawValue,
                        "permissionsCount": permissions.count
                    ]
                )
                self.toastMessage = Language.get("RoleRank_Save_Success", alter: "تم حفظ وتطبيق الدور بنجاح")
                completion(true)
            }
        }
    }

    public func deleteCustomRole(role: PlatformRoleModel, completion: @escaping (Bool) -> Void) {
        guard canManage else {
            completion(false)
            return
        }
        guard !role.isBuiltIn else {
            completion(false)
            return
        }

        if !role.assignedStaffUids.isEmpty {
            let msg = String.localizedStringWithFormat(
                Language.get("RoleRank_Delete_Blocked_HasStaff", alter: "لا يمكن حذف هذا الدور لوجود %d موظف مسند إليه حالياً. يرجى نقل الموظفين أولاً."),
                role.assignedStaffUids.count
            )
            self.deletionErrorMessage = msg
            completion(false)
            return
        }

        let db = Firestore.firestore()
        db.collection("staff_roles").document(role.id).delete { [weak self] error in
            guard let self = self else { return }
            if let error {
                self.errorMessage = error.localizedDescription
                completion(false)
                return
            }

            self.writeAuditTrail(
                action: "delete_staff_role",
                targetId: role.id,
                metadata: [
                    "title": role.titleEn,
                    "rank": role.rank
                ]
            )
            self.toastMessage = Language.get("RoleRank_Delete_Success", alter: "تم حذف الدور بنجاح")
            completion(true)
        }
    }

    private func writeAuditTrail(action: String, targetId: String, metadata: [String: Any]) {
        let adminUid = Auth.auth().currentUser?.uid ?? "unknown_admin"
        let auditPayload: [String: Any] = [
            "action": action,
            "targetCollection": "staff_roles",
            "targetId": targetId,
            "adminUid": adminUid,
            "metadata": metadata,
            "timestamp": FieldValue.serverTimestamp()
        ]
        Firestore.firestore().collection("AdminAuditLogs").addDocument(data: auditPayload)
    }
}

// MARK: - 5. Color Hex Helper

fileprivate extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xff0000) >> 16) / 255
            let g = Double((hexNumber & 0x00ff00) >> 8) / 255
            let b = Double(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b)
            return
        }
        self.init(red: 0.85, green: 0.15, blue: 0.30)
    }
}

// MARK: - 6. Main Sovereign Role Rank Screen

public struct AdminRoleRankSecurityLevelsView: View {
    public var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AdminRoleRankViewModel()

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sovereignTopBar
                executiveClearanceCockpit

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: AdminSpacing.md) {
                        filterAndSearchMatrix
                        rankedRolesStream
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.top, AdminSpacing.sm)
                    .padding(.bottom, AdminSpacing.xxl)
                }
                .refreshable {
                    viewModel.startListening()
                }
            }

            // Toast Floating Capsule
            if let toast = viewModel.toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.white)
                        Text(toast)
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .ppSuccess), in: Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                    .padding(.bottom, AdminSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { viewModel.toastMessage = nil }
                    }
                }
            }
        }
        .background(
            NavigationLink(
                destination: RoleRankEditorSheet(
                    existingRole: viewModel.editingRole,
                    onSave: { roleData in
                        viewModel.saveCustomRole(
                            existingId: viewModel.editingRole?.id,
                            titleAr: roleData.titleAr,
                            titleEn: roleData.titleEn,
                            descAr: roleData.descAr,
                            descEn: roleData.descEn,
                            rank: roleData.rank,
                            tier: roleData.tier,
                            iconName: roleData.iconName,
                            accentHex: roleData.accentHex,
                            permissions: roleData.permissions
                        ) { success in
                            if success {
                                viewModel.isShowingEditor = false
                                viewModel.editingRole = nil
                            }
                        }
                    },
                    onDismiss: {
                        viewModel.isShowingEditor = false
                        viewModel.editingRole = nil
                    }
                ),
                isActive: $viewModel.isShowingEditor
            ) {
                EmptyView()
            }
            .hidden()
        )
        .sheet(item: $viewModel.inspectingMatrixRole) { role in
            RolePermissionsMatrixSheet(role: role)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .sheet(item: $viewModel.inspectingStaffRole) { role in
            RoleAssignedStaffSheet(role: role, staffMembers: viewModel.staffMembers)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .alert(
            Language.get("RoleRank_Delete_Confirm_Title", alter: "تأكيد حذف الدور المخصص"),
            isPresented: Binding(
                get: { viewModel.roleToDelete != nil },
                set: { if !$0 { viewModel.roleToDelete = nil } }
            )
        ) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                viewModel.roleToDelete = nil
            }
            Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                if let role = viewModel.roleToDelete {
                    viewModel.deleteCustomRole(role: role) { _ in
                        viewModel.roleToDelete = nil
                    }
                }
            }
        } message: {
            if let role = viewModel.roleToDelete {
                Text(String.localizedStringWithFormat(
                    Language.get("RoleRank_Delete_Confirm_Message", alter: "هل أنت متأكد من حذف الدور المخصص '%@'؟ لا يمكن التراجع عن هذه العملية."),
                    role.localizedTitle
                ))
            }
        }
        .alert(
            Language.get("Error", alter: "خطأ في العملية"),
            isPresented: Binding(
                get: { viewModel.deletionErrorMessage != nil },
                set: { if !$0 { viewModel.deletionErrorMessage = nil } }
            )
        ) {
            Button(Language.get("OK", alter: "حسناً"), role: .cancel) {
                viewModel.deletionErrorMessage = nil
            }
        } message: {
            if let err = viewModel.deletionErrorMessage {
                Text(err)
            }
        }
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .onChange(of: viewModel.searchText) { _ in
            viewModel.applyFilter()
        }
        .onChange(of: viewModel.selectedTierFilter) { _ in
            viewModel.applyFilter()
        }
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Sovereign Top Bar

    private var sovereignTopBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("RoleRank_Title", alter: "رتب الأدوار ومستويات الأمان"),
            subtitle: Language.get("RoleRank_Subtitle", alter: "الهيكل الهرمي لحوكمة الصلاحيات والوصول"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            HStack(spacing: 8) {
                if viewModel.canManage {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.editingRole = nil
                        viewModel.isShowingEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.shield.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(Language.get("RoleRank_NewRole_Btn", alter: "إضافة دور"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                        .background(
                            LinearGradient(
                                colors: [AdminSurface.primary, Color(red: 0.92, green: 0.18, blue: 0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .shadow(color: AdminSurface.primary.opacity(0.3), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.startListening()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 40, height: 40)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Executive Clearance Cockpit (Telemetry & IAM Overview)

    private var executiveClearanceCockpit: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.12, blue: 0.28),
                                    Color(red: 0.45, green: 0.10, blue: 0.65)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                        )
                        .shadow(color: Color(red: 0.85, green: 0.12, blue: 0.28).opacity(0.3), radius: 8, y: 3)

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Language.get("RoleRank_Badge", alter: "حوكمة IAM السيادية"))
                            .font(Font.custom("Beiruti-Bold", size: 17))
                            .foregroundColor(AdminSurface.primaryText)

                        Text("100 / 100")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    }

                    Text(Language.isRTL() ? "مصفوفة المستويات الأمنية وحماية الصلاحيات الإدارية" : "Security clearance hierarchy & operational access radar")
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(viewModel.allRoles.count)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("RoleRank_TotalRoles", alter: "إجمالي الأدوار"))
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }

            // 4-Tier Distribution Pulse Bar
            HStack(spacing: 6) {
                tierStatCard(tier: .tier1, count: viewModel.allRoles.filter { $0.clearanceTier == .tier1 }.count)
                tierStatCard(tier: .tier2, count: viewModel.allRoles.filter { $0.clearanceTier == .tier2 }.count)
                tierStatCard(tier: .tier3, count: viewModel.allRoles.filter { $0.clearanceTier == .tier3 }.count)
                tierStatCard(tier: .tier4, count: viewModel.allRoles.filter { $0.clearanceTier == .tier4 }.count)
            }
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface)
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: AdminStroke.hairline),
            alignment: .bottom
        )
    }

    private func tierStatCard(tier: SecurityClearanceTier, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tier.primaryColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(AdminSurface.primaryText)
                Text(tier.shortName.prefix(6))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(AdminSurface.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(tier.primaryColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Filter and Search Matrix

    private var filterAndSearchMatrix: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(AdminSurface.secondaryText)

                TextField(
                    Language.get("RoleRank_Search_Placeholder", alter: "ابحث باسم الدور، الرتبة، أو الصلاحيات..."),
                    text: $viewModel.searchText
                )
                .font(Font.custom("Beiruti-Regular", size: 14))
                .foregroundColor(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.7), lineWidth: 0.8)
            )

            // Tier Segment Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tierFilterChip(id: "all", title: Language.get("RoleRank_AllTiers", alter: "جميع المستويات"))
                    tierFilterChip(id: "tier_1", title: "Tier 1 — السيادية", color: SecurityClearanceTier.tier1.primaryColor)
                    tierFilterChip(id: "tier_2", title: "Tier 2 — العمليات", color: SecurityClearanceTier.tier2.primaryColor)
                    tierFilterChip(id: "tier_3", title: "Tier 3 — الخدمات", color: SecurityClearanceTier.tier3.primaryColor)
                    tierFilterChip(id: "tier_4", title: "Tier 4 — المراقبة", color: SecurityClearanceTier.tier4.primaryColor)
                    tierFilterChip(id: "custom_only", title: Language.get("RoleRank_CustomRoles", alter: "أدوار مخصصة"), color: AdminSurface.primary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func tierFilterChip(id: String, title: String, color: Color? = nil) -> some View {
        let isSelected = viewModel.selectedTierFilter == id
        let activeColor = color ?? AdminSurface.primary

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                viewModel.selectedTierFilter = id
            }
        } label: {
            HStack(spacing: 5) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 12.5))
                    .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected ? activeColor : AdminSurface.surface,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
            )
            .shadow(color: isSelected ? activeColor.opacity(0.24) : Color.clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ranked Roles Stream (Spatial Cards)

    private var rankedRolesStream: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(AdminSurface.primary)
                    Text(Language.get("Loading", alter: "جارٍ تحميل مصفوفة الرتب..."))
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if viewModel.filteredRoles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 36))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    Text(Language.get("NoResults", alter: "لا توجد أدوار مطابقة للبحث أو التصفية"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundColor(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            } else {
                ForEach(viewModel.filteredRoles) { role in
                    SovereignRoleRankCard(
                        role: role,
                        staffMembers: viewModel.staffMembers,
                        canManage: viewModel.canManage,
                        onInspectMatrix: {
                            viewModel.inspectingMatrixRole = role
                        },
                        onInspectStaff: {
                            viewModel.inspectingStaffRole = role
                        },
                        onClone: {
                            viewModel.editingRole = nil
                            viewModel.isShowingEditor = true
                        },
                        onEdit: {
                            viewModel.editingRole = role
                            viewModel.isShowingEditor = true
                        },
                        onDelete: {
                            viewModel.roleToDelete = role
                        }
                    )
                }
            }
        }
    }
}

// MARK: - 7. Sovereign Role Rank Card Component

private struct SovereignRoleRankCard: View {
    let role: PlatformRoleModel
    let staffMembers: [PPStaffDoc]
    let canManage: Bool
    let onInspectMatrix: () -> Void
    let onInspectStaff: () -> Void
    let onClone: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var assignedStaff: [PPStaffDoc] {
        staffMembers.filter { role.assignedStaffUids.contains($0.uid) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                // Rank Number Shield
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(role.accentColor.opacity(0.14))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(role.accentColor.opacity(0.4), lineWidth: 1)
                        )

                    VStack(spacing: 0) {
                        Image(systemName: role.iconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(role.accentColor)
                        Text("#\(role.rank)")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(role.accentColor)
                    }
                }

                // Role Title & Tier Pill
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(role.localizedTitle)
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(1)

                        if role.isBuiltIn {
                            Text(Language.get("SystemRole", alter: "نظامي"))
                                .font(Font.custom("Beiruti-Bold", size: 9.5))
                                .foregroundColor(role.clearanceTier.primaryColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(role.clearanceTier.primaryColor.opacity(0.12), in: Capsule())
                        } else {
                            Text(Language.get("CustomRole", alter: "مخصص"))
                                .font(Font.custom("Beiruti-Bold", size: 9.5))
                                .foregroundColor(Color(uiColor: .ppPrimary))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color(uiColor: .ppPrimary).opacity(0.12), in: Capsule())
                        }
                    }

                    Text(role.clearanceTier.title)
                        .font(Font.custom("Beiruti-Medium", size: 11.5))
                        .foregroundColor(role.clearanceTier.primaryColor)
                        .lineLimit(1)
                }

                Spacer()

                // Assigned Staff Pill
                Button(action: onInspectStaff) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                        Text(String.localizedStringWithFormat(
                            Language.get("RoleRank_AssignedStaffCount_Format", alter: "%d موظف"),
                            role.assignedStaffUids.count
                        ))
                        .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundColor(role.assignedStaffUids.isEmpty ? AdminSurface.secondaryText : Color(uiColor: .ppPrimary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        role.assignedStaffUids.isEmpty
                            ? AdminSurface.secondaryText.opacity(0.08)
                            : Color(uiColor: .ppPrimary).opacity(0.10),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            // Description
            if !role.localizedDesc.isEmpty {
                Text(role.localizedDesc)
                    .font(Font.custom("Beiruti-Regular", size: 12.5))
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Permission Capacity Progress Gauge
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String.localizedStringWithFormat(
                        Language.get("RoleRank_PermissionCapacity", alter: "%d من %d صلاحية (%d%% تغطية)"),
                        role.permissions.count,
                        SecurityPermissionCatalog.shared.totalPermissionsCount,
                        Int(role.coveragePercentage * 100)
                    ))
                    .font(Font.custom("Beiruti-Medium", size: 11))
                    .foregroundColor(AdminSurface.secondaryText)

                    Spacer()

                    Text("\(Int(role.coveragePercentage * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(role.accentColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdminSurface.hairline)
                            .frame(height: 5)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [role.accentColor, role.clearanceTier.secondaryColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(role.coveragePercentage)), height: 5)
                    }
                }
                .frame(height: 5)
            }

            // Action Rail
            HStack(spacing: 8) {
                Button(action: onInspectMatrix) {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                        Text(Language.get("RoleRank_Inspect_Matrix", alter: "مصفوفة الصلاحيات"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onInspectStaff) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 12, weight: .semibold))
                        Text(Language.get("RoleRank_Personnel_Roster", alter: "الكادر"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundColor(AdminSurface.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                if canManage {
                    if !role.isBuiltIn {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(uiColor: .ppPrimary))
                                .frame(width: 32, height: 32)
                                .background(Color(uiColor: .ppPrimary).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("RoleRank_Edit_Btn", alter: "تعديل الدور"))

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(uiColor: .ppError))
                                .frame(width: 32, height: 32)
                                .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Language.get("RoleRank_Delete_Btn", alter: "حذف الدور"))
                    } else {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                            .frame(width: 32, height: 32)
                    }
                }
            }
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    role.accentColor.opacity(0.24),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
    }
}

// MARK: - 8. Sheet: Role Permissions Matrix Inspector

public struct RolePermissionsMatrixSheet: View {
    let role: PlatformRoleModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchKeyword: String = ""
    @State private var selectedModuleKey: String = "all"

    public var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 14) {
                            filterBar

                            ForEach(filteredModules) { module in
                                moduleMatrixCard(module: module)
                            }
                        }
                        .padding(AdminSpacing.base)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(role.accentColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: role.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(role.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(role.localizedTitle)
                        .font(Font.custom("Beiruti-Bold", size: 17))
                        .foregroundColor(AdminSurface.primaryText)
                    Text("#\(role.rank)")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(role.accentColor)
                }

                Text(role.clearanceTier.title)
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundColor(role.clearanceTier.primaryColor)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 36, height: 36)
                    .background(AdminSurface.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.surface)
        .overlay(Rectangle().fill(AdminSurface.hairline).frame(height: 1), alignment: .bottom)
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(AdminSurface.secondaryText)
                TextField(Language.get("Search", alter: "تصفية الصلاحيات..."), text: $searchKeyword)
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                if !searchKeyword.isEmpty {
                    Button(action: { searchKeyword = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 0.8))
        }
    }

    private var filteredModules: [SecurityPermissionModule] {
        let catalog = SecurityPermissionCatalog.shared.modules
        let query = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if query.isEmpty { return catalog }

        return catalog.compactMap { mod in
            let filteredPerms = mod.permissions.filter { perm in
                perm.key.lowercased().contains(query) ||
                perm.titleAr.lowercased().contains(query) ||
                perm.titleEn.lowercased().contains(query)
            }
            if !filteredPerms.isEmpty || mod.titleAr.lowercased().contains(query) || mod.titleEn.lowercased().contains(query) {
                return SecurityPermissionModule(
                    key: mod.key,
                    titleAr: mod.titleAr,
                    titleEn: mod.titleEn,
                    icon: mod.icon,
                    permissions: filteredPerms.isEmpty ? mod.permissions : filteredPerms
                )
            }
            return nil
        }
    }

    private func moduleMatrixCard(module: SecurityPermissionModule) -> some View {
        let grantedCount = module.permissions.filter { role.permissions.contains($0.key) }.count
        let totalCount = module.permissions.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: module.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(role.accentColor)
                Text(module.localizedTitle)
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text("\(grantedCount) / \(totalCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(grantedCount > 0 ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((grantedCount > 0 ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText).opacity(0.12), in: Capsule())
            }

            VStack(spacing: 4) {
                ForEach(module.permissions) { perm in
                    let isGranted = role.permissions.contains(perm.key)
                    HStack(spacing: 8) {
                        Image(systemName: isGranted ? "checkmark.circle.fill" : "minus.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isGranted ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText.opacity(0.4))

                        VStack(alignment: .leading, spacing: 0) {
                            Text(perm.localizedTitle)
                                .font(Font.custom("Beiruti-Medium", size: 12.5))
                                .foregroundColor(isGranted ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.6))
                            Text(perm.key)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                        }

                        Spacer()

                        if perm.isHighRisk {
                            Text(Language.isRTL() ? "عالي الحساسية" : "High Risk")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Color(uiColor: .ppError))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color(uiColor: .ppError).opacity(0.10), in: Capsule())
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(12)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8))
    }
}

// MARK: - 9. Sheet: Role Assigned Staff Roster

public struct RoleAssignedStaffSheet: View {
    let role: PlatformRoleModel
    let staffMembers: [PPStaffDoc]
    @Environment(\.dismiss) private var dismiss

    private var assigned: [PPStaffDoc] {
        staffMembers.filter { role.assignedStaffUids.contains($0.uid) }
    }

    public var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(Language.get("RoleRank_Personnel_Roster", alter: "أعضاء الكادر المفوّض"))
                                    .font(Font.custom("Beiruti-Bold", size: 17))
                                    .foregroundColor(AdminSurface.primaryText)
                                Text("(\(assigned.count))")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(role.accentColor)
                            }
                            Text(role.localizedTitle)
                                .font(Font.custom("Beiruti-Medium", size: 12.5))
                                .foregroundColor(role.accentColor)
                        }
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AdminSurface.primaryText)
                                .frame(width: 36, height: 36)
                                .background(AdminSurface.surface, in: Circle())
                                .overlay(Circle().strokeBorder(Color(uiColor: .ppSurfaceBorder), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(AdminSpacing.base)
                    .background(AdminSurface.surface)
                    .overlay(Rectangle().fill(AdminSurface.hairline).frame(height: 1), alignment: .bottom)

                    if assigned.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 40))
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                            Text(Language.get("RoleRank_NoAssignedStaff", alter: "لا يوجد موظفون مسندون حالياً لهذا الدور"))
                                .font(Font.custom("Beiruti-Bold", size: 15))
                                .foregroundColor(AdminSurface.primaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 10) {
                                ForEach(assigned) { staff in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(role.accentColor.opacity(0.12))
                                                .frame(width: 42, height: 42)
                                            Text(String((staff.displayName ?? staff.email ?? "U").prefix(1)).uppercased())
                                                .font(.system(size: 17, weight: .bold))
                                                .foregroundColor(role.accentColor)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(staff.displayName ?? staff.email ?? staff.uid)
                                                .font(Font.custom("Beiruti-Bold", size: 14.5))
                                                .foregroundColor(AdminSurface.primaryText)

                                            if let email = staff.email, !email.isEmpty {
                                                Text(email)
                                                    .font(.system(size: 11.5))
                                                    .foregroundColor(AdminSurface.secondaryText)
                                            }

                                            Text(staff.uid)
                                                .font(.system(size: 9.5, design: .monospaced))
                                                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                                        }

                                        Spacer()

                                        Circle()
                                            .fill(staff.isActive() ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))
                                            .frame(width: 8, height: 8)
                                    }
                                    .padding(12)
                                    .background(AdminSurface.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8))
                                }
                            }
                            .padding(AdminSpacing.base)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - 10. Sheet: Role Rank & Security Level Editor

public struct RoleRankEditorData: Sendable {
    public var titleAr: String
    public var titleEn: String
    public var descAr: String
    public var descEn: String
    public var rank: Int
    public var tier: SecurityClearanceTier
    public var iconName: String
    public var accentHex: String
    public var permissions: Set<String>
}

public struct RoleRankEditorSheet: View {
    let existingRole: PlatformRoleModel?
    let onSave: (RoleRankEditorData) -> Void
    let onDismiss: () -> Void

    @State private var titleAr: String = ""
    @State private var titleEn: String = ""
    @State private var descAr: String = ""
    @State private var descEn: String = ""
    @State private var rank: Double = 50
    @State private var tier: SecurityClearanceTier = .tier2
    @State private var iconName: String = "shield.fill"
    @State private var accentHex: String = "#2563EB"
    @State private var selectedPermissions: Set<String> = []
    @State private var isSaving: Bool = false

    private let availableIcons = [
        "shield.fill", "crown.fill", "gearshape.2.fill", "cube.box.fill",
        "creditcard.fill", "cart.fill", "building.2.fill", "headphones",
        "cross.case.fill", "star.fill", "sparkles", "person.badge.shield.checkmark.fill"
    ]

    private let availableColors = [
        "#B81430", "#D4AF37", "#1472B8", "#2563EB",
        "#0D9488", "#10B981", "#7C3AED", "#EA580C", "#64748B"
    ]

    public init(existingRole: PlatformRoleModel?, onSave: @escaping (RoleRankEditorData) -> Void, onDismiss: @escaping () -> Void) {
        self.existingRole = existingRole
        self.onSave = onSave
        self.onDismiss = onDismiss
        _titleAr = State(initialValue: existingRole?.titleAr ?? "")
        _titleEn = State(initialValue: existingRole?.titleEn ?? "")
        _descAr = State(initialValue: existingRole?.descAr ?? "")
        _descEn = State(initialValue: existingRole?.descEn ?? "")
        _rank = State(initialValue: Double(existingRole?.rank ?? 50))
        _tier = State(initialValue: existingRole?.clearanceTier ?? .tier2)
        _iconName = State(initialValue: existingRole?.iconName ?? "shield.fill")
        _accentHex = State(initialValue: existingRole?.accentHex ?? "#2563EB")
        _selectedPermissions = State(initialValue: existingRole?.permissions ?? [])
    }

    public var body: some View {
        ZStack {
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sovereignEditorNavBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        identityCard
                        rankAndClearanceTierCard
                        iconAndThemeCard
                        permissionsMatrixCard
                    }
                    .padding(AdminSpacing.base)
                }
            }
        }
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var sovereignEditorNavBar: some View {
        AdminSovereignNavigationBar(
            title: existingRole != nil ? Language.get("RoleRank_Editor_Edit_Title", alter: "تعديل الدور المخصص") : Language.get("RoleRank_Editor_Create_Title", alter: "صياغة دور مخصص جديد"),
            subtitle: Language.isRTL() ? "تحديد الصلاحيات ورتبة الوصول" : "Configure clearance & permissions",
            onBack: onDismiss
        ) {
            Button(action: saveTapped) {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                        Text(Language.get("Save", alter: "حفظ"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(canSave ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.3), in: Capsule())
                .shadow(color: canSave ? AdminSurface.primary.opacity(0.32) : Color.clear, radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(!canSave || isSaving)
        }
    }

    private var canSave: Bool {
        !titleAr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !titleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSaving = true
        let data = RoleRankEditorData(
            titleAr: titleAr,
            titleEn: titleEn,
            descAr: descAr,
            descEn: descEn,
            rank: Int(rank),
            tier: tier,
            iconName: iconName,
            accentHex: accentHex,
            permissions: selectedPermissions
        )
        onSave(data)
    }

    // MARK: Identity Card
    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.isRTL() ? "بيانات وهوية الدور" : "Role Identity")
                .font(Font.custom("Beiruti-Bold", size: 14.5))
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                TextField(Language.get("RoleRank_RoleName_Ar", alter: "اسم الدور بالعربية *"), text: $titleAr)
                    .font(Font.custom("Beiruti-Regular", size: 14))
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 10))

                TextField(Language.get("RoleRank_RoleName_En", alter: "اسم الدور بالإنجليزية *"), text: $titleEn)
                    .font(Font.custom("Beiruti-Regular", size: 14))
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 10))

                TextField(Language.get("RoleRank_RoleDesc_Ar", alter: "وصف المهام والمسؤوليات بالعربية"), text: $descAr)
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 10))

                TextField(Language.get("RoleRank_RoleDesc_En", alter: "وصف المهام والمسؤوليات بالإنجليزية"), text: $descEn)
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .multilineTextAlignment(.leading)
                    .padding(10)
                    .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Rank and Clearance Tier Card
    private var rankAndClearanceTierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Language.get("RoleRank_RankSlider_Title", alter: "الرتبة التسلسلية (١ - ٩٩)"))
                    .font(Font.custom("Beiruti-Bold", size: 14.5))
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text("#\(Int(rank))")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(tier.primaryColor)
            }

            Slider(value: $rank, in: 1...99, step: 1) {
                Text("Rank")
            }
            .tint(tier.primaryColor)
            .onChange(of: rank) { newRank in
                tier = SecurityClearanceTier.tierForRank(Int(newRank))
            }

            Text(tier.title)
                .font(Font.custom("Beiruti-Bold", size: 13))
                .foregroundColor(tier.primaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(tier.primaryColor.opacity(0.12), in: Capsule())

            Text(tier.localizedDescription)
                .font(Font.custom("Beiruti-Regular", size: 12))
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Icon & Theme Card
    private var iconAndThemeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("RoleRank_Color_Select_Title", alter: "اللون المميز والأيقونة"))
                .font(Font.custom("Beiruti-Bold", size: 14.5))
                .foregroundColor(AdminSurface.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Icons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        let isSelected = iconName == icon
                        Button {
                            iconName = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                .frame(width: 38, height: 38)
                                .background(isSelected ? Color(hex: accentHex) : AdminSurface.background, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Colors
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableColors, id: \.self) { hex in
                        let isSelected = accentHex == hex
                        Button {
                            accentHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .shadow(color: Color(hex: hex).opacity(isSelected ? 0.5 : 0), radius: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Permissions Matrix Card
    private var permissionsMatrixCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Language.get("RoleRank_Permissions_Select_Title", alter: "تفويض الصلاحيات (١٨ وحدة)"))
                    .font(Font.custom("Beiruti-Bold", size: 14.5))
                    .foregroundColor(AdminSurface.primaryText)
                Spacer()
                Text("\(selectedPermissions.count) / \(SecurityPermissionCatalog.shared.totalPermissionsCount)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(uiColor: .ppPrimary))
            }

            // Rapid Presets
            HStack(spacing: 8) {
                presetButton(title: Language.get("RoleRank_Preset_Full", alter: "تفويض كامل")) {
                    selectedPermissions = Set(SecurityPermissionCatalog.shared.allPermissions.map { $0.key })
                }
                presetButton(title: Language.get("RoleRank_Preset_Ops", alter: "عمليات ومخزون")) {
                    selectedPermissions = Set([
                        "dashboard.view", "stock.view", "stock.manage", "pos.view", "pos.sell", "delivery.view", "branches.view"
                    ])
                }
                presetButton(title: Language.get("RoleRank_Preset_ReadOnly", alter: "رصد فقط")) {
                    selectedPermissions = Set(["dashboard.view", "reports.view"])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Module Checkboxes
            VStack(spacing: 10) {
                ForEach(SecurityPermissionCatalog.shared.modules) { module in
                    let allGranted = module.permissions.allSatisfy { selectedPermissions.contains($0.key) }
                    let anyGranted = module.permissions.contains { selectedPermissions.contains($0.key) }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button {
                                if allGranted {
                                    for p in module.permissions { selectedPermissions.remove(p.key) }
                                } else {
                                    for p in module.permissions { selectedPermissions.insert(p.key) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: allGranted ? "checkmark.square.fill" : (anyGranted ? "minus.square.fill" : "square"))
                                        .foregroundColor(anyGranted ? Color(uiColor: .ppPrimary) : AdminSurface.secondaryText)
                                    Text(module.localizedTitle)
                                        .font(Font.custom("Beiruti-Bold", size: 13))
                                        .foregroundColor(AdminSurface.primaryText)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }

                        ForEach(module.permissions) { perm in
                            let checked = selectedPermissions.contains(perm.key)
                            Button {
                                if checked {
                                    selectedPermissions.remove(perm.key)
                                } else {
                                    selectedPermissions.insert(perm.key)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13))
                                        .foregroundColor(checked ? Color(uiColor: .ppPrimary) : AdminSurface.secondaryText.opacity(0.5))
                                    Text(perm.localizedTitle)
                                        .font(Font.custom("Beiruti-Regular", size: 12))
                                        .foregroundColor(checked ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .padding(.leading, 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func presetButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }) {
            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 11))
                .foregroundColor(Color(uiColor: .ppPrimary))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(uiColor: .ppPrimary).opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
