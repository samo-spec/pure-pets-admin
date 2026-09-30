//
//  WantedPetsHomeView.swift
//  Pure Pets Admin
//
//  The operational entry point for customer requests for incoming pets.
//

import SwiftUI
import UIKit

public struct WantedPetsHomeView: View {
    @StateObject private var service = WantedPetsService.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool

    @State private var showAddRequest = false
    @State private var selectedPetGroup: WantedPetCategoryGroup?
    @State private var selectedItemForDetail: CustomerWantedPet?
    @State private var inFlightItemIDs: Set<String> = []
    @State private var copiedItemId: String? = nil
    @State private var actionFailure: String?
    @State private var actionFeedbackMessage: String?
    @State private var canManageRequests = false

    private let onDismiss: (() -> Void)?

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private func handleBack() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var sovereignHeaderView: some View {
        AdminSovereignNavigationBar(
            title: Language.get("WantedPets_Title", alter: "قائمة الطلبات"),
            subtitle: nil,
            isModal: false,
            customTopSpacing: 0,
            onBack: {
                handleBack()
            }
        ) {
            if canManageRequests {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAddRequest = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                            )
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(uiColor: .ppPrimary))
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .disabled(service.isMutating)
                .accessibilityLabel(Language.get("WantedPets_Add_Action", alter: "إضافة طلب جديد"))
            }
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    sovereignHeaderView

                    List {
                        topDeck
                            .listRowInsets(EdgeInsets(top: AdminSpacing.sm, leading: AdminSpacing.screenMargin,
                                                      bottom: AdminSpacing.lg, trailing: AdminSpacing.screenMargin))
                            .wantedPetsRowChrome()

                        if let error = service.errorMessage, !service.items.isEmpty {
                    refreshWarning(error)
                        .listRowInsets(EdgeInsets(top: 0, leading: AdminSpacing.screenMargin,
                                                  bottom: AdminSpacing.base, trailing: AdminSpacing.screenMargin))
                        .wantedPetsRowChrome()
                }

                if service.isLoading && service.items.isEmpty {
                    loadingState
                        .wantedPetsRowChrome()
                } else if let error = service.errorMessage, service.items.isEmpty {
                    unavailableState(error)
                        .wantedPetsRowChrome()
                } else if service.filteredItems.isEmpty {
                    emptyState
                        .wantedPetsRowChrome()
                } else {
                    sectionHeading
                        .listRowInsets(EdgeInsets(top: 0, leading: AdminSpacing.screenMargin,
                                                  bottom: AdminSpacing.sm, trailing: AdminSpacing.screenMargin))
                        .wantedPetsRowChrome()

                    if service.selectedFilter == .byPet && service.searchQuery.isEmpty {
                        ForEach(service.categoryGroups) { group in
                            petGroupRow(group)
                                .listRowInsets(EdgeInsets(top: AdminSpacing.sm, leading: AdminSpacing.screenMargin,
                                                          bottom: AdminSpacing.sm, trailing: AdminSpacing.screenMargin))
                                .wantedPetsRowChrome()
                        }
                    } else {
                        ForEach(service.filteredItems) { item in
                            customerRow(item)
                                .listRowInsets(EdgeInsets(top: AdminSpacing.sm, leading: AdminSpacing.screenMargin,
                                                          bottom: AdminSpacing.sm, trailing: AdminSpacing.screenMargin))
                                .wantedPetsRowChrome()
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if canManageRequests && item.status == .waiting {
                                        Button {
                                            transition(item, to: .contacted)
                                        } label: {
                                            Label(Language.get("WantedPets_Mark_Contacted", alter: "تحديد كمتواصل معه"),
                                                  systemImage: "phone.bubble.left.fill")
                                        }
                                        .tint(Color(uiColor: .systemBlue))
                                    } else if canManageRequests && item.status == .contacted {
                                        Button {
                                            transition(item, to: .interested)
                                        } label: {
                                            Label(Language.get("WantedPets_Mark_Interested", alter: "مهتم بالحيوان"),
                                                  systemImage: "star.fill")
                                        }
                                        .tint(Color(uiColor: .systemPurple))
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if canManageRequests && item.status.isActive {
                                        Button {
                                            selectedItemForDetail = item
                                        } label: {
                                            Label(Language.get("WantedPets_Review_Close", alter: "مراجعة الإغلاق"),
                                                  systemImage: "xmark.circle")
                                        }
                                        .tint(AdminSurface.crimson)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AdminSurface.background.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .refreshable { service.startLiveListener() }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .modifier(WantedPetsRootSwipeNavigation(
                isRootVisible: !showAddRequest && selectedPetGroup == nil && selectedItemForDetail == nil,
                needsFallback: true,
                onBack: handleBack
            ))
            .navigationDestination(isPresented: $showAddRequest) {
                AddWantedPetSheet { _ in
                    actionFeedbackMessage = Language.get("WantedPets_Added_Success", alter: "تم حفظ الطلب بنجاح")
                }
            }
            .navigationDestination(item: $selectedPetGroup) { group in
                WaitingCustomersView(petTitle: group.displayName,
                                     mainKindId: group.mainKindId,
                                     subkindId: group.subkindId,
                                     customers: group.items)
            }
            .navigationDestination(item: $selectedItemForDetail) { item in
                WantedPetDetailView(wantedPetId: item.id)
            }
            .overlay(alignment: .bottom) {
                if let message = actionFeedbackMessage {
                    feedbackBanner(message)
                        .padding(.bottom, 24)
                }
            }
            .alert(Language.get("WantedPets_Action_Error_Title", alter: "تعذّر تنفيذ الإجراء"),
                   isPresented: Binding(get: { actionFailure != nil },
                                        set: { if !$0 { actionFailure = nil } })) {
                Button(Language.get("WantedPets_Dismiss_Error", alter: "حسنًا"), role: .cancel) { actionFailure = nil }
            } message: {
                Text(actionFailure ?? "")
            }
            .task(id: actionFeedbackMessage) {
                guard actionFeedbackMessage != nil else { return }
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(AdminAnimation.motion(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                    actionFeedbackMessage = nil
                }
            }
            .onAppear(perform: refreshAuthorization)
            .onReceive(NotificationCenter.default.publisher(
                for: Notification.Name("PPAdminCommandAuthorizationDidChangeNotification")
            )) { _ in
                refreshAuthorization()
            }
        }
    }
    .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
}

    // MARK: - The queue at a glance

    private var topDeck: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            overview

            if let staff = PPStaffAuth.shared().cachedCurrentStaff,
               staff.isActive(), !staff.hasPermission("stock.manage") {
                Text(Language.get("WantedPets_View_Only", alter: "يمكنك عرض الطلبات، لكن تعديلها يتطلب صلاحية إدارة المخزون"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            discoveryControls
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                colors: [AdminSurface.surface, AdminSurface.surface.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            .clipShape(RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
            .padding(.horizontal, -AdminSpacing.md)
            .padding(.bottom, -AdminSpacing.md)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var isOverviewUnavailable: Bool {
        service.items.isEmpty && (service.isLoading || service.errorMessage != nil)
    }

    private var overviewScope: String {
        if service.isLoading {
            return Language.get("WantedPets_Header_Updating", alter: "جارٍ تحديث الطلبات")
        }
        if service.errorMessage != nil {
            return isOverviewUnavailable
                ? Language.get("WantedPets_Count_Unavailable", alter: "العدد غير متاح")
                : Language.get("WantedPets_Header_Last_Loaded", alter: "آخر بيانات محمّلة")
        }
        return Language.get("WantedPets_Overview_Recent", alter: "ضمن أحدث الطلبات")
    }

    private func overviewCount(_ count: Int) -> String {
        guard !isOverviewUnavailable else { return "—" }
        return count.formatted(.number.locale(Locale(identifier: Language.isRTL() ? "ar" : "en")))
    }

    private var overview: some View {
        let overviewLayout = dynamicTypeSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.base))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.lg))

        return VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
                Text(Language.get("WantedPets_Overview_Label", alter: "حركة الطلبات"))
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: AdminSpacing.sm)
                if service.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AdminSurface.primary)
                        .accessibilityLabel(Language.get("WantedPets_Header_Updating", alter: "جارٍ تحديث الطلبات"))
                }
            }

            overviewLayout {
                waitingFocus
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    statusMetric(count: service.contactedCount,
                                 title: Language.get("WantedPets_Summary_Contacted", alter: "تم التواصل"),
                                 symbol: "phone.fill", tint: Color(uiColor: .systemBlue),
                                 filter: .contacted)

                    Rectangle()
                        .fill(AdminSurface.hairline.opacity(0.35))
                        .frame(height: AdminStroke.hairline)
                        .padding(.horizontal, AdminSpacing.md)
                        .accessibilityHidden(true)

                    statusMetric(count: service.interestedCount,
                                 title: Language.get("WantedPets_Summary_Interested", alter: "مهتمون"),
                                 symbol: "heart.fill", tint: AdminSurface.primary,
                                 filter: .interested)
                }
                .frame(maxWidth: .infinity)
                .background(AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
            }

            Text(overviewScope)
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .contain)
    }

    private var waitingFocus: some View {
        Button {
            selectFilter(.waiting)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: AdminSpacing.sm) {
                        waitingCountLabel

                        Image(systemName: "arrow.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                            .frame(width: 30, height: 30)
                            .background(AdminSurface.primary.opacity(0.08), in: Circle())
                            .accessibilityHidden(true)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    waitingCountLabel
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(Language.get("WantedPets_Header_Awaiting_Contact", alter: "بانتظار التواصل"))
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(WantedPetsPressStyle())
        .disabled(isOverviewUnavailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Language.get("WantedPets_Header_Awaiting_Contact", alter: "بانتظار التواصل"))
        .accessibilityValue(isOverviewUnavailable
            ? Language.get("WantedPets_Count_Unavailable", alter: "العدد غير متاح")
            : overviewCount(service.waitingCount))
        .accessibilityAddTraits(service.selectedFilter == .waiting ? .isSelected : [])
        .accessibilityHint(Language.get("WantedPets_Filter_Hint", alter: "عرض هذه الطلبات"))
    }

    private var waitingCountLabel: some View {
        Text(overviewCount(service.waitingCount))
            .font(dynamicTypeSize.isAccessibilitySize
                  ? AdminType.title
                  : Font.custom("Beiruti-Bold", size: 64, relativeTo: .largeTitle))
            .monospacedDigit()
            .foregroundStyle(AdminSurface.primary)
            .contentTransition(reduceMotion ? .identity : .numericText())
    }

    private func statusMetric(count: Int, title: String, symbol: String,
                              tint: Color, filter: WantedPetsFilter) -> some View {
        let metricLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.sm))

        return Button {
            selectFilter(filter)
        } label: {
            metricLayout {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                Text(overviewCount(count))
                    .font(AdminType.title2)
                    .monospacedDigit()
                    .foregroundStyle(AdminSurface.primaryText)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(WantedPetsPressStyle())
        .disabled(isOverviewUnavailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOverviewUnavailable
            ? Language.get("WantedPets_Count_Unavailable", alter: "العدد غير متاح")
            : overviewCount(count))
        .accessibilityAddTraits(service.selectedFilter == filter ? .isSelected : [])
        .accessibilityHint(Language.get("WantedPets_Filter_Hint", alter: "عرض هذه الطلبات"))
    }

    // MARK: - Search and filters

    private var discoveryControls: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            searchField
            filterRail
        }
    }

    private var searchField: some View {
        HStack(spacing: AdminSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSearchFocused ? AdminSurface.primary : AdminSurface.secondaryText)
                .frame(width: 28)
                .accessibilityHidden(true)

            TextField(Language.get("WantedPets_Header_Search", alter: "الاسم، الهاتف، أو الحيوان"),
                      text: $service.searchQuery,
                      prompt: Text(Language.get("WantedPets_Header_Search", alter: "الاسم، الهاتف، أو الحيوان"))
                        .foregroundColor(AdminSurface.secondaryText))
            .font(AdminType.body)
            .foregroundStyle(AdminSurface.primaryText)
            .multilineTextAlignment(.leading)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isSearchFocused)
            .onSubmit { isSearchFocused = false }
            .padding(.vertical, AdminSpacing.md)
            .accessibilityLabel(Language.get("WantedPets_Search_Placeholder", alter: "بحث بالاسم، الهاتف، الفئة..."))
            .accessibilityIdentifier("wantedPets.search")

            if !service.searchQuery.isEmpty {
                Button {
                    service.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("WantedPets_Clear_Search", alter: "مسح البحث"))
            }
        }
        .padding(.leading, AdminSpacing.base)
        .padding(.trailing, service.searchQuery.isEmpty ? AdminSpacing.base : AdminSpacing.xs)
        .frame(minHeight: 56)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous)
                .strokeBorder(isSearchFocused ? AdminSurface.primary : AdminSurface.hairline,
                              lineWidth: isSearchFocused ? AdminStroke.medium : AdminStroke.hairline)
                .allowsHitTesting(false)
        }
        .animation(AdminAnimation.motion(AdminAnimation.fast, reduceMotion: reduceMotion), value: isSearchFocused)
    }

    private var filterRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.sm) {
                    ForEach(WantedPetsFilter.allCases) { filter in
                        HStack(spacing: AdminSpacing.sm) {
                            let isSelected = service.selectedFilter == filter
                            Button {
                                selectFilter(filter)
                            } label: {
                                HStack(spacing: AdminSpacing.xs) {
                                    if filter == .byPet {
                                        Image(systemName: "pawprint.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .accessibilityHidden(true)
                                    }
                                    Text(filter.title)
                                        .font(AdminType.subheadlineBold)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, AdminSpacing.base)
                                .padding(.vertical, AdminSpacing.sm)
                                .frame(minHeight: AdminTouchTarget.minimum)
                                .foregroundStyle(isSelected ? AdminSurface.surface : AdminSurface.primaryText)
                                .background(isSelected ? AdminSurface.primaryText : AdminSurface.surface, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline,
                                                      lineWidth: AdminStroke.hairline)
                                }
                                .contentShape(Capsule())
                            }
                            .buttonStyle(WantedPetsPressStyle())
                            .accessibilityLabel(filter.title)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            .accessibilityIdentifier("wantedPets.filter.\(filter.id)")

                            if filter == .byPet {
                                Capsule()
                                    .fill(AdminSurface.hairline)
                                    .frame(width: 1, height: 20)
                                    .padding(.horizontal, AdminSpacing.xs)
                                    .accessibilityHidden(true)
                            }
                        }
                        .id(filter.id)
                    }
                }
            }
            .onAppear {
                proxy.scrollTo(service.selectedFilter.id, anchor: .center)
            }
            .onChange(of: service.selectedFilter) { _, filter in
                withAnimation(AdminAnimation.motion(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                    proxy.scrollTo(filter.id, anchor: .center)
                }
            }
        }
        .accessibilityLabel(Language.get("WantedPets_Filters_Label", alter: "تصفية الطلبات"))
    }

    private func selectFilter(_ filter: WantedPetsFilter) {
        isSearchFocused = false
        guard service.selectedFilter != filter else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(AdminAnimation.motion(AdminAnimation.filterSwap, reduceMotion: reduceMotion)) {
            service.selectedFilter = filter
        }
    }

    // MARK: - Requests

    private var sectionHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(service.selectedFilter == .byPet && service.searchQuery.isEmpty
                 ? Language.get("WantedPets_Group_Heading", alter: "الحيوانات المطلوبة")
                 : Language.get("WantedPets_Request_Heading", alter: "طلبات العملاء"))
                .font(Font.custom("Beiruti-Bold", size: 18))
                .foregroundStyle(AdminSurface.primaryText)
            Spacer()
            Text(String(service.selectedFilter == .byPet && service.searchQuery.isEmpty
                        ? service.categoryGroups.count : service.filteredItems.count))
                .font(Font.custom("Beiruti-Bold", size: 14))
                .monospacedDigit()
                .foregroundStyle(AdminSurface.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(AdminSurface.cardElevated, in: Capsule())
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func petGroupRow(_ group: WantedPetCategoryGroup) -> some View {
        let accent = group.accentColor
        let symbol = group.petSymbol

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedPetGroup = group
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                HStack(alignment: .top, spacing: AdminSpacing.md) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        // Category / Species Super-tag if subkind has a parent category
                        if let sub = group.subkindName, !sub.isEmpty, !group.mainKindName.isEmpty, group.mainKindName != sub {
                            HStack(spacing: 4) {
                                Circle().fill(accent).frame(width: 5, height: 5)
                                Text(group.mainKindName)
                                    .font(Font.custom("Beiruti-Medium", size: 12))
                                    .foregroundStyle(accent)
                            }
                        }

                        Text(group.displayName)
                            .font(Font.custom("Beiruti-Bold", size: 28, relativeTo: .title2))
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        if let oldest = group.oldestWaitingDurationText {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                Text(String(format: Language.get("WantedPets_Oldest_Waiting", alter: "أقدم طلب منذ %@"), oldest))
                                    .font(AdminType.footnote)
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: AdminSpacing.sm)

                    // MainKind Species Squircle Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(0.18),
                                        accent.opacity(0.07)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
                }

                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                HStack(spacing: AdminSpacing.xs) {
                    Text("\(group.waitingCount > 0 ? group.waitingCount : group.items.count)")
                        .font(AdminType.title2)
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    Text(group.waitingCount > 0
                         ? Language.get("WantedPets_Summary_Waiting", alter: "ينتظرون")
                         : Language.get("WantedPets_Requests_Label", alter: "طلبات"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer(minLength: AdminSpacing.sm)

                    HStack(spacing: 4) {
                        Text(Language.get("WantedPets_Open_Group", alter: "عرض العملاء"))
                            .font(AdminType.footnoteBold)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                }
            }
            .padding(AdminSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(accent.opacity(0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        }
        .buttonStyle(WantedPetsPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.displayName), \(group.waitingCount > 0 ? group.waitingCount : group.items.count) \(group.waitingCount > 0 ? Language.get("WantedPets_Summary_Waiting", alter: "ينتظرون") : Language.get("WantedPets_Requests_Label", alter: "طلبات"))")
        .accessibilityHint(Language.get("WantedPets_Open_Group", alter: "عرض العملاء"))
    }

    private func customerRow(_ item: CustomerWantedPet) -> some View {
        let isCopied = copiedItemId == item.id
        let isInFlight = inFlightItemIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: 0) {
            // Main card body - tap to view complete customer dossier
            Button {
                selectedItemForDetail = item
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    // 1. Header: Monogram Avatar + Customer Identity & Phone + Status Badge Pill
                    HStack(alignment: .center, spacing: 12) {
                        // Monogram Avatar
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            item.status.tintColor.opacity(0.18),
                                            item.status.tintColor.opacity(0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text(customerInitials(item.customerName))
                                .font(Font.custom("Beiruti-Bold", size: 16))
                                .foregroundStyle(item.status.tintColor)
                        }
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(item.status.tintColor.opacity(0.25), lineWidth: 1)
                        )

                        // Name & Phone with inline copy
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.customerName)
                                .font(Font.custom("Beiruti-Bold", size: 18))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)

                            HStack(spacing: 6) {
                                Text(item.formattedPhoneDisplay)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .environment(\.layoutDirection, .leftToRight)

                                Button {
                                    copyPhone(item.phoneNumber, itemId: item.id)
                                } label: {
                                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(isCopied ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Language.get("Copy", alter: "نسخ"))
                            }
                        }

                        Spacer(minLength: 4)

                        // Status Badge Pill
                        HStack(spacing: 5) {
                            Image(systemName: item.status.iconName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(item.status.title)
                                .font(Font.custom("Beiruti-Bold", size: 12))
                        }
                        .foregroundStyle(item.status.tintColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(item.status.tintColor.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(item.status.tintColor.opacity(0.24), lineWidth: 0.8)
                        )
                    }

                    // 2. Pet Title & Duration Strip
                    HStack(alignment: .center, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: item.kindPetSymbol)
                                .font(.system(size: 11, weight: .bold))
                            Text(item.requestedPetTitle)
                                .font(Font.custom("Beiruti-Bold", size: 15))
                        }
                        .foregroundStyle(item.kindAccentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(item.kindAccentColor.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(item.kindAccentColor.opacity(0.24), lineWidth: 0.8)
                        )

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10, weight: .medium))
                            Text(item.waitingDurationText)
                                .font(Font.custom("Beiruti-Regular", size: 12))
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                    }

                    // 3. Preferences & Metadata Chips
                    customerPreferencesStrip(item)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Language.get("WantedPets_Open_Request", alter: "عرض تفاصيل الطلب"))

            // 4. Integrated Tactical Action Dock
            if canManageRequests {
                Rectangle()
                    .fill(AdminSurface.hairline.opacity(0.65))
                    .frame(height: 1)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    // Direct Communication Row: WhatsApp & Call
                    let contactLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 8))

                    contactLayout {
                        // WhatsApp Action Button (Apple-Emerald Gradient)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            openWhatsApp(for: item)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(Language.get("WantedPets_Quick_WhatsApp", alter: "واتساب"))
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.16, green: 0.78, blue: 0.40),
                                        Color(red: 0.11, green: 0.69, blue: 0.34)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .shadow(color: Color(red: 0.13, green: 0.74, blue: 0.36).opacity(0.24), radius: 4, y: 2)
                        }
                        .buttonStyle(TactileActionButtonStyle())
                        .accessibilityLabel(Language.get("WantedPets_Quick_WhatsApp", alter: "واتساب"))

                        // Phone Call Button (Frosted iOS Blue)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            callPhone(item.phoneNumber)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(Language.get("WantedPets_Quick_Call", alter: "اتصال"))
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                            }
                            .foregroundStyle(Color(uiColor: .systemBlue))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                Color(uiColor: .systemBlue).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(uiColor: .systemBlue).opacity(0.22), lineWidth: 1)
                            )
                        }
                        .buttonStyle(TactileActionButtonStyle())
                        .accessibilityLabel(Language.get("WantedPets_Quick_Call", alter: "اتصال"))
                    }

                    // Smart Lifecycle Progression Action Button
                    if item.status == .waiting {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            transition(item, to: .contacted)
                        } label: {
                            HStack(spacing: 6) {
                                if isInFlight {
                                    ProgressView()
                                        .tint(Color(uiColor: .systemBlue))
                                        .scaleEffect(0.85)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                Text(Language.get("WantedPets_Mark_Contacted", alter: "تحديد كمتواصل معه"))
                                    .font(Font.custom("Beiruti-Bold", size: 13))
                            }
                            .foregroundStyle(Color(uiColor: .systemBlue))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                Color(uiColor: .systemBlue).opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color(uiColor: .systemBlue).opacity(0.22), lineWidth: 1)
                            )
                        }
                        .buttonStyle(TactileActionButtonStyle())
                        .disabled(isInFlight || service.isMutating)
                    } else if item.status == .contacted {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            transition(item, to: .interested)
                        } label: {
                            HStack(spacing: 6) {
                                if isInFlight {
                                    ProgressView()
                                        .tint(Color(uiColor: .systemPurple))
                                        .scaleEffect(0.85)
                                } else {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                Text(Language.get("WantedPets_Mark_Interested", alter: "تحديد كمهتم بالحيوان"))
                                    .font(Font.custom("Beiruti-Bold", size: 13))
                            }
                            .foregroundStyle(Color(uiColor: .systemPurple))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                Color(uiColor: .systemPurple).opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color(uiColor: .systemPurple).opacity(0.22), lineWidth: 1)
                            )
                        }
                        .buttonStyle(TactileActionButtonStyle())
                        .disabled(isInFlight || service.isMutating)
                    } else if item.status == .interested {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedItemForDetail = item
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .bold))
                                Text(Language.get("WantedPets_Open_Request", alter: "عرض تفاصيل الطلب والمطابقة"))
                                    .font(Font.custom("Beiruti-Bold", size: 13))
                            }
                            .foregroundStyle(AdminSurface.primary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                AdminSurface.primarySoft,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 1)
                            )
                        }
                        .buttonStyle(TactileActionButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private func customerPreferencesStrip(_ item: CustomerWantedPet) -> some View {
        let hasSex = item.sexPreference != .any
        let hasColor = !(item.colorPreference ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBudget = (item.budgetMax ?? 0) > 0
        let hasSource = item.contactSource != .other

        if hasSex || hasColor || hasBudget || hasSource {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if hasSex {
                        chip(icon: "figure.stand", text: item.sexPreference.title)
                    }
                    if let color = item.colorPreference, !color.isEmpty {
                        chip(icon: "paintpalette.fill", text: color)
                    }
                    if let budget = item.budgetMax, budget > 0 {
                        chip(icon: "banknote.fill", text: String(format: "≤ %.0f", budget))
                    }
                    if hasSource {
                        chip(icon: item.contactSource.iconName, text: item.contactSource.title)
                    }
                }
            }
        } else {
            Text(item.preferencesSummary)
                .font(Font.custom("Beiruti-Regular", size: 13))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Font.custom("Beiruti-Medium", size: 11))
        }
        .foregroundStyle(AdminSurface.secondaryText)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(AdminSurface.cardElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(AdminSurface.hairline.opacity(0.6), lineWidth: 0.6))
    }

    private func customerInitials(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "؟" }
        let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if components.count >= 2,
           let firstChar = components[0].first,
           let secondChar = components[1].first {
            return "\(firstChar) \(secondChar)"
        } else if let firstChar = trimmed.first {
            return String(firstChar)
        }
        return "؟"
    }

    private func copyPhone(_ phoneNumber: String, itemId: String) {
        UIPasteboard.general.string = phoneNumber
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedItemId = itemId
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if copiedItemId == itemId {
                withAnimation(.easeInOut(duration: 0.2)) {
                    copiedItemId = nil
                }
            }
        }
    }

    // MARK: - Loading, empty, and recovery

    private var loadingState: some View {
        VStack(spacing: AdminSpacing.md) {
            ProgressView()
                .tint(AdminSurface.primary)
            Text(Language.get("WantedPets_Loading", alter: "جاري التحميل..."))
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .listRowInsets(EdgeInsets(top: AdminSpacing.xl, leading: AdminSpacing.screenMargin,
                                  bottom: AdminSpacing.xl, trailing: AdminSpacing.screenMargin))
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        let isSearch = !service.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isGloballyEmpty = service.items.isEmpty
        return statePanel(icon: isSearch ? "magnifyingglass" : "pawprint",
                          title: isSearch
                            ? Language.get("WantedPets_Empty_Search_Title", alter: "لا توجد نتائج مطابقة للبحث")
                            : isGloballyEmpty
                                ? Language.get("WantedPets_Empty_All_Title", alter: "لا توجد طلبات بعد")
                                : Language.get("WantedPets_Empty_Filter_Title", alter: "لا توجد طلبات بهذه الحالة"),
                          detail: isSearch
                            ? Language.get("WantedPets_Empty_Search_Subtitle", alter: "جرّب البحث باسم أو رقم هاتف أو فئة أخرى")
                            : isGloballyEmpty
                                ? canManageRequests
                                    ? Language.get("WantedPets_Empty_All_Manage", alter: "أضف طلب العميل للتواصل معه عند وصول الحيوان")
                                    : Language.get("WantedPets_Empty_All_View", alter: "ستظهر طلبات العملاء هنا عند إضافتها")
                                : Language.get("WantedPets_Empty_Filter_Subtitle", alter: "اختر حالة أخرى لرؤية الطلبات"))
    }

    private func unavailableState(_ error: String) -> some View {
        statePanel(icon: "wifi.exclamationmark",
                   title: Language.get("WantedPets_Error_Title", alter: "تعذّر تحميل الطلبات"),
                   detail: error,
                   retry: true)
    }

    private func statePanel(icon: String, title: String, detail: String, retry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 56, height: 56)
                .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .accessibilityHidden(true)
            Text(title)
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if retry {
                Button {
                    service.startLiveListener()
                } label: {
                    Label(Language.get("WantedPets_Retry", alter: "إعادة المحاولة"), systemImage: "arrow.clockwise")
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primary)
                        .frame(minHeight: AdminTouchTarget.minimum)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .padding(AdminSpacing.lg)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .listRowInsets(EdgeInsets(top: AdminSpacing.sm, leading: AdminSpacing.screenMargin,
                                  bottom: AdminSpacing.sm, trailing: AdminSpacing.screenMargin))
    }

    private func refreshWarning(_ error: String) -> some View {
        HStack(alignment: .top, spacing: AdminSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AdminSurface.amber)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(Language.get("WantedPets_Stale_Title", alter: "تعذّر تحديث الطلبات"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(error)
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                service.startLiveListener()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
            }
            .accessibilityLabel(Language.get("WantedPets_Retry", alter: "إعادة المحاولة"))
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.amber.opacity(0.09), in: RoundedRectangle(cornerRadius: AdminRadius.medium))
    }


    private func feedbackBanner(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(AdminType.subheadlineBold)
            .foregroundStyle(.white)
            .padding(.horizontal, AdminSpacing.base)
            .padding(.vertical, AdminSpacing.md)
            .background(AdminSurface.primaryText, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func refreshAuthorization() {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isActive() else {
            canManageRequests = false
            return
        }
        canManageRequests = staff.hasPermission("stock.manage")
    }

    private func transition(_ item: CustomerWantedPet, to status: WantedPetStatus) {
        guard canManageRequests, !service.isMutating, !inFlightItemIDs.contains(item.id) else { return }
        inFlightItemIDs.insert(item.id)
        Task {
            defer { inFlightItemIDs.remove(item.id) }
            do {
                try await service.transitionStatus(id: item.id, targetStatus: status)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                actionFailure = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func openWhatsApp(for item: CustomerWantedPet) {
        let rawNumber = item.normalizedPhoneNumber.isEmpty ? item.phoneNumber : item.normalizedPhoneNumber
        let digits = rawNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        let message = String(format: Language.get("WantedPets_WhatsApp_CheckIn_Template",
                                                  alter: "مرحباً %@، نتواصل معك من بيور بيتس بخصوص طلبك لـ %@. هل لا يزال طلبك قائماً؟"),
                             item.customerName, item.requestedPetTitle)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(digits)"
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        guard !digits.isEmpty,
              let url = components.url,
              UIApplication.shared.canOpenURL(url) else {
            actionFailure = Language.get("WantedPets_Contact_Unavailable", alter: "تعذّر فتح وسيلة التواصل لهذا الرقم")
            return
        }
        UIApplication.shared.open(url)
    }

    private func callPhone(_ phoneNumber: String) {
        let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard !cleaned.isEmpty,
              let url = URL(string: "tel:\(cleaned)"),
              UIApplication.shared.canOpenURL(url) else {
            actionFailure = Language.get("WantedPets_Contact_Unavailable", alter: "تعذّر فتح وسيلة التواصل لهذا الرقم")
            return
        }
        UIApplication.shared.open(url)
    }
}

/// A queue screen owns its gesture only while it is the visible destination.
/// Removing the bridge while pushing lets the child own its pending-write guard;
/// recreating it on return restores the root's native configuration.
struct WantedPetsRootSwipeNavigation: ViewModifier {
    let isRootVisible: Bool
    let needsFallback: Bool
    let onBack: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isPopping = false

    func body(content: Content) -> some View {
        content
            .background {
                if isRootVisible {
                    PPSwipeToPopUIKitBridge(
                        isEnabled: true,
                        isRTL: layoutDirection == .rightToLeft,
                        onCustomPop: onBack,
                        onNavigationStatusChanged: { _ in }
                    )
                }
            }
            .overlay(alignment: .leading) {
                // A UIKit-hosted root needs its outer-host back callback. A
                // destination in the SwiftUI stack uses native interactive pop.
                if isRootVisible && needsFallback {
                    PPSwipeToPopFallbackEdgeStrip(
                        isRTL: layoutDirection == .rightToLeft,
                        onPop: {
                            guard !isPopping else { return }
                            isPopping = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onBack()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                isPopping = false
                            }
                        }
                    )
                }
            }
    }
}

fileprivate extension View {
    func wantedPetsRowChrome() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct WantedPetsPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(AdminAnimation.motion(.easeOut(duration: 0.14), reduceMotion: reduceMotion),
                       value: configuration.isPressed)
    }
}

private struct TactileActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
