import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth

// The existing UIKit route and PPServiceManager retain navigation/data authority.
extension PPServiceModel: @retroactive Identifiable, @unchecked Sendable {
    public var id: String { serviceID }
}

func PPServiceText(_ key: String) -> String { Language.get(key, alter: nil) }

func PPServiceNeedsReview(_ service: PPServiceModel) -> Bool {
    !service.isDeleted && (service.isBlocked || service.isDisabled ||
        service.verificationStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "verified")
}

func PPServicePrice(_ price: Double) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return String(format: PPServiceText("Service_Workspace_Price_Format"),
                  formatter.string(from: NSNumber(value: price)) ?? "—")
}

func PPServiceStatusColor(_ service: PPServiceModel) -> Color {
    if service.isDeleted { return AdminSurface.secondaryText }
    if service.isBlocked { return AdminSurface.danger }
    if service.isDisabled { return AdminSurface.amber }
    return AdminSurface.emerald
}

enum AdminServicePrimaryFilter: Int, CaseIterable, Identifiable {
    case all, live, review, archived
    var id: Int { rawValue }
    var title: String {
        PPServiceText(["Service_Filter_All", "Service_Filter_Live", "Service_Filter_NeedsReview",
                       "Service_Filter_Archived"][rawValue])
    }
}

enum AdminServiceSecondaryFilter: Int, CaseIterable, Identifiable {
    case any, needsReview, verified, pending, blocked, disabled
    var id: Int { rawValue }
    var title: String {
        PPServiceText(["Service_Filter_Any", "Service_Filter_NeedsReview", "Service_Filter_Verified",
                       "Service_Filter_Pending", "Service_Filter_Blocked", "Service_Filter_Disabled"][rawValue])
    }
}

enum AdminServiceSortOption: Int, CaseIterable, Identifiable {
    case updatedDesc, titleAsc, priceHigh, priceLow, availableSoonest
    var id: Int { rawValue }
    var title: String {
        PPServiceText(["Service_Sort_Updated", "Service_Sort_Title", "Service_Sort_PriceHigh",
                       "Service_Sort_PriceLow", "Service_Sort_Available"][rawValue])
    }
}

enum AdminServiceActiveSheet: Identifiable {
    case add, edit(PPServiceModel), moderate(PPServiceModel)
    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let service): return "edit_\(service.serviceID)"
        case .moderate(let service): return "moderate_\(service.serviceID)"
        }
    }
}

// Access stays on MainActor; this lifetime object also removes the listener if
// SwiftUI releases a host without delivering its normal disappearance callback.
private final class PPServiceListenerLifetime: @unchecked Sendable {
    var registration: (any ListenerRegistration)?
    deinit { registration?.remove() }
}

@MainActor
final class AdminServicesViewModel: ObservableObject {
    @Published private(set) var allServices: [PPServiceModel] = []
    @Published private(set) var filteredServices: [PPServiceModel] = []
    @Published var searchQuery = "" { didSet { applyFilters() } }
    @Published var primaryFilter: AdminServicePrimaryFilter = .all { didSet { applyFilters() } }
    @Published var secondaryFilter: AdminServiceSecondaryFilter = .any { didSet { applyFilters() } }
    @Published var sortOption: AdminServiceSortOption = .updatedDesc { didSet { applyFilters() } }
    @Published var category = "" { didSet { applyFilters() } }
    @Published var selectedServiceID: String?
    @Published var activeSheet: AdminServiceActiveSheet?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canRead = false
    @Published private(set) var canManage = false
    @Published private(set) var hasMore = false
    @Published private(set) var hasAdditionalPages = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var mutationID: String?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var lastReceivedAt: Date?
    let openDetail: (PPServiceModel) -> Void
    var onAddService: (() -> Void)?
    var onEditService: ((PPServiceModel) -> Void)?
    var onModerateService: ((PPServiceModel) -> Void)?

    private let lifetime = PPServiceListenerLifetime()
    private let pageSize = 100
    private var firstPage: [PPServiceModel] = []
    private var additional: [String: PPServiceModel] = [:]
    private var cursor: String?
    private var generation = 0
    private var active = false

    init(
        openDetail: @escaping (PPServiceModel) -> Void,
        onAddService: (() -> Void)? = nil,
        onEditService: ((PPServiceModel) -> Void)? = nil,
        onModerateService: ((PPServiceModel) -> Void)? = nil
    ) {
        self.openDetail = openDetail
        self.onAddService = onAddService
        self.onEditService = onEditService
        self.onModerateService = onModerateService
    }

    var selectedService: PPServiceModel? { allServices.first { $0.serviceID == selectedServiceID } }
    var totalCount: Int { allServices.count }
    var liveCount: Int { allServices.filter { $0.isLive() }.count }
    var reviewCount: Int { allServices.filter(PPServiceNeedsReview).count }
    var archivedCount: Int { allServices.filter { $0.isDeleted }.count }
    var categories: [String] { Array(Set(allServices.map(\.category).filter { !$0.isEmpty })).sorted() }
    var isRefined: Bool { secondaryFilter != .any || sortOption != .updatedDesc || !category.isEmpty }
    var isFiltered: Bool { isRefined || primaryFilter != .all || !searchQuery.isEmpty }

    func count(for filter: AdminServicePrimaryFilter) -> Int {
        switch filter {
        case .all: return totalCount
        case .live: return liveCount
        case .review: return reviewCount
        case .archived: return archivedCount
        }
    }

    func startListening() {
        guard !active else { return }
        active = true
        authorizeAndListen()
    }

    func stopListening() {
        active = false
        generation += 1
        lifetime.registration?.remove()
        lifetime.registration = nil
        isLoading = false
        isLoadingMore = false
    }

    func refreshTriggered() {
        guard active, mutationID == nil else { return }
        generation += 1
        lifetime.registration?.remove()
        lifetime.registration = nil
        firstPage = []
        additional = [:]
        cursor = nil
        hasAdditionalPages = false
        authorizeAndListen()
    }

    private func authorizeAndListen() {
        generation += 1
        let requestGeneration = generation
        isLoading = true
        errorMessage = nil
        PPStaffAuth.shared().refreshCurrentStaff { [weak self] staff, error in
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == requestGeneration else { return }
                let uid = Auth.auth().currentUser?.uid
                self.canManage = error == nil && PPServiceManager.shared().currentAdminCanManageServices()
                self.canRead = self.canManage || (error == nil && staff?.uid == uid && staff?.isActive() == true &&
                    staff?.hasPermission("services.view") == true)
                guard self.canRead else {
                    self.allServices = []
                    self.filteredServices = []
                    self.selectedServiceID = nil
                    self.activeSheet = nil
                    self.isLoading = false
                    self.errorMessage = error.map { _ in PPServiceText("Service_Workspace_AuthorizationError") }
                    return
                }
                self.lifetime.registration = PPServiceManager.shared().observeServicePage(withLimit: self.pageSize) { [weak self] services, error in
                    Task { @MainActor [weak self] in
                        guard let self, self.active, self.generation == requestGeneration else { return }
                        self.isLoading = false
                        if let nsError = error as NSError?, nsError.code != 299 {
                            self.errorMessage = nsError.localizedDescription
                            if nsError.code == 403 {
                                self.canRead = false; self.canManage = false
                                self.allServices = []; self.filteredServices = []; self.selectedServiceID = nil
                                self.activeSheet = nil
                                self.lifetime.registration?.remove(); self.lifetime.registration = nil
                            }
                            return
                        }
                        self.firstPage = services ?? []
                        self.hasLoaded = true
                        self.lastReceivedAt = Date()
                        self.errorMessage = error?.localizedDescription
                        if !self.hasAdditionalPages {
                            self.cursor = self.firstPage.last?.serviceID
                            self.hasMore = self.firstPage.count == self.pageSize
                        }
                        self.mergePages()
                    }
                }
            }
        }
    }

    func loadMore() {
        guard active, canRead, hasMore, !isLoadingMore, !isLoading, let cursor else { return }
        isLoadingMore = true
        let requestGeneration = generation
        PPServiceManager.shared().fetchServicePage(afterServiceID: cursor, limit: pageSize) { [weak self] services, error in
            Task { @MainActor [weak self] in
                guard let self, self.active, self.generation == requestGeneration else { return }
                self.isLoadingMore = false
                if let error { self.errorMessage = error.localizedDescription; return }
                let items = services ?? []
                for item in items { self.additional[item.serviceID] = item }
                self.cursor = items.last?.serviceID ?? cursor
                self.hasMore = items.count == self.pageSize
                self.hasAdditionalPages = !self.additional.isEmpty
                self.mergePages()
            }
        }
    }

    private func mergePages() {
        var records = additional
        for item in firstPage { records[item.serviceID] = item }
        allServices = Array(records.values)
        applyFilters()
    }

    func applyFilters() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let pending = ["pending", "pending_review", "verification_pending"]
        filteredServices = allServices.filter { service in
            switch primaryFilter {
            case .all: break
            case .live: if !service.isLive() { return false }
            case .review: if !PPServiceNeedsReview(service) { return false }
            case .archived: if !service.isDeleted { return false }
            }
            let verification = service.verificationStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch secondaryFilter {
            case .any: break
            case .needsReview: if !PPServiceNeedsReview(service) { return false }
            case .verified: if verification != "verified" { return false }
            case .pending: if !pending.contains(verification) { return false }
            case .blocked: if !service.isBlocked { return false }
            case .disabled: if !service.isDisabled { return false }
            }
            if !category.isEmpty && service.category != category { return false }
            guard !query.isEmpty else { return true }
            return [service.title, service.serviceDescriptionText, service.category, service.categoryID,
                    service.serviceOwnerID, service.serviceID, service.verificationStatus, service.subscriptionPlan]
                .contains { $0.localizedStandardContains(query) }
        }.sorted { left, right in
            switch sortOption {
            case .titleAsc:
                let order = left.title.localizedStandardCompare(right.title)
                if order != .orderedSame { return order == .orderedAscending }
            case .priceHigh: if left.price != right.price { return left.price > right.price }
            case .priceLow: if left.price != right.price { return left.price < right.price }
            case .availableSoonest:
                let a = left.availableDate ?? .distantFuture, b = right.availableDate ?? .distantFuture
                if a != b { return a < b }
            case .updatedDesc:
                let a = left.updatedAt ?? left.timestamp ?? left.createdAt ?? .distantPast
                let b = right.updatedAt ?? right.timestamp ?? right.createdAt ?? .distantPast
                if a != b { return a > b }
            }
            return left.serviceID < right.serviceID
        }
        if !filteredServices.contains(where: { $0.serviceID == selectedServiceID }) {
            selectedServiceID = filteredServices.first?.serviceID
        }
    }

    func resetFilters() {
        searchQuery = ""; primaryFilter = .all; secondaryFilter = .any; sortOption = .updatedDesc; category = ""
    }

    func present(_ sheet: AdminServiceActiveSheet) {
        guard canManage, mutationID == nil else { return }
        switch sheet {
        case .add:
            if let onAddService {
                onAddService()
                return
            }
            let controller = PPAddEditServiceViewController(service: nil)
            controller.hidesBottomBarWhenPushed = true
            PPAdminNavigationFallback.presentOrPush(controller)
        case .edit(let service):
            if let onEditService {
                onEditService(service)
                return
            }
            let controller = PPAddEditServiceViewController(service: service)
            controller.hidesBottomBarWhenPushed = true
            PPAdminNavigationFallback.presentOrPush(controller)
        case .moderate(let service):
            if let onModerateService {
                onModerateService(service)
                return
            }
            let controller = PPServiceModerationViewController(service: service)
            controller.hidesBottomBarWhenPushed = true
            PPAdminNavigationFallback.presentOrPush(controller)
        }
    }

    func reviewNext() {
        guard let service = filteredServices.first(where: PPServiceNeedsReview) ?? allServices.first(where: PPServiceNeedsReview) else { return }
        present(.moderate(service))
    }

    func toggleDisabled(service: PPServiceModel) {
        perform(service: service, expected: { $0.isDisabled == !service.isDisabled },
                message: PPServiceText(service.isDisabled ? "Service_Enabled_Success" : "Service_Disabled_Success")) { completion in
            PPServiceManager.shared().setDisabled(!service.isDisabled, forServiceID: service.serviceID, auditNote: nil, completion: completion)
        }
    }

    func toggleBlocked(service: PPServiceModel) {
        perform(service: service, expected: { $0.isBlocked == !service.isBlocked },
                message: PPServiceText(service.isBlocked ? "Service_Unblocked_Success" : "Service_Blocked_Success")) { completion in
            PPServiceManager.shared().setBlocked(!service.isBlocked, forServiceID: service.serviceID, auditNote: nil, completion: completion)
        }
    }

    func toggleArchived(service: PPServiceModel) {
        perform(service: service, expected: { $0.isDeleted == !service.isDeleted },
                message: PPServiceText(service.isDeleted ? "Service_Restored_Success" : "Service_Archived_Success")) { completion in
            if service.isDeleted {
                PPServiceManager.shared().restoreServiceID(service.serviceID, auditNote: nil, completion: completion)
            } else {
                PPServiceManager.shared().archiveServiceID(service.serviceID, auditNote: nil, completion: completion)
            }
        }
    }

    func deletePermanently(service: PPServiceModel) {
        guard canManage, mutationID == nil else { return }
        mutationID = service.serviceID
        errorMessage = nil; successMessage = nil
        PPServiceManager.shared().deleteServicePermanently(service.serviceID, auditNote: nil) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mutationID = nil
                if let error { self.errorMessage = error.localizedDescription; return }
                self.additional.removeValue(forKey: service.serviceID)
                self.firstPage.removeAll { $0.serviceID == service.serviceID }
                self.mergePages()
                self.successMessage = PPServiceText("Service_Deleted_Success")
            }
        }
    }

    private func perform(service: PPServiceModel, expected: @escaping @Sendable (PPServiceModel) -> Bool,
                         message: String, operation: (@escaping PPServiceVoidBlock) -> Void) {
        guard canManage, mutationID == nil else { return }
        mutationID = service.serviceID
        errorMessage = nil; successMessage = nil
        operation { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error { self.mutationID = nil; self.errorMessage = error.localizedDescription; return }
                PPServiceManager.shared().fetchService(byID: service.serviceID) { [weak self] observed, readError in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.mutationID = nil
                        guard readError == nil, let observed, expected(observed) else {
                            self.errorMessage = PPServiceText("Service_Workspace_AwaitingConfirmation")
                            return
                        }
                        if self.additional[observed.serviceID] != nil { self.additional[observed.serviceID] = observed }
                        if let index = self.firstPage.firstIndex(where: { $0.serviceID == observed.serviceID }) { self.firstPage[index] = observed }
                        self.mergePages()
                        self.successMessage = message
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }
        }
    }
}

public struct AdminServicesView: View {
    public var onDismiss: (() -> Void)?
    public var onAddService: (() -> Void)?
    public var onEditService: ((PPServiceModel) -> Void)?
    public var onModerateService: ((PPServiceModel) -> Void)?
    @StateObject private var model: AdminServicesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var language = Language.currentLanguageCode()
    @State private var showsRefinement = false
    @State private var confirmation: PPServiceListConfirmation?

    public init(
        onDismiss: (() -> Void)? = nil,
        onOpenService: @escaping (PPServiceModel) -> Void,
        onAddService: (() -> Void)? = nil,
        onEditService: ((PPServiceModel) -> Void)? = nil,
        onModerateService: ((PPServiceModel) -> Void)? = nil
    ) {
        self.onDismiss = onDismiss
        self.onAddService = onAddService
        self.onEditService = onEditService
        self.onModerateService = onModerateService
        _model = StateObject(wrappedValue: AdminServicesViewModel(
            openDetail: onOpenService,
            onAddService: onAddService,
            onEditService: onEditService,
            onModerateService: onModerateService
        ))
    }

    public var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 860 && !typeSize.isAccessibilitySize
            let topInset = max(geometry.safeAreaInsets.top, PPStatusBarHelper.statusBarHeight)
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                header
                if wide {
                    HStack(alignment: .top, spacing: 28) {
                        collection(inspector: true).padding(.trailing, 4)
                        if let selected = model.selectedService {
                            PPServiceInspector(service: selected, canManage: model.canManage && model.mutationID == nil,
                                view: { model.openDetail(selected) }, edit: { model.present(.edit(selected)) },
                                moderate: { model.present(.moderate(selected)) })
                                .frame(width: min(380, geometry.size.width * 0.38))
                        }
                    }
                    .padding(.horizontal, 28)
                } else {
                    collection(inspector: false).padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: 1240).frame(maxWidth: .infinity)
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .foregroundStyle(AdminSurface.primaryText)
        .accessibilityIdentifier("admin.services.workspace")
        .environment(\.layoutDirection, language.hasPrefix("ar") ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: language.hasPrefix("ar") ? "ar_QA" : "en_QA"))
        .onAppear { model.startListening() }
        .onDisappear { model.stopListening() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshTriggered() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LanguageDidChangeNotification"))) { _ in
            language = Language.currentLanguageCode()
        }
        .sheet(isPresented: $showsRefinement) {
            PPServiceRefinementSheet(model: model)
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if let action = confirmation {
                Button(action.title, role: action.isDestructive ? .destructive : nil) { action.execute(model); confirmation = nil }
                Button(PPServiceText("Cancel"), role: .cancel) { confirmation = nil }
            }
        } message: {
            Text(confirmation?.message ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { if let onDismiss { onDismiss() } else { dismiss() } } label: {
                Image(systemName: "arrow.backward").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44).background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(PPServicePressStyle()).accessibilityLabel(PPServiceText("Back"))
            VStack(alignment: .leading, spacing: 2) {
                Text(PPServiceText("Services")).font(AdminType.title)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                Text(PPServiceText("Service_Workspace_Collection")).font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button(PPServiceText("Refresh"), systemImage: "arrow.clockwise") { model.refreshTriggered() }
                Button(PPServiceText("Service_Workspace_Add"), systemImage: "plus") { model.present(.add) }.disabled(!model.canManage)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold)).frame(width: 44, height: 44)
                    .background(AdminSurface.card, in: Circle())
            }.accessibilityLabel(PPServiceText("Service_Workspace_Actions"))
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 2)
    }

    private func collection(inspector: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.canRead {
                    if model.hasLoaded { reviewFocus }
                    search
                    if model.hasLoaded { filters }
                    if let error = model.errorMessage {
                        PPServiceNotice(text: error, isError: true, actionTitle: PPServiceText("Retry"), action: model.refreshTriggered)
                    }
                    if let message = model.successMessage {
                        PPServiceNotice(text: message, isError: false, actionTitle: PPServiceText("Dismiss")) { model.successMessage = nil }
                    }
                    if model.isLoading && !model.hasLoaded {
                        loading
                    } else if model.filteredServices.isEmpty && model.hasLoaded {
                        empty
                    } else {
                        resultHeading
                        ForEach(model.filteredServices) { service in
                            PPServiceCollectionRecord(service: service, canManage: model.canManage,
                                busy: model.mutationID != nil, selectsInPlace: inspector, selected: model.selectedServiceID == service.serviceID,
                                view: { model.selectedServiceID = service.serviceID; model.openDetail(service) },
                                select: { model.selectedServiceID = service.serviceID },
                                edit: { model.present(.edit(service)) }, moderate: { model.present(.moderate(service)) },
                                request: { confirmation = $0 })
                        }
                    }
                    if model.hasMore {
                        Button { model.loadMore() } label: {
                            HStack {
                                if model.isLoadingMore { ProgressView() }
                                Text(PPServiceText("Service_Workspace_LoadMore")).font(AdminType.headline)
                                Image(systemName: "arrow.down")
                            }.frame(maxWidth: .infinity).frame(minHeight: 52)
                        }.buttonStyle(PPServicePressStyle()).disabled(model.isLoadingMore || model.isLoading)
                    }
                    if model.hasAdditionalPages {
                        Text(PPServiceText("Service_Workspace_AdditionalPageNote")).font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                } else if model.isLoading {
                    loading
                } else {
                    PPServiceBlankState(symbol: "lock.shield", title: PPServiceText("Service_Workspace_NoAccess"),
                        message: model.errorMessage ?? PPServiceText("Service_Error_NoPermission"),
                        actionTitle: PPServiceText("Retry"), action: model.refreshTriggered)
                }
            }
            .padding(.top, 2).padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { model.refreshTriggered() }
    }

    private var reviewFocus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                if model.reviewCount > 0 {
                    Text(model.reviewCount, format: .number)
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(AdminSurface.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(PPServiceText(model.reviewCount > 0 ? "Service_Workspace_ReviewFocus" : "Service_Workspace_AllClear"))
                        .font(AdminType.title3).bold().fixedSize(horizontal: false, vertical: true)
                    Text(PPServiceText(model.reviewCount > 0 ? "Service_Workspace_ReviewFocusDetail" : "Service_Workspace_AllClearDetail"))
                        .font(AdminType.subheadline).foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(String(format: PPServiceText("Service_Workspace_ReviewCount_Format"), model.reviewCount))
            if model.reviewCount > 0 && model.canManage {
                Button { model.reviewNext() } label: {
                    HStack(spacing: 8) {
                        Text(PPServiceText("Service_Workspace_ReviewNext")).font(AdminType.footnoteBold)
                        Image(systemName: "arrow.forward").font(.system(size: 11, weight: .bold))
                    }.frame(minHeight: 36).padding(.horizontal, 16)
                }
                .buttonStyle(PPServicePressStyle()).foregroundStyle(.white)
                .background(AdminSurface.primary, in: Capsule()).disabled(model.mutationID != nil)
            }
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AdminSurface.secondaryText).accessibilityHidden(true)
            TextField(PPServiceText("Service_Workspace_Search"), text: $model.searchQuery)
                .font(AdminType.body).submitLabel(.search)
                .multilineTextAlignment(.leading)
                .accessibilityLabel(PPServiceText("Service_Workspace_Search"))
            if !model.searchQuery.isEmpty {
                Button { model.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(PPServiceText("Service_Workspace_ClearSearch"))
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 56)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { filterItems }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) { filterItems }
            }
            HStack(alignment: .center, spacing: 12) {
                Text(PPServiceText(model.hasMore || model.hasAdditionalPages ? "Service_Workspace_LoadedCollection" : "Service_Workspace_EntireCollection"))
                    .font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { showsRefinement = true } label: {
                    Label(PPServiceText("Service_Workspace_Refine"), systemImage: model.isRefined ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                        .font(AdminType.footnoteBold).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(model.isRefined ? AdminSurface.primary : AdminSurface.primaryText)
            }
        }
    }

    @ViewBuilder private var filterItems: some View {
        ForEach(AdminServicePrimaryFilter.allCases) { filter in
            Button { model.primaryFilter = filter } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.count(for: filter), format: .number).font(AdminType.title2).monospacedDigit()
                    Text(filter.title).font(AdminType.footnoteBold).fixedSize(horizontal: false, vertical: true)
                    Capsule().fill(model.primaryFilter == filter ? AdminSurface.primary : AdminSurface.hairline).frame(height: 3)
                }
                .foregroundStyle(model.primaryFilter == filter ? AdminSurface.primary : AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.trailing, 12)
            }
            .buttonStyle(PPServicePressStyle()).accessibilityElement(children: .ignore)
            .accessibilityLabel(filter.title).accessibilityValue(model.count(for: filter).formatted())
            .accessibilityAddTraits(model.primaryFilter == filter ? .isSelected : [])
        }
    }

    private var resultHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(PPServiceText(model.primaryFilter == .review ? "Service_Workspace_ReviewQueue" : "Service_Workspace_ServicesHeading"))
                .font(AdminType.headline).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if model.isLoading { ProgressView().accessibilityLabel(PPServiceText("Service_Workspace_Refreshing")) }
            else { Text(model.filteredServices.count, format: .number).font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText) }
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressView(PPServiceText("Service_Workspace_Loading")).font(AdminType.callout)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 24).fill(AdminSurface.card).frame(height: 148).accessibilityHidden(true)
            }
        }
    }

    private var empty: some View {
        PPServiceBlankState(symbol: model.isFiltered ? "magnifyingglass" : "sparkles",
            title: PPServiceText(model.isFiltered ? "Service_Workspace_NoMatches" : "Service_Workspace_EmptyTitle"),
            message: PPServiceText(model.isFiltered ? "Service_Workspace_NoMatchesDetail" : "Service_Workspace_EmptyDetail"),
            actionTitle: model.isFiltered ? PPServiceText("Service_Workspace_Reset") : (model.canManage ? PPServiceText("Service_Workspace_Add") : nil),
            action: { if model.isFiltered { model.resetFilters() } else { model.present(.add) } })
    }
}

private enum PPServiceListConfirmation {
    case disabled(PPServiceModel), blocked(PPServiceModel), archived(PPServiceModel), delete(PPServiceModel)
    var title: String {
        switch self {
        case .disabled(let service): return PPServiceText(service.isDisabled ? "Service_Action_Enable" : "Service_Action_Disable")
        case .blocked(let service): return PPServiceText(service.isBlocked ? "Service_Action_Unblock" : "Service_Action_Block")
        case .archived(let service): return PPServiceText(service.isDeleted ? "Service_Action_Restore" : "Service_Action_Archive")
        case .delete: return PPServiceText("Service_Confirm_Delete_Title")
        }
    }
    var isDestructive: Bool { if case .delete = self { return true }; return false }
    var message: String {
        switch self {
        case .delete: return PPServiceText("Service_Confirm_Delete_Subtitle")
        case .disabled: return PPServiceText("Service_Workspace_DisableEffect")
        case .blocked: return PPServiceText("Service_Workspace_BlockEffect")
        case .archived: return PPServiceText("Service_Workspace_ArchiveEffect")
        }
    }
    @MainActor func execute(_ model: AdminServicesViewModel) {
        switch self {
        case .disabled(let service): model.toggleDisabled(service: service)
        case .blocked(let service): model.toggleBlocked(service: service)
        case .archived(let service): model.toggleArchived(service: service)
        case .delete(let service): model.deletePermanently(service: service)
        }
    }
}

private struct PPServiceCollectionRecord: View {
    let service: PPServiceModel
    let canManage: Bool
    let busy: Bool
    let selectsInPlace: Bool
    let selected: Bool
    let view: () -> Void
    let select: () -> Void
    let edit: () -> Void
    let moderate: () -> Void
    let request: (PPServiceListConfirmation) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: selectsInPlace ? select : view) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        PPServiceArtwork(service: service, size: 64)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(service.category.isEmpty ? service.localizedTypeName() : service.category)
                                .font(AdminType.captionBold).foregroundStyle(AdminSurface.primary)
                            Text(service.title).font(AdminType.title2).foregroundStyle(AdminSurface.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(PPServicePrice(service.price)).font(AdminType.headline)
                                .foregroundStyle(AdminSurface.primaryText).environment(\.layoutDirection, .leftToRight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { statusLabels }
                        VStack(alignment: .leading, spacing: 8) { statusLabels }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(PPServicePressStyle())
            .accessibilityElement(children: .combine).accessibilityHint(PPServiceText("Service_Workspace_OpenHint"))
            Rectangle().fill(AdminSurface.hairline).frame(height: 1).padding(.horizontal, 20)
            if canManage {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 4) { actions }.padding(12)
                } else {
                    HStack(spacing: 8) { actions }.padding(12)
                }
            } else {
                Button(action: view) {
                    Label(PPServiceText("Service_Action_View"), systemImage: "arrow.forward").font(AdminType.headline)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 48).padding(.horizontal, 20)
                }.buttonStyle(.plain)
            }
        }
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(selectsInPlace && selected ? AdminSurface.primary.opacity(0.4) : .clear, lineWidth: 1) }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(PPServiceNeedsReview(service) ? AdminSurface.primary : PPServiceStatusColor(service))
                .frame(width: 3, height: 32).padding(.leading, 1).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var statusLabels: some View {
        Label {
            Text(service.localizedPrimaryStatusTitle()).foregroundStyle(AdminSurface.primaryText)
        } icon: {
            Image(systemName: service.isDeleted ? "archivebox" : (service.isLive() ? "circle.fill" : "pause.circle"))
                .foregroundStyle(PPServiceStatusColor(service))
        }.font(AdminType.footnoteBold)
        Label(service.localizedVerificationTitle(), systemImage: service.verificationStatus.lowercased() == "verified" ? "checkmark.seal" : "clock")
            .font(AdminType.footnote).foregroundStyle(AdminSurface.secondaryText)
    }

    @ViewBuilder private var actions: some View {
        Button(action: moderate) {
            Label(PPServiceText(PPServiceNeedsReview(service) ? "Service_Workspace_Review" : "Service_Action_Moderate"), systemImage: "slider.horizontal.3")
                .font(AdminType.headline).frame(maxWidth: .infinity).frame(minHeight: 48)
                .background(AdminSurface.primarySoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(PPServicePressStyle()).foregroundStyle(AdminSurface.primary).disabled(busy)
        Button(action: edit) {
            Label(PPServiceText("Service_Action_Edit"), systemImage: "pencil").font(AdminType.headline)
                .frame(maxWidth: .infinity).frame(minHeight: 48)
        }.buttonStyle(PPServicePressStyle()).disabled(busy)
        Menu {
            Button(PPServiceText("Service_Action_View"), systemImage: "eye", action: view)
            Button(PPServiceText(service.isDisabled ? "Service_Action_Enable" : "Service_Action_Disable"), systemImage: "pause.circle") { request(.disabled(service)) }
            Button(PPServiceText(service.isBlocked ? "Service_Action_Unblock" : "Service_Action_Block"), systemImage: "hand.raised") { request(.blocked(service)) }
            Button(PPServiceText(service.isDeleted ? "Service_Action_Restore" : "Service_Action_Archive"), systemImage: "archivebox") { request(.archived(service)) }
            Button(PPServiceText("Service_Workspace_Delete"), systemImage: "trash", role: .destructive) { request(.delete(service)) }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).frame(minWidth: 48, minHeight: 48)
        }.disabled(busy).accessibilityLabel(PPServiceText("Service_Workspace_Actions"))
    }
}

struct PPServiceArtwork: View {
    let service: PPServiceModel
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let url = URL(string: service.imageURL), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { placeholder }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size).clipped()
        .background(AdminSurface.primarySoft.opacity(0.3), in: RoundedRectangle(cornerRadius: size * 0.25))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25)).accessibilityHidden(true)
    }
    private var placeholder: some View {
        Image(systemName: service.type == .grooming ? "scissors" : "pawprint")
            .font(.system(size: size * 0.36, weight: .light)).foregroundStyle(AdminSurface.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PPServiceInspector: View {
    let service: PPServiceModel
    let canManage: Bool
    let view: () -> Void
    let edit: () -> Void
    let moderate: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(PPServiceText("Service_Workspace_SelectedRecord")).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
                PPServiceArtwork(service: service, size: 96)
                Text(service.title).font(AdminType.title).fixedSize(horizontal: false, vertical: true)
                Text(service.serviceDescriptionText).font(AdminType.body).foregroundStyle(AdminSurface.secondaryText)
                Text(PPServicePrice(service.price)).font(AdminType.title2).environment(\.layoutDirection, .leftToRight)
                Divider()
                Label(service.localizedVerificationTitle(), systemImage: "checkmark.seal").font(AdminType.headline)
                Text(service.localizedSubscriptionSummary()).font(AdminType.callout).foregroundStyle(AdminSurface.secondaryText)
                if canManage {
                    Button(action: moderate) { Label(PPServiceText("Service_Action_Moderate"), systemImage: "slider.horizontal.3").frame(maxWidth: .infinity).frame(minHeight: 52) }
                        .buttonStyle(PPServicePressStyle()).foregroundStyle(.white).background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18))
                    Button(action: edit) { Label(PPServiceText("Service_Action_Edit"), systemImage: "pencil").frame(maxWidth: .infinity).frame(minHeight: 48) }.buttonStyle(.plain)
                }
                Button(action: view) { Label(PPServiceText("Service_Workspace_FullRecord"), systemImage: "arrow.forward").frame(minHeight: 44) }.buttonStyle(.plain)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }.background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct PPServiceRefinementSheet: View {
    @ObservedObject var model: AdminServicesViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Picker(PPServiceText("Service_Workspace_Status"), selection: $model.secondaryFilter) {
                    ForEach(AdminServiceSecondaryFilter.allCases) { Text($0.title).tag($0) }
                }
                Picker(PPServiceText("Service_Workspace_Sort"), selection: $model.sortOption) {
                    ForEach(AdminServiceSortOption.allCases) { Text($0.title).tag($0) }
                }
                Picker(PPServiceText("Service_Field_Category"), selection: $model.category) {
                    Text(PPServiceText("Service_Workspace_AllCategories")).tag("")
                    ForEach(model.categories, id: \.self) { Text($0).tag($0) }
                }
                Button(PPServiceText("Service_Workspace_Reset")) { model.resetFilters() }
            }
            .font(AdminType.body).navigationTitle(PPServiceText("Service_Workspace_Refine"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(PPServiceText("Done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

struct PPServiceNotice: View {
    let text: String
    var isError: Bool
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(isError ? AdminSurface.danger : AdminSurface.emerald)
            }.font(AdminType.callout).foregroundStyle(AdminSurface.primaryText)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(AdminType.headline).frame(minHeight: 44)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background((isError ? AdminSurface.danger : AdminSurface.emerald).opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .contain)
    }
}

struct PPServiceBlankState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(AdminSurface.primary).accessibilityHidden(true)
            Text(title).font(AdminType.title2).accessibilityAddTraits(.isHeader)
            Text(message).font(AdminType.body).foregroundStyle(AdminSurface.secondaryText)
            if let actionTitle, let action { Button(actionTitle, action: action).font(AdminType.headline).frame(minHeight: 48) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 32)
    }
}

struct PPServicePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct AdminServiceAddEditSheetRepresentable: UIViewControllerRepresentable {
    let service: PPServiceModel?
    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: PPAddEditServiceViewController(service: service))
        navigation.navigationBar.isHidden = true
        return navigation
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct AdminServiceModerationSheetRepresentable: UIViewControllerRepresentable {
    let service: PPServiceModel
    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: PPServiceModerationViewController(service: service))
        navigation.navigationBar.isHidden = true
        return navigation
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
