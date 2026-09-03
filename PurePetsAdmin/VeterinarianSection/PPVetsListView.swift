import SwiftUI

// MARK: - Filter Enum

fileprivate enum VetListFilter: Int, CaseIterable {
    case all = 0
    case active
    case disabled

    var titleKey: String {
        switch self {
        case .all: return "Vet_Filter_All"
        case .active: return "Vet_Filter_Active"
        case .disabled: return "Vet_Filter_Disabled"
        }
    }
}

extension PPVetModel: @unchecked Sendable {}

// MARK: - ViewModel

@MainActor
final class PPVetsListViewModel: ObservableObject {
    @Published private(set) var allVets: [PPVetModel] = []
    @Published private(set) var filteredVets: [PPVetModel] = []
    @Published var searchText: String = ""
    @Published fileprivate var activeFilter: VetListFilter = .all
    @Published private(set) var isLoading: Bool = true

    private var listener: AnyObject?

    var totalCount: Int { allVets.count }
    var activeCount: Int { allVets.filter { !$0.isDisabled }.count }
    var disabledCount: Int { allVets.filter { $0.isDisabled }.count }

    func startListening() {
        listener = PPVetManager.shared().observeAllVets { [weak self] vets, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.allVets = vets ?? []
                self.isLoading = false
                self.applyFilter()
            }
        }
    }

    func stopListening() {
        listener = nil
    }

    func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = allVets.filter { vet in
            switch activeFilter {
            case .all: break
            case .active: if vet.isDisabled { return false }
            case .disabled: if !vet.isDisabled { return false }
            }
            guard !query.isEmpty else { return true }
            let name = (vet.title ?? "").lowercased()
            let desc = (vet.descriptionText ?? "").lowercased()
            let phone = (vet.phone ?? "").lowercased()
            return name.contains(query) || desc.contains(query) || phone.contains(query)
        }
        result.sort { a, b in
            if a.isDisabled != b.isDisabled { return !a.isDisabled }
            return (a.title ?? "").localizedCaseInsensitiveCompare(b.title ?? "") == .orderedAscending
        }
        filteredVets = result
    }

    func refresh() async {
        await withCheckedContinuation { continuation in
            PPVetManager.shared().fetchAllVets { [weak self] vets, _ in
                Task { @MainActor in
                    self?.allVets = vets ?? []
                    self?.applyFilter()
                    continuation.resume()
                }
            }
        }
    }

    func toggleDisabled(for vet: PPVetModel) {
        let newState = !vet.isDisabled
        PPVetManager.shared().setDisabled(newState, forVetID: vet.vetID, completion: nil)
    }

    func deleteVet(_ vet: PPVetModel) {
        PPVetManager.shared().deleteVet(vet, completion: nil)
    }
}

// MARK: - Main View

@MainActor
struct PPVetsListView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PPVetsListViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onPushViewController: (UIViewController) -> Void

    @State private var showAddVet = false
    @State private var vetToDelete: PPVetModel?
    @State private var vetToToggle: PPVetModel?
    @State private var showEntranceAnimation = false

    init(onPushViewController: @escaping (UIViewController) -> Void = { _ in }, onDismiss: (() -> Void)? = nil) {
        self.onPushViewController = onPushViewController
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            dossierHeaderView

            ScrollView {
                LazyVStack(spacing: 0) {
                    statsHeader
                    filterSegment
                    searchField
                    vetList
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .refreshable { await viewModel.refresh() }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            viewModel.startListening()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.1)) {
                showEntranceAnimation = true
            }
        }
        .onDisappear { viewModel.stopListening() }
        .onChange(of: viewModel.searchText) { _ in viewModel.applyFilter() }
        .onChange(of: viewModel.activeFilter) { _ in viewModel.applyFilter() }
        .confirmationDialog(
            Language.get("Vet_Confirm_Delete_Title", alter: nil),
            isPresented: Binding(
                get: { vetToDelete != nil },
                set: { if !$0 { vetToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(Language.get("Delete", alter: nil), role: .destructive) {
                if let vet = vetToDelete { viewModel.deleteVet(vet) }
                vetToDelete = nil
            }
            Button(Language.get("Cancel", alter: nil), role: .cancel) { vetToDelete = nil }
        } message: {
            Text(Language.get("Vet_Confirm_Delete_Msg", alter: nil))
        }
        .confirmationDialog(
            "",
            isPresented: Binding(
                get: { vetToToggle != nil },
                set: { if !$0 { vetToToggle = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let vet = vetToToggle {
                let newState = !vet.isDisabled
                let btnKey = newState ? "Vet_Action_Disable" : "Vet_Action_Enable"
                Button(Language.get(btnKey, alter: nil), role: newState ? .destructive : nil) {
                    viewModel.toggleDisabled(for: vet)
                    vetToToggle = nil
                }
                Button(Language.get("Cancel", alter: nil), role: .cancel) { vetToToggle = nil }
            }
        } message: {
            if let vet = vetToToggle {
                let newState = !vet.isDisabled
                let msgKey = newState ? "Vet_Confirm_Disable_Msg" : "Vet_Confirm_Enable_Msg"
                Text(Language.get(msgKey, alter: nil))
            }
        }
    }

    // MARK: - Sovereign Navigation Bar

    private var dossierHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Vet_Section_Title", alter: "إدارة الأطباء البيطريين والعيادات"),
            subtitle: Language.get("CommandCenter_Operations_Workspace", alter: "مساحة العمليات"),
            onBack: {
                if let onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }
        ) {
            if viewModel.isLoading {
                ProgressView().tint(AdminSurface.primary)
            } else {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            }
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 10) {
            statPill(value: viewModel.totalCount, captionKey: "Vet_Filter_All", accent: AdminSurface.primary)
            statPill(value: viewModel.activeCount, captionKey: "Vet_Filter_Active", accent: Color(uiColor: .ppSuccess))
            statPill(value: viewModel.disabledCount, captionKey: "Vet_Filter_Disabled", accent: Color(uiColor: .ppError))
        }
        .padding(.bottom, 12)
    }

    private func statPill(value: Int, captionKey: String, accent: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(AdminType.title3)
                .foregroundColor(accent)
                .monospacedDigit()
            Text(Language.get(captionKey, alter: nil))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AdminSurface.hairline.opacity(0.72))
        )
    }

    // MARK: - Filter Segment

    private var filterSegment: some View {
        HStack(spacing: 0) {
            ForEach(VetListFilter.allCases, id: \.rawValue) { filter in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        viewModel.activeFilter = filter
                    }
                } label: {
                    let filterTitle = localizedFilterTitle(for: filter)
                    Text(filterTitle)
                        .font(viewModel.activeFilter == filter ? AdminType.footnoteBold : AdminType.footnote)
                        .foregroundColor(viewModel.activeFilter == filter ? .white : AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
            }
        }
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline.opacity(0.82))
        )
        .overlay(
           GeometryReader { geo in
                let segWidth = geo.size.width / 3
                let offsetX: CGFloat = {
                    switch viewModel.activeFilter {
                    case .all: return 0
                    case .active: return segWidth
                    case .disabled: return segWidth * 2
                    }
                }()
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AdminSurface.primary)
                    .frame(width: segWidth, height: 48)
                    .offset(x: offsetX)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.activeFilter)
            }
        )
        .padding(.bottom, 12)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AdminSurface.secondaryText)
            TextField(Language.get("Vet_Search_Placeholder", alter: nil), text: $viewModel.searchText)
                .font(AdminType.body)
                .foregroundColor(AdminSurface.primaryText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AdminSurface.hairline.opacity(0.85))
        )
        .padding(.bottom, 12)
    }

    // MARK: - Vet List

    @ViewBuilder
    private var vetList: some View {
        if viewModel.isLoading {
            VStack(spacing: 14) {
                ProgressView().tint(AdminSurface.primary)
                Text(Language.get("Vet_Loading", alter: nil))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if viewModel.filteredVets.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(viewModel.filteredVets.enumerated()), id: \.element.vetID) { index, vet in
                    let animDelay = 0.04 * Double(index)
                    let itemAnim: Animation? = reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.88).delay(animDelay)
                    vetCard(vet)
                        .opacity(showEntranceAnimation ? 1 : 0)
                        .offset(y: showEntranceAnimation ? 0 : 24)
                        .animation(itemAnim, value: showEntranceAnimation)
                }
            }
        }
    }

    private func localizedFilterTitle(for filter: VetListFilter) -> String {
        Language.get(filter.titleKey, alter: nil)
    }

    @ViewBuilder
    private func vetAvatarContent(for logoURL: String?) -> some View {
        if let logoURL, !logoURL.isEmpty, let url = URL(string: logoURL) {
            AsyncImage(url: url) { phase in
                vetAsyncImageContent(for: phase)
            }
        } else {
            vetPlaceholderImage
        }
    }

    @ViewBuilder
    private func vetAsyncImageContent(for phase: AsyncImagePhase) -> some View {
        switch phase {
        case .success(let image):
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .failure:
            vetPlaceholderImage
        case .empty:
            ProgressView()
                .tint(AdminSurface.primary)
        @unknown default:
            vetPlaceholderImage
        }
    }

    private var vetPlaceholderImage: some View {
        Image(systemName: "stethoscope.circle.fill")
            .foregroundColor(AdminSurface.primary)
    }

    // MARK: - Vet Card

    private func vetCard(_ vet: PPVetModel) -> some View {
        let isDisabled = vet.isDisabled
        let titleText = (vet.title?.isEmpty == false) ? vet.title! : "\u{2014}"

        return Button {
            navigateToDetail(vet)
        } label: {
            HStack(spacing: 0) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    // Ring
                    Circle()
                        .stroke(isDisabled ? AdminSurface.secondaryText.opacity(0.15) : AdminSurface.primary, lineWidth: 2.5)
                        .frame(width: 57, height: 57)

                    // Image
                    vetAvatarContent(for: vet.logoURL)
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .background(
                            Circle().fill(AdminSurface.primary.opacity(0.06))
                        )

                    // Online dot
                    Circle()
                        .fill(isDisabled ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(AdminSurface.background, lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
                .opacity(isDisabled ? 0.5 : 1.0)

                // Text content
                VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 3) {
                    Text(titleText)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .lineLimit(1)

                    Text(subtitleText(for: vet))
                        .font(AdminType.subheadline)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Status badge
                        Text(isDisabled ? Language.get("Vet_Status_Disabled", alter: nil) : Language.get("Vet_Status_Active", alter: nil))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                (isDisabled ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.85),
                                in: Capsule()
                            )

                        // Subscription pill
                        let tierName = subscriptionTierName(for: vet)
                        let expired = isSubscriptionExpired(vet)
                        Text(tierName)
                            .font(AdminType.caption2)
                            .foregroundColor(expired ? Color(uiColor: .ppError) : AdminSurface.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .overlay(
                                Capsule().stroke(
                                    expired ? Color(uiColor: .ppError) : AdminSurface.primary.opacity(0.3),
                                    lineWidth: 1
                                )
                            )

                        Spacer(minLength: 0)

                        // Cost
                        if vet.vetCost > 0 {
                            Text("\(Int(vet.vetCost)) \(Language.get("QAR", alter: nil))")
                                .font(AdminType.footnoteBold)
                                .foregroundColor(AdminSurface.primaryText)
                        }
                    }
                }
                .padding(.leading, 14)

                // Chevron
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.4))
                    .padding(.leading, 8)
            }
            .padding(14)
            .background(
                AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AdminSurface.hairline.opacity(0.9))
            )
            .shadow(color: Color.black.opacity(0.045), radius: 10, x: 0, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(VetCardButtonStyle())
        .contextMenu {
            Button { navigateToDetail(vet) } label: {
                Label(Language.get("Vet_Detail_Title", alter: nil), systemImage: "eye")
            }
            Button { navigateToEdit(vet) } label: {
                Label(Language.get("Vet_Edit_Title", alter: nil), systemImage: "pencil")
            }
            Divider()
            Button { vetToToggle = vet } label: {
                let disabled = vet.isDisabled
                Label(
                    disabled ? Language.get("Vet_Action_Enable", alter: nil) : Language.get("Vet_Action_Disable", alter: nil),
                    systemImage: disabled ? "checkmark.circle" : "nosign"
                )
            }
            Button { navigateToSubscription(vet) } label: {
                Label(Language.get("Vet_Subscription", alter: nil), systemImage: "creditcard.circle")
            }
            Button { callVet(vet) } label: {
                Label(Language.get("Vet_Field_Phone", alter: nil), systemImage: "phone")
            }
            Divider()
            Button(role: .destructive) { vetToDelete = vet } label: {
                Label(Language.get("Delete", alter: nil), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { navigateToEdit(vet) } label: {
                Image(systemName: "pencil.circle.fill")
            }
            .tint(Color(uiColor: .ppInfo))

            Button { vetToToggle = vet } label: {
                Image(systemName: vet.isDisabled ? "checkmark.circle.fill" : "nosign")
            }
            .tint(vet.isDisabled ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))

            Button { navigateToSubscription(vet) } label: {
                Image(systemName: "creditcard.circle.fill")
            }
            .tint(AdminSurface.primary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { vetToDelete = vet } label: {
                Image(systemName: "trash.circle.fill")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "stethoscope")
                .font(.system(size: 52))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.3))
            Text(Language.get("Vet_Empty_List", alter: nil))
                .font(AdminType.body)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                showAddVet = true
            } label: {
                Label(Language.get("Vet_Add_Title", alter: nil), systemImage: "plus.circle.fill")
                    .font(AdminType.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.top, 40)
    }

    // MARK: - Helpers

    private func subtitleText(for vet: PPVetModel) -> String {
        var parts: [String] = []
        let typeName = localizedTypeName(vet)
        if !typeName.isEmpty { parts.append(typeName) }
        if let phone = vet.phone, !phone.isEmpty { parts.append(phone) }
        return parts.joined(separator: "  \u{00B7}  ")
    }

    private func localizedTypeName(_ vet: PPVetModel) -> String {
        switch vet.type {
        case .personal: return Language.get("Vet_Type_Personal", alter: nil)
        case .company: return Language.get("Vet_Type_Company", alter: nil)
        default: return ""
        }
    }

    private func subscriptionTierName(for vet: PPVetModel) -> String {
        switch vet.subscriptionTier {
        case .free: return Language.get("Vet_Sub_Free", alter: nil)
        case .basic: return Language.get("Vet_Sub_Basic", alter: nil)
        case .premium: return Language.get("Vet_Sub_Premium", alter: nil)
        default: return ""
        }
    }


    private func isSubscriptionExpired(_ vet: PPVetModel) -> Bool {
        guard let endDate = vet.subscriptionEndDate else { return false }
        return endDate.compare(Date()) == .orderedAscending
    }

    private func navigateToDetail(_ vet: PPVetModel) {
        onPushViewController(PPVetDetailViewController(vet: vet))
    }

    private func navigateToEdit(_ vet: PPVetModel) {
        onPushViewController(PPAddEditVetViewController(vet: vet))
    }

    private func navigateToSubscription(_ vet: PPVetModel) {
        onPushViewController(PPVetSubscriptionViewController(vet: vet))
    }

    private func callVet(_ vet: PPVetModel) {
        guard let phone = vet.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phone.isEmpty,
              let url = URL(string: "tel://\(phone)") else { return }
        UIApplication.shared.open(url)
    }

}

// MARK: - Button Style (press feedback)

private struct VetCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - UIViewController Bridge (for ObjC route factory)

@objc class PPVetsListHostingController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground
        let swiftUIView = PPVetsListView { [weak self] viewController in
            self?.navigationController?.pushViewController(viewController, animated: true)
        }
        let hostingController = UIHostingController(rootView: swiftUIView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}
