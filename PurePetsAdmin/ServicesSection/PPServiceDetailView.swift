import SwiftUI
import UIKit

// PPServiceDetailViewController remains the only navigation and mutation owner.
@objc(PPServiceDetailAction)
enum PPServiceDetailAction: Int {
    case close, refresh, edit, moderate, archive, delete
}

@MainActor
private final class PPServiceDetailState: ObservableObject {
    @Published var service: PPServiceModel
    @Published var refreshing = false
    @Published var mutating = false
    @Published var canManage = false
    @Published var errorMessage: String?

    init(service: PPServiceModel) { self.service = service }
}

@objc(PPServiceDetailHostingController)
final class PPServiceDetailHostingController: UIViewController {
    private let state: PPServiceDetailState
    private let actionHandler: (PPServiceDetailAction) -> Void

    @objc(initWithService:actionHandler:)
    init(service: PPServiceModel, actionHandler: @escaping (PPServiceDetailAction) -> Void) {
        state = PPServiceDetailState(service: service)
        self.actionHandler = actionHandler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(service:actionHandler:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .ppBackground
        let host = UIHostingController(rootView: PPServiceDetailScreen(state: state, action: actionHandler))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    @objc(updateWithService:refreshing:mutating:canManage:errorMessage:)
    func update(service: PPServiceModel, refreshing: Bool, mutating: Bool,
                canManage: Bool, errorMessage: String?) {
        state.service = service
        state.refreshing = refreshing
        state.mutating = mutating
        state.canManage = canManage
        state.errorMessage = errorMessage
    }
}

private struct PPServiceDetailScreen: View {
    @ObservedObject var state: PPServiceDetailState
    let action: (PPServiceDetailAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var language = Language.currentLanguageCode() ?? "ar"
    @State private var showsRecord = false
    @State private var showsSubscription = false

    private var service: PPServiceModel { state.service }
    private var isRTL: Bool { language.hasPrefix("ar") }
    private var busy: Bool { state.refreshing || state.mutating }
    private var mayAct: Bool { state.canManage && !busy }
    private var needsReview: Bool {
        // Unknown and legacy values must never acquire a verified seal.
        service.verificationStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "verified"
    }
    private var statusColor: Color {
        if service.isDeleted { return AdminSurface.secondaryText }
        if service.isBlocked { return AdminSurface.danger }
        if service.isDisabled { return AdminSurface.amber }
        return AdminSurface.emerald
    }
    private var serviceSymbol: String { service.type == .grooming ? "scissors" : "pawprint" }
    private var locale: Locale { Locale(identifier: isRTL ? "ar_QA" : "en_QA") }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760 && !dynamicTypeSize.isAccessibilitySize
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let error = state.errorMessage { recoveryNotice(error) }

                    if wide {
                        HStack(alignment: .top, spacing: 40) {
                            VStack(alignment: .leading, spacing: 28) {
                                identity
                                priceAndAvailability
                                descriptionSection
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 24) {
                                statusSection
                                classificationSection
                                subscriptionSection
                            }
                            .frame(width: min(340, geometry.size.width * 0.36), alignment: .leading)
                        }
                    } else {
                        identity
                        priceAndAvailability
                        statusSection
                        descriptionSection
                        classificationSection
                        subscriptionSection
                    }

                    recordSection
                    revisionFootnote
                }
                .frame(maxWidth: 1024, alignment: .leading)
                .padding(.horizontal, wide ? 32 : 24)
                .padding(.top, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(AdminSurface.background)
        }
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionDock }
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, locale)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LanguageDidChangeNotification"))) { _ in
            language = Language.currentLanguageCode() ?? "ar"
        }
        .accessibilityIdentifier("admin.service.detail")
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button { action(.close) } label: {
                Image(systemName: isRTL ? "chevron.right" : "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(detailText("Service_Detail_Back"))
            .accessibilityIdentifier("admin.service.detail.back")

            Text(detailText("Service_Detail_Title"))
                .font(AdminType.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { action(.refresh) } label: {
                ZStack {
                    if state.refreshing { ProgressView().tint(AdminSurface.primary) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .medium)) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .disabled(busy)
            .accessibilityLabel(detailText(state.refreshing ? "Service_Detail_Refreshing" : "Service_Detail_Refresh"))

            if state.canManage {
                Menu {
                    Button { action(.archive) } label: {
                        Label(detailText(service.isDeleted ? "Service_Action_Restore" : "Service_Action_Archive"),
                              systemImage: service.isDeleted ? "arrow.uturn.backward" : "archivebox")
                    }
                    Divider()
                    Button(role: .destructive) { action(.delete) } label: {
                        Label(detailText("Service_Detail_Delete"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!mayAct)
                .accessibilityLabel(detailText("Service_Detail_More"))
                .accessibilityIdentifier("admin.service.detail.more")
            }
        }
        .foregroundStyle(AdminSurface.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(AdminSurface.background)
        .overlay(alignment: .bottom) { Divider().overlay(AdminSurface.hairline) }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                serviceImage
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.localizedTypeName())
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primary)
                    Text(nonempty(service.category))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(service.title.isEmpty ? detailText("Service_Untitled") : service.title)
                .font(AdminType.largeTitle)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var serviceImage: some View {
        Group {
            if !service.imageURL.isEmpty, let url = URL(string: service.imageURL) {
                AdminRemoteImage(url: url, contentMode: .fill, targetSize: CGSize(width: 88, height: 88)) {
                    imageFallback
                }
            } else { imageFallback }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var imageFallback: some View {
        ZStack {
            AdminSurface.primary.opacity(0.07)
            Image(systemName: serviceSymbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AdminSurface.primary)
        }
    }

    private var priceAndAvailability: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                price.fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 8)
                availability
            }
            VStack(alignment: .leading, spacing: 18) { price; availability }
        }
        .padding(.vertical, 22)
        .overlay(alignment: .top) { Divider().overlay(AdminSurface.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(AdminSurface.hairline) }
    }

    private var price: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detailText("Service_Field_Price"))
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedPrice)
                    .font(Font.custom("Beiruti-Bold", size: 42, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .environment(\.layoutDirection, .leftToRight)
                Text(detailText("QAR"))
                    .font(AdminType.subheadlineBold)
            }
            .foregroundStyle(AdminSurface.primaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(detailText("Service_Field_AvailableDate"), systemImage: "calendar")
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
            Text(formattedDate(service.availableDate))
                .font(AdminType.bodyBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusLine(title: "Service_Field_Status", value: service.localizedPrimaryStatusTitle(),
                       symbol: service.isLive() ? "checkmark.circle" : "pause.circle", tint: statusColor)
            Divider().overlay(AdminSurface.hairline)
            statusLine(title: "Service_Field_VerificationStatus", value: service.localizedVerificationTitle(),
                       symbol: needsReview ? "checklist" : "checkmark.seal", tint: AdminSurface.primary)
            if needsReview {
                Text(detailText("Service_Detail_ReviewHint"))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(AdminSurface.primary)
                .frame(width: 3).padding(.vertical, 24)
        }
    }

    private func statusLine(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 21, weight: .regular))
                .foregroundStyle(tint).frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(detailText(title)).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
                Text(value).font(AdminType.title3).foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Service_Detail_About", symbol: "text.quote")
            Text(nonempty(service.serviceDescriptionText))
                .font(AdminType.body)
                .foregroundStyle(service.serviceDescriptionText.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var classificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Service_Detail_Classification", symbol: "tag")
            detailRow("Service_Field_Type", value: service.localizedTypeName())
            detailRow("Service_Field_Category", value: nonempty(service.category))
            detailRow("Service_Field_OwnerID", value: nonempty(service.serviceOwnerID), technical: true)
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            disclosureButton("Service_Detail_Subscription", summary: service.localizedSubscriptionSummary(),
                             symbol: "calendar.badge.clock", expanded: $showsSubscription)
            if showsSubscription {
                detailRow("Service_Field_SubscriptionPlan", value: nonempty(service.subscriptionPlan))
                detailRow("Service_Field_SubscriptionType", value: nonempty(service.subscriptionType))
                detailRow("Service_Field_SubscriptionStatus", value: nonempty(service.subscriptionStatus))
                detailRow("Service_Field_SubscriptionActive", value: detailText(service.subscriptionActive ? "Service_Subscription_Active" : "Service_Subscription_Inactive"))
                detailRow("Service_Field_SubscriptionStart", value: formattedDate(service.subscriptionStartDate))
                detailRow("Service_Field_SubscriptionEnd", value: formattedDate(service.subscriptionEndDate))
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) { Divider().overlay(AdminSurface.hairline) }
    }

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            disclosureButton("Service_Detail_Record", summary: detailText("Service_Detail_RecordHint"),
                             symbol: "doc.text", expanded: $showsRecord)
            if showsRecord {
                detailRow("Service_Field_ID", value: nonempty(service.serviceID), technical: true)
                detailRow("Service_Field_CategoryID", value: nonempty(service.categoryID), technical: true)
                detailRow("Service_Field_PetMainKindID", value: String(service.petMainKindID), technical: true)
                detailRow("Service_Field_Timestamp", value: formattedDate(service.timestamp))
                detailRow("Service_Field_CreatedAt", value: formattedDate(service.createdAt))
                detailRow("Service_Field_UpdatedAt", value: formattedDate(service.updatedAt))
                detailRow("Service_Field_ImageURL", value: nonempty(service.imageURL), technical: true)
                detailRow("Service_Field_BlurHash", value: nonempty(service.blurHash), technical: true)
                if !service.serviceFlags.isEmpty {
                    detailRow("Service_Field_ServiceFlags", value: json(service.serviceFlags), technical: true)
                }
                if !service.extraFields.isEmpty {
                    detailRow("Service_Field_ExtraJSON", value: json(service.extraFields), technical: true)
                }
            }
        }
        .padding(.top, 22)
        .overlay(alignment: .top) { Divider().overlay(AdminSurface.hairline) }
    }

    private var revisionFootnote: some View {
        Label {
            Text(detailText("Service_Field_UpdatedAt") + " · " + formattedDate(service.updatedAt))
                .fixedSize(horizontal: false, vertical: true)
        } icon: { Image(systemName: "clock").accessibilityHidden(true) }
        .font(AdminType.footnote)
        .foregroundStyle(AdminSurface.secondaryText)
    }

    private var actionDock: some View {
        VStack(spacing: 10) {
            if state.mutating {
                HStack(spacing: 10) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(detailText("Service_Detail_Saving")).font(AdminType.callout)
                }
                .accessibilityElement(children: .combine)
            } else if state.refreshing {
                HStack(spacing: 10) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(detailText("Service_Detail_Refreshing")).font(AdminType.callout)
                }
                .accessibilityElement(children: .combine)
            } else if !state.canManage && !state.refreshing && state.errorMessage == nil {
                Label(detailText("Service_Detail_ReadOnly"), systemImage: "lock")
                    .font(AdminType.callout).foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.canManage {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    actionButton(needsReview ? "Service_Action_Edit" : "Service_Detail_Manage", symbol: needsReview ? "pencil" : "slider.horizontal.3", primary: false) {
                        action(needsReview ? .edit : .moderate)
                    }
                    actionButton(needsReview ? "Service_Detail_Review" : "Service_Detail_Edit", symbol: needsReview ? "checklist" : "pencil", primary: true) {
                        action(needsReview ? .moderate : .edit)
                    }
                }
                .disabled(!mayAct)
                .opacity(mayAct ? 1 : 0.5)
            }
        }
        .frame(maxWidth: 1024)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.background)
        .overlay(alignment: .top) { Divider().overlay(AdminSurface.hairline) }
    }

    private func actionButton(_ key: String, symbol: String, primary: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(detailText(key), systemImage: symbol)
                .font(AdminType.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(primary ? Color(uiColor: PPOnPrimaryColor()) : AdminSurface.primaryText)
                .background(primary ? AdminSurface.primary : AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PPServiceDetailPressStyle())
    }

    private func recoveryNotice(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(detailText("Service_Detail_RefreshFailed"), systemImage: "exclamationmark.triangle")
                .font(AdminType.headline)
            Text(message).font(AdminType.callout).fixedSize(horizontal: false, vertical: true)
            Button(detailText("Service_Detail_Retry")) { action(.refresh) }
                .font(AdminType.headline).frame(minHeight: 44).disabled(busy)
        }
        .foregroundStyle(AdminSurface.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("admin.service.detail.recovery")
    }

    private func sectionHeading(_ key: String, symbol: String) -> some View {
        Label(detailText(key), systemImage: symbol)
            .font(AdminType.headline)
            .foregroundStyle(AdminSurface.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private func detailRow(_ key: String, value: String, technical: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(detailText(key)).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
            Text(value)
                .font(technical ? .system(.callout, design: .monospaced) : AdminType.bodyBold)
                .foregroundStyle(AdminSurface.primaryText)
                .environment(\.layoutDirection, technical ? .leftToRight : (isRTL ? .rightToLeft : .leftToRight))
                .multilineTextAlignment(technical && isRTL ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func disclosureButton(_ key: String, summary: String, symbol: String, expanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(detailText(key)).font(AdminType.headline)
                    Text(summary).font(AdminType.callout).foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: expanded.wrappedValue ? "minus" : "plus")
                    .font(.system(size: 16, weight: .medium)).accessibilityHidden(true)
            }
            .foregroundStyle(AdminSurface.primaryText)
            .multilineTextAlignment(.leading)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(detailText(expanded.wrappedValue ? "Service_Detail_Expanded" : "Service_Detail_Collapsed"))
        .accessibilityHint(detailText(expanded.wrappedValue ? "Service_Detail_CollapseHint" : "Service_Detail_ExpandHint"))
    }

    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: service.price)) ?? nonempty("")
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return detailText("Service_Value_NotSpecified") }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func nonempty(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? detailText("Service_Value_NotSpecified") : value
    }

    private func json(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return detailText("Service_Value_NotSpecified") }
        return text
    }
}

private struct PPServiceDetailPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private func detailText(_ key: String) -> String {
    Language.get(key, alter: NSLocalizedString(key, comment: ""))
}
