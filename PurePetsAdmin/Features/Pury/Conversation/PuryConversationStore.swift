//
//  PuryConversationStore.swift
//  PurePetsAdmin
//
//  Ephemeral in-memory conversation and state store for Pury Admin Operational Agent.
//  Invariants:
//   - Zero disk persistence (cleared on sign-out, session change, or app kill).
//   - Bounded history (maximum 8 turns sent to backend).
//   - Enforces truthful UI state machine.
//

import SwiftUI
import Combine

@MainActor
public final class PuryConversationStore: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case ready
        case empty
        case denied(String)
        case confirmationRequired(PuryConfirmationAction)
        case conflictStale(String)
        case error(String)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.ready, .ready), (.empty, .empty):
                return true
            case (.denied(let l), .denied(let r)):
                return l == r
            case (.confirmationRequired(let l), .confirmationRequired(let r)):
                return l.token == r.token
            case (.conflictStale(let l), .conflictStale(let r)):
                return l == r
            case (.error(let l), .error(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    // MARK: - Published Properties

    @Published public private(set) var state: State = .idle
    @Published public private(set) var messages: [PuryMessage] = []
    @Published public private(set) var activeProposal: PuryConfirmationAction? = nil
    @Published public var currentInputText: String = ""
    @Published public var language: String = Language.isRTL() ? "ar" : "en"

    private let service: PuryAdminService
    private let maxHistoryTurns = 8
    private var cancellables = Set<AnyCancellable>()
    private let sessionId = UUID().uuidString

    public init(service: PuryAdminService = .shared) {
        self.service = service
    }

    // MARK: - User Intent Actions

    public func sendMessage(_ text: String, screenContext: PuryScreenContext?) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMsg = PuryMessage(role: .user, text: trimmed)
        messages.append(userMsg)
        currentInputText = ""
        state = .loading

        let historyPayload = recentHistoryPayload()

        do {
            let response = try await service.sendChatMessage(
                message: trimmed,
                sessionId: sessionId,
                language: language,
                history: historyPayload,
                screenContext: screenContext
            )

            handleResponse(response)
        } catch let err as PuryError {
            handleError(err)
        } catch {
            let msg = error.localizedDescription
            state = .error(msg)
            messages.append(PuryMessage(role: .model, text: msg))
        }
    }

    public func confirmAction(_ action: PuryConfirmationAction, screenContext: PuryScreenContext?) async {
        state = .loading
        activeProposal = nil

        var confirmDict: [String: Any] = [
            "token": action.token,
            "intent": action.intent,
            "actionId": action.actionId
        ]
        if let d = action.domain { confirmDict["domain"] = d }
        if let c = action.collectionTarget { confirmDict["collectionTarget"] = c }
        if let e = action.entityId { confirmDict["entityId"] = e }
        if let p = action.permissionRequired { confirmDict["permissionRequired"] = p }
        if let u = action.updates { confirmDict["updates"] = u }

        let historyPayload = recentHistoryPayload()
        let confirmText = Language.get("Pury_Confirm_Prompt", alter: "تأكيد تنفيذ العملية")

        do {
            let response = try await service.sendChatMessage(
                message: confirmText,
                sessionId: sessionId,
                language: language,
                history: historyPayload,
                screenContext: screenContext,
                confirmAction: confirmDict
            )

            handleResponse(response)
        } catch let err as PuryError {
            handleError(err)
        } catch {
            let msg = error.localizedDescription
            state = .error(msg)
            messages.append(PuryMessage(role: .model, text: msg))
        }
    }

    public func cancelAction() {
        activeProposal = nil
        state = .ready
        let cancelNotice = Language.get("Pury_Action_Cancelled", alter: "تم إلغاء العملية المقترحة دون أي تعديل.")
        messages.append(PuryMessage(role: .model, text: cancelNotice))
    }

    public func clearHistory() {
        messages.removeAll()
        activeProposal = nil
        state = .idle
    }

    // MARK: - Private Helpers

    private func handleResponse(_ response: PuryChatResponse) {
        let meta = response.metadata

        if let err = meta.error, !err.isEmpty {
            let summary = meta.errorSummary ?? err
            if err == "permission_denied" {
                state = .denied(summary)
            } else if err == "conflict_stale" {
                state = .conflictStale(summary)
            } else {
                state = .error(summary)
            }
            messages.append(PuryMessage(role: .model, text: summary, metadata: meta))
            return
        }

        if meta.confirmationRequired == true, let action = meta.confirmationAction {
            activeProposal = action
            state = .confirmationRequired(action)
            messages.append(PuryMessage(role: .model, text: response.text, metadata: meta))
            return
        }

        activeProposal = nil
        let isResultEmpty = (meta.result_count == 0 && response.text.isEmpty)
        state = isResultEmpty ? .empty : .ready

        messages.append(PuryMessage(role: .model, text: response.text, metadata: meta))
    }

    private func handleError(_ err: PuryError) {
        let desc = err.localizedDescription
        switch err {
        case .permissionDenied:
            state = .denied(desc)
        case .conflictStale:
            state = .conflictStale(desc)
        default:
            state = .error(desc)
        }
        messages.append(PuryMessage(role: .model, text: desc))
    }

    private func recentHistoryPayload() -> [[String: String]] {
        messages.suffix(maxHistoryTurns).compactMap { msg in
            let r = msg.role == .user ? "user" : "model"
            return ["role": r, "text": msg.text]
        }
    }
}
