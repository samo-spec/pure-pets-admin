//
//  PuryModels.swift
//  PurePetsAdmin
//
//  Authoritative data and contract models for Pury Admin Operational Agent.
//  Matches Cloud Functions GeneKit Pury contracts.
//

import Foundation

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

    public var displayLabel: String {
        if let stayId = stayId, !stayId.isEmpty {
            return Language.get("Pury_Context_Stay", alter: "إقامة فندقية: #\(stayId.prefix(8))")
        }
        if let reservationId = reservationId, !reservationId.isEmpty {
            return Language.get("Pury_Context_Reservation", alter: "حجز فندقي: #\(reservationId.prefix(8))")
        }
        if let accommodationId = accommodationId, !accommodationId.isEmpty {
            return Language.get("Pury_Context_Suite", alter: "جناح فندقي: #\(accommodationId)")
        }
        if let entityType = entityType, let entityId = entityId, !entityId.isEmpty {
            return "\(entityType): #\(entityId.prefix(8))"
        }
        if let screen = screen {
            return localizedScreenName(screen)
        }
        if let route = route {
            return localizedScreenName(route)
        }
        return Language.get("Pury_Context_Admin", alter: "لوحة الإدارة")
    }

    private func localizedScreenName(_ name: String) -> String {
        switch name.lowercased() {
        case "command", "commandcenter", "command_center":
            return Language.get("Pury_Context_Command", alter: "مركز العمليات والقيادة")
        case "hotel":
            return Language.get("Pury_Context_Hotel", alter: "فندق الحيوانات")
        case "pos":
            return Language.get("Pury_Context_POS", alter: "نقطة البيع السريع")
        case "fulfillment":
            return Language.get("Pury_Context_Fulfillment", alter: "أوامر التجهيز والتسليم")
        case "more":
            return Language.get("Pury_Context_More", alter: "المزيد والإعدادات")
        case "accessories", "accessory":
            return Language.get("Pury_Context_Accessories", alter: "المستلزمات والمخزون")
        case "livepets", "live_pets", "livepet":
            return Language.get("Pury_Context_LivePets", alter: "الحيوانات الحية")
        case "food":
            return Language.get("Pury_Context_Food", alter: "قسم الأغذية")
        case "users", "userscol":
            return Language.get("Pury_Context_Users", alter: "ملفات العملاء")
        case "staff", "staff_users":
            return Language.get("Pury_Context_Staff", alter: "فريق العمل والأطباء")
        case "branches", "branch":
            return Language.get("Pury_Context_Branches", alter: "الفروع والمستودعات")
        case "paymentorder", "order", "orders":
            return Language.get("Pury_Context_Orders", alter: "إدارة الطلبات")
        default:
            return name
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
