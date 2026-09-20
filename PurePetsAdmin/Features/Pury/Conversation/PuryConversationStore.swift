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
        case pending(String)
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
            case (.pending(let l), .pending(let r)):
                return l == r
            case (.conflictStale(let l), .conflictStale(let r)):
                return l == r
            case (.error(let l), .error(let r)):
                return l == r
            default:
                return false
            }
        }

        public var isWaitingOrThinking: Bool {
            switch self {
            case .loading, .pending:
                return true
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

    public var isWaitingOrThinking: Bool {
        state.isWaitingOrThinking
    }

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

        let historyPayload = recentHistoryPayload()
        let confirmText = Language.get("Pury_Confirm_Prompt", alter: "تأكيد تنفيذ العملية")

        do {
            let response = try await service.sendChatMessage(
                message: confirmText,
                sessionId: sessionId,
                language: language,
                history: historyPayload,
                screenContext: screenContext,
                confirmAction: action
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

        if meta.commandState == "in_progress" || meta.commandState == "receipt_finalize_pending" {
            activeProposal = nil
            let message = !response.text.isEmpty
                ? response.text
                : Language.get("Pury_Command_Pending", alter: "يتم استكمال الأمر المؤكد بأمان.")
            state = .pending(message)
            messages.append(PuryMessage(role: .model, text: message, metadata: meta))
            return
        }

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


extension PuryConversationStore.State {
    var puryMotionState: PuryMotionState {
        switch self {
        case .idle: return .idle
        case .loading: return .thinking
        case .pending: return .searching
        case .ready: return .success
        case .empty: return .confused
        case .confirmationRequired: return .warning
        case .conflictStale: return .warning
        case .denied, .error: return .error
        }
    }
}
