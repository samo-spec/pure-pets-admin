//
//  PuryAssistantSheetView.swift
//  PurePetsAdmin
//
//  Native, studio-grade category-defining operational AI assistant sheet for Pure Pets Admin.
//  Preserves operator screen position and bounded context.
//

import SwiftUI
import Foundation

@available(iOS 16.0, *)
struct PuryAssistantSheetView: View {
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    var screenContext: PuryScreenContext? = nil

    @StateObject private var store = PuryConversationStore()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool

    // MARK: - Animation Control Flags

    /// Temporarily disables all continuous living/alive screen animations across the entire Pury chat screen
    /// (ambient background atmosphere pulse, avatar living breathing/stardust drift, status dot scaling, and synaptic beacon pulse).
    private static let isScreenAliveAnimationEnabled: Bool = false

    /// Scroll anchors. The reading dossier and a pending Tier-3 approval both need to be
    /// reachable from outside the `ScrollViewReader`.
    private static let readingAnchor = "pury_reading_dossier"
    private static let pendingApprovalAnchor = "pury_pending_approval"

    /// Authoritative horizontal breathing room for all sheet subviews.
    private static let sheetHorizontalMargin: CGFloat = 20

    /// Optical perimeter beyond the system safe area. The system safe area protects
    /// hardware; this keeps interactive chrome from visually touching the screen edge.
    private static let sheetPerimeterInset: CGFloat = 8

    /// The foreground crown begins below the status-bar safe-area boundary; only the
    /// decorative atmosphere is allowed to extend behind system chrome.
    private static let navigationSafeAreaClearance: CGFloat = 8

    /// A completed answer needs a distinct handoff before the next operator prompt. The
    /// stack keeps its normal rhythm elsewhere; this is only answer -> new question space.
    private static let answerToNextQueryBreathingRoom: CGFloat = 14

    // Living Avatar & Motion States
    @State private var ambientPulse: Bool = false

    /// Presentation-only crown state. The crown compacts on real product signals —
    /// the operator is composing, or the conversation already has depth — rather than
    /// on scroll offset, which avoids mid-scroll jitter and layout feedback loops.
    @State private var isClearConfirmationPresented: Bool = false

    /// Set from the composer to move the conversation to an anchor that lives inside the
    /// scroll view, which the composer cannot reach directly.
    @State private var pendingScrollTarget: String? = nil

    private var isCrownCompact: Bool {
        isInputFocused || store.messages.count >= 3
    }

    private var isRTL: Bool {
        if store.language == "ar" { return true }
        if store.language == "en" { return false }
        return Language.isRTL()
    }

    /// Pury's own conversation language. `isRTL` already originates from
    /// `PuryConversationStore.language`, so deriving the language code from it keeps every
    /// string on this surface resolving from one source rather than the app-wide bundle.
    private var language: String { isRTL ? "ar" : "en" }


    init(
        session: AdminSession,
        router: AdminRouter,
        screenContext: PuryScreenContext? = nil
    ) {
        PPBrandFont.registerIfNeeded()
        self.session = session
        self.router = router
        self.screenContext = screenContext
    }

    var body: some View {
        ZStack {
            // Ambient Atmospheric Background
            ambientAtmosphere

            // Conversation Ledger
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        if store.messages.isEmpty {
                            PuryLaunchDeck(
                                language: store.language,
                                isRTL: isRTL,
                                screenContext: screenContext,
                                authorizedIntentIDs: authorizedIntentIDs,
                                authorizedQueryIDs: authorizedQueryIDs,
                                onRun: { prompt in rerunQuery(prompt) }
                            )
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        } else {
                            ForEach(store.messages) { message in
                                messageStreamRow(for: message)
                                    .padding(.bottom, bottomBreathingRoom(after: message))
                                    .id(message.id)
                            }

                            if store.isWaitingOrThinking {
                                PuryReadingDossier(
                                    language: store.language,
                                    isRTL: isRTL,
                                    allowsMotion: !reduceMotion
                                )
                                .id(Self.readingAnchor)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }
                    .padding(.horizontal, Self.sheetHorizontalMargin)
                    .padding(.top, 14)
                    .padding(.bottom, 24) // composer owns its space through safeAreaInset
                    .frame(maxWidth: 680)
                }
                .frame(maxWidth: .infinity)
                // Content dissolves into the command bar instead of being clipped by it.
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [AdminSurface.background.opacity(0), AdminSurface.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)
                    .allowsHitTesting(false)
                }
                .onChange(of: store.messages.count) { _ in
                    scrollToLatest(proxy: proxy)
                }
                .onChange(of: store.state) { _ in
                    scrollToLatest(proxy: proxy)
                }
                .onChange(of: pendingScrollTarget) { target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    pendingScrollTarget = nil
                }
            }
            .padding(.horizontal, Self.sheetPerimeterInset)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Single authored header surface: identity, bound data scope, and the
            // live state machine on one crown spanning edge-to-edge and filling the
            // top safe area layout guide inset.
            puryCommandCrown
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingInputDock
                .padding(.horizontal, Self.sheetPerimeterInset)
                .padding(.bottom, Self.sheetPerimeterInset)
        }
        .ignoresSafeArea(.all, edges: .top)
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .confirmationDialog(
            PuryLocale.text(
                "Pury_Clear_Chat",
                language: store.language,
                ar: "مسح المحادثة",
                en: "Clear Conversation"
            ),
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                PuryLocale.text(
                    "Pury_Clear_Confirm_Action",
                    language: store.language,
                    ar: "مسح المحادثة",
                    en: "Clear Conversation"
                ),
                role: .destructive
            ) {
                store.clearHistory()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

            Button(
                PuryLocale.text("Pury_Clear_Cancel_Action", language: store.language, ar: "إلغاء", en: "Cancel"),
                role: .cancel
            ) {}
        } message: {
            Text(
                PuryLocale.text(
                    "Pury_Clear_Confirm_Message",
                    language: store.language,
                    ar: "سيتم حذف هذه المحادثة من الجهاز فقط. لن يتأثر أي سجل تشغيلي.",
                    en: "This clears the conversation on this device only. No operational record is affected."
                )
            )
        }
        .onAppear {
            PPBrandFont.registerIfNeeded()
            guard Self.isScreenAliveAnimationEnabled && !reduceMotion else {
                ambientPulse = false
                return
            }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                ambientPulse = true
            }
        }
    }

    // MARK: - Ambient Atmosphere

    private var ambientAtmosphere: some View {
        // Size-class safe: the glow is placed by layout alignment rather than by a
        // hard-coded main-screen width, which is wrong on iPad, Slide Over, and Split View.
        ZStack(alignment: .top) {
            AdminSurface.background

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            PuryBrand.hotPink.opacity(Self.isScreenAliveAnimationEnabled && ambientPulse ? 0.14 : 0.06),
                            PuryBrand.violet.opacity(Self.isScreenAliveAnimationEnabled && ambientPulse ? 0.07 : 0.025),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 40,
                        endRadius: 360
                    )
                )
                .frame(width: 460, height: 460)
                .offset(y: -110)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Operator Authorization Projection

    /// Launch-deck offers are gated by the same `AdminRoute` authorization the app uses for
    /// navigation, so Pury never proposes a query whose result the operator cannot open.
    private func isAuthorized(_ route: AdminRoute) -> Bool {
        route.isAuthorized(for: session)
    }

    private var authorizedIntentIDs: Set<String> {
        var allowed: Set<String> = []
        if isAuthorized(.hotel) { allowed.insert("hotel") }
        if isAuthorized(.accessories) || isAuthorized(.food) || isAuthorized(.livePets) { allowed.insert("stock") }
        if isAuthorized(.fulfillment) || isAuthorized(.payments) { allowed.insert("orders") }
        if isAuthorized(.payments) || isAuthorized(.accounting) { allowed.insert("performance") }
        return allowed
    }

    private var authorizedQueryIDs: Set<String> {
        var allowed: Set<String> = []
        if isAuthorized(.veterinarians) || isAuthorized(.staff) { allowed.insert("vets") }
        if isAuthorized(.adoptionManager) { allowed.insert("adoption") }
        if isAuthorized(.hotel) { allowed.insert("guests") }
        if isAuthorized(.accessories) { allowed.insert("audit") }
        if isAuthorized(.delivery) { allowed.insert("delivery") }
        if isAuthorized(.hotel) { allowed.insert("bookings") }
        if isAuthorized(.branches) { allowed.insert("branches") }
        if isAuthorized(.community) || isAuthorized(.moderation) { allowed.insert("missing") }
        if isAuthorized(.pointOfSale) || isAuthorized(.payments) { allowed.insert("posSales") }
        if isAuthorized(.livePets) { allowed.insert("livePets") }
        return allowed
    }

    // MARK: - Pury Command Crown
    private var puryCommandCrown: some View {
        PuryCommandCrown(
            language: store.language,
            isRTL: isRTL,
            state: store.state,
            screenContext: screenContext,
            isCompact: isCrownCompact,
            canClearConversation: !store.messages.isEmpty,
            onSelectLanguage: { code in
                guard store.language != code else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)) {
                    store.language = code
                }
                UISelectionFeedbackGenerator().selectionChanged()
            },
            onRequestClear: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isClearConfirmationPresented = true
            },
            onClose: {
                dismiss()
            }
        )
    }

    // MARK: - Message Stream Rows

    @ViewBuilder
    private func messageStreamRow(for message: PuryMessage) -> some View {
        if message.role == .user {
            PuryQueryTurn(
                text: message.text,
                timestamp: message.timestamp,
                isRTL: isRTL,
                language: store.language,
                showsInlineRerun: isLatestQuery(message) && !store.isWaitingOrThinking,
                onRerun: { rerunQuery(message.text) }
            )
        } else {
            puryAnswerTurn(message)
        }
    }

    /// Only the most recent operator query carries a visible re-run control; older turns
    /// keep it in their context menu so the stream never repeats chrome on every row.
    private func isLatestQuery(_ message: PuryMessage) -> Bool {
        store.messages.last(where: { $0.role == .user })?.id == message.id
    }

    private func bottomBreathingRoom(after message: PuryMessage) -> CGFloat {
        guard message.role == .model,
              let index = store.messages.firstIndex(where: { $0.id == message.id }) else {
            return 0
        }
        let nextIndex = store.messages.index(after: index)
        guard nextIndex < store.messages.endIndex,
              store.messages[nextIndex].role == .user else {
            return 0
        }
        return Self.answerToNextQueryBreathingRoom
    }

    /// Operational data moves underneath the operator, so asking the same question again
    /// is a first-class action rather than a retype.
    private func rerunQuery(_ text: String) {
        guard !store.isWaitingOrThinking else { return }
        isInputFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await store.sendMessage(text, screenContext: screenContext)
        }
    }

    private struct PuryRenderableStructuredContent {
        /// Entity-merged records. Cards and data blocks describing the same entity collapse
        /// into one projection, so a record can no longer appear twice in one answer.
        let records: [PuryRecordProjection]

        var hasResults: Bool { !records.isEmpty }
    }

    private func renderableStructuredContent(for message: PuryMessage) -> PuryRenderableStructuredContent {
        PuryRenderableStructuredContent(records: PuryAnswerProjection.records(for: message.metadata))
    }


    private enum PuryNarrativeRole {
        case title
        case subtitle
        case body
        case bullet
    }

    private struct PuryNarrativeBlock: Identifiable {
        let id = UUID()
        let role: PuryNarrativeRole
        let text: String
    }

    private func semanticNarrativeBlocks(
        for message: PuryMessage,
        structuredContent: PuryRenderableStructuredContent
    ) -> [PuryNarrativeBlock] {
        let cleaned = PuryResponseDisplaySanitizer.cleanNarrative(
            message.text,
            hasStructuredData: structuredContent.hasResults
        )
        let blocks = narrativeBlocks(from: cleaned)
        guard structuredContent.hasResults else { return blocks }
        return nonRedundantNarrativeBlocks(blocks, structuredContent: structuredContent)
    }

    private func narrativeBlocks(from cleanedText: String) -> [PuryNarrativeBlock] {
        let rawLines = cleanedText.components(separatedBy: "\n")
        var blocks: [PuryNarrativeBlock] = []
        var paragraph: [String] = []
        var hasEmittedContent = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }

            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            let endsLikeSentence = text.last.map { ".!?؟".contains($0) } ?? false
            let isShort = text.count <= 72 && words <= 10
            let role: PuryNarrativeRole
            if !hasEmittedContent && isShort && !endsLikeSentence {
                role = .title
            } else if isShort && text.hasSuffix(":") {
                role = .subtitle
            } else {
                role = .body
            }
            blocks.append(PuryNarrativeBlock(role: role, text: text))
            hasEmittedContent = true
        }

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if line.hasPrefix("• ") {
                flushParagraph()
                let bullet = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !bullet.isEmpty {
                    blocks.append(PuryNarrativeBlock(role: .bullet, text: bullet))
                    hasEmittedContent = true
                }
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        return blocks
    }

    private func structuredEvidenceTokens(_ content: PuryRenderableStructuredContent) -> Set<String> {
        var evidence: [String] = []
        for record in content.records {
            evidence.append(record.title)
            if let subtitle = record.subtitle { evidence.append(subtitle) }
            if let status = record.status { evidence.append(status) }
            if let badge = record.badge { evidence.append(badge) }
            if let collection = record.collection { evidence.append(collection) }
            for field in record.fields {
                evidence.append(field.cleanLabel)
                evidence.append(field.cleanValue)
            }
        }
        return Set(evidence.flatMap(answerTokens))
    }

    private func answerTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "of", "to", "for", "in", "on", "is", "are", "was", "were",
            "this", "that", "these", "those", "with", "from", "at", "by", "your", "you", "i", "we", "it",
            "من", "في", "على", "إلى", "الى", "عن", "هو", "هي", "هذا", "هذه", "ذلك", "تلك", "مع", "تم", "و", "أو"
        ]
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count > 1 && !stopWords.contains(token)
            }
    }

    /// When an answer carries records, a bulleted prose list of those same records is by
    /// definition a restatement — the records are the canonical form of the enumeration. So
    /// bullets are dropped wholesale and only genuine interpretation survives, capped so a
    /// verbose model cannot flood the turn.
    private func nonRedundantNarrativeBlocks(
        _ blocks: [PuryNarrativeBlock],
        structuredContent: PuryRenderableStructuredContent
    ) -> [PuryNarrativeBlock] {
        let evidence = structuredEvidenceTokens(structuredContent)
        let interpretiveCues = [
            "recommend", "suggest", "attention", "risk", "warning", "because", "next step", "should",
            "أنصح", "اقترح", "انتبه", "مخاطر", "تحذير", "لأن", "الخطوة التالية", "ينبغي", "يرجى", "راجع"
        ]
        let boilerplatePrefixes = [
            "here are", "i found", "found ", "results", "these are", "the results", "sure", "certainly",
            "إليك", "وجدت", "تم العثور", "النتائج", "هذه النتائج", "بالتأكيد", "يسعدني", "سأقدم"
        ]

        let kept = blocks.filter { block in
            // Enumeration never survives alongside the records it enumerates.
            if block.role == .bullet { return false }

            let folded = block.text
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            if boilerplatePrefixes.contains(where: { folded.contains($0) }) { return false }
            if interpretiveCues.contains(where: { folded.contains($0) }) { return true }

            let tokens = Set(answerTokens(block.text))
            guard !tokens.isEmpty else { return false }
            let overlap = Double(tokens.intersection(evidence).count) / Double(tokens.count)
            if tokens.count <= 2 && tokens.isSubset(of: evidence) { return false }
            if tokens.count >= 3 && overlap >= 0.5 { return false }
            return true
        }

        return Array(kept.prefix(2))
    }

    private func narrativePlainText(_ blocks: [PuryNarrativeBlock]) -> String {
        blocks.map { block in
            switch block.role {
            case .bullet: return "• \(block.text)"
            default: return block.text
            }
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func semanticNarrativeView(_ blocks: [PuryNarrativeBlock]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(blocks) { block in
                switch block.role {
                case .title:
                    Text(block.text)
                        .font(PPBrandFont.bold(size: 17, relativeTo: .headline))
                        .foregroundStyle(PuryBrand.primary)
                        .lineSpacing(2)
                case .subtitle:
                    Text(block.text)
                        .font(PPBrandFont.medium(size: 14, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineSpacing(3)
                case .body:
                    Text(block.text)
                        .font(PPBrandFont.regular(size: 15, relativeTo: .body))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineSpacing(5)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(PuryBrand.primary)
                            .frame(width: 5, height: 5)
                            .accessibilityHidden(true)
                        Text(block.text)
                            .font(PPBrandFont.regular(size: 14.5, relativeTo: .body))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineSpacing(4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
    }

    private func puryAnswerTurn(_ message: PuryMessage) -> some View {
        let structuredContent = renderableStructuredContent(for: message)
        let narrativeBlocks = semanticNarrativeBlocks(for: message, structuredContent: structuredContent)
        let copyText = narrativePlainText(narrativeBlocks)

        // Provenance is earned: the live-records badge is only claimed when the turn
        // actually carries records, and it counts merged entities — not card plus block
        // duplicates, which previously doubled the number the badge advertised.
        let recordCount: Int? = structuredContent.hasResults
            ? structuredContent.records.count
            : nil
        let latencyMs = message.metadata?.latencyMs
        let showsFooter = !copyText.isEmpty || (latencyMs ?? 0) > 0

        return VStack(alignment: .leading, spacing: 10) {
            PuryAnswerTurnHeader(
                language: store.language,
                isRTL: isRTL,
                timestamp: message.timestamp,
                recordCount: recordCount,
                isReading: false
            )

            purySmartAnswerView(message, structuredContent: structuredContent, narrativeBlocks: narrativeBlocks)

            if let action = message.metadata?.confirmationAction,
               message.metadata?.confirmationRequired == true,
               store.activeProposal?.token == action.token {
                PuryActionConfirmationCard(
                    action: action,
                    onConfirm: {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        Task {
                            await store.confirmAction(action, screenContext: screenContext)
                        }
                    },
                    onCancel: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.cancelAction()
                    }
                )
                .id(Self.pendingApprovalAnchor)
            }

            if showsFooter {
                PuryAnswerTurnFooter(
                    language: store.language,
                    latencyMs: latencyMs,
                    canCopy: !copyText.isEmpty,
                    onCopy: {
                        // Copy only operator-facing prose; never copy hidden tool traces.
                        UIPasteboard.general.string = copyText
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                )
            }
        }
    }

    // MARK: - Category-Defining Dynamic Answer Orchestrator

    /// Resolves the answer to a single form and renders only that form. Nothing here may
    /// present the same record through two components.
    @ViewBuilder
    private func purySmartAnswerView(
        _ message: PuryMessage,
        structuredContent: PuryRenderableStructuredContent,
        narrativeBlocks: [PuryNarrativeBlock]
    ) -> some View {
        let form = PuryAnswerProjection.form(
            metadata: message.metadata,
            records: structuredContent.records,
            hasNarrative: !narrativeBlocks.isEmpty
        )

        VStack(alignment: .leading, spacing: 12) {
            // Interpretation may accompany records; enumeration may not.
            if !narrativeBlocks.isEmpty, !isExceptionForm(form) {
                semanticNarrativeView(narrativeBlocks)
            }

            switch form {
            case .advisory:
                EmptyView()

            case .exception(let kind):
                PuryExceptionPanel(
                    kind: kind,
                    summary: PuryResponseDisplaySanitizer.cleanNarrative(message.text, hasStructuredData: false),
                    requiredPermission: message.metadata?.permissionRequired,
                    language: language,
                    onRetry: lastOperatorQuery.map { query in { rerunQuery(query) } }
                )

            case .emptyVerdict:
                PuryEmptyVerdictView(
                    language: language,
                    scopeLabel: screenContext?.displayLabel(language: language),
                    onBroaden: { isInputFocused = true }
                )

            case .dossier(let record):
                PuryRecordDossierView(
                    record: record,
                    language: language,
                    isRTL: isRTL,
                    recordTypeName: recordTypeName(for: record),
                    symbol: recordSymbol(for: record),
                    accent: recordAccent(for: record),
                    onOpenRecord: openProjectedRecord
                )

            case .stockLedger(let records):
                PuryStockLedgerView(
                    records: records,
                    language: language,
                    isRTL: isRTL,
                    onOpenInventory: { handleDeepLink(entityType: "petAccessories", entityId: "") },
                    onOpenRecord: openProjectedRecord
                )

            case .roster(let records):
                PuryRecordRosterView(
                    records: records,
                    language: language,
                    isRTL: isRTL,
                    title: structuredResultTitle(message: message, records: records, count: records.count),
                    symbol: recordSymbol(for: records.first),
                    onOpenRecord: openProjectedRecord
                )

            case .metricBoard(let records):
                PuryMetricBoardView(
                    records: records,
                    language: language,
                    title: structuredResultTitle(message: message, records: records, count: records.count),
                    onOpenRecord: openProjectedRecord
                )
            }
        }
    }

    private func isExceptionForm(_ form: PuryAnswerForm) -> Bool {
        if case .exception = form { return true }
        return false
    }

    private var lastOperatorQuery: String? {
        store.messages.last(where: { $0.role == .user })?.text
    }

    private func openProjectedRecord(_ record: PuryRecordProjection) {
        guard let type = record.navigationType else { return }
        handleDeepLink(entityType: type, entityId: record.entityId ?? "")
    }

    private func recordSignature(for record: PuryRecordProjection?) -> String {
        [record?.entityType, record?.collection, record?.badge, record?.title]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private func recordSymbol(for record: PuryRecordProjection?) -> String {
        let signature = recordSignature(for: record)
        if signature.contains("hotel") || signature.contains("stay") || signature.contains("إقامة") { return "building.2.fill" }
        if signature.contains("order") || signature.contains("طلب") { return "shippingbox.fill" }
        if signature.contains("accessor") || signature.contains("product") || signature.contains("منتج") { return "cube.box.fill" }
        if signature.contains("staff") || signature.contains("vet") { return "stethoscope" }
        if signature.contains("user") || signature.contains("customer") || signature.contains("عميل") { return "person.crop.circle.fill" }
        if signature.contains("branch") || signature.contains("فرع") { return "mappin.and.ellipse" }
        return "doc.text.fill"
    }

    private func recordAccent(for record: PuryRecordProjection?) -> Color {
        let signature = recordSignature(for: record)
        if signature.contains("hotel") || signature.contains("stay") { return AdminSurface.emerald }
        if signature.contains("order") { return Color(red: 59/255, green: 130/255, blue: 246/255) }
        if signature.contains("accessor") || signature.contains("product") { return AdminSurface.amber }
        return PuryBrand.primary
    }

    private func recordTypeName(for record: PuryRecordProjection) -> String {
        if let collection = record.collection,
           let name = PuryFieldSemantics.collectionName(collection, language: language) {
            return name
        }
        if let entityType = record.entityType,
           let name = PuryFieldSemantics.collectionName(entityType, language: language) {
            return name
        }
        return PuryLocale.text("Pury_Record_Generic", language: language, ar: "بيانات السجل", en: "Record Details")
    }

    private func structuredResultTitle(
        message: PuryMessage,
        records: [PuryRecordProjection],
        count: Int
    ) -> String {
        let signature = ([message.metadata?.domain, message.metadata?.operation]
            + records.flatMap { [$0.entityType, $0.collection, $0.badge] })
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if (signature.contains("hotel") || signature.contains("stay")) && signature.contains("active") {
            return localizedResultTitle(
                key: "Pury_Results_ActiveStays_Format",
                ar: "الإقامات النشطة: %@",
                en: "%@ active stays",
                count: count
            )
        }
        if signature.contains("hotel") || signature.contains("stay") {
            return localizedResultTitle(
                key: "Pury_Results_Hotel_Format",
                ar: "نتائج الفندق: %@",
                en: "%@ hotel results",
                count: count
            )
        }
        if signature.contains("order") {
            return localizedResultTitle(
                key: "Pury_Results_Orders_Format",
                ar: "نتائج الطلبات: %@",
                en: "%@ order results",
                count: count
            )
        }
        if signature.contains("stock") || signature.contains("product") || signature.contains("accessor") {
            return localizedResultTitle(
                key: "Pury_Results_Inventory_Format",
                ar: "نتائج المخزون: %@",
                en: "%@ inventory results",
                count: count
            )
        }
        return localizedResultTitle(
            key: "Pury_Results_Operational_Format",
            ar: "نتائج تشغيلية: %@",
            en: "%@ operational results",
            count: count
        )
    }

    private func localizedResultTitle(key: String, ar: String, en: String, count: Int) -> String {
        PuryLocale.format(key, language: language, ar: ar, en: en, String(count))
    }

    private func telemetryGridView(_ items: [PuryTelemetryItem]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                telemetryMetricCard(item)
            }
        }
    }

    private func telemetryMetricCard(_ item: PuryTelemetryItem) -> some View {
        Button {
            if let route = item.deepLinkRoute {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handleDeepLink(entityType: route, entityId: "")
            }
        } label: {
            HStack(spacing: 12) {
                // Category Icon in Squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.tint.opacity(0.14))
                        .frame(width: 42, height: 42)

                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(item.tint)
                }

                // Title and Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)

                    if let sub = item.subtitle {
                        Text(sub)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Living Metric Count Badge
                let isZero = item.count == "0" || item.count == "٠"
                PuryInfoPill(item.count, tone: isZero ? .neutral : .emerald, isSmall: false)

                // Directional navigation chevron if deep link available
                if item.deepLinkRoute != nil {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                        .padding(.leading, 2)
                }
            }
            .padding(12)
            .background(AdminSurface.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func editorialAdvisoryCallout(_ noticeText: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                .padding(.top, 2)

            Text(noticeText)
                .font(PPBrandFont.regular(size: 13, relativeTo: .footnote))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.25), lineWidth: 0.75)
        )
    }

    // MARK: - Domain Semantic Card View

    private func semanticCardView(_ card: PuryCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack(alignment: .top, spacing: 10) {
                // Card Category Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardIconColor(card).opacity(0.12))
                        .frame(width: 40, height: 40)

                    Image(systemName: cardIconName(card))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(cardIconColor(card))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(card.cleanTitle)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let sub = card.cleanSubtitle {
                        Text(sub)
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if let badge = card.badge ?? card.status, !badge.isEmpty {
                    statusPill(badge)
                }
            }

            // Details Grid
            if let details = card.details, !details.isEmpty {
                Divider()
                    .overlay(AdminSurface.hairline)

                VStack(spacing: 8) {
                    ForEach(details) { field in
                        HStack {
                            Text(field.cleanLabel)
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                            Text(field.cleanValue)
                                .font(PPBrandFont.medium(size: 13, relativeTo: .caption))
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                    }
                }
            }

            // Interactive Navigation CTA
            if let route = card.actionRoute ?? card.entityType, !route.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    handleDeepLink(entityType: route, entityId: card.entityId ?? "")
                } label: {
                    HStack(spacing: 6) {
                        Text(actionLabelForEntity(route))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Image(systemName: "chevron.forward")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AdminSurface.control)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func cardIconName(_ card: PuryCard) -> String {
        let lower = (card.entityType ?? "").lowercased()
        if card.isHotelCard || lower.contains("hotel") || lower.contains("stay") { return "building.2.fill" }
        if card.isProductCard || lower.contains("product") || lower.contains("stock") || lower.contains("accessory") { return "shippingbox.fill" }
        if card.isOrderCard || lower.contains("order") { return "bag.fill" }
        if lower.contains("pet") || lower.contains("adopt") { return "pawprint.fill" }
        if lower.contains("vet") || lower.contains("staff") { return "stethoscope" }
        if lower.contains("user") { return "person.2.fill" }
        if lower.contains("branch") { return "mappin.and.ellipse" }
        return "doc.text.fill"
    }

    private func cardIconColor(_ card: PuryCard) -> Color {
        let lower = (card.entityType ?? "").lowercased()
        if card.isHotelCard || lower.contains("hotel") || lower.contains("stay") { return Color(red: 16/255, green: 185/255, blue: 129/255) }
        if card.isProductCard || lower.contains("product") || lower.contains("stock") || lower.contains("accessory") { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        if card.isOrderCard || lower.contains("order") { return Color(red: 59/255, green: 130/255, blue: 246/255) }
        if lower.contains("pet") || lower.contains("adopt") { return Color(red: 236/255, green: 72/255, blue: 153/255) }
        if lower.contains("vet") || lower.contains("staff") { return Color(red: 20/255, green: 184/255, blue: 166/255) }
        if lower.contains("user") { return Color(red: 99/255, green: 102/255, blue: 241/255) }
        if lower.contains("branch") { return Color(red: 249/255, green: 115/255, blue: 22/255) }
        return Color(red: 139/255, green: 92/255, blue: 246/255)
    }

    private func actionLabelForEntity(_ entityType: String) -> String {
        let lower = entityType.lowercased()
        if lower.contains("hotel") || lower.contains("stay") {
            return PuryLocale.text("Pury_CTA_Hotel", language: language, ar: "فتح لوحة تحكم الفندق", en: "Open Hotel Dashboard")
        }
        if lower.contains("order") {
            return PuryLocale.text("Pury_CTA_Order", language: language, ar: "عرض تفاصيل الطلب", en: "View Order Details")
        }
        if lower.contains("product") || lower.contains("stock") || lower.contains("access") {
            return PuryLocale.text("Pury_CTA_Product", language: language, ar: "إدارة المنتج في المخزن", en: "Manage Product Stock")
        }
        if lower.contains("pet") || lower.contains("adopt") {
            return PuryLocale.text("Pury_CTA_Listings", language: language, ar: "عرض إعلانات الحيوانات", en: "View Pet Listings")
        }
        if lower.contains("staff") || lower.contains("vet") {
            return PuryLocale.text("Pury_CTA_MedicalStaff", language: language, ar: "عرض الكادر الطبي", en: "View Medical Staff")
        }
        if lower.contains("user") {
            return PuryLocale.text("Pury_CTA_Users", language: language, ar: "عرض المستخدمين", en: "View Users")
        }
        if lower.contains("branch") {
            return PuryLocale.text("Pury_CTA_Branch", language: language, ar: "عرض تفاصيل الفرع", en: "View Branch Details")
        }
        return PuryLocale.text(
            "Pury_View_Record",
            language: language,
            ar: "فتح السجل في لوحة الإدارة",
            en: "View Record in Admin"
        )
    }

    private func statusPill(_ status: String) -> some View {
        let cleanStatus = PuryModelsSanitizer.cleanText(status)
        let lower = cleanStatus.lowercased()
        let tone: PuryPillTone
        if lower.contains("نشط") || lower.contains("مكتمل") || lower.contains("active") || lower.contains("متوفر") || lower.contains("متاح") {
            tone = .emerald
        } else if lower.contains("معلق") || lower.contains("حرج") || lower.contains("pending") || lower.contains("منخفض") {
            tone = .amber
        } else if lower.contains("ملغي") || lower.contains("نفد") || lower.contains("cancelled") || lower.contains("مرفوض") {
            tone = .crimson
        } else {
            tone = .emerald
        }
        return PuryInfoPill(cleanStatus, tone: tone, isSmall: true)
    }

    // MARK: - Command Bar

    private var floatingInputDock: some View {
        VStack(spacing: 8) {
            // A pending Tier-3 approval must stay reachable even after it scrolls away.
            if store.activeProposal != nil {
                PuryPendingApprovalRail(language: store.language) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    pendingScrollTarget = Self.pendingApprovalAnchor
                }
                .padding(.horizontal, Self.sheetHorizontalMargin)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if showsSuggestionRail {
                suggestionRail
            }

            composerRow
        }
        .frame(maxWidth: 680)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: store.activeProposal?.token)
    }

    /// The previous rail was also hidden whenever the operator had typed anything, which
    /// moved the input field mid-typing. It now only changes on send and on answer, so the
    /// composer never shifts under an active cursor.
    private var showsSuggestionRail: Bool {
        !store.messages.isEmpty && !store.isWaitingOrThinking
    }

    /// Follow-up suggestions are composed from the same scope-aware intent set as the
    /// launch deck, so they stay relevant to the screen the operator came from.
    private var suggestionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PuryLaunchDeckComposer.intents(context: screenContext, language: store.language)) { intent in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        rerunQuery(intent.prompt)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: intent.symbol)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(intent.accent)

                            Text(intent.title)
                                .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(AdminSurface.surface, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                intent.isScoped ? intent.accent.opacity(0.40) : AdminSurface.hairline,
                                lineWidth: intent.isScoped ? 1 : 0.75
                            )
                        )
                    }
                    .buttonStyle(PuryTactilePressStyle(pressedScale: 0.95))
                    .accessibilityLabel(intent.title)
                }
            }
            .padding(.horizontal, Self.sheetHorizontalMargin)
        }
    }

    private var composerRow: some View {
        let trimmed = store.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty && !store.isWaitingOrThinking
        let placeholder = PuryLocale.text(
            "Pury_Input_Placeholder",
            language: store.language,
            ar: "اسأل بيوري عن أي تفاصيل تشغيلية...",
            en: "Ask Pury about any operational details..."
        )

        return HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $store.currentInputText, axis: .vertical)
                .font(PPBrandFont.regular(size: 15, relativeTo: .body))
                .multilineTextAlignment(.leading)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit { submitInput() }
                .padding(.vertical, 9)
                .accessibilityLabel(placeholder)

            if !trimmed.isEmpty {
                Button {
                    store.currentInputText = ""
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 11)
                .accessibilityLabel(
                    PuryLocale.text("Pury_Composer_Clear", language: store.language, ar: "مسح النص", en: "Clear text")
                )
                .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }

            sendControl(canSend: canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            AdminSurface.surface.opacity(0.95)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isInputFocused ? PuryBrand.primary : AdminSurface.hairline,
                    lineWidth: isInputFocused ? 1.5 : 0.75
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, Self.sheetHorizontalMargin)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: trimmed.isEmpty)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isInputFocused)
    }

    /// `arrow.up` is direction-neutral, so the send glyph reads correctly in Arabic and
    /// English without mirroring.
    private func sendControl(canSend: Bool) -> some View {
        Button {
            submitInput()
        } label: {
            ZStack {
                Circle()
                    .fill(AdminSurface.control)

                if canSend {
                    Circle()
                        .fill(PuryBrand.identityGradient)
                        .shadow(color: PuryBrand.glow.opacity(0.34), radius: 7, x: 0, y: 3)
                }

                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : AdminSurface.secondaryText.opacity(0.7))
            }
            .frame(width: 38, height: 38)
            .scaleEffect(canSend ? 1 : 0.94)
        }
        .buttonStyle(PuryTactilePressStyle(pressedScale: 0.9))
        .disabled(!canSend)
        .accessibilityLabel(
            PuryLocale.text("Pury_Composer_Send", language: store.language, ar: "إرسال", en: "Send")
        )
    }

    // MARK: - Actions & Navigation

    private func submitInput() {
        let text = store.currentInputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isInputFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await store.sendMessage(text, screenContext: screenContext)
        }
    }

    /// A long structured dossier is read from its beginning: anchoring an arriving answer
    /// to the bottom would hide the result summary the operator needs first.
    private func scrollToLatest(proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
            if store.isWaitingOrThinking {
                proxy.scrollTo(Self.readingAnchor, anchor: .bottom)
            } else if let last = store.messages.last {
                proxy.scrollTo(last.id, anchor: last.role == .user ? .bottom : .top)
            }
        }
    }

    private func handleDeepLink(entityType: String, entityId: String) {
        dismiss()
        switch entityType.lowercased() {
        case "order", "orders":
            router.presentedRoute = .paymentOrder(entityId)
        case "petaccessories", "product", "accessories":
            router.presentedRoute = .accessories
        case "livepet", "livepets":
            router.presentedRoute = .livePets
        case "hotel", "stay", "reservation", "hotelstays":
            router.presentedRoute = .hotel
        case "userscol", "user", "users":
            router.presentedRoute = .users
        case "staff_users", "staff":
            router.presentedRoute = .staff
        case "branches", "branch":
            router.presentedRoute = .branches
        default:
            break
        }
    }
}


// MARK: - Pury Response Presentation Sanitizer

/// Presentation-only cleanup for assistant prose. Backend `structuredData` remains
/// authoritative; this utility only prevents execution traces from leaking into operator UI.
public enum PuryResponseDisplaySanitizer {
    private static let traceMarkers = [
        "TOOL CALL", "TOOL RESPONSE", "FUNCTION CALL", "FUNCTION RESPONSE",
        "<TOOL_CALL", "</TOOL_CALL", "<TOOL_RESPONSE", "</TOOL_RESPONSE"
    ]

    public static func cleanNarrative(_ rawText: String, hasStructuredData: Bool) -> String {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        var output: [String] = []
        var inFence = false
        var suppressFence = false
        var suppressTracePayload = false
        var tracePayloadDepth = 0
        var sawTracePayload = false
        var inStructuredPayload = false
        var structuredPayloadDepth = 0

        for rawLine in normalized.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = trimmed.uppercased()

            if trimmed.hasPrefix("```") {
                if inFence {
                    inFence = false
                    suppressFence = false
                } else {
                    let descriptor = trimmed.lowercased()
                    suppressFence = hasStructuredData || descriptor.contains("json") || descriptor.contains("tool")
                    inFence = true
                }
                continue
            }
            if inFence && suppressFence { continue }

            if isTraceMarker(upper) {
                suppressTracePayload = true
                tracePayloadDepth = 0
                sawTracePayload = false
                continue
            }

            if suppressTracePayload {
                if trimmed.isEmpty {
                    suppressTracePayload = false
                    continue
                }

                if !sawTracePayload && looksLikeToolIdentifier(trimmed) {
                    continue
                }

                if !sawTracePayload && startsJSONPayload(trimmed) {
                    sawTracePayload = true
                    tracePayloadDepth = structuralDepthDelta(trimmed)
                    if tracePayloadDepth <= 0 { suppressTracePayload = false }
                    continue
                }

                if sawTracePayload {
                    tracePayloadDepth += structuralDepthDelta(trimmed)
                    if tracePayloadDepth <= 0 { suppressTracePayload = false }
                    continue
                }

                // No technical payload followed the marker; treat this as human prose.
                suppressTracePayload = false
            }

            if hasStructuredData && !inStructuredPayload && startsJSONPayload(trimmed) {
                structuredPayloadDepth = structuralDepthDelta(trimmed)
                inStructuredPayload = structuredPayloadDepth > 0
                continue
            }

            if inStructuredPayload {
                structuredPayloadDepth += structuralDepthDelta(trimmed)
                if structuredPayloadDepth <= 0 { inStructuredPayload = false }
                continue
            }

            let cleaned = cleanMarkdownArtifacts(trimmed)
            if cleaned.isEmpty {
                if output.last?.isEmpty == false { output.append("") }
            } else {
                output.append(cleaned)
            }
        }

        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isTraceMarker(_ upperLine: String) -> Bool {
        traceMarkers.contains { upperLine.hasPrefix($0) || upperLine.contains("[\($0)]") }
    }

    private static func startsJSONPayload(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first == "{" || first == "["
    }

    private static func looksLikeToolIdentifier(_ line: String) -> Bool {
        guard !line.contains(" "), line.count < 160 else { return false }
        return line.contains("_") || line.contains(".") || line.contains("/")
    }

    private static func structuralDepthDelta(_ line: String) -> Int {
        line.reduce(into: 0) { depth, character in
            if character == "{" || character == "[" { depth += 1 }
            if character == "}" || character == "]" { depth -= 1 }
        }
    }

    private static func cleanMarkdownArtifacts(_ line: String) -> String {
        var value = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")

        while value.hasPrefix("#") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespaces)
        }
        if value.hasPrefix("> ") { value = String(value.dropFirst(2)) }
        if value.hasPrefix("* ") || value.hasPrefix("- ") {
            value = "• " + String(value.dropFirst(2))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Category-Defining Living Info Pill & Status Capsule

public enum PuryPillTone: Sendable {
    case emerald
    case amber
    case crimson
    case cobalt
    case violet
    case currency
    case neutral

    public var tintColor: Color {
        switch self {
        case .emerald: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .amber: return Color(red: 245/255, green: 158/255, blue: 11/255)
        case .crimson: return Color(red: 239/255, green: 68/255, blue: 68/255)
        case .cobalt: return Color(red: 59/255, green: 130/255, blue: 246/255)
        case .violet: return Color(red: 139/255, green: 92/255, blue: 246/255)
        case .currency: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .neutral: return AdminSurface.secondaryText
        }
    }
}

public struct PuryInfoPill: View {
    public let text: String
    public let icon: String?
    public let tone: PuryPillTone
    public let isPulse: Bool
    public let copyable: Bool
    public let isSmall: Bool

    @State private var copied: Bool = false

    public init(
        _ text: String,
        icon: String? = nil,
        tone: PuryPillTone = .neutral,
        isPulse: Bool = false,
        copyable: Bool = false,
        isSmall: Bool = false
    ) {
        self.text = text
        self.icon = icon
        self.tone = tone
        self.isPulse = isPulse
        self.copyable = copyable
        self.isSmall = isSmall
    }

    public var body: some View {
        Button {
            guard copyable else { return }
            UIPasteboard.general.string = text
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                copied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            HStack(spacing: 5) {
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: isSmall ? 9 : 11, weight: .bold))
                        .foregroundStyle(tone.tintColor)
                } else if isPulse {
                    Circle()
                        .fill(tone.tintColor)
                        .frame(width: isSmall ? 5 : 6, height: isSmall ? 5 : 6)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: isSmall ? 9 : 11, weight: .bold))
                        .foregroundStyle(tone.tintColor)
                }

                Text(text)
                    .font(PPBrandFont.bold(size: isSmall ? 11 : 13, relativeTo: isSmall ? .caption2 : .caption))
                    .foregroundStyle(tone.tintColor)

                if copyable && !copied {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tone.tintColor.opacity(0.6))
                }
            }
            .padding(.horizontal, isSmall ? 8 : 12)
            .padding(.vertical, isSmall ? 4 : 6)
            .background(tone.tintColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tone.tintColor.opacity(0.28), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .disabled(!copyable)
    }
}

// MARK: - Living Product Stock Showcase Card

public struct PuryProductItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let quantity: Int
    public let price: String?
    public let category: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        quantity: Int,
        price: String? = nil,
        category: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.quantity = quantity
        self.price = price
        self.category = category
    }
}

public struct PuryProductCardView: View {
    public let product: PuryProductItem
    public let isRTL: Bool

    private var language: String { isRTL ? "ar" : "en" }
    public let onManageStock: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Category Squircle Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(productIconColor.opacity(0.14))
                        .frame(width: 44, height: 44)

                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(productIconColor)
                }

                // Title & Category
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.title)
                        .font(PPBrandFont.bold(size: 16, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let sub = product.subtitle ?? product.category {
                        Text(sub)
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Price Capsule
                if let price = product.price, !price.isEmpty {
                    PuryInfoPill(price, tone: .currency, isSmall: false)
                }
            }

            // Stock Urgency & Visual Filament
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    stockStatusPill
                    Spacer()
                    Text(stockStatusLabel)
                        .font(AdminType.caption2Medium)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                // Visual Filament Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdminSurface.hairline.opacity(0.8))
                            .frame(height: 5)

                        Capsule()
                            .fill(stockFilamentColor)
                            .frame(width: max(8, geo.size.width * stockFillPercentage), height: 5)
                    }
                }
                .frame(height: 5)
            }

            Divider()
                .overlay(AdminSurface.hairline)

            // Direct 1-Tap Stock Action
            Button(action: onManageStock) {
                HStack(spacing: 6) {
                    Text(PuryLocale.text("Pury_CTA_Product", language: language, ar: "إدارة المنتج في المخزن", en: "Manage Product Stock"))
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.primary)

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)

                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AdminSurface.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 2)
    }

    private var productIconColor: Color {
        if product.quantity == 0 { return Color(red: 239/255, green: 68/255, blue: 68/255) }
        if product.quantity <= 3 { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        return Color(red: 16/255, green: 185/255, blue: 129/255)
    }

    private var stockFilamentColor: Color {
        if product.quantity == 0 { return Color(red: 239/255, green: 68/255, blue: 68/255) }
        if product.quantity <= 3 { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        return Color(red: 16/255, green: 185/255, blue: 129/255)
    }

    private var stockFillPercentage: CGFloat {
        if product.quantity == 0 { return 0.05 }
        if product.quantity <= 3 { return CGFloat(product.quantity) / 10.0 }
        return min(1.0, CGFloat(product.quantity) / 20.0)
    }

    private var stockStatusPill: some View {
        if product.quantity == 0 {
            return PuryInfoPill(PuryLocale.text("Pury_Stock_Out", language: language, ar: "نفد من المخزون", en: "Out of Stock"), tone: .crimson, isSmall: true)
        } else if product.quantity <= 3 {
            return PuryInfoPill(PuryLocale.text("Pury_Stock_Low", language: language, ar: "مخزون حرج", en: "Low Stock"), tone: .amber, isPulse: true, isSmall: true)
        } else {
            return PuryInfoPill(PuryLocale.text("Pury_Stock_In", language: language, ar: "متوفر", en: "In Stock"), tone: .emerald, isSmall: true)
        }
    }

    private var stockStatusLabel: String {
        if product.quantity == 0 {
            return PuryLocale.text("Pury_Stock_Units_None", language: language, ar: "0 وحدات متبقية", en: "0 units remaining")
        } else {
            return PuryLocale.format(
                "Pury_Stock_Units_Format",
                language: language,
                ar: "%@ وحدات متوفرة",
                en: "%@ units available",
                String(product.quantity)
            )
        }
    }
}

// MARK: - Sculpted Operational Record Card

public struct PuryRecordCardView: View {
    public let block: PuryDataBlock
    public let isRTL: Bool
    public var onDeepLink: ((String, String) -> Void)? = nil
    @State private var isExpanded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: String { isRTL ? "ar" : "en" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Human record identity: primary fact first, operational context second.
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(recordAccentColor.opacity(0.10))
                        .frame(width: 34, height: 34)

                    Image(systemName: recordIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(recordAccentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(recordPrimaryField?.cleanValue ?? blockTitle)
                        .font(PPBrandFont.bold(size: 15, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = recordSubtitleText {
                        Text(subtitle)
                            .font(PPBrandFont.medium(size: 12.5, relativeTo: .caption))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if let status = recordStatusField {
                    fieldValueView(status)
                } else if isExpanded {
                    PuryInfoPill("#\(block.id.prefix(6))", tone: .neutral, copyable: true, isSmall: true)
                }
            }

            Divider()
                .overlay(AdminSurface.hairline)

            // Filtered Human Fields
            let visibleFields = isExpanded ? visibleRecordFields : Array(visibleRecordFields.prefix(4))
            VStack(spacing: 8) {
                ForEach(visibleFields) { field in
                    HStack(alignment: .center) {
                        Text(localizedLabel(field.cleanLabel))
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.secondaryText)

                        Spacer()

                        fieldValueView(field)
                    }
                }
            }

            // Progressive Disclosure
            if visibleRecordFields.count > 4 {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded
                            ? (PuryLocale.text("Pury_Record_ShowLess", language: language, ar: "إخفاء التفاصيل", en: "Show less"))
                            : PuryLocale.format(
                                "Pury_Record_ShowMore_Format",
                                language: language,
                                ar: "عرض المزيد (+%@)",
                                en: "Show more (+%@)",
                                String(visibleRecordFields.count - 4)
                            )
                        )
                        .font(PPBrandFont.medium(size: 12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.primary)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }

            // Interactive Navigation Action if route available
            if let actionTitle = actionTitleForBlock(block) {
                Divider()
                    .overlay(AdminSurface.hairline)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDeepLink?(block.collection ?? block.type, block.id)
                } label: {
                    HStack(spacing: 6) {
                        Text(actionTitle)
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primary)

                        Image(systemName: "chevron.forward")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AdminSurface.control)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }


    private var recordPrimaryField: PuryField? {
        let priority: Set<String> = [
            "name", "title", "petname", "pet_name", "fullname", "full_name",
            "username", "ordernumber", "order_number", "orderreference", "order_reference",
            "reference", "sku"
        ]
        return block.fields.first { priority.contains($0.cleanLabel.lowercased()) }
    }

    private var recordStatusField: PuryField? {
        block.fields.first { field in
            let key = field.cleanLabel.lowercased().replacingOccurrences(of: "_", with: "")
            return key == "status" || key == "state"
        }
    }

    private var recordSubtitleField: PuryField? {
        let hotelPriority = ["suite", "suitename", "room", "roomname", "ownername", "breed"]
        let inventoryPriority = ["category", "brand", "sku"]
        let userPriority = ["email", "phone", "phonenumber"]
        let genericPriority = ["category", "ownername", "breed", "email"]
        let priorities: [String]
        if recordSignature.contains("hotel") || recordSignature.contains("stay") {
            priorities = hotelPriority
        } else if recordSignature.contains("product") || recordSignature.contains("access") || recordSignature.contains("stock") {
            priorities = inventoryPriority
        } else if recordSignature.contains("user") || recordSignature.contains("staff") {
            priorities = userPriority
        } else {
            priorities = genericPriority
        }
        for priority in priorities {
            if let field = block.fields.first(where: {
                $0.cleanLabel.lowercased().replacingOccurrences(of: "_", with: "") == priority
            }) {
                return field
            }
        }
        return nil
    }

    private var recordSubtitleText: String? {
        guard recordPrimaryField != nil else { return nil }
        guard let field = recordSubtitleField, !field.cleanValue.isEmpty else { return blockTitle }
        return "\(blockTitle) · \(field.cleanValue)"
    }

    private var visibleRecordFields: [PuryField] {
        let hidden = Set([recordPrimaryField?.id, recordSubtitleField?.id, recordStatusField?.id].compactMap { $0 })
        return block.fields.filter { !hidden.contains($0.id) }
    }

    private var recordSignature: String {
        (block.collection ?? block.type).lowercased()
    }

    private var recordIconName: String {
        if recordSignature.contains("hotel") || recordSignature.contains("stay") { return "bed.double.fill" }
        if recordSignature.contains("order") { return "bag.fill" }
        if recordSignature.contains("product") || recordSignature.contains("access") || recordSignature.contains("stock") { return "shippingbox.fill" }
        if recordSignature.contains("user") { return "person.crop.circle.fill" }
        if recordSignature.contains("staff") || recordSignature.contains("vet") { return "stethoscope" }
        if recordSignature.contains("adopt") || recordSignature.contains("pet") { return "pawprint.fill" }
        return "list.bullet.rectangle.portrait.fill"
    }

    private var recordAccentColor: Color {
        if recordSignature.contains("hotel") || recordSignature.contains("stay") { return Color(red: 16/255, green: 185/255, blue: 129/255) }
        if recordSignature.contains("order") { return Color(red: 59/255, green: 130/255, blue: 246/255) }
        if recordSignature.contains("product") || recordSignature.contains("access") || recordSignature.contains("stock") { return Color(red: 245/255, green: 158/255, blue: 11/255) }
        if recordSignature.contains("adopt") || recordSignature.contains("pet") { return Color(red: 236/255, green: 72/255, blue: 153/255) }
        return Color(red: 99/255, green: 102/255, blue: 241/255)
    }

    private var blockTitle: String {
        if let col = block.collection, !col.isEmpty {
            return localizedCollectionName(col)
        }
        return PuryLocale.text("Pury_Record_Generic", language: language, ar: "بيانات السجل", en: "Record Details")
    }

    private func localizedCollectionName(_ col: String) -> String {
        let lower = col.lowercased()
        if lower.contains("access") || lower.contains("product") || lower.contains("stock") {
            return PuryLocale.text("Pury_Record_InventoryItem", language: language, ar: "منتج المخزون", en: "Inventory item")
        }
        if lower.contains("hotel") || lower.contains("stay") {
            return PuryLocale.text("Pury_Record_HotelStay", language: language, ar: "إقامة فندقية", en: "Hotel stay")
        }
        if lower.contains("order") {
            return PuryLocale.text("Pury_Record_Order", language: language, ar: "طلب", en: "Order")
        }
        if lower.contains("user") {
            return PuryLocale.text("Pury_Record_Customer", language: language, ar: "ملف العميل", en: "Customer")
        }
        if lower.contains("branch") {
            return PuryLocale.text("Pury_Record_Branch", language: language, ar: "بيانات الفرع", en: "Branch")
        }
        if lower.contains("staff") || lower.contains("vet") {
            return PuryLocale.text("Pury_Record_StaffMember", language: language, ar: "عضو الفريق", en: "Staff member")
        }
        if lower.contains("adopt") {
            return PuryLocale.text("Pury_Record_Adoption", language: language, ar: "سجل تبنٍ", en: "Adoption record")
        }
        return humanizedFallbackLabel(col)
    }

    private func localizedLabel(_ label: String) -> String {
        let lower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "petname", "pet_name":
            return PuryLocale.text("Pury_Field_Pet", language: language, ar: "الحيوان", en: "Pet")
        case "petcategory", "pet_category":
            return PuryLocale.text("Pury_Field_PetCategory", language: language, ar: "فئة الحيوان", en: "Pet category")
        case "breed":
            return PuryLocale.text("Pury_Field_Breed", language: language, ar: "السلالة", en: "Breed")
        case "ownername", "owner_name":
            return PuryLocale.text("Pury_Field_Owner", language: language, ar: "المالك", en: "Owner")
        case "checkin", "checkindate", "check_in", "check_in_date":
            return PuryLocale.text("Pury_Field_CheckIn", language: language, ar: "تسجيل الدخول", en: "Check-in")
        case "expectedcheckout", "expectedcheckoutdate", "expected_checkout", "expected_checkout_date":
            return PuryLocale.text("Pury_Field_ExpectedCheckout", language: language, ar: "المغادرة المتوقعة", en: "Expected checkout")
        case "checkout", "checkoutdate", "check_out", "check_out_date":
            return PuryLocale.text("Pury_Field_Checkout", language: language, ar: "المغادرة", en: "Checkout")
        case "suite", "suitename", "suite_name":
            return PuryLocale.text("Pury_Field_Suite", language: language, ar: "الجناح", en: "Suite")
        case "room", "roomname", "room_name", "accommodation":
            return PuryLocale.text("Pury_Field_Room", language: language, ar: "الغرفة", en: "Room")
        case "price":
            return PuryLocale.text("Pury_Field_Price", language: language, ar: "السعر", en: "Price")
        case "quantity", "stock":
            return PuryLocale.text("Pury_Field_AvailableQuantity", language: language, ar: "الكمية المتوفرة", en: "Available quantity")
        case "status":
            return PuryLocale.text("Pury_Field_Status", language: language, ar: "الحالة", en: "Status")
        case "category":
            return PuryLocale.text("Pury_Field_Category", language: language, ar: "التصنيف", en: "Category")
        case "name", "title":
            return PuryLocale.text("Pury_Field_Name", language: language, ar: "الاسم", en: "Name")
        case "description":
            return PuryLocale.text("Pury_Field_Description", language: language, ar: "الوصف", en: "Description")
        case "phone", "phonenumber", "phone_number":
            return PuryLocale.text("Pury_Field_Phone", language: language, ar: "رقم الهاتف", en: "Phone")
        case "email":
            return PuryLocale.text("Pury_Field_Email", language: language, ar: "البريد الإلكتروني", en: "Email")
        case "createdat", "created_at":
            return PuryLocale.text("Pury_Field_Created", language: language, ar: "تاريخ الإنشاء", en: "Created")
        case "updatedat", "updated_at":
            return PuryLocale.text("Pury_Field_LastUpdated", language: language, ar: "آخر تحديث", en: "Last updated")
        default:
            return humanizedFallbackLabel(label)
        }
    }

    private func humanizedFallbackLabel(_ label: String) -> String {
        let snakeSpaced = label.replacingOccurrences(of: "_", with: " ")
        let camelSpaced = snakeSpaced.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        let normalized = camelSpaced
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return label }
        if isRTL { return normalized }
        return normalized.prefix(1).uppercased() + String(normalized.dropFirst())
    }

    private func actionTitleForBlock(_ block: PuryDataBlock) -> String? {
        let target = (block.collection ?? block.type).lowercased()
        if target.contains("access") || target.contains("product") {
            return PuryLocale.text("Pury_CTA_ProductCatalog", language: language, ar: "إدارة هذا المنتج في المخزن", en: "Manage Product in Catalog")
        }
        if target.contains("hotel") || target.contains("stay") {
            return PuryLocale.text("Pury_CTA_HotelStay", language: language, ar: "فتح تفاصيل الإقامة الفندقية", en: "View Hotel Stay Details")
        }
        if target.contains("order") {
            return PuryLocale.text("Pury_CTA_Order", language: language, ar: "عرض تفاصيل الطلب", en: "View Order Details")
        }
        if target.contains("user") {
            return PuryLocale.text("Pury_CTA_UserProfile", language: language, ar: "عرض ملف المستخدم", en: "View User Profile")
        }
        if target.contains("branch") {
            return PuryLocale.text("Pury_CTA_Branch", language: language, ar: "عرض تفاصيل الفرع", en: "View Branch Details")
        }
        return PuryLocale.text(
            "Pury_View_Record",
            language: language,
            ar: "فتح السجل في لوحة الإدارة",
            en: "View Record in Admin"
        )
    }

    @ViewBuilder
    private func fieldValueView(_ field: PuryField) -> some View {
        let val = field.cleanValue
        let valLower = val.lowercased()

        if val.contains("ر.ق") || val.contains("QAR") || val.contains("ريال") || field.cleanLabel.lowercased().contains("price") {
            PuryInfoPill(val, tone: .currency, isSmall: true)
                .environment(\.layoutDirection, .leftToRight)
        } else if ["active", "نشط", "مكتمل", "completed", "متاح", "available", "true"].contains(valLower) {
            PuryInfoPill(valLower == "true" ? (PuryLocale.text("Pury_Value_Active", language: language, ar: "مفعّل", en: "Active")) : val, tone: .emerald, isSmall: true)
        } else if ["pending", "معلق", "قيد الانتظار", "draft", "مسودة"].contains(valLower) {
            PuryInfoPill(val, tone: .amber, isSmall: true)
        } else if ["cancelled", "ملغي", "مرفوض", "rejected", "out_of_stock", "نفد", "false"].contains(valLower) {
            PuryInfoPill(valLower == "false" ? (PuryLocale.text("Pury_Value_Disabled", language: language, ar: "معطّل", en: "Disabled")) : val, tone: .crimson, isSmall: true)
        } else {
            Text(val)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
                .environment(
                    \.layoutDirection,
                    fieldUsesLTR(field) ? .leftToRight : (isRTL ? .rightToLeft : .leftToRight)
                )
        }
    }

    private func fieldUsesLTR(_ field: PuryField) -> Bool {
        let type = field.type?.lowercased() ?? ""
        let label = field.cleanLabel.lowercased().replacingOccurrences(of: "_", with: "")
        let ltrTypes: Set<String> = ["id", "url", "email", "phone", "currency", "number", "date", "datetime"]
        if ltrTypes.contains(type) { return true }
        return label.contains("email") || label.contains("phone") || label.contains("url") || label.contains("price") || label.contains("date") || label.contains("time")
    }
}

// MARK: - High-Craft Native Markdown Table Card

public struct PuryTableData: Identifiable, Equatable {
    public let id: String = UUID().uuidString
    public let headers: [String]
    public let rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

public struct PuryMarkdownTableCard: View {
    public let table: PuryTableData
    public let isRTL: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header Row
                    HStack(spacing: 0) {
                        ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                            Text(header)
                                .font(PPBrandFont.bold(size: 13, relativeTo: .caption))
                                .foregroundStyle(AdminSurface.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(minWidth: 100, alignment: .leading)

                            if index < table.headers.count - 1 {
                                Divider().overlay(AdminSurface.hairline)
                            }
                        }
                    }
                    .background(AdminSurface.control.opacity(0.8))

                    Divider().overlay(AdminSurface.hairline)

                    // Data Rows
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                                Text(cell)
                                    .font(PPBrandFont.regular(size: 13, relativeTo: .caption))
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(minWidth: 100, alignment: .leading)

                                if colIndex < row.count - 1 {
                                    Divider().overlay(AdminSurface.hairline.opacity(0.5))
                                }
                            }
                        }
                        .background(rowIndex % 2 == 1 ? AdminSurface.control.opacity(0.25) : AdminSurface.surface)

                        if rowIndex < table.rows.count - 1 {
                            Divider().overlay(AdminSurface.hairline.opacity(0.35))
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }
}

// MARK: - Studio Content & Telemetry Engine

public struct PuryTelemetryItem: Identifiable, Equatable {
    public let id: String = UUID().uuidString
    public let title: String
    public let subtitle: String?
    public let count: String
    public let icon: String
    public let tint: Color
    public let collectionKey: String?
    public let deepLinkRoute: String?

    public init(
        title: String,
        subtitle: String? = nil,
        count: String,
        icon: String,
        tint: Color,
        collectionKey: String? = nil,
        deepLinkRoute: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.icon = icon
        self.tint = tint
        self.collectionKey = collectionKey
        self.deepLinkRoute = deepLinkRoute
    }
}

public struct PuryParsedMessageContent {
    public let introNarrative: String?
    public let products: [PuryProductItem]
    public let tables: [PuryTableData]
    public let telemetryItems: [PuryTelemetryItem]
    public let advisoryNotices: [String]
    public let outroNotice: String?
    public let cleanFullText: String

    public init(
        introNarrative: String?,
        products: [PuryProductItem],
        tables: [PuryTableData],
        telemetryItems: [PuryTelemetryItem],
        advisoryNotices: [String],
        outroNotice: String?,
        cleanFullText: String
    ) {
        self.introNarrative = introNarrative
        self.products = products
        self.tables = tables
        self.telemetryItems = telemetryItems
        self.advisoryNotices = advisoryNotices
        self.outroNotice = outroNotice
        self.cleanFullText = cleanFullText
    }
}

public enum PuryContentParser {
    public static func parse(_ rawText: String, isRTL: Bool) -> PuryParsedMessageContent {
        let lines = rawText.components(separatedBy: .newlines)
        var introLines: [String] = []
        var outroLines: [String] = []
        var products: [PuryProductItem] = []
        var tables: [PuryTableData] = []
        var telemetryItems: [PuryTelemetryItem] = []
        var advisoryNotices: [String] = []
        var foundStructuredItem = false

        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                i += 1
                continue
            }

            // 1. Table Detection
            if line.contains("|") {
                var tableLines: [String] = []
                while i < lines.count && lines[i].contains("|") {
                    let tLine = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tLine.isEmpty {
                        tableLines.append(tLine)
                    }
                    i += 1
                }
                if let table = parseMarkdownTable(tableLines) {
                    foundStructuredItem = true
                    tables.append(table)
                } else {
                    for tl in tableLines {
                        if foundStructuredItem { outroLines.append(cleanMarkdown(tl)) }
                        else { introLines.append(cleanMarkdown(tl)) }
                    }
                }
                continue
            }

            // 2. Advisory / Notice Detection (💡, ⚠️, ملاحظة, تنبيه)
            if isAdvisoryNoticeLine(line) {
                let cleanNotice = cleanMarkdown(line)
                if !cleanNotice.isEmpty {
                    advisoryNotices.append(cleanNotice)
                }
                i += 1
                continue
            }

            // 3. Product with Stock & Price Detection
            if let product = parseProductLine(line, isRTL: isRTL) {
                foundStructuredItem = true
                products.append(product)
                i += 1
                continue
            }

            // 4. Metric Telemetry Line Detection
            if let metric = parseMetricLine(line, isRTL: isRTL) {
                foundStructuredItem = true
                telemetryItems.append(metric)
                i += 1
                continue
            }

            // 5. Conversational narrative line
            let cleaned = cleanMarkdown(line)
            if !cleaned.isEmpty {
                if foundStructuredItem {
                    outroLines.append(cleaned)
                } else {
                    introLines.append(cleaned)
                }
            }
            i += 1
        }

        let intro = introLines.isEmpty ? nil : introLines.joined(separator: "\n")
        let outro = outroLines.isEmpty ? nil : outroLines.joined(separator: "\n")
        let full = cleanMarkdown(rawText)

        return PuryParsedMessageContent(
            introNarrative: intro,
            products: products,
            tables: tables,
            telemetryItems: telemetryItems,
            advisoryNotices: advisoryNotices,
            outroNotice: outro,
            cleanFullText: full
        )
    }

    private static func isAdvisoryNoticeLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("ملاحظة") || lower.contains("تنبيه") || lower.contains("تنويه") ||
           lower.contains("💡") || lower.contains("⚠️") || lower.contains("note:") || lower.contains("warning:") {
            return true
        }
        return false
    }

    private static func parseProductLine(_ line: String, isRTL: Bool) -> PuryProductItem? {
        let language = isRTL ? "ar" : "en"
        guard line.hasPrefix("*") || line.hasPrefix("-") || line.hasPrefix("•") else {
            return nil
        }

        var text = line
        if text.hasPrefix("*") || text.hasPrefix("-") || text.hasPrefix("•") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let parts = text.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        let rawKey = parts[0].trimmingCharacters(in: .whitespaces)
        let rawVal = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

        let title = cleanMarkdown(rawKey)
        let cleanVal = cleanMarkdown(rawVal)

        // Check if value contains product stock or pricing keywords
        let lowerVal = cleanVal.lowercased()
        let hasStock = lowerVal.contains("متوفر") || lowerVal.contains("وحدات") || lowerVal.contains("وحدة") ||
                       lowerVal.contains("قطعة") || lowerVal.contains("كمية") || lowerVal.contains("مخزون") ||
                       lowerVal.contains("نفد") || lowerVal.contains("available") || lowerVal.contains("stock")
        let hasPrice = lowerVal.contains("ر.ق") || lowerVal.contains("ريال") || lowerVal.contains("qar") ||
                       lowerVal.contains("qr") || lowerVal.contains("بسعر") || lowerVal.contains("سعر") ||
                       lowerVal.contains("price")

        guard hasStock || hasPrice else { return nil }

        // Extract quantity:
        var quantity = 0
        if lowerVal.contains("نفد") {
            quantity = 0
        } else {
            let patterns = [
                #"(?:متوفر|الكمية|مخزون|stock)\s*:?\s*(\d+)"#,
                #"(\d+)\s*(?:وحدة|وحدات|قطع|قطعة|units)"#
            ]
            for pat in patterns {
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                   let match = regex.firstMatch(in: cleanVal, options: [], range: NSRange(location: 0, length: cleanVal.utf16.count)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: cleanVal),
                   let qty = Int(cleanVal[range]) {
                    quantity = qty
                    break
                }
            }
        }

        // Extract price:
        var priceString: String? = nil
        let pricePattern = #"(?:بسعر|سعر)?\s*(\d+(?:\.\d+)?)\s*(ر\.ق|ريال|QAR|qr)?"#
        if let regex = try? NSRegularExpression(pattern: pricePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: cleanVal, options: [], range: NSRange(location: 0, length: cleanVal.utf16.count)),
           let fullRange = Range(match.range(at: 0), in: cleanVal) {
            let matchedPrice = cleanVal[fullRange].trimmingCharacters(in: .whitespaces)
            if matchedPrice.contains("ر.ق") || matchedPrice.contains("ريال") || matchedPrice.contains("QAR") {
                priceString = matchedPrice.replacingOccurrences(of: "بسعر", with: "").trimmingCharacters(in: .whitespaces)
            } else if let numRange = Range(match.range(at: 1), in: cleanVal) {
                let num = cleanVal[numRange]
                priceString = PuryLocale.format(
                    "Pury_Currency_QAR_Format",
                    language: language,
                    ar: "%@ ر.ق.",
                    en: "%@ QAR",
                    String(num)
                )
            }
        }

        return PuryProductItem(
            title: title,
            quantity: quantity,
            price: priceString,
            category: PuryLocale.text("Pury_Catalog_StoreCatalog", language: language, ar: "مخزون المتجر", en: "Store Catalog")
        )
    }

    private static func parseMetricLine(_ line: String, isRTL: Bool) -> PuryTelemetryItem? {
        let language = isRTL ? "ar" : "en"
        guard line.hasPrefix("*") || line.hasPrefix("-") || line.hasPrefix("•") else {
            return nil
        }

        var text = line
        if text.hasPrefix("*") || text.hasPrefix("-") || text.hasPrefix("•") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let parts = text.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        let rawKey = parts[0].trimmingCharacters(in: .whitespaces)
        let rawVal = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)

        let count = cleanMarkdown(rawVal).trimmingCharacters(in: .whitespaces)
        guard !count.isEmpty else { return nil }

        // Must be a genuine short metric (max 25 characters)
        guard count.count <= 25 else { return nil }

        let cleanKey = cleanMarkdown(rawKey)

        var collectionKey: String? = nil
        var displayTitle = cleanKey

        if let openParen = cleanKey.range(of: "("),
           let closeParen = cleanKey.range(of: ")", range: openParen.upperBound..<cleanKey.endIndex) {
            let inside = String(cleanKey[openParen.upperBound..<closeParen.lowerBound]).trimmingCharacters(in: .whitespaces)
            collectionKey = inside.lowercased()
            let beforeParen = String(cleanKey[..<openParen.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !beforeParen.isEmpty {
                displayTitle = beforeParen
            }
        }

        let meta = resolveCollectionMetadata(collectionKey: collectionKey, title: displayTitle, isRTL: isRTL)

        return PuryTelemetryItem(
            title: meta.title,
            subtitle: meta.subtitle,
            count: count,
            icon: meta.icon,
            tint: meta.tint,
            collectionKey: collectionKey,
            deepLinkRoute: meta.deepLinkRoute
        )
    }

    private static func parseMarkdownTable(_ lines: [String]) -> PuryTableData? {
        guard lines.count >= 2 else { return nil }

        // Parse header row
        let headerRow = lines[0].components(separatedBy: "|")
            .map { cleanMarkdown($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !headerRow.isEmpty else { return nil }

        // Find data rows (skip delimiter line)
        var rows: [[String]] = []
        for line in lines.dropFirst() {
            if line.contains("---") { continue }

            let cols = line.components(separatedBy: "|")
                .map { cleanMarkdown($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !cols.isEmpty {
                rows.append(cols)
            }
        }

        guard !rows.isEmpty else { return nil }
        return PuryTableData(headers: headerRow, rows: rows)
    }

    private static func resolveCollectionMetadata(
        collectionKey: String?,
        title: String,
        isRTL: Bool
    ) -> (title: String, subtitle: String?, icon: String, tint: Color, deepLinkRoute: String?) {
        let language = isRTL ? "ar" : "en"
        let key = (collectionKey ?? "").lowercased()
        let lowerTitle = title.lowercased()

        if key.contains("vet") || lowerTitle.contains("بيطر") || lowerTitle.contains("أطباء") || lowerTitle.contains("طبيب") {
            return (
                title: PuryLocale.text("Pury_Metric_Vets_Title", language: language, ar: "الأطباء البيطريون", en: "Veterinarians"),
                subtitle: PuryLocale.text("Pury_Metric_Vets_Sub", language: language, ar: "كادر طبي معتمد", en: "Certified Medical Staff"),
                icon: "stethoscope",
                tint: Color(red: 20/255, green: 184/255, blue: 166/255),
                deepLinkRoute: "staff"
            )
        } else if key.contains("pet_ad") || key.contains("petad") || lowerTitle.contains("إعلان") || lowerTitle.contains("اعلان") {
            return (
                title: PuryLocale.text("Pury_Metric_Listings_Title", language: language, ar: "إعلانات الحيوانات", en: "Pet Listings"),
                subtitle: PuryLocale.text("Pury_Metric_Listings_Sub", language: language, ar: "إعلانات منشورة", en: "Active Listings"),
                icon: "pawprint.fill",
                tint: Color(red: 245/255, green: 158/255, blue: 11/255),
                deepLinkRoute: "livePets"
            )
        } else if key.contains("service") || lowerTitle.contains("خدمات") || lowerTitle.contains("خدمة") {
            return (
                title: PuryLocale.text("Pury_Metric_Services_Title", language: language, ar: "عروض الخدمات", en: "Service Offers"),
                subtitle: PuryLocale.text("Pury_Metric_Services_Sub", language: language, ar: "باقات مفعّلة", en: "Active Service Packages"),
                icon: "sparkles.rectangle.stack.fill",
                tint: Color(red: 139/255, green: 92/255, blue: 246/255),
                deepLinkRoute: "hotel"
            )
        } else if key.contains("adopt") || lowerTitle.contains("تبني") {
            return (
                title: PuryLocale.text("Pury_Metric_Adoption_Title", language: language, ar: "طلبات التبني", en: "Adoption Requests"),
                subtitle: PuryLocale.text("Pury_Metric_Adoption_Sub", language: language, ar: "حيوانات مؤهلة", en: "Eligible for Adoption"),
                icon: "heart.circle.fill",
                tint: Color(red: 236/255, green: 72/255, blue: 153/255),
                deepLinkRoute: "livePets"
            )
        } else if key.contains("accessory") || key.contains("product") || key.contains("stock") || lowerTitle.contains("منتج") || lowerTitle.contains("مخزون") {
            return (
                title: PuryLocale.text("Pury_Metric_Products_Title", language: language, ar: "منتجات المتجر", en: "Store Products"),
                subtitle: PuryLocale.text("Pury_Metric_Products_Sub", language: language, ar: "المخزون المسجل", en: "Catalog Inventory"),
                icon: "shippingbox.fill",
                tint: Color(red: 59/255, green: 130/255, blue: 246/255),
                deepLinkRoute: "accessories"
            )
        } else if key.contains("order") || lowerTitle.contains("طلب") {
            return (
                title: PuryLocale.text("Pury_Metric_Orders_Title", language: language, ar: "أوامر الشراء", en: "Orders Queue"),
                subtitle: PuryLocale.text("Pury_Metric_Orders_Sub", language: language, ar: "طلبات معتمدة", en: "Active Orders"),
                icon: "bag.fill",
                tint: Color(red: 16/255, green: 185/255, blue: 129/255),
                deepLinkRoute: "orders"
            )
        } else if key.contains("hotel") || key.contains("stay") || lowerTitle.contains("فندق") || lowerTitle.contains("إقامة") {
            return (
                title: PuryLocale.text("Pury_Metric_HotelStays_Title", language: language, ar: "إشغال الفندق", en: "Hotel Stays"),
                subtitle: PuryLocale.text("Pury_Metric_HotelStays_Sub", language: language, ar: "نزلاء حاليون", en: "Current Guests"),
                icon: "building.2.fill",
                tint: Color(red: 16/255, green: 185/255, blue: 129/255),
                deepLinkRoute: "hotel"
            )
        } else if key.contains("user") || lowerTitle.contains("مستخدم") {
            return (
                title: PuryLocale.text("Pury_Metric_Users_Title", language: language, ar: "المستخدمين", en: "Registered Users"),
                subtitle: PuryLocale.text("Pury_Metric_Users_Sub", language: language, ar: "حسابات نشطة", en: "Platform Accounts"),
                icon: "person.2.fill",
                tint: Color(red: 99/255, green: 102/255, blue: 241/255),
                deepLinkRoute: "users"
            )
        } else if key.contains("branch") || lowerTitle.contains("فرع") {
            return (
                title: PuryLocale.text("Pury_Metric_Branches_Title", language: language, ar: "فروع بيور بيتس", en: "Branches"),
                subtitle: PuryLocale.text("Pury_Metric_Branches_Sub", language: language, ar: "مواقع تشغيلية", en: "Active Locations"),
                icon: "mappin.and.ellipse",
                tint: Color(red: 249/255, green: 115/255, blue: 22/255),
                deepLinkRoute: "branches"
            )
        }

        return (
            title: title.isEmpty ? (collectionKey ?? (PuryLocale.text("Pury_Metric_Generic", language: language, ar: "عنصر تشغيلي", en: "Operational Metric"))) : title,
            subtitle: collectionKey,
            icon: "chart.bar.fill",
            tint: Color(red: 16/255, green: 185/255, blue: 129/255),
            deepLinkRoute: nil
        )
    }

    public static func cleanMarkdown(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        if result.hasPrefix("* ") || result.hasPrefix("- ") || result.hasPrefix("• ") {
            result = String(result.dropFirst(2))
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
