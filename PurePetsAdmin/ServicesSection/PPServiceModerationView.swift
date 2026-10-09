import SwiftUI
import UIKit

@objc(PPServiceModerationPhase)
enum PPServiceModerationPhase: Int {
    case loading, ready, saving, confirming, saved, failed, conflict, unavailable
    case awaitingConfirmation
}

private struct PPServiceReviewChange: Identifiable {
    let id: String
    let before: String
    let after: String
}

@MainActor
private final class PPServiceModerationDraft: ObservableObject {
    @Published var baseline: PPServiceModel
    @Published var disabled = false
    @Published var blocked = false
    @Published var verification = ""
    @Published var subscriptionType = ""
    @Published var subscriptionPlan = ""
    @Published var subscriptionStatus = ""
    @Published var subscriptionActive = false
    @Published var hasStart = false
    @Published var hasEnd = false
    @Published var start = Date()
    @Published var end = Date()
    @Published var flags = ""
    @Published var note = ""
    @Published var phase: PPServiceModerationPhase = .loading
    @Published var canManage = false
    @Published var error: String?
    @Published var validationError: String?

    init(service: PPServiceModel) {
        baseline = Self.snapshotCopy(service)
        reset(to: service)
    }

    func reset(to service: PPServiceModel) {
        baseline = Self.snapshotCopy(service)
        disabled = service.isDisabled
        blocked = service.isBlocked
        verification = service.verificationStatus
        subscriptionType = service.subscriptionType
        subscriptionPlan = service.subscriptionPlan
        subscriptionStatus = service.subscriptionStatus
        subscriptionActive = service.subscriptionActive
        hasStart = service.subscriptionStartDate != nil
        hasEnd = service.subscriptionEndDate != nil
        start = service.subscriptionStartDate ?? Date()
        end = service.subscriptionEndDate ?? Date()
        flags = Self.json(service.serviceFlags)
        note = ""
        validationError = nil
    }

    var busy: Bool { phase == .loading || phase == .saving || phase == .confirming }
    var canEdit: Bool { canManage && !busy && phase != .saved && phase != .unavailable && phase != .conflict && phase != .awaitingConfirmation }
    var hasChanges: Bool { !changes.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var futureVisible: Bool { !baseline.isDeleted && !disabled && !blocked }
    var verificationLabel: String {
        let copy = Self.snapshotCopy(baseline)
        copy.verificationStatus = verification
        return copy.localizedVerificationTitle()
    }

    var changes: [PPServiceReviewChange] {
        var rows: [PPServiceReviewChange] = []
        func append(_ key: String, _ old: String, _ new: String) {
            if old != new { rows.append(.init(id: key, before: display(old), after: display(new))) }
        }
        func bool(_ value: Bool) -> String { PPServiceText(value ? "Yes" : "No") }
        append("Service_Field_IsDisabled", bool(baseline.isDisabled), bool(disabled))
        append("Service_Field_IsBlocked", bool(baseline.isBlocked), bool(blocked))
        append("Service_Field_VerificationStatus", baseline.verificationStatus, verification)
        append("Service_Field_SubscriptionType", baseline.subscriptionType, subscriptionType)
        append("Service_Field_SubscriptionPlan", baseline.subscriptionPlan, subscriptionPlan)
        append("Service_Field_SubscriptionStatus", baseline.subscriptionStatus, subscriptionStatus)
        append("Service_Field_SubscriptionActive", bool(baseline.subscriptionActive), bool(subscriptionActive))
        append("Service_Field_SubscriptionStart", date(baseline.subscriptionStartDate), date(hasStart ? start : nil))
        append("Service_Field_SubscriptionEnd", date(baseline.subscriptionEndDate), date(hasEnd ? end : nil))
        if parsedFlags.map({ NSDictionary(dictionary: $0).isEqual(to: baseline.serviceFlags) }) != true {
            rows.append(.init(id: "Service_Field_ServiceFlags", before: Self.json(baseline.serviceFlags), after: flags))
        }
        return rows
    }

    var parsedFlags: [String: Any]? {
        let value = flags.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return [:] }
        guard let data = value.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data),
              let object = parsed as? [String: Any] else { return nil }
        return object
    }

    func candidate() -> PPServiceModel? {
        validationError = nil
        guard let parsedFlags else {
            validationError = PPServiceText("Service_Error_FlagsJSONInvalid"); return nil
        }
        guard !hasStart || !hasEnd || start <= end else {
            validationError = PPServiceText("Service_Error_SubscriptionDateOrder"); return nil
        }
        guard let compactFlags = try? JSONSerialization.data(withJSONObject: parsedFlags, options: [.sortedKeys, .withoutEscapingSlashes]),
              compactFlags.count <= 16_384, note.utf16.count <= 2_000,
              [verification, subscriptionType, subscriptionPlan, subscriptionStatus].allSatisfy({ $0.utf16.count <= 160 }) else {
            validationError = PPServiceText("Service_Review_InputTooLong"); return nil
        }
        guard Self.validMetadata(parsedFlags) else {
            validationError = PPServiceText("Service_Review_FlagsStructure"); return nil
        }
        let value = Self.snapshotCopy(baseline)
        value.isDisabled = disabled
        value.isBlocked = blocked
        value.verificationStatus = verification.trimmingCharacters(in: .whitespacesAndNewlines)
        value.subscriptionType = subscriptionType.trimmingCharacters(in: .whitespacesAndNewlines)
        value.subscriptionPlan = subscriptionPlan.trimmingCharacters(in: .whitespacesAndNewlines)
        value.subscriptionStatus = subscriptionStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        value.subscriptionActive = subscriptionActive
        value.subscriptionStartDate = hasStart ? start : nil
        value.subscriptionEndDate = hasEnd ? end : nil
        value.serviceFlags = parsedFlags
        return value
    }

    private func display(_ value: String) -> String { value.isEmpty ? PPServiceText("Service_Value_NotSpecified") : value }

    private static func snapshotCopy(_ service: PPServiceModel) -> PPServiceModel {
        if let copy = service.copy() as? PPServiceModel { return copy }
        return PPServiceModel.fromDictionary(service.toDictionary(), withID: service.serviceID)
    }

    // Same bounds as Infra's metadata validator; the server remains authority.
    private static func validMetadata(_ value: Any, depth: Int = 0) -> Bool {
        guard depth <= 6 else { return false }
        if value is NSNull { return true }
        if let text = value as? String { return text.utf16.count <= 8_000 }
        if let number = value as? NSNumber { return number.doubleValue.isFinite }
        if let array = value as? [Any] {
            return array.count <= 100 && array.allSatisfy { validMetadata($0, depth: depth + 1) }
        }
        guard let object = value as? [String: Any], object.count <= 100 else { return false }
        return object.allSatisfy { key, entry in
            !key.isEmpty && key.utf16.count <= 120 && !["__proto__", "prototype", "constructor"].contains(key)
                && validMetadata(entry, depth: depth + 1)
        }
    }
    private func date(_ value: Date?) -> String {
        guard let value else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }
    private static func json(_ object: [String: Any]) -> String {
        guard !object.isEmpty, let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
}

// The existing PPServiceModerationViewController owns authorization, persistence
// and navigation. This host owns only the presentation and its isolated draft.
@objc(PPServiceModerationHostingController)
final class PPServiceModerationHostingController: UIViewController {
    private let draft: PPServiceModerationDraft
    private let closeHandler: () -> Void
    private let reloadHandler: () -> Void
    private let saveHandler: (PPServiceModel, PPServiceModel, String) -> Void

    @objc(initWithService:closeHandler:reloadHandler:saveHandler:)
    init(service: PPServiceModel, closeHandler: @escaping () -> Void, reloadHandler: @escaping () -> Void,
         saveHandler: @escaping (PPServiceModel, PPServiceModel, String) -> Void) {
        draft = PPServiceModerationDraft(service: service)
        self.closeHandler = closeHandler
        self.reloadHandler = reloadHandler
        self.saveHandler = saveHandler
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(service:closeHandler:reloadHandler:saveHandler:)") }

    @objc var hasUnsavedChanges: Bool { draft.hasChanges && draft.phase != .saved }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: PPServiceModerationScreen(draft: draft, close: closeHandler,
            reload: reloadHandler, save: saveHandler))
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    @objc(updateWithService:phase:canManage:errorMessage:replaceDraft:)
    func update(service: PPServiceModel, phase: PPServiceModerationPhase, canManage: Bool,
                errorMessage: String?, replaceDraft: Bool) {
        if replaceDraft { draft.reset(to: service) }
        draft.phase = phase
        draft.canManage = canManage
        draft.error = errorMessage
    }
}

private struct PPServiceModerationScreen: View {
    @ObservedObject var draft: PPServiceModerationDraft
    let close: () -> Void
    let reload: () -> Void
    let save: (PPServiceModel, PPServiceModel, String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = Language.currentLanguageCode()
    @State private var showsConfirmation = false
    @State private var showsReloadConfirmation = false
    @FocusState private var isEditingText: Bool
    @AccessibilityFocusState private var completionFocused: Bool

    private var service: PPServiceModel { draft.baseline }
    private var locale: Locale { Locale(identifier: language.hasPrefix("ar") ? "ar_QA" : "en_QA") }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                navigation
                ScrollViewReader { proxy in
                  ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        identity
                        VStack(alignment: .leading, spacing: 12) {
                            if let error = draft.error { recovery(error) }
                            if let error = draft.validationError { PPServiceNotice(text: error, isError: true) }
                        }.id("review.feedback")
                        if draft.phase == .saved {
                            saved
                        } else if geometry.size.width >= 820 && !typeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: 28) {
                                VStack(alignment: .leading, spacing: 28) { availability; verification; audit }
                                VStack(alignment: .leading, spacing: 28) { preview; subscription; advanced }
                            }
                        } else {
                            preview
                            availability
                            verification
                            subscription
                            audit
                            advanced
                        }
                    }
                    .padding(24).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
                  }.scrollDismissesKeyboard(.interactively)
                    .onChange(of: draft.validationError) { _, message in
                        if let message { revealFeedback(message, proxy: proxy) }
                    }
                    .onChange(of: draft.error) { _, message in
                        if let message { revealFeedback(message, proxy: proxy) }
                    }
                    .onChange(of: draft.phase) { _, phase in
                        if phase == .saved {
                            proxy.scrollTo("review.saved", anchor: .top)
                            completionFocused = true
                        }
                    }
                }
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { decisionBar }
        }
        .font(AdminType.body).foregroundStyle(AdminSurface.primaryText)
        .accessibilityIdentifier("admin.services.moderation")
        .environment(\.layoutDirection, language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
        .environment(\.locale, locale)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LanguageDidChangeNotification"))) { _ in
            language = Language.currentLanguageCode()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(PPServiceText("Done")) { isEditingText = false }
            }
        }
        .sheet(isPresented: $showsConfirmation) { confirmation }
        .confirmationDialog(PPServiceText("Service_Review_ReloadTitle"), isPresented: $showsReloadConfirmation, titleVisibility: .visible) {
            Button(PPServiceText("Service_Review_DiscardReload"), role: .destructive, action: reload)
            Button(PPServiceText("Cancel"), role: .cancel) {}
        } message: { Text(PPServiceText("Service_Review_ReloadDetail")) }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                    .background(AdminSurface.card, in: Circle())
            }.buttonStyle(PPServicePressStyle()).accessibilityLabel(PPServiceText("Close"))
                .disabled(draft.phase == .saving || draft.phase == .confirming)
            VStack(alignment: .leading, spacing: 2) {
                Text(PPServiceText("Service_Review_Title")).font(AdminType.title2).accessibilityAddTraits(.isHeader)
                Text(PPServiceText("Service_Review_Subtitle")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "checkmark.shield").font(.system(size: 24, weight: .light)).foregroundStyle(AdminSurface.primary)
                .accessibilityHidden(true)
        }.padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 16) {
            PPServiceArtwork(service: service, size: 72)
            VStack(alignment: .leading, spacing: 8) {
                Text(service.category.isEmpty ? service.localizedTypeName() : service.category).font(AdminType.captionBold).foregroundStyle(AdminSurface.primary)
                Text(service.title).font(AdminType.title).fixedSize(horizontal: false, vertical: true)
                Text(PPServicePrice(service.price)).font(AdminType.headline).environment(\.layoutDirection, .leftToRight)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 4)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(PPServiceText("Service_Review_AfterSaving")).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
            Label(PPServiceText(draft.futureVisible ? "Service_Review_Visible" : "Service_Review_Hidden"),
                  systemImage: draft.futureVisible ? "eye" : "eye.slash")
                .font(AdminType.title2).foregroundStyle(AdminSurface.primaryText)
            Text(PPServiceText("Service_Review_VisibilityExplanation")).font(AdminType.callout).foregroundStyle(AdminSurface.secondaryText)
            Divider()
            Label(draft.verificationLabel, systemImage: draft.verification.lowercased() == "verified" ? "checkmark.seal" : "clock")
                .font(AdminType.headline).foregroundStyle(AdminSurface.primary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .combine)
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Service_Review_Availability", 1)
            VStack(spacing: 0) {
                Toggle(isOn: Binding(get: { !draft.disabled }, set: { draft.disabled = !$0 })) {
                    controlLabel("Service_Review_Available", "Service_Review_AvailableDetail", "sun.max")
                }.padding(20)
                Divider().padding(.horizontal, 20)
                Toggle(isOn: $draft.blocked) {
                    controlLabel("Service_Review_Restricted", "Service_Review_RestrictedDetail", "hand.raised")
                }.padding(20).tint(AdminSurface.danger)
            }
            .tint(AdminSurface.primary).background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24))
            .disabled(!draft.canEdit)
            if service.isDeleted {
                Text(PPServiceText("Service_Review_ArchivedNote")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verification: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Service_Review_Verification", 2)
            Text(PPServiceText("Service_Review_VerificationDetail")).font(AdminType.callout).foregroundStyle(AdminSurface.secondaryText)
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] :
                [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                verificationChoice("verified", "Service_Review_Verified", "checkmark.seal")
                verificationChoice("pending", "Service_Review_Pending", "clock")
                verificationChoice("rejected", "Service_Review_Rejected", "xmark.seal")
                verificationChoice("unverified", "Service_Review_Unverified", "questionmark.circle")
            }.disabled(!draft.canEdit)
            DisclosureGroup {
                technicalField("Service_Field_VerificationStatus", text: $draft.verification)
                    .padding(.top, 12).disabled(!draft.canEdit)
            } label: {
                Text(PPServiceText("Service_Review_CustomVerification")).frame(minHeight: 44, alignment: .leading)
            }.font(AdminType.footnote).tint(AdminSurface.secondaryText)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verificationChoice(_ value: String, _ key: String, _ symbol: String) -> some View {
        let normalized = draft.verification.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selected = normalized == value || (value == "pending" && ["pending_review", "verification_pending"].contains(normalized))
        return Button { draft.verification = value; UISelectionFeedbackGenerator().selectionChanged() } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 22, weight: .light))
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 16)) }
                }
                Text(PPServiceText(key)).font(AdminType.headline).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .foregroundStyle(selected ? AdminSurface.primary : AdminSurface.primaryText)
                .background(selected ? AdminSurface.primarySoft.opacity(0.5) : AdminSurface.card, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(selected ? AdminSurface.primary.opacity(0.6) : .clear, lineWidth: 1) }
        }.buttonStyle(PPServicePressStyle()).accessibilityLabel(PPServiceText(key))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var subscription: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Service_Moderation_SubscriptionSection", 3)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 20) {
                    technicalField("Service_Field_SubscriptionType", text: $draft.subscriptionType)
                    technicalField("Service_Field_SubscriptionPlan", text: $draft.subscriptionPlan)
                    technicalField("Service_Field_SubscriptionStatus", text: $draft.subscriptionStatus)
                    Toggle(PPServiceText("Service_Field_SubscriptionActive"), isOn: $draft.subscriptionActive).tint(AdminSurface.primary)
                    optionalDate("Service_Field_SubscriptionStart", enabled: $draft.hasStart, date: $draft.start)
                    optionalDate("Service_Field_SubscriptionEnd", enabled: $draft.hasEnd, date: $draft.end)
                }.padding(.top, 20).disabled(!draft.canEdit)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.localizedSubscriptionSummary()).font(AdminType.headline)
                    Text(PPServiceText("Service_Review_SubscriptionDetail")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                }
            }.tint(AdminSurface.primary).padding(20).background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audit: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Service_Review_Note", 4)
            Text(PPServiceText("Service_Review_NoteDetail")).font(AdminType.callout).foregroundStyle(AdminSurface.secondaryText)
            TextField(PPServiceText("Service_Field_AuditNote_Placeholder"), text: $draft.note, axis: .vertical)
                .lineLimit(3...8).multilineTextAlignment(.leading).focused($isEditingText)
                .accessibilityLabel(PPServiceText("Service_Field_AuditNote"))
                .padding(20).background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20)).disabled(!draft.canEdit)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var advanced: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 16) {
                Text(PPServiceText("Service_Review_FlagsDetail")).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                TextField(PPServiceText("Service_Field_ServiceFlags_Placeholder"), text: $draft.flags, axis: .vertical)
                    .font(.system(.footnote, design: .monospaced)).lineLimit(4...12)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight).focused($isEditingText)
                    .accessibilityLabel(PPServiceText("Service_Field_ServiceFlags"))
                    .padding(16).background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 16)).disabled(!draft.canEdit)
                Text(PPServiceText("Service_Field_ID")).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
                Text(service.serviceID).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight).frame(maxWidth: .infinity, alignment: .leading)
                Text(PPServiceText("Service_Field_OwnerID")).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
                Text(service.serviceOwnerID).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    .environment(\.layoutDirection, .leftToRight).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.top, 16)
        } label: { Label(PPServiceText("Service_Review_RecordOptions"), systemImage: "curlybraces").font(AdminType.headline).frame(minHeight: 44) }
            .tint(AdminSurface.secondaryText).padding(20).background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private var decisionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.phase == .saving || draft.phase == .confirming || draft.phase == .loading {
                HStack(spacing: 12) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(PPServiceText(draft.phase == .confirming ? "Service_Review_Confirming" :
                        (draft.phase == .saving ? "Service_Saving" : "Service_Review_Loading"))).font(AdminType.headline)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
            } else if draft.phase == .saved {
                Button(action: close) { Text(PPServiceText("Done")).font(AdminType.headline).frame(maxWidth: .infinity).frame(minHeight: 54) }
                    .buttonStyle(PPServicePressStyle()).foregroundStyle(.white).background(AdminSurface.primary, in: Capsule())
            } else if draft.phase == .awaitingConfirmation {
                Button(action: reload) {
                    Label(PPServiceText("Service_Review_CheckStatus"), systemImage: "arrow.clockwise")
                        .font(AdminType.headline).frame(maxWidth: .infinity).frame(minHeight: 54)
                }.buttonStyle(PPServicePressStyle()).foregroundStyle(.white).background(AdminSurface.primary, in: Capsule())
                Text(draft.error ?? PPServiceText("Service_Review_AcceptedPending")).font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText).fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    isEditingText = false
                    guard draft.candidate() != nil else { return }
                    showsConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Text(PPServiceText("Service_Review_ReviewDecision")).font(AdminType.headline)
                        Spacer(minLength: 8)
                        Text(draft.changes.count, format: .number).font(AdminType.headline).monospacedDigit()
                        Image(systemName: "arrow.forward").font(.system(size: 14, weight: .semibold))
                    }.padding(.horizontal, 22).frame(minHeight: 56)
                }
                .buttonStyle(PPServicePressStyle()).foregroundStyle(draft.canEdit && draft.hasChanges ? .white : AdminSurface.secondaryText)
                .background(draft.canEdit && draft.hasChanges ? AdminSurface.primary : AdminSurface.card, in: Capsule())
                .disabled(!draft.canEdit || !draft.hasChanges)
                Text(PPServiceText("Service_Review_SaveFootnote")).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            .background(AdminSurface.background)
    }

    private var confirmation: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(PPServiceText("Service_Review_ConfirmDetail")).font(AdminType.body).foregroundStyle(AdminSurface.secondaryText)
                    ForEach(draft.changes) { change in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(PPServiceText(change.id)).font(AdminType.headline)
                            Text(change.before.isEmpty ? PPServiceText("Service_Value_NotSpecified") : change.before)
                                .font(AdminType.callout).foregroundStyle(AdminSurface.secondaryText)
                            Label(change.after.isEmpty ? PPServiceText("Service_Value_NotSpecified") : change.after, systemImage: "arrow.turn.down.forward")
                                .font(AdminType.bodyBold).foregroundStyle(AdminSurface.primary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                    if !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(PPServiceText("Service_Field_AuditNote")).font(AdminType.headline)
                        Text(draft.note).font(AdminType.body)
                    }
                    Button {
                        guard draft.canEdit, let candidate = draft.candidate() else { return }
                        showsConfirmation = false
                        save(candidate, draft.baseline, draft.note)
                    } label: {
                        Label(PPServiceText("Service_Review_ConfirmSave"), systemImage: "checkmark").font(AdminType.headline)
                            .frame(maxWidth: .infinity).frame(minHeight: 56)
                    }.buttonStyle(PPServicePressStyle()).foregroundStyle(.white)
                        .background(AdminSurface.primary, in: Capsule()).disabled(!draft.canEdit)
                }.padding(24)
            }
            .background(AdminSurface.background).navigationTitle(PPServiceText("Service_Review_ConfirmTitle"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(PPServiceText("Cancel")) { showsConfirmation = false } } }
        }
        .environment(\.layoutDirection, language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private var saved: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.seal").font(.system(size: 52, weight: .light)).foregroundStyle(AdminSurface.emerald).accessibilityHidden(true)
            Text(PPServiceText("Service_Review_SavedTitle")).font(AdminType.title).accessibilityAddTraits(.isHeader)
                .accessibilityFocused($completionFocused)
            Text(PPServiceText("Service_Review_SavedDetail")).font(AdminType.body).foregroundStyle(AdminSurface.secondaryText)
            preview
        }.padding(.vertical, 24).id("review.saved")
    }

    private func recovery(_ error: String) -> some View {
        PPServiceNotice(text: error, isError: draft.phase != .awaitingConfirmation,
            actionTitle: (draft.phase == .conflict || draft.phase == .unavailable || draft.phase == .failed) ? PPServiceText("Service_Review_Reload") : nil) {
                if draft.hasChanges { showsReloadConfirmation = true } else { reload() }
            }
    }

    private func revealFeedback(_ message: String, proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("review.feedback", anchor: .top) }
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: message) }
    }

    private func sectionHeading(_ key: String, _ number: Int) -> some View {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumIntegerDigits = 2
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        let ordinal = formatter.string(from: NSNumber(value: number)) ?? String(number)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(ordinal).font(.system(.caption, design: .monospaced)).foregroundStyle(AdminSurface.primary).accessibilityHidden(true)
            Text(PPServiceText(key)).font(AdminType.title3).accessibilityAddTraits(.isHeader)
        }
    }

    private func controlLabel(_ title: String, _ detail: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(PPServiceText(title), systemImage: symbol).font(AdminType.headline)
            Text(PPServiceText(detail)).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func technicalField(_ key: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PPServiceText(key)).font(AdminType.footnoteBold).foregroundStyle(AdminSurface.secondaryText)
            TextField(PPServiceText("Service_Value_NotSpecified"), text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled().multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .leftToRight).focused($isEditingText)
                .accessibilityLabel(PPServiceText(key)).padding(14)
                .background(AdminSurface.background, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func optionalDate(_ key: String, enabled: Binding<Bool>, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(PPServiceText(key), isOn: enabled).tint(AdminSurface.primary)
            if enabled.wrappedValue {
                DatePicker(PPServiceText(key), selection: date, displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden().font(AdminType.callout)
                    .frame(minHeight: 44, alignment: .leading).accessibilityLabel(PPServiceText(key))
            }
        }
    }
}
