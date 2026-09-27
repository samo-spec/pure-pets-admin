//
//  WaitingCustomersView.swift
//  Pure Pets Admin
//
//  Created for Pure Pets Platform.
//  Category-defining Apple-grade Waiting Customers Operational Command Center.
//  Tactile Queue Cards • Live Match Badges • Direct Communication Dock • Batch Workflow.
//

import SwiftUI
import UIKit

public struct WaitingCustomersView: View {
    public let petTitle: String
    public let mainKindId: Int
    public let subkindId: Int?
    public let initialCustomers: [CustomerWantedPet]?

    @StateObject private var service = WantedPetsService.shared
    @State private var customers: [CustomerWantedPet] = []
    @State private var matchResults: [WantedPetMatchResult] = []
    
    // Interaction & Operational States
    @State private var searchText: String = ""
    @State private var activeFilter: WaitingFilter = .all
    @State private var isSelectionMode: Bool = false
    @State private var selectedIds: Set<String> = []
    @State private var isBatchContacting: Bool = false
    @State private var showDetailId: String? = nil
    @State private var showAddCustomerSheet: Bool = false
    @State private var feedbackNotice: String? = nil
    @State private var copiedId: String? = nil

    private enum WaitingFilter: Hashable {
        case all
        case exact
        case uncontacted
        case interested
    }

    public init(
        petTitle: String,
        mainKindId: Int,
        subkindId: Int? = nil,
        customers: [CustomerWantedPet]? = nil
    ) {
        self.petTitle = petTitle
        self.mainKindId = mainKindId
        self.subkindId = subkindId
        self.initialCustomers = customers
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            AdminSurface.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AdminSpacing.md) {
                    // 1. Hero Pet Demand Island
                    heroPetHeaderCard
                        .padding(.horizontal, AdminSpacing.base)
                        .padding(.top, AdminSpacing.xs)

                    // 2. Queue List / Filtered Cards
                    if customers.isEmpty {
                        emptyStateView
                            .padding(.horizontal, AdminSpacing.base)
                    } else if filteredCustomers.isEmpty {
                        emptyFilterView
                            .padding(.horizontal, AdminSpacing.base)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(filteredCustomers.enumerated()), id: \.element.id) { index, item in
                                customerCard(item, queueIndex: index)
                            }
                        }
                        .padding(.horizontal, AdminSpacing.base)
                        .padding(.bottom, isSelectionMode && !selectedIds.isEmpty ? 90 : AdminSpacing.xl)
                    }
                }
            }

            // 3. Floating Batch Action Island (When multi-selection active)
            if isSelectionMode && !selectedIds.isEmpty {
                batchActionBar
            }
        }
        .navigationTitle(String(format: Language.get("WaitingFor_Pet_Title", alter: "المنتظرون: %@"), petTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showAddCustomerSheet = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .accessibilityLabel(Language.get("WantedPets_Add_Title", alter: "إضافة طلب عميل"))
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isSelectionMode ? Language.get("Done", alter: "تم") : Language.get("Select", alter: "تحديد")) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedIds.removeAll()
                        }
                    }
                }
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primary)
            }
        }
        .sheet(isPresented: $showAddCustomerSheet) {
            AddWantedPetSheet { _ in
                loadCustomers()
                feedbackNotice = Language.get("WantedPets_Added_Success", alter: "تمت إضافة الطلب بنجاح")
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { showDetailId != nil },
            set: { if !$0 { showDetailId = nil } }
        )) {
            if let id = showDetailId {
                WantedPetDetailView(wantedPetId: id)
            }
        }
        .onAppear {
            loadCustomers()
        }
        .overlay(alignment: .bottom) {
            if let notice = feedbackNotice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(uiColor: .ppSuccess))
                    Text(notice)
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.88), in: Capsule())
                .padding(.bottom, isSelectionMode && !selectedIds.isEmpty ? 95 : 24)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        withAnimation { feedbackNotice = nil }
                    }
                }
            }
        }
    }

    // MARK: - 1. Hero Pet Demand Island

    private var heroPetHeaderCard: some View {
        let categoryName = MainKindsModel.kindName(forID: mainKindId)
        let totalCount = customers.count

        return VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                // Pet Avatar/Icon with subtle glow
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary.opacity(0.18), AdminSurface.primary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 50, height: 50)
                .overlay(
                    Circle().strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    // Taxonomy Breadcrumb
                    HStack(spacing: 5) {
                        if !categoryName.isEmpty {
                            Text(categoryName)
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Text(Language.get("WantedPets_DemandHeader_Species", alter: "طلب عملاء مخصص"))
                            .font(Font.custom("Beiruti-Medium", size: 12))
                            .foregroundStyle(AdminSurface.primary)
                    }

                    // Pet Breed Title
                    Text(petTitle)
                        .font(Font.custom("Beiruti-Bold", size: 22))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Queue Count Pill
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(totalCount)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(uiColor: .systemOrange))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(uiColor: .systemOrange).opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(uiColor: .systemOrange).opacity(0.25), lineWidth: 0.8))

                    Text(Language.get("WantedPets_InQueue_Label", alter: "في قائمة الانتظار"))
                        .font(Font.custom("Beiruti-Regular", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            // Quick Filter & Search Strip
            filterAndSearchStrip
        }
        .padding(16)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
    }

    // MARK: - Search & Filter Strip

    private var filterAndSearchStrip: some View {
        VStack(spacing: 10) {
            // Live Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)

                TextField(Language.get("WantedPets_SearchCustomer_Placeholder", alter: "ابحث بالاسم أو رقم الهاتف..."), text: $searchText)
                    .font(Font.custom("Beiruti-Regular", size: 14))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.5))

            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    filterChip(
                        title: Language.get("All", alter: "الكل"),
                        count: customers.count,
                        filter: .all
                    )
                    filterChip(
                        title: Language.get("WantedPets_Filter_Exact", alter: "⭐ تطابق تام"),
                        count: exactMatchesCount,
                        filter: .exact
                    )
                    filterChip(
                        title: Language.get("WantedPets_Filter_Uncontacted", alter: "⏳ بانتظار التواصل"),
                        count: uncontactedCount,
                        filter: .uncontacted
                    )
                    filterChip(
                        title: Language.get("WantedPets_Filter_Interested", alter: "💜 مهتمون"),
                        count: interestedCount,
                        filter: .interested
                    )
                }
            }
        }
    }

    private func filterChip(title: String, count: Int, filter: WaitingFilter) -> some View {
        let isSelected = activeFilter == filter
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                activeFilter = filter
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 13))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.25) : AdminSurface.cardElevated, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Customer Demand Dossier Card

    private func customerCard(_ item: CustomerWantedPet, queueIndex: Int) -> some View {
        let isSelected = selectedIds.contains(item.id)
        let match = matchResult(for: item)
        let isCopied = copiedId == item.id

        return HStack(alignment: .top, spacing: 12) {
            // Selection Checkbox in selection mode
            if isSelectionMode {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    toggleSelection(for: item.id)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Card Top Metadata: Queue Rank, Wait Duration, Match Badge
                HStack(alignment: .center) {
                    // Queue Rank Tag (#1, #2...)
                    HStack(spacing: 3) {
                        Text("#\(queueIndex + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        Text(queueIndex == 0 ? Language.get("WantedPets_FirstInLine", alter: "الأقدم") : Language.get("WantedPets_InQueue_Short", alter: "بالدور"))
                            .font(Font.custom("Beiruti-Bold", size: 10))
                    }
                    .foregroundStyle(queueIndex == 0 ? Color(uiColor: .systemAmber) : AdminSurface.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        (queueIndex == 0 ? Color(uiColor: .systemAmber) : AdminSurface.secondaryText).opacity(0.12),
                        in: Capsule()
                    )

                    // Waiting Duration Badge
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(item.waitingDurationText)
                            .font(Font.custom("Beiruti-Regular", size: 11))
                    }
                    .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    // Match Level Badge
                    HStack(spacing: 4) {
                        Image(systemName: match.matchLevel.iconName)
                            .font(.system(size: 10))
                        Text(match.matchLevel.title)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .foregroundStyle(match.matchLevel.tintColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(match.matchLevel.tintColor.opacity(0.12), in: Capsule())
                }

                // Customer Identity Row: Initials Avatar, Name, Phone, Contact Source
                HStack(alignment: .center, spacing: 10) {
                    // Avatar Initials
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                        Text(customerInitials(item.customerName))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .fill(Color(uiColor: .ppSuccess))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(AdminSurface.surface, lineWidth: 1.5))
                            .offset(x: 13, y: 13),
                        alignment: .center
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.customerName)
                                .font(Font.custom("Beiruti-Bold", size: 18))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)

                            // Contact Source Tag
                            HStack(spacing: 3) {
                                Image(systemName: item.contactSource.iconName)
                                    .font(.system(size: 9))
                                Text(item.contactSource.title)
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                            }
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.cardElevated, in: Capsule())
                        }

                        // Phone number with copy button
                        HStack(spacing: 6) {
                            Text(item.formattedPhoneDisplay)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .environment(\.layoutDirection, .leftToRight)

                            Button {
                                copyPhone(item)
                            } label: {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(isCopied ? Color(uiColor: .ppSuccess) : AdminSurface.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    // Tap to View Dossier Chevron
                    Button {
                        showDetailId = item.id
                    } label: {
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(8)
                            .background(AdminSurface.cardElevated, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Preferences & Desires Matrix (Gender, Color, Budget, Notes)
                preferencesPillsView(item)

                // Match Explanation Text
                if !match.matchReason.isEmpty {
                    Text(match.matchReason)
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 2)
                }

                Divider()
                    .background(AdminSurface.hairline)

                // Interactive Operational Action Dock
                HStack(spacing: 8) {
                    // WhatsApp Action
                    Button {
                        openWhatsApp(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 13))
                            Text(Language.get("WhatsApp", alter: "واتساب"))
                                .font(Font.custom("Beiruti-Bold", size: 13))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Color(uiColor: .ppSuccess), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // Phone Call Action
                    Button {
                        callPhone(item.phoneNumber)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(width: 42, height: 38)
                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)

                    // Quick Status Action (Mark Contacted / Interested)
                    if item.status == .waiting {
                        Button {
                            markSingleContacted(item)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "phone.bubble.left.fill")
                                    .font(.system(size: 11))
                                Text(Language.get("WantedPet_Action_MarkContacted_Short", alter: "تم التواصل"))
                                    .font(Font.custom("Beiruti-Bold", size: 13))
                            }
                            .foregroundStyle(Color(uiColor: .systemBlue))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 38)
                            .background(Color(uiColor: .systemBlue).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(uiColor: .systemBlue).opacity(0.25), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    } else if item.status == .contacted {
                        Button {
                            markSingleInterested(item)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                Text(Language.get("WantedPet_Status_Interested", alter: "مهتم"))
                                    .font(Font.custom("Beiruti-Bold", size: 13))
                            }
                            .foregroundStyle(Color(uiColor: .systemPurple))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 38)
                            .background(Color(uiColor: .systemPurple).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(uiColor: .systemPurple).opacity(0.25), lineWidth: 0.75))
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Current status badge
                        HStack(spacing: 4) {
                            Circle().fill(item.status.tintColor).frame(width: 6, height: 6)
                            Text(item.status.title)
                                .font(Font.custom("Beiruti-Bold", size: 12))
                                .foregroundStyle(item.status.tintColor)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 38)
                        .background(item.status.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.75)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 8 : 4, y: 2)
        .onTapGesture {
            if isSelectionMode {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                toggleSelection(for: item.id)
            } else {
                showDetailId = item.id
            }
        }
    }

    // MARK: - Preferences & Desires Matrix

    @ViewBuilder
    private func preferencesPillsView(_ item: CustomerWantedPet) -> some View {
        let hasSex = item.sexPreference != .any
        let hasColor = !(item.colorPreference ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBudget = (item.budgetMax ?? 0) > 0
        let hasNotes = !(item.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasSex || hasColor || hasBudget || hasNotes {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if hasSex {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.stand")
                                .font(.system(size: 9))
                            Text(item.sexPreference.title)
                                .font(Font.custom("Beiruti-Medium", size: 11))
                        }
                        .foregroundStyle(AdminSurface.primaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AdminSurface.cardElevated, in: Capsule())
                    }

                    if let color = item.colorPreference, !color.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 9))
                            Text(color)
                                .font(Font.custom("Beiruti-Medium", size: 11))
                        }
                        .foregroundStyle(AdminSurface.primaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AdminSurface.cardElevated, in: Capsule())
                    }

                    if let budget = item.budgetMax, budget > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 9))
                            Text(String(format: "≤ %.0f", budget))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(Color(uiColor: .systemGreen))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .systemGreen).opacity(0.12), in: Capsule())
                    }
                }

                if let notes = item.notes, !notes.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.top, 2)
                        Text(notes)
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.cardElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    // MARK: - 3. Floating Batch Action Island

    private var batchActionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(AdminSurface.primary)
                    Text(String(format: Language.get("WantedPets_Selected_Count", alter: "تم تحديد %d عملاء"), selectedIds.count))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Text(Language.get("WantedPets_BatchContact_Subtitle", alter: "تحديث جماعي لحالة التواصل"))
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            Button {
                executeBatchContact()
            } label: {
                HStack(spacing: 6) {
                    if isBatchContacting {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "phone.bubble.left.fill")
                            .font(.system(size: 13))
                    }
                    Text(Language.get("WantedPets_BatchContact_Action", alter: "تحديد كـ تم التواصل"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(AdminSurface.primary, in: Capsule())
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 3)
            }
            .disabled(isBatchContacting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, AdminSpacing.base)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AdminSurface.primary.opacity(0.08))
                    .frame(width: 90, height: 90)

                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(AdminSurface.primary)
            }
            .padding(.top, 40)

            VStack(spacing: 6) {
                Text(Language.get("WantedPets_NoWaiting_Title", alter: "لا يوجد عملاء ينتظرون هذا الحيوان"))
                    .font(Font.custom("Beiruti-Bold", size: 18))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("WantedPets_NoWaiting_Subtitle", alter: "يمكن إضافة طلب عميل جديد للتواصل معه فور توفر أي دفعة قادمة."))
                    .font(Font.custom("Beiruti-Regular", size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showAddCustomerSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                    Text(Language.get("WantedPets_Add_Title", alter: "إضافة طلب عميل جديد"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(AdminSurface.primary, in: Capsule())
                .shadow(color: AdminSurface.primary.opacity(0.25), radius: 8, y: 3)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(AdminSurface.secondaryText)
                .padding(.top, 30)

            Text(Language.get("NoSearchResults", alter: "لا توجد نتائج مطابقة"))
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)

            Button {
                withAnimation {
                    searchText = ""
                    activeFilter = .all
                }
            } label: {
                Text(Language.get("ResetFilters", alter: "إعادة ضبط التصفية"))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Helpers & Data Filtering

    private var filteredCustomers: [CustomerWantedPet] {
        var list = customers

        // 1. Text Search
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.customerName.lowercased().contains(query) ||
                $0.phoneNumber.contains(query) ||
                ($0.notes?.lowercased().contains(query) ?? false)
            }
        }

        // 2. Filter Tag
        switch activeFilter {
        case .all:
            break
        case .exact:
            list = list.filter { matchResult(for: $0).matchLevel == .exact }
        case .uncontacted:
            list = list.filter { $0.status == .waiting }
        case .interested:
            list = list.filter { $0.status == .interested }
        }

        return list
    }

    private var exactMatchesCount: Int {
        customers.filter { matchResult(for: $0).matchLevel == .exact }.count
    }

    private var uncontactedCount: Int {
        customers.filter { $0.status == .waiting }.count
    }

    private var interestedCount: Int {
        customers.filter { $0.status == .interested }.count
    }

    private func customerInitials(_ name: String) -> String {
        let parts = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts[1].first {
            return "\(first)\(second)"
        } else if let first = name.first {
            return String(first)
        }
        return "🐾"
    }

    // MARK: - Actions & Operational Triggers

    private func loadCustomers() {
        if let initial = initialCustomers {
            self.customers = initial
            return
        }

        let filtered = service.items.filter { item in
            guard item.status.isActive else { return false }
            if item.mainKindId != mainKindId { return false }
            if let sId = subkindId, item.subkindId != nil, item.subkindId != sId { return false }
            return true
        }

        self.customers = filtered.sorted { $0.createdAt < $1.createdAt } // Oldest first
    }

    private func matchResult(for item: CustomerWantedPet) -> WantedPetMatchResult {
        if let found = matchResults.first(where: { $0.wantedPet.id == item.id }) {
            return found
        }

        if item.subkindId == nil {
            return WantedPetMatchResult(
                wantedPet: item,
                matchLevel: .broad,
                matchReason: Language.get("WantedPets_BroadCategory_Match", alter: "طلب عام للفئة")
            )
        } else if item.sexPreference == .any && (item.colorPreference == nil || item.colorPreference?.isEmpty == true) {
            return WantedPetMatchResult(
                wantedPet: item,
                matchLevel: .exact,
                matchReason: Language.get("WantedPets_ExactPreferences_Match", alter: "تطابق تام للفصيلة والمواصفات")
            )
        } else {
            return WantedPetMatchResult(
                wantedPet: item,
                matchLevel: .compatible,
                matchReason: item.preferencesSummary
            )
        }
    }

    private func toggleSelection(for id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func markSingleContacted(_ item: CustomerWantedPet) {
        Task {
            do {
                try await service.transitionStatus(id: item.id, targetStatus: .contacted, contactChannel: "whatsapp")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                feedbackNotice = Language.get("WantedPet_Contacted_Success", alter: "تم تحديث حالة العميل كـ تم التواصل")
                loadCustomers()
            } catch {
                // error handling
            }
        }
    }

    private func markSingleInterested(_ item: CustomerWantedPet) {
        Task {
            do {
                try await service.transitionStatus(id: item.id, targetStatus: .interested)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                feedbackNotice = Language.get("WantedPet_Interested_Success", alter: "تم تحديد العميل كـ مهتم")
                loadCustomers()
            } catch {
                // error handling
            }
        }
    }

    private func copyPhone(_ item: CustomerWantedPet) {
        UIPasteboard.general.string = item.phoneNumber
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation {
            copiedId = item.id
            feedbackNotice = Language.get("PhoneCopied", alter: "تم نسخ الرقم")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation {
                if copiedId == item.id {
                    copiedId = nil
                }
            }
        }
    }

    private func executeBatchContact() {
        isBatchContacting = true
        let idsToUpdate = Array(selectedIds)

        Task {
            do {
                _ = try await service.batchMarkContacted(ids: idsToUpdate, channel: "whatsapp")
                await MainActor.run {
                    self.isBatchContacting = false
                    self.isSelectionMode = false
                    self.selectedIds.removeAll()
                    self.feedbackNotice = String(format: Language.get("WantedPets_BatchContacted_Success", alter: "تم تحديث %d عملاء كـ تم التواصل"), idsToUpdate.count)
                    self.loadCustomers()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    self.isBatchContacting = false
                }
            }
        }
    }

    private func openWhatsApp(_ item: CustomerWantedPet) {
        let digits = item.normalizedPhoneNumber.isEmpty ? item.phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression) : item.normalizedPhoneNumber
        let template = String(format: Language.get("WantedPet_WhatsApp_Template", alter: "مرحباً %@، يسعدنا إخبارك بتوفر %@ في بيور بيتس. هل ما زلت مهتماً؟"), item.customerName, petTitle)
        guard let encoded = template.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://wa.me/\(digits)?text=\(encoded)") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func callPhone(_ phoneNumber: String) {
        let clean = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "tel://\(clean)") else { return }
        UIApplication.shared.open(url)
    }
}
