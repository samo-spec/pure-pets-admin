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
    @FocusState private var isSearchFocused: Bool

    @State private var showAddSheet = false
    @State private var selectedPetGroup: WantedPetCategoryGroup?
    @State private var selectedItemForDetail: CustomerWantedPet?
    @State private var inFlightItemIDs: Set<String> = []
    @State private var actionFailure: String?
    @State private var actionFeedbackMessage: String?
    @State private var canManageRequests = false

    private let onDismiss: (() -> Void)?

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            List {
                overview
                    .listRowInsets(EdgeInsets(top: AdminSpacing.sm, leading: AdminSpacing.screenMargin,
                                              bottom: AdminSpacing.lg, trailing: AdminSpacing.screenMargin))
                    .wantedPetsRowChrome()

                if let staff = PPStaffAuth.shared().cachedCurrentStaff,
                   staff.isActive(), !staff.hasPermission("stock.manage") {
                    Text(Language.get("WantedPets_View_Only", alter: "يمكنك عرض الطلبات، لكن تعديلها يتطلب صلاحية إدارة المخزون"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .listRowInsets(EdgeInsets(top: 0, leading: AdminSpacing.screenMargin,
                                                  bottom: AdminSpacing.base, trailing: AdminSpacing.screenMargin))
                        .wantedPetsRowChrome()
                }

                searchField
                    .listRowInsets(EdgeInsets(top: 0, leading: AdminSpacing.screenMargin,
                                              bottom: AdminSpacing.md, trailing: AdminSpacing.screenMargin))
                    .wantedPetsRowChrome()

                filterRail
                    .listRowInsets(EdgeInsets(top: 0, leading: AdminSpacing.screenMargin,
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if canManageRequests && !isSearchFocused {
                    addRequestDock
                }
            }
            .navigationTitle(Language.get("WantedPets_Title", alter: "قائمة الطلبات"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                        }
                        .accessibilityLabel(Language.get("Back", alter: "رجوع"))
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddWantedPetSheet { _ in
                    actionFeedbackMessage = Language.get("WantedPets_Added_Success", alter: "تم حفظ الطلب بنجاح")
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                        .padding(.bottom, canManageRequests ? 82 : 16)
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
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - The queue at a glance

    private var overview: some View {
        let isUnavailable = service.items.isEmpty && (service.isLoading || service.errorMessage != nil)
        let countLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: AdminSpacing.base))

        return VStack(alignment: .leading, spacing: AdminSpacing.base) {
            HStack(spacing: AdminSpacing.sm) {
                Circle()
                    .fill(AdminSurface.primary)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(Language.get("WantedPets_Overview_Label", alter: "حركة الطلبات"))
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer(minLength: 8)
                if service.isLoading && !service.items.isEmpty {
                    ProgressView()
                        .tint(AdminSurface.primary)
                        .accessibilityLabel(Language.get("WantedPets_Loading", alter: "جاري التحميل..."))
                }
            }

            countLayout {
                Text(isUnavailable ? "—" : "\(service.waitingCount)")
                    .font(Font.custom("Beiruti-Bold", size: 72, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(AdminSurface.primary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .minimumScaleFactor(0.8)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("WantedPets_Overview_Waiting", alter: "طلبات قيد الانتظار"))
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("WantedPets_Overview_Recent", alter: "ضمن أحدث الطلبات"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.bottom, AdminSpacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)

            let metricLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
                : AnyLayout(HStackLayout(spacing: AdminSpacing.base))

            metricLayout {
                statusMetric(count: service.contactedCount,
                             isUnavailable: isUnavailable,
                             title: Language.get("WantedPets_Summary_Contacted", alter: "تم التواصل"),
                             icon: "phone.fill",
                             tint: Color(uiColor: .systemBlue),
                             filter: .contacted)
                statusMetric(count: service.interestedCount,
                             isUnavailable: isUnavailable,
                             title: Language.get("WantedPets_Summary_Interested", alter: "مهتمون"),
                             icon: "heart.fill",
                             tint: AdminSurface.primary,
                             filter: .interested)
            }
        }
        .padding(AdminSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.hero, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isUnavailable
            ? Language.get("WantedPets_Count_Unavailable", alter: "العدد غير متاح")
            : "\(service.waitingCount) \(Language.get("WantedPets_Overview_Waiting", alter: "طلبات قيد الانتظار"))")
    }

    private func statusMetric(count: Int, isUnavailable: Bool, title: String, icon: String, tint: Color,
                              filter: WantedPetsFilter) -> some View {
        Button {
            selectFilter(filter)
        } label: {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(isUnavailable ? "—" : "\(count)")
                    .font(AdminType.headlineBold)
                    .monospacedDigit()
                    .foregroundStyle(AdminSurface.primaryText)
                Text(title)
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(minHeight: AdminTouchTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isUnavailable
            ? "\(title), \(Language.get("WantedPets_Count_Unavailable", alter: "العدد غير متاح"))"
            : "\(count) \(title)")
        .accessibilityHint(Language.get("WantedPets_Filter_Hint", alter: "عرض هذه الطلبات"))
    }

    // MARK: - Search and filters

    private var searchField: some View {
        HStack(spacing: AdminSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityHidden(true)

            TextField(Language.get("WantedPets_Search_Placeholder", alter: "بحث بالاسم، الهاتف، الفئة..."),
                      text: $service.searchQuery)
                .font(AdminType.body)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.leading)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .accessibilityLabel(Language.get("WantedPets_Search_Placeholder", alter: "بحث بالاسم، الهاتف، الفئة..."))

            if !service.searchQuery.isEmpty {
                Button {
                    service.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("WantedPets_Clear_Search", alter: "مسح البحث"))
            }
        }
        .padding(.leading, AdminSpacing.base)
        .padding(.trailing, service.searchQuery.isEmpty ? AdminSpacing.base : AdminSpacing.xs)
        .frame(minHeight: 54)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        }
    }

    private var filterRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AdminSpacing.lg) {
                    ForEach(WantedPetsFilter.allCases) { filter in
                        let isSelected = service.selectedFilter == filter
                        Button {
                            selectFilter(filter)
                        } label: {
                            Text(filter.title)
                                .font(isSelected ? AdminType.subheadlineBold : AdminType.subheadline)
                                .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                                .lineLimit(1)
                                .frame(minHeight: AdminTouchTarget.minimum)
                                .overlay(alignment: .bottom) {
                                    Capsule()
                                        .fill(isSelected ? AdminSurface.primary : .clear)
                                        .frame(height: 3)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(filter.id)
                    }
                }
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
        guard service.selectedFilter != filter else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        isSearchFocused = false
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
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
            Spacer()
            Text(String(service.selectedFilter == .byPet && service.searchQuery.isEmpty
                        ? service.categoryGroups.count : service.filteredItems.count))
                .font(AdminType.footnoteBold)
                .monospacedDigit()
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func petGroupRow(_ group: WantedPetCategoryGroup) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedPetGroup = group
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.base) {
                HStack(alignment: .top, spacing: AdminSpacing.md) {
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(group.displayName)
                            .font(Font.custom("Beiruti-Bold", size: 28, relativeTo: .title2))
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        if let oldest = group.oldestWaitingDurationText {
                            Text(String(format: Language.get("WantedPets_Oldest_Waiting", alter: "أقدم طلب منذ %@"), oldest))
                                .font(AdminType.footnote)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: AdminSpacing.sm)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 48, height: 48)
                        .background(AdminSurface.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        .foregroundStyle(AdminSurface.primary)
                    Text(group.waitingCount > 0
                         ? Language.get("WantedPets_Summary_Waiting", alter: "ينتظرون")
                         : Language.get("WantedPets_Requests_Label", alter: "طلبات"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer(minLength: AdminSpacing.sm)
                    Text(Language.get("WantedPets_Open_Group", alter: "عرض العملاء"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.primary)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(AdminSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        }
        .buttonStyle(WantedPetsPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.displayName), \(group.waitingCount > 0 ? group.waitingCount : group.items.count) \(group.waitingCount > 0 ? Language.get("WantedPets_Summary_Waiting", alter: "ينتظرون") : Language.get("WantedPets_Requests_Label", alter: "طلبات"))")
        .accessibilityHint(Language.get("WantedPets_Open_Group", alter: "عرض العملاء"))
    }

    private func customerRow(_ item: CustomerWantedPet) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            Button {
                selectedItemForDetail = item
            } label: {
                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    HStack(alignment: .top, spacing: AdminSpacing.sm) {
                        Text(item.customerName)
                            .font(AdminType.title3)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Label(item.status.title, systemImage: item.status.iconName)
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(item.status.tintColor)
                            .lineLimit(2)
                    }
                    Text(item.requestedPetTitle)
                        .font(AdminType.bodyBold)
                        .foregroundStyle(AdminSurface.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.preferencesSummary)
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    let detailLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.xs))
                        : AnyLayout(HStackLayout(spacing: AdminSpacing.sm))

                    detailLayout {
                        Text(item.formattedPhoneDisplay)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .environment(\.layoutDirection, .leftToRight)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("·")
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Text(item.waitingDurationText)
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    Label(item.contactSource.title, systemImage: item.contactSource.iconName)
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Language.get("WantedPets_Open_Request", alter: "عرض تفاصيل الطلب"))

            if canManageRequests {
                Rectangle()
                    .fill(AdminSurface.hairline)
                    .frame(height: 1)
                    .accessibilityHidden(true)

                let contactLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
                    : AnyLayout(HStackLayout(spacing: AdminSpacing.sm))

                contactLayout {
                    contactButton(Language.get("WantedPets_Quick_WhatsApp", alter: "واتساب"),
                                  icon: "message.fill") { openWhatsApp(for: item) }
                    contactButton(Language.get("WantedPets_Quick_Call", alter: "اتصال"),
                                  icon: "phone.fill") { callPhone(item.phoneNumber) }
                }
                if item.status == .waiting {
                    contactButton(Language.get("WantedPets_Mark_Contacted", alter: "تحديد كمتواصل معه"),
                                  icon: "checkmark") {
                        transition(item, to: .contacted)
                    }
                    .disabled(inFlightItemIDs.contains(item.id) || service.isMutating)
                }
            }
        }
        .padding(AdminSpacing.cardPadding)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        }
    }

    private func contactButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(2)
                .padding(.horizontal, AdminSpacing.md)
                .frame(minHeight: AdminTouchTarget.minimum)
                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: AdminRadius.small))
        }
        .buttonStyle(.plain)
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

    // MARK: - Create and contact actions

    private var addRequestDock: some View {
        Button {
            guard canManageRequests else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showAddSheet = true
        } label: {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text(Language.get("WantedPets_Add_Action", alter: "إضافة طلب جديد"))
                    .font(AdminType.headlineBold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
        }
        .buttonStyle(WantedPetsPressStyle())
        .disabled(service.isMutating)
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.top, AdminSpacing.md)
        .padding(.bottom, AdminSpacing.sm)
        .background {
            AdminSurface.background
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    AdminSurface.hairline.frame(height: 1)
                }
        }
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

private extension View {
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
