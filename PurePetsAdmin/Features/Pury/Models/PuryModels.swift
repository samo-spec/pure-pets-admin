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
            return screen
        }
        if let route = route {
            return route
        }
        return Language.get("Pury_Context_Admin", alter: "لوحة الإدارة")
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

// MARK: - Confirmation Action Proposal

public struct PuryConfirmationAction: Codable, Sendable {
    public let actionId: String
    public let token: String
    public let intent: String
    public let domain: String?
    public let collectionTarget: String?
    public let entityId: String?
    public let permissionRequired: String?
    public let updates: [String: String]?
    public let beforeState: [String: String]?
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
        updates: [String: String]? = nil,
        beforeState: [String: String]? = nil,
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
        self.warnings = warnings
        self.riskTier = riskTier
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
        errorSummary: String? = nil
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
