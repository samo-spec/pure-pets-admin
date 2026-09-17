//
//  PuryModels.swift
//  PurePetsAdmin
//
//  Authoritative data and contract models for Pury Admin Operational Agent.
//  Matches Cloud Functions GeneKit Pury contracts.
//

import Foundation

// MARK: - Pury Language-Scoped Localization

/// Pury owns a conversation language that can legitimately differ from the app-wide
/// `Language` selection (an operator may read the console in Arabic and interrogate
/// Pury in English, or the reverse). `Language.get` always resolves against the
/// *app* bundle, so using it inside Pury produces a mixed-language surface.
///
/// `PuryLocale` resolves the same `Localizable.strings` tables against the bundle for
/// Pury's own language, and — unlike `Language.get` — distinguishes "key missing" from
/// "key present" so a missing key can never leak the opposite language's fallback.
private final class PuryLocaleBundleCache: @unchecked Sendable {
    static let shared = PuryLocaleBundleCache()

    private let lock = NSLock()
    private var bundles: [String: Bundle] = [:]

    func bundle(for code: String) -> Bundle {
        lock.lock()
        defer { lock.unlock() }
        if let cached = bundles[code] { return cached }
        let resolved = Bundle.main.path(forResource: code, ofType: "lproj")
            .flatMap { Bundle(path: $0) } ?? .main
        bundles[code] = resolved
        return resolved
    }
}

public enum PuryLocale {
    /// Sentinel that can never appear in a shipped strings file, used to detect a missing key.
    private static let missingMarker = "\u{1}pury.missing.key\u{1}"

    /// Normalizes any language input to the two codes Pure Pets ships (`ar` / `en`).
    public static func normalized(_ language: String?) -> String {
        guard let language, !language.isEmpty else { return Language.isRTL() ? "ar" : "en" }
        return language.lowercased().hasPrefix("ar") ? "ar" : "en"
    }

    public static func isArabic(_ language: String?) -> Bool {
        normalized(language) == "ar"
    }

    /// Resolves `key` in Pury's language, falling back to the matching in-code literal
    /// for that same language when the key is absent from the strings table.
    public static func text(_ key: String, language: String?, ar: String, en: String) -> String {
        let code = normalized(language)
        let resolved = PuryLocaleBundleCache.shared
            .bundle(for: code)
            .localizedString(forKey: key, value: missingMarker, table: nil)
        if resolved == missingMarker || resolved.isEmpty { return code == "ar" ? ar : en }
        return resolved
    }

    /// Format-string variant. Pury's identifier tokens must stay Western-digit and
    /// unlocalized, so formatting deliberately runs without a locale.
    public static func format(
        _ key: String,
        language: String?,
        ar: String,
        en: String,
        _ arguments: CVarArg...
    ) -> String {
        let template = text(key, language: language, ar: ar, en: en)
        return String(format: template, arguments: arguments)
    }
}

// MARK: - Bound Data Scope Facets

/// One inspectable line of Pury's current data binding.
/// `isTechnical` marks values that are backend identifiers: they must render
/// left-to-right and monospaced even inside an Arabic RTL layout.
public struct PuryScopeFacet: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let value: String
    public let isTechnical: Bool

    public init(id: String, label: String, value: String, isTechnical: Bool) {
        self.id = id
        self.label = label
        self.value = value
        self.isTechnical = isTechnical
    }
}

// MARK: - Risk Tiers

public enum PuryRiskTier: Int, Codable, Sendable {
    /// Read / analyze / search / navigate queries. Immediate execution.
    case tier0Read = 0
    /// Local previews, drafts, and authoring suggestions. No persistent mutation.
    case tier1Preview = 1
    /// Low-risk reversible writes on explicit server allowlist. Immediate execution with audit trail.
    case tier2AllowlistedWrite = 2
    /// Consequential or sensitive operations. Requires explicit human confirmation with cryptographic token.
    case tier3ConfirmationRequired = 3

    public var localizedTitle: String {
        switch self {
        case .tier0Read:
            return Language.get("Pury_Tier0_Title", alter: "استعلام وقراءة")
        case .tier1Preview:
            return Language.get("Pury_Tier1_Title", alter: "معاينة واقتراح مسودة")
        case .tier2AllowlistedWrite:
            return Language.get("Pury_Tier2_Title", alter: "إجراء تشغيلي مباشر")
        case .tier3ConfirmationRequired:
            return Language.get("Pury_Tier3_Title", alter: "إجراء حساس يتطلب التأكيد")
        }
    }
}

// MARK: - Client Metadata

public struct PuryClientInfo: Codable, Sendable {
    public let platform: String
    public let appVersion: String?
    public let buildNumber: String?
    public let locale: String?

    public init(
        platform: String = "ios-admin",
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        buildNumber: String? = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
        locale: String? = Language.isRTL() ? "ar" : "en"
    ) {
        self.platform = platform
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.locale = locale
    }
}

// MARK: - Screen Context Hint

public struct PuryScreenContext: Codable, Sendable, Equatable {
    public var screen: String?
    public var route: String?
    public var branchId: String?
    public var entityType: String?
    public var entityId: String?
    public var reservationId: String?
    public var stayId: String?
    public var accommodationId: String?
    public var metadata: [String: String]?

    public init(
        screen: String? = nil,
        route: String? = nil,
        branchId: String? = nil,
        entityType: String? = nil,
        entityId: String? = nil,
        reservationId: String? = nil,
        stayId: String? = nil,
        accommodationId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.screen = screen
        self.route = route
        self.branchId = branchId
        self.entityType = entityType
        self.entityId = entityId
        self.reservationId = reservationId
        self.stayId = stayId
        self.accommodationId = accommodationId
        self.metadata = metadata
    }

    public var isEmpty: Bool {
        screen == nil && route == nil && branchId == nil && entityId == nil && reservationId == nil && stayId == nil
    }

    /// True when Pury is bound to something more specific than "the admin console",
    /// i.e. there is a real binding worth inspecting.
    public var hasInspectableScope: Bool {
        !scopeFacets(language: nil).isEmpty
    }

    public var displayLabel: String {
        displayLabel(language: nil)
    }

    /// Operator-facing label for the current binding, resolved in Pury's own language.
    ///
    /// Never returns a raw internal identifier: an unmapped screen or route falls back to
    /// the localized console label, and the raw route stays available through
    /// `scopeFacets(language:)` where it is presented as a technical value.
    public func displayLabel(language: String?) -> String {
        if let stayId = stayId, !stayId.isEmpty {
            return PuryLocale.format(
                "Pury_Context_Stay",
                language: language,
                ar: "إقامة فندقية: #%@",
                en: "Hotel Stay: #%@",
                String(stayId.prefix(8))
            )
        }
        if let reservationId = reservationId, !reservationId.isEmpty {
            return PuryLocale.format(
                "Pury_Context_Reservation",
                language: language,
                ar: "حجز فندقي: #%@",
                en: "Hotel Reservation: #%@",
                String(reservationId.prefix(8))
            )
        }
        if let accommodationId = accommodationId, !accommodationId.isEmpty {
            return PuryLocale.format(
                "Pury_Context_Suite",
                language: language,
                ar: "جناح فندقي: #%@",
                en: "Hotel Suite: #%@",
                accommodationId
            )
        }
        if let entityType = entityType,
           let entityId = entityId,
           !entityId.isEmpty,
           let recordName = Self.localizedRecordName(entityType, language: language) {
            return "\(recordName): #\(entityId.prefix(8))"
        }
        if let screen = screen, let mapped = Self.localizedScreenName(screen, language: language) {
            return mapped
        }
        if let route = route, let mapped = Self.localizedScreenName(route, language: language) {
            return mapped
        }
        return Self.consoleLabel(language: language)
    }

    /// Inspectable breakdown of exactly what Pury is bound to right now.
    /// Only non-empty bindings are emitted, so the inspector never shows hollow rows.
    public func scopeFacets(language: String?) -> [PuryScopeFacet] {
        var facets: [PuryScopeFacet] = []

        if let screen = screen, !screen.isEmpty {
            let mapped = Self.localizedScreenName(screen, language: language)
            facets.append(
                PuryScopeFacet(
                    id: "screen",
                    label: PuryLocale.text("Pury_Scope_Screen", language: language, ar: "الشاشة", en: "Screen"),
                    value: mapped ?? screen,
                    isTechnical: mapped == nil
                )
            )
        }

        if let entityType = entityType, !entityType.isEmpty {
            let mapped = Self.localizedRecordName(entityType, language: language)
            facets.append(
                PuryScopeFacet(
                    id: "entityType",
                    label: PuryLocale.text("Pury_Scope_RecordType", language: language, ar: "نوع السجل", en: "Record type"),
                    value: mapped ?? entityType,
                    isTechnical: mapped == nil
                )
            )
        }

        if let entityId = entityId, !entityId.isEmpty {
            facets.append(
                PuryScopeFacet(
                    id: "entityId",
                    label: PuryLocale.text("Pury_Scope_Record", language: language, ar: "معرّف السجل", en: "Record ID"),
                    value: entityId,
                    isTechnical: true
                )
            )
        }

        if let reservationId = reservationId, !reservationId.isEmpty {
            facets.append(
                PuryScopeFacet(
                    id: "reservationId",
                    label: PuryLocale.text("Pury_Scope_Reservation", language: language, ar: "الحجز", en: "Reservation"),
                    value: reservationId,
                    isTechnical: true
                )
            )
        }

        if let stayId = stayId, !stayId.isEmpty {
            facets.append(
                PuryScopeFacet(
                    id: "stayId",
                    label: PuryLocale.text("Pury_Scope_Stay", language: language, ar: "الإقامة", en: "Stay"),
                    value: stayId,
                    isTechnical: true
                )
            )
        }

        if let accommodationId = accommodationId, !accommodationId.isEmpty {
            facets.append(
                PuryScopeFacet(
                    id: "accommodationId",
                    label: PuryLocale.text("Pury_Scope_Suite", language: language, ar: "الجناح", en: "Suite"),
                    value: accommodationId,
                    isTechnical: true
                )
            )
        }

        if let branchId = branchId, !branchId.isEmpty {
            facets.append(
                PuryScopeFacet(
                    id: "branchId",
                    label: PuryLocale.text("Pury_Scope_Branch", language: language, ar: "الفرع", en: "Branch"),
                    value: branchId,
                    isTechnical: true
                )
            )
        }

        if let route = route, !route.isEmpty {
            let mapped = Self.localizedScreenName(route, language: language)
            facets.append(
                PuryScopeFacet(
                    id: "route",
                    label: PuryLocale.text("Pury_Scope_Route", language: language, ar: "المسار", en: "Route"),
                    value: mapped ?? route,
                    isTechnical: mapped == nil
                )
            )
        }

        return facets
    }

    private static func consoleLabel(language: String?) -> String {
        PuryLocale.text("Pury_Context_Admin", language: language, ar: "لوحة الإدارة", en: "Admin Console")
    }

    /// Returns `nil` for identifiers Pury has no operator-facing name for, so callers
    /// can fall back deliberately instead of leaking an internal token into the UI.
    private static func localizedScreenName(_ name: String, language: String?) -> String? {
        switch name.lowercased() {
        case "command", "commandcenter", "command_center":
            return PuryLocale.text("Pury_Context_Command", language: language, ar: "مركز العمليات والقيادة", en: "Command Center")
        case "work":
            return PuryLocale.text("Pury_Context_Work", language: language, ar: "التجارة والمخزون", en: "Commerce & Inventory")
        case "operations":
            return PuryLocale.text("Pury_Context_Operations", language: language, ar: "التشغيل والخدمات", en: "Operations & Services")
        case "customers", "people":
            return PuryLocale.text("Pury_Context_People", language: language, ar: "العملاء والفريق", en: "People & Staff")
        case "hotel":
            return PuryLocale.text("Pury_Context_Hotel", language: language, ar: "فندق الحيوانات", en: "Pet Hotel")
        case "pos", "pointofsale":
            return PuryLocale.text("Pury_Context_POS", language: language, ar: "نقطة البيع السريع", en: "Point of Sale")
        case "fulfillment":
            return PuryLocale.text("Pury_Context_Fulfillment", language: language, ar: "أوامر التجهيز والتسليم", en: "Fulfillment & Delivery")
        case "more":
            return PuryLocale.text("Pury_Context_More", language: language, ar: "المزيد والإعدادات", en: "More & Settings")
        case "accessories", "accessory":
            return PuryLocale.text("Pury_Context_Accessories", language: language, ar: "المستلزمات والمخزون", en: "Accessories & Stock")
        case "livepets", "live_pets", "livepet":
            return PuryLocale.text("Pury_Context_LivePets", language: language, ar: "الحيوانات الحية", en: "Live Pets")
        case "food":
            return PuryLocale.text("Pury_Context_Food", language: language, ar: "قسم الأغذية", en: "Pet Food")
        case "users", "userscol":
            return PuryLocale.text("Pury_Context_Users", language: language, ar: "ملفات العملاء", en: "Customer Profiles")
        case "staff", "staff_users":
            return PuryLocale.text("Pury_Context_Staff", language: language, ar: "فريق العمل والأطباء", en: "Staff & Veterinarians")
        case "branches", "branch":
            return PuryLocale.text("Pury_Context_Branches", language: language, ar: "الفروع والمستودعات", en: "Branches & Warehouses")
        case "paymentorder", "order", "orders":
            return PuryLocale.text("Pury_Context_Orders", language: language, ar: "إدارة الطلبات", en: "Order Management")
        default:
            return nil
        }
    }

    /// Maps backend collection identities to the operator-facing record names Pury
    /// already ships. Returns `nil` for unmapped collections.
    private static func localizedRecordName(_ entityType: String, language: String?) -> String? {
        switch entityType.lowercased() {
        case "userscol", "users":
            return PuryLocale.text("Pury_Record_Customer", language: language, ar: "ملف العميل", en: "Customer Profile")
        case "petaccessories", "accessories":
            return PuryLocale.text("Pury_Record_InventoryItem", language: language, ar: "منتج المخزون", en: "Inventory Item")
        case "staff_users", "staff":
            return PuryLocale.text("Pury_Record_StaffMember", language: language, ar: "عضو الفريق", en: "Staff Member")
        case "branches", "branch":
            return PuryLocale.text("Pury_Record_Branch", language: language, ar: "بيانات الفرع", en: "Branch Record")
        case "orders", "order", "paymentorder":
            return PuryLocale.text("Pury_Record_Order", language: language, ar: "طلب", en: "Order")
        case "hotelstays", "hotelstay", "stays":
            return PuryLocale.text("Pury_Record_HotelStay", language: language, ar: "إقامة فندقية", en: "Hotel Stay")
        case "adoption", "adoptions":
            return PuryLocale.text("Pury_Record_Adoption", language: language, ar: "سجل تبنٍ", en: "Adoption Record")
        default:
            return nil
        }
    }
}

// MARK: - Structured Data & Cards

public struct PuryField: Codable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let value: String
    public let type: String?
    public let tone: String?

    public init(label: String, value: String, type: String? = nil, tone: String? = nil) {
        self.label = label
        self.value = value
        self.type = type
        self.tone = tone
    }

    public var cleanLabel: String {
        PuryModelsSanitizer.cleanText(label)
    }

    public var cleanValue: String {
        PuryModelsSanitizer.cleanText(value)
    }
}

public struct PuryCard: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let status: String?
    public let badge: String?
    public let entityType: String?
    public let entityId: String?
    public let details: [PuryField]?
    public let actionRoute: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        status: String? = nil,
        badge: String? = nil,
        entityType: String? = nil,
        entityId: String? = nil,
        details: [PuryField]? = nil,
        actionRoute: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.badge = badge
        self.entityType = entityType
        self.entityId = entityId
        self.details = details
        self.actionRoute = actionRoute
    }

    public var cleanTitle: String {
        PuryModelsSanitizer.cleanText(title)
    }

    public var cleanSubtitle: String? {
        guard let sub = subtitle, !sub.isEmpty else { return nil }
        return PuryModelsSanitizer.cleanText(sub)
    }

    public var isHotelCard: Bool {
        entityType?.lowercased().contains("hotel") == true ||
        badge?.contains("إقامة") == true ||
        cleanTitle.contains("إقامة") == true ||
        cleanTitle.contains("جناح")
    }

    public var isProductCard: Bool {
        entityType?.lowercased().contains("product") == true ||
        entityType?.lowercased().contains("stock") == true ||
        badge?.contains("منتج") == true
    }

    public var isOrderCard: Bool {
        entityType?.lowercased().contains("order") == true ||
        badge?.contains("طلب") == true
    }
}

public enum PuryModelsSanitizer {
    public static func cleanText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.contains("\"ar\"") {
            if let data = trimmed.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let isRTL = Language.isRTL()
                if isRTL, let ar = dict["ar"] as? String, !ar.isEmpty {
                    return ar
                } else if let en = dict["en"] as? String, !en.isEmpty {
                    return en
                } else if let ar = dict["ar"] as? String {
                    return ar
                }
            }
        }
        return trimmed
    }
}

public struct PuryDataBlock: Codable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let collection: String?
    public let fields: [PuryField]

    public init(id: String, type: String, collection: String? = nil, fields: [PuryField]) {
        self.id = id
        self.type = type
        self.collection = collection
        self.fields = fields
    }
}

public struct PuryEntityRef: Codable, Sendable {
    public let kind: String
    public let id: String

    public init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }
}

public struct PuryStructuredData: Codable, Sendable {
    public let version: Int?
    public let renderer: String?
    public let cards: [PuryCard]?
    public let dataBlocks: [PuryDataBlock]?
    public let resultRefs: [String]?

    public init(
        version: Int? = 1,
        renderer: String? = "pury_admin_ios_v1",
        cards: [PuryCard]? = nil,
        dataBlocks: [PuryDataBlock]? = nil,
        resultRefs: [String]? = nil
    ) {
        self.version = version
        self.renderer = renderer
        self.cards = cards
        self.dataBlocks = dataBlocks
        self.resultRefs = resultRefs
    }
}

// MARK: - Lossless JSON Contract Value

public indirect enum PuryJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([PuryJSONValue])
    case object([String: PuryJSONValue])
    case null

    public init(any: Any) {
        switch any {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Int64:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as NSNumber:
            self = .number(value.doubleValue)
        case let value as String:
            self = .string(value)
        case let value as [Any]:
            self = .array(value.map(PuryJSONValue.init(any:)))
        case let value as [String: Any]:
            self = .object(value.mapValues(PuryJSONValue.init(any:)))
        default:
            self = .string(String(describing: any))
        }
    }

    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value, value >= Double(Int.min), value <= Double(Int.max) {
                return Int(value)
            }
            return value
        case .bool(let value): return value
        case .array(let values): return values.map(\.anyValue)
        case .object(let values): return values.mapValues(\.anyValue)
        case .null: return NSNull()
        }
    }

    public var displayText: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .array(let values): return values.map(\.displayText).joined(separator: ", ")
        case .object(let values):
            return values.keys.sorted().map { key in
                "\(key): \(values[key]?.displayText ?? "")"
            }.joined(separator: "\n")
        case .null: return "—"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([PuryJSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: PuryJSONValue].self) { self = .object(value); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Pury JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Confirmation Action Proposal

public struct PuryConfirmationAction: Codable, Sendable {
    public let actionId: String
    public let token: String
    public let intent: String
    public let domain: String?
    public let collectionTarget: String?
    public let entityId: String?
    public let permissionRequired: String?
    public let updates: [String: PuryJSONValue]?
    public let beforeState: [String: PuryJSONValue]?
    public let scope: PuryJSONValue?
    public let expectedRevision: Int?
    public let beforeStateHash: String?
    public let policyVersion: String?
    public let expiresAt: Int64?
    public let warnings: [String]?
    public let riskTier: Int?

    public init(
        actionId: String,
        token: String,
        intent: String,
        domain: String? = nil,
        collectionTarget: String? = nil,
        entityId: String? = nil,
        permissionRequired: String? = nil,
        updates: [String: PuryJSONValue]? = nil,
        beforeState: [String: PuryJSONValue]? = nil,
        scope: PuryJSONValue? = nil,
        expectedRevision: Int? = nil,
        beforeStateHash: String? = nil,
        policyVersion: String? = nil,
        expiresAt: Int64? = nil,
        warnings: [String]? = nil,
        riskTier: Int? = 3
    ) {
        self.actionId = actionId
        self.token = token
        self.intent = intent
        self.domain = domain
        self.collectionTarget = collectionTarget
        self.entityId = entityId
        self.permissionRequired = permissionRequired
        self.updates = updates
        self.beforeState = beforeState
        self.scope = scope
        self.expectedRevision = expectedRevision
        self.beforeStateHash = beforeStateHash
        self.policyVersion = policyVersion
        self.expiresAt = expiresAt
        self.warnings = warnings
        self.riskTier = riskTier
    }

    /// Confirmation execution intentionally sends only the opaque signed token
    /// and UI action identity. Server execution reconstructs every protected
    /// field from the cryptographically signed envelope and ignores client echo.
    public func asDictionary() -> [String: Any] {
        [
            "token": token,
            "actionId": actionId,
        ]
    }
}

// MARK: - Response Metadata

public struct PuryResponseMetadata: Codable, Sendable {
    public let intent: String?
    public let domain: String?
    public let operation: String?
    public let riskTier: Int?
    public let permissionRequired: String?
    public let confirmationRequired: Bool?
    public let confirmationAction: PuryConfirmationAction?
    public let structuredData: PuryStructuredData?
    public let resultRefs: [PuryEntityRef]?
    public let result_count: Int?
    public let source_used: String?
    public let latencyMs: Int?
    public let clientType: String?
    public let agent: String?
    public let callable: String?
    public let error: String?
    public let errorSummary: String?
    public let commandState: String?
    public let commandId: String?
    public let replayed: Bool?
    public let requestId: String?

    public init(
        intent: String? = nil,
        domain: String? = nil,
        operation: String? = nil,
        riskTier: Int? = nil,
        permissionRequired: String? = nil,
        confirmationRequired: Bool? = nil,
        confirmationAction: PuryConfirmationAction? = nil,
        structuredData: PuryStructuredData? = nil,
        resultRefs: [PuryEntityRef]? = nil,
        result_count: Int? = nil,
        source_used: String? = nil,
        latencyMs: Int? = nil,
        clientType: String? = nil,
        agent: String? = nil,
        callable: String? = nil,
        error: String? = nil,
        errorSummary: String? = nil,
        commandState: String? = nil,
        commandId: String? = nil,
        replayed: Bool? = nil,
        requestId: String? = nil
    ) {
        self.intent = intent
        self.domain = domain
        self.operation = operation
        self.riskTier = riskTier
        self.permissionRequired = permissionRequired
        self.confirmationRequired = confirmationRequired
        self.confirmationAction = confirmationAction
        self.structuredData = structuredData
        self.resultRefs = resultRefs
        self.result_count = result_count
        self.source_used = source_used
        self.latencyMs = latencyMs
        self.clientType = clientType
        self.agent = agent
        self.callable = callable
        self.error = error
        self.errorSummary = errorSummary
        self.commandState = commandState
        self.commandId = commandId
        self.replayed = replayed
        self.requestId = requestId
    }
}

// MARK: - In-Memory Conversation Message

public enum PuryMessageRole: String, Codable, Sendable {
    case user
    case model
    case system
}

public struct PuryMessage: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let role: PuryMessageRole
    public let text: String
    public let timestamp: Date
    public let metadata: PuryResponseMetadata?

    public init(
        id: UUID = UUID(),
        role: PuryMessageRole,
        text: String,
        timestamp: Date = Date(),
        metadata: PuryResponseMetadata? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.metadata = metadata
    }

    public static func == (lhs: PuryMessage, rhs: PuryMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text && lhs.role == rhs.role
    }
}

// MARK: - Inline Authoring Task

public enum PuryAuthoringTask: String, Codable, CaseIterable, Sendable {
    case translate = "editor_translate"
    case improveName = "editor_improve_name"
    case generateDescription = "editor_generate_description"
    case rewriteShorter = "editor_rewrite_shorter"
    case improveBilingual = "editor_improve_bilingual"

    public var localizedLabel: String {
        switch self {
        case .translate:
            return Language.get("Pury_Task_Translate", alter: "ترجمة فورية")
        case .improveName:
            return Language.get("Pury_Task_ImproveName", alter: "تحسين الاسم")
        case .generateDescription:
            return Language.get("Pury_Task_GenDesc", alter: "توليد وصف متكامل")
        case .rewriteShorter:
            return Language.get("Pury_Task_Shorten", alter: "اختصار وإيجاز")
        case .improveBilingual:
            return Language.get("Pury_Task_ImproveBilingual", alter: "صياغة اللغتين معاً")
        }
    }

    public var icon: String {
        switch self {
        case .translate: return "character.bubble"
        case .improveName: return "wand.and.stars"
        case .generateDescription: return "text.badge.plus"
        case .rewriteShorter: return "arrow.down.right.and.arrow.up.left"
        case .improveBilingual: return "arrow.left.arrow.right"
        }
    }
}

public struct PuryAuthoringResponse: Codable, Sendable {
    public let nameAr: String?
    public let nameEn: String?
    public let descAr: String?
    public let descEn: String?
    public let limitations: [String]?
    public let factsUsed: [String]?
    public let task: String?

    public init(
        nameAr: String? = nil,
        nameEn: String? = nil,
        descAr: String? = nil,
        descEn: String? = nil,
        limitations: [String]? = nil,
        factsUsed: [String]? = nil,
        task: String? = nil
    ) {
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.descAr = descAr
        self.descEn = descEn
        self.limitations = limitations
        self.factsUsed = factsUsed
        self.task = task
    }
}
