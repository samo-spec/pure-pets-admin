//
//  PuryAdminService.swift
//  PurePetsAdmin
//
//  Authoritative Firebase Functions bridge for Pury Admin Operational Agent.
//  Invokes `puryAdminChat` and `puryAdminAuthor` callables.
//

import Foundation
import FirebaseAuth
import FirebaseFunctions

public enum PuryError: LocalizedError {
    case unauthenticated
    case permissionDenied(String)
    case invalidArgument(String)
    case conflictStale(String)
    case networkError(String)
    case invalidResponse
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return Language.get("Pury_Err_Unauthenticated", alter: "يجب تسجيل الدخول كأحد موظفي بيور بيتس المعتمدين.")
        case .permissionDenied(let reason):
            return reason.isEmpty
                ? Language.get("Pury_Err_PermissionDenied", alter: "ليس لديك الصلاحية الكافية للوصول إلى مساعد بيوري أو تنفيذ هذا الأمر.")
                : reason
        case .invalidArgument(let reason):
            return reason
        case .conflictStale(let reason):
            return reason.isEmpty
                ? Language.get("Pury_Err_ConflictStale", alter: "تغيرت حالة السجل أثناء المعالجة. يرجى تحديث البيانات والمحاولة مجدداً.")
                : reason
        case .networkError(let message):
            return "\(Language.get("Pury_Err_Network", alter: "خطأ في الاتصال بالخادم")): \(message)"
        case .invalidResponse:
            return Language.get("Pury_Err_InvalidResponse", alter: "استجابة غير متوقعة من خادم بيوري.")
        case .serverError(let message):
            return message
        }
    }
}

public actor PuryAdminService {
    public static let shared = PuryAdminService()

    private let functions: Functions
    private let timeoutInterval: TimeInterval = 25.0

    public init(functions: Functions = Functions.functions(region: "us-central1")) {
        self.functions = functions
    }

    // MARK: - Chat Callable

    public func sendChatMessage(
        message: String,
        sessionId: String?,
        language: String,
        history: [[String: String]],
        screenContext: PuryScreenContext?,
        confirmAction: [String: Any]? = nil
    ) async throws -> PuryChatResponse {
        guard Auth.auth().currentUser != nil else {
            throw PuryError.unauthenticated
        }

        var contextDict: [String: Any] = [
            "history": history.map { item in
                ["role": item["role"] ?? "user", "text": item["text"] ?? ""]
            }
        ]

        if let sc = screenContext, !sc.isEmpty {
            var scDict: [String: Any] = [:]
            if let s = sc.screen { scDict["screen"] = s }
            if let r = sc.route { scDict["route"] = r }
            if let b = sc.branchId { scDict["branchId"] = b }
            if let et = sc.entityType { scDict["entityType"] = et }
            if let ei = sc.entityId { scDict["entityId"] = ei }
            if let res = sc.reservationId { scDict["reservationId"] = res }
            if let st = sc.stayId { scDict["stayId"] = st }
            if let acc = sc.accommodationId { scDict["accommodationId"] = acc }
            contextDict["screenContext"] = scDict
        }

        let client = PuryClientInfo(locale: language)
        var clientDict: [String: Any] = [
            "platform": client.platform,
            "locale": language
        ]
        if let v = client.appVersion { clientDict["appVersion"] = v }
        if let b = client.buildNumber { clientDict["buildNumber"] = b }

        var payload: [String: Any] = [
            "message": message,
            "language": language,
            "context": contextDict,
            "client": clientDict
        ]

        if let sId = sessionId, !sId.isEmpty {
            payload["sessionId"] = sId
        }

        if let ca = confirmAction {
            payload["confirmAction"] = ca
        }

        let dict = try await executeCallable(name: "puryAdminChat", payload: payload)
        return try parseChatResponse(from: dict)
    }

    // MARK: - Authoring Callable

    public func requestAuthoring(
        task: PuryAuthoringTask,
        itemType: String,
        sourceLanguage: String,
        targetLanguage: String,
        currentText: [String: String],
        attributes: [String: String] = [:]
    ) async throws -> PuryAuthoringResponse {
        guard Auth.auth().currentUser != nil else {
            throw PuryError.unauthenticated
        }

        let client = PuryClientInfo(locale: sourceLanguage)
        var clientDict: [String: Any] = [
            "platform": client.platform,
            "locale": sourceLanguage
        ]
        if let v = client.appVersion { clientDict["appVersion"] = v }
        if let b = client.buildNumber { clientDict["buildNumber"] = b }

        let payload: [String: Any] = [
            "task": task.rawValue,
            "itemType": itemType,
            "sourceLanguage": sourceLanguage,
            "targetLanguage": targetLanguage,
            "currentText": currentText,
            "attributes": attributes,
            "client": clientDict
        ]

        let dict = try await executeCallable(name: "puryAdminAuthor", payload: payload)
        return PuryAuthoringResponse(
            nameAr: dict["nameAr"] as? String,
            nameEn: dict["nameEn"] as? String,
            descAr: dict["descAr"] as? String,
            descEn: dict["descEn"] as? String,
            limitations: dict["limitations"] as? [String],
            factsUsed: dict["factsUsed"] as? [String],
            task: dict["task"] as? String ?? task.rawValue
        )
    }

    // MARK: - Core Callable Execution

    private struct PurySendablePayload: @unchecked Sendable {
        let dict: [String: Any]
    }

    private func executeCallable(name: String, payload: [String: Any]) async throws -> [String: Any] {
        let callable = functions.httpsCallable(name)
        callable.timeoutInterval = timeoutInterval
        let boxed = PurySendablePayload(dict: payload)

        do {
            let resultBox = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PurySendablePayload, Error>) in
                callable.call(boxed.dict) { result, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let dict = result?.data as? [String: Any] {
                        continuation.resume(returning: PurySendablePayload(dict: dict))
                    } else {
                        continuation.resume(throwing: PuryError.invalidResponse)
                    }
                }
            }
            return resultBox.dict
        } catch let puryErr as PuryError {
            throw puryErr
        } catch let err as NSError {
            throw mapFunctionsError(err)
        }
    }

    public nonisolated func requestAuthoring(
        task: PuryAuthoringTask,
        itemType: String,
        sourceLanguage: String,
        targetLanguage: String,
        currentText: [String: String],
        attributes: [String: Any]
    ) async throws -> PuryAuthoringResponse {
        let stringAttrs = attributes.compactMapValues { "\($0)" }
        return try await requestAuthoring(
            task: task,
            itemType: itemType,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            currentText: currentText,
            attributes: stringAttrs
        )
    }

    // MARK: - Error Mapping

    private func mapFunctionsError(_ err: NSError) -> PuryError {
        if err.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: err.code)
            let details = err.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            let message = err.localizedDescription

            switch code {
            case .unauthenticated:
                return .unauthenticated
            case .permissionDenied:
                let msg = details?["message"] as? String ?? message
                return .permissionDenied(msg)
            case .invalidArgument:
                let msg = details?["message"] as? String ?? message
                return .invalidArgument(msg)
            case .failedPrecondition, .aborted, .alreadyExists:
                let msg = details?["message"] as? String ?? message
                return .conflictStale(msg)
            default:
                return .serverError(message)
            }
        }
        return .networkError(err.localizedDescription)
    }

    // MARK: - Parsing Helpers

    private func parseChatResponse(from dict: [String: Any]) throws -> PuryChatResponse {
        let text = dict["text"] as? String ?? ""
        let metaDict = dict["metadata"] as? [String: Any] ?? [:]

        var confirmationAction: PuryConfirmationAction? = nil
        if let caDict = metaDict["confirmationAction"] as? [String: Any] {
            confirmationAction = PuryConfirmationAction(
                actionId: caDict["actionId"] as? String ?? "",
                token: caDict["token"] as? String ?? "",
                intent: caDict["intent"] as? String ?? "",
                domain: caDict["domain"] as? String,
                collectionTarget: caDict["collectionTarget"] as? String,
                entityId: caDict["entityId"] as? String,
                permissionRequired: caDict["permissionRequired"] as? String,
                updates: caDict["updates"] as? [String: String],
                beforeState: caDict["beforeState"] as? [String: String],
                warnings: caDict["warnings"] as? [String],
                riskTier: caDict["riskTier"] as? Int ?? 3
            )
        }

        var structuredData: PuryStructuredData? = nil
        if let sdDict = metaDict["structuredData"] as? [String: Any] {
            var cards: [PuryCard] = []
            if let cardList = sdDict["cards"] as? [[String: Any]] {
                for cardDict in cardList {
                    var fields: [PuryField]? = nil
                    if let fList = cardDict["details"] as? [[String: Any]] {
                        fields = fList.compactMap { f in
                            guard let l = f["label"] as? String, let v = f["value"] as? String else { return nil }
                            return PuryField(label: l, value: v, type: f["type"] as? String, tone: f["tone"] as? String)
                        }
                    }
                    cards.append(PuryCard(
                        id: cardDict["id"] as? String ?? UUID().uuidString,
                        title: cardDict["title"] as? String ?? "",
                        subtitle: cardDict["subtitle"] as? String,
                        status: cardDict["status"] as? String,
                        badge: cardDict["badge"] as? String,
                        entityType: cardDict["entityType"] as? String,
                        entityId: cardDict["entityId"] as? String,
                        details: fields,
                        actionRoute: cardDict["actionRoute"] as? String
                    ))
                }
            }

            var blocks: [PuryDataBlock] = []
            if let blockList = sdDict["dataBlocks"] as? [[String: Any]] {
                for bDict in blockList {
                    let type = bDict["type"] as? String ?? "record"
                    let col = bDict["collection"] as? String
                    var fields: [PuryField] = []
                    if let fList = bDict["fields"] as? [[String: Any]] {
                        fields = fList.compactMap { f in
                            guard let l = f["label"] as? String, let v = f["value"] as? String else { return nil }
                            return PuryField(label: l, value: v, type: f["type"] as? String, tone: f["tone"] as? String)
                        }
                    }
                    blocks.append(PuryDataBlock(
                        id: bDict["id"] as? String ?? UUID().uuidString,
                        type: type,
                        collection: col,
                        fields: fields
                    ))
                }
            }

            structuredData = PuryStructuredData(
                version: sdDict["version"] as? Int ?? 1,
                renderer: sdDict["renderer"] as? String,
                cards: cards.isEmpty ? nil : cards,
                dataBlocks: blocks.isEmpty ? nil : blocks,
                resultRefs: sdDict["resultRefs"] as? [String]
            )
        }

        let metadata = PuryResponseMetadata(
            intent: metaDict["intent"] as? String,
            domain: metaDict["domain"] as? String,
            operation: metaDict["operation"] as? String,
            riskTier: metaDict["riskTier"] as? Int,
            permissionRequired: metaDict["permissionRequired"] as? String,
            confirmationRequired: metaDict["confirmationRequired"] as? Bool,
            confirmationAction: confirmationAction,
            structuredData: structuredData,
            resultRefs: nil,
            result_count: metaDict["result_count"] as? Int,
            source_used: metaDict["source_used"] as? String,
            latencyMs: metaDict["latencyMs"] as? Int,
            clientType: metaDict["clientType"] as? String,
            agent: metaDict["agent"] as? String,
            callable: metaDict["callable"] as? String,
            error: metaDict["error"] as? String,
            errorSummary: metaDict["errorSummary"] as? String
        )

        return PuryChatResponse(text: text, metadata: metadata)
    }
}

public struct PuryChatResponse: Sendable {
    public let text: String
    public let metadata: PuryResponseMetadata

    public init(text: String, metadata: PuryResponseMetadata) {
        self.text = text
        self.metadata = metadata
    }
}
