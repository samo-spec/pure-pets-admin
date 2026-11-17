//
//  PPDeliveryPickupStoreSheet.swift
//  PurePetsAdmin
//
//  NextGen V10 Category-Defining Delivery Pickup Store Decision Surface.
//  Reimagined from absolute first principles:
//  - Tactical Dispatch & Inventory Reassurance Header (Live courier telemetry & stock lock)
//  - State-of-the-art Diagnostic Recovery Portal with animated retry & ambient warning aura
//  - Holographic Hub Matrix with primary iridescent glow on currently assigned store
//  - Alternative authorized store cards with interactive spring radio checks & micro-haptics
//  - Shimmering skeleton states & floating glass action dock
//  - Native Arabic-first RTL alignment with Beiruti typography & Dynamic Type
//

import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - Store Choice Model

public struct PPDeliveryStoreChoice: Identifiable, Hashable {
    public let id: String
    public let branchId: String
    public let nameAr: String
    public let nameEn: String
    public let formattedAddress: String
    public let isCurrent: Bool
    public let titleBadge: String?
    public let phone: String?
    public let distanceKm: Double?

    public init(
        id: String,
        branchId: String,
        nameAr: String,
        nameEn: String,
        formattedAddress: String,
        isCurrent: Bool,
        titleBadge: String? = nil,
        phone: String? = nil,
        distanceKm: Double? = nil
    ) {
        self.id = id
        self.branchId = branchId
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.formattedAddress = formattedAddress
        self.isCurrent = isCurrent
        self.titleBadge = titleBadge
        self.phone = phone
        self.distanceKm = distanceKm
    }

    public var displayName: String {
        let isRTL = Language.isRTL()
        if isRTL {
            return !nameAr.isEmpty ? nameAr : (!nameEn.isEmpty ? nameEn : formattedAddress)
        } else {
            return !nameEn.isEmpty ? nameEn : (!nameAr.isEmpty ? nameAr : formattedAddress)
        }
    }

    public var secondaryName: String? {
        let isRTL = Language.isRTL()
        if isRTL {
            return (!nameEn.isEmpty && nameEn != nameAr) ? nameEn : nil
        } else {
            return (!nameAr.isEmpty && nameAr != nameEn) ? nameAr : nil
        }
    }
}

// MARK: - View Model

@MainActor
public final class PPDeliveryPickupStoreViewModel: ObservableObject {
    @Published public var choices: [PPDeliveryStoreChoice] = []
    @Published public var selectedBranchId: String? = nil
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var isCurrentStoreUnavailable: Bool = false
    @Published public var retryCount: Int = 0
    @Published public private(set) var nextCursor: String? = nil

    public let record: PPFulfillmentRecord
    private let sessionUID: String

    public init(record: PPFulfillmentRecord) {
        self.record = record
        self.sessionUID = Auth.auth().currentUser?.uid ?? ""
    }

    public func loadOptions() {
        loadPage(after: nil)
    }

    public func loadMore() {
        guard let nextCursor else { return }
        loadPage(after: nextCursor)
    }

    private func loadPage(after cursor: String?) {
        guard !isLoading else { return }
        let firstPage = cursor == nil
        isLoading = true
        errorMessage = nil
        if firstPage {
            isCurrentStoreUnavailable = false
            choices = []
            selectedBranchId = nil
            nextCursor = nil
        }

        PPFulfillmentService.shared().fetchPickupOptions(for: record, afterBranchID: cursor) { [weak self] result, error in
            // Capture an immutable Sendable snapshot before hopping from the
            // Objective-C callback to the main actor; do not transfer Any dictionaries.
            let encodedResult = result.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                if let error = error {
                    let desc = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !desc.isEmpty && !desc.hasPrefix("The operation couldn") {
                        self.errorMessage = desc
                    } else {
                        self.errorMessage = Language.get("PickupStore_LoadFailed", alter: "تعذر تحميل متاجر الاستلام. تحقق من الاتصال والصلاحيات ثم أعد المحاولة.")
                    }
                    self.triggerErrorHaptic()
                    return
                }

                guard let encodedResult,
                      let data = (try? JSONSerialization.jsonObject(with: encodedResult)) as? [String: Any] else {
                    self.errorMessage = Language.get("PickupStore_LoadFailed", alter: "تعذر تحميل متاجر الاستلام. تحقق من الاتصال والصلاحيات ثم أعد المحاولة.")
                    self.triggerErrorHaptic()
                    return
                }

                guard self.validateSession() else {
                    self.choices = []
                    self.selectedBranchId = nil
                    self.nextCursor = nil
                    self.errorMessage = Language.get("PPOrder_Error_SessionChanged", alter: "")
                    return
                }
                var parsedChoices: [PPDeliveryStoreChoice] = firstPage ? [] : self.choices
                let currentDict = data["current"] as? [String: Any]
                let currentBranchId = currentDict?["pickupBranchId"] as? String

                if firstPage, let currentDict = currentDict,
                   let currentAddr = currentDict["pickupAddress"] as? [String: Any] {
                    let branchNames = currentAddr["branchName"] as? [String: Any] ?? [:]
                    let nameAr = branchNames["ar"] as? String ?? ""
                    let nameEn = branchNames["en"] as? String ?? ""
                    let formatted = currentAddr["formattedAddress"] as? String ?? ""
                    let source = currentDict["pickupStoreSource"] as? String ?? ""
                    let badge = (source == "consumer_stock")
                        ? Language.get("PickupStore_Default", alter: "المتجر الافتراضي للطلب")
                        : Language.get("PickupStore_Current", alter: "المتجر المعين حالياً")

                    let currentChoice = PPDeliveryStoreChoice(
                        id: currentBranchId ?? "current_branch",
                        branchId: currentBranchId ?? "",
                        nameAr: nameAr,
                        nameEn: nameEn,
                        formattedAddress: formatted,
                        isCurrent: true,
                        titleBadge: badge,
                        phone: currentAddr["phone"] as? String,
                        distanceKm: nil
                    )
                    parsedChoices.append(currentChoice)
                }

                if let storesList = data["stores"] as? [[String: Any]] {
                    for store in storesList {
                        guard let bId = store["branchId"] as? String,
                              let addr = store["pickupAddress"] as? [String: Any],
                              bId != currentBranchId,
                              !parsedChoices.contains(where: { $0.branchId == bId }) else { continue }

                        let bNames = addr["branchName"] as? [String: Any] ?? [:]
                        let nameAr = bNames["ar"] as? String ?? ""
                        let nameEn = bNames["en"] as? String ?? ""
                        let formatted = addr["formattedAddress"] as? String ?? ""

                        let choice = PPDeliveryStoreChoice(
                            id: bId,
                            branchId: bId,
                            nameAr: nameAr,
                            nameEn: nameEn,
                            formattedAddress: formatted,
                            isCurrent: false,
                            titleBadge: nil,
                            phone: addr["phone"] as? String,
                            distanceKm: nil
                        )
                        parsedChoices.append(choice)
                    }
                }

                self.choices = parsedChoices
                self.nextCursor = data["nextCursor"] as? String
                if firstPage { self.isCurrentStoreUnavailable = (currentDict == nil) }

                // Retain a real saved pickup (including a saved point without
                // a branch id). A replacement always needs an explicit choice.
                if firstPage, currentDict != nil, parsedChoices.first?.isCurrent == true {
                    self.selectedBranchId = currentBranchId ?? ""
                }

                self.triggerSuccessHaptic()
            }
        }
    }

    public func selectChoice(_ choice: PPDeliveryStoreChoice) {
        guard selectedBranchId != choice.branchId else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            selectedBranchId = choice.branchId
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    public func retry() {
        retryCount += 1
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        loadOptions()
    }

    public func validateSession() -> Bool {
        guard let currentUID = Auth.auth().currentUser?.uid, !currentUID.isEmpty else { return false }
        return currentUID == sessionUID
    }

    private func triggerSuccessHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    private func triggerErrorHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }
}

// MARK: - Category-Defining Sheet View

public struct PPDeliveryPickupStoreSheet: View {
    @StateObject private var viewModel: PPDeliveryPickupStoreViewModel
    private let onConfirm: @MainActor (String?) -> Void
    private let onCancel: @MainActor () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isConfirmPressed = false

    public init(
        record: PPFulfillmentRecord,
        onConfirm: @escaping @MainActor (String?) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: PPDeliveryPickupStoreViewModel(record: record))
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        ZStack {
            // Ambient Atmosphere Canvas
            canvasBackground

            VStack(spacing: 0) {
                // Top Grabber & Navigation Header
                topBarHeader

                // Scrollable Content Matrix
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        // Operational Briefing Hero Card
                        operationalHeroCard

                        // Dynamic State Content
                        if viewModel.isLoading && viewModel.choices.isEmpty {
                            skeletonLoadingSection
                        } else if let errorMessage = viewModel.errorMessage {
                            diagnosticErrorSection(errorMessage: errorMessage)
                        } else if viewModel.choices.isEmpty && viewModel.nextCursor == nil {
                            emptyStateSection
                        } else {
                            storeChoicesMatrix
                        }

                        // Bottom Spacer for Dock clearance
                        Spacer()
                            .frame(height: 90)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // Sticky Bottom Glass Action Dock
                stickyActionDock
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            viewModel.loadOptions()
        }
    }

    // MARK: - Atmosphere Canvas

    private var canvasBackground: some View {
        ZStack {
            AdminSurface.background
                .ignoresSafeArea()

            // Subtle warm luxury radiant aura
            RadialGradient(
                gradient: Gradient(colors: [
                    AdminSurface.primarySoft.opacity(colorScheme == .dark ? 0.14 : 0.08),
                    Color.clear
                ]),
                center: .top,
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Top Navigation Header

    private var topBarHeader: some View {
        VStack(spacing: 8) {
            // Tactile Grabber Pill
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            HStack(spacing: 12) {
                // Leading: Dismiss Button
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(AdminType.subheadline)
                    }
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(AdminSurface.control.opacity(0.8))
                    )
                }

                Spacer()

                // Center Title with Icon
                HStack(spacing: 6) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)

                    Text(Language.get("PickupStore_Title", alter: "متجر الاستلام"))
                        .font(AdminType.headlineBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                Spacer()

                // Trailing: Fulfillment Context Badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(AdminSurface.emerald)
                        .frame(width: 7, height: 7)

                    Text(Language.get("Fulfillment_Ready", alter: "جاهز للاستلام"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.emerald)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(AdminSurface.emerald.opacity(0.12))
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)

            Divider()
                .background(AdminSurface.hairline.opacity(0.5))
        }
    }

    // MARK: - Operational Briefing Hero Card

    private var operationalHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                // Illuminated Courier 3D Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AdminSurface.primary.opacity(0.22),
                                    AdminSurface.primarySoft.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AdminSurface.primary.opacity(0.35), lineWidth: 1)
                        )

                    Image(systemName: "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(Language.get("PickupStore_Intro", alter: "من أين يستلم المندوب هذا الطلب؟"))
                        .font(AdminType.title3Bold)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    let orderNo = viewModel.record.parentOrderNumber
                    if !orderNo.isEmpty {
                        HStack(spacing: 6) {
                            Text(Language.get("OrderNumber_Label", alter: "طلب رقم:"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)

                            Text("#\(orderNo)")
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primaryText)

                            let customer = viewModel.record.customerName
                            if !customer.isEmpty {
                                Text("•")
                                    .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                                Text(customer)
                                    .font(AdminType.caption2)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            // Inventory Safety Rail Banner ("حماية المخزون")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AdminSurface.emerald)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("PickupStore_InventorySafetyTitle", alter: "حماية حجز المخزون"))
                        .font(AdminType.caption1Bold)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(viewModel.isCurrentStoreUnavailable
                         ? Language.get("PickupStore_CurrentUnavailable", alter: "المتجر الحالي غير متوفر للاستلام. يرجى اختيار متجر بديل للمتابعة.")
                         : Language.get("PickupStore_InventoryUnaffected", alter: "تابع بمتجر الاستلام الحالي أو اختر متجراً آخر ضمن صلاحياتك. يتغير موقع استلام التوصيل فقط ولا يتأثر مخزون الطلب."))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.emerald.opacity(colorScheme == .dark ? 0.12 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AdminSurface.emerald.opacity(0.22), lineWidth: 1)
                    )
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Store Choices Matrix

    private var storeChoicesMatrix: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header for section
            HStack {
                Text(Language.get("PickupStore_Choose", alter: "موقع استلام الطلب"))
                    .font(AdminType.headlineBold)
                    .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Text(String(format: Language.get("PickupStore_CountBadge", alter: "%d مراكز متاحة"), viewModel.choices.count))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(AdminSurface.control)
                    )
            }
            .padding(.horizontal, 4)

            // Current / Default Store Card (Hero Position)
            if let currentStore = viewModel.choices.first(where: { $0.isCurrent }) {
                storeRowCard(store: currentStore, isHeroCurrent: true)
            }

            // Alternative Stores Section
            let alternatives = viewModel.choices.filter { !$0.isCurrent }
            if !alternatives.isEmpty {
                if viewModel.choices.contains(where: { $0.isCurrent }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AdminSurface.secondaryText)

                        Text(Language.get("PickupStore_AlternativesHeader", alter: "مراكز استلام بديلة مصرحة"))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        Spacer()
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
                }

                ForEach(alternatives) { store in
                    storeRowCard(store: store, isHeroCurrent: false)
                }
            }

            if viewModel.nextCursor != nil {
                Button(action: { viewModel.loadMore() }) {
                    HStack(spacing: 8) {
                        if viewModel.isLoading { ProgressView() }
                        Text(Language.get("PickupStore_LoadMore", alter: ""))
                            .font(AdminType.subheadlineBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(viewModel.isLoading)
            }

            // Explanatory Footer Notice
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.8))

                Text(Language.get("PickupStore_Footer", alter: "يتم إرسال موقع الفرع المختار مباشرة إلى تطبيق السائق لتوجيهه في مرحلة الاستلام."))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    // MARK: - Store Row Card

    private func storeRowCard(store: PPDeliveryStoreChoice, isHeroCurrent: Bool) -> some View {
        let isSelected = viewModel.selectedBranchId == store.branchId

        return Button(action: {
            viewModel.selectChoice(store)
        }) {
            HStack(alignment: .top, spacing: 14) {
                // Radio Concentric Checkmark Indicator
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? AdminSurface.primary : AdminSurface.hairline,
                            lineWidth: isSelected ? 2.5 : 1.5
                        )
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(AdminSurface.primary)
                            .frame(width: 14, height: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 4)

                // Store Information Block
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(store.displayName)
                            .font(AdminType.headlineBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        // Badge for Default or Current Store
                        if let badge = store.titleBadge {
                            Text(badge)
                                .font(AdminType.caption2Bold)
                                .foregroundColor(isHeroCurrent ? AdminSurface.primary : AdminSurface.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(isHeroCurrent
                                              ? AdminSurface.primarySoft.opacity(colorScheme == .dark ? 0.25 : 0.15)
                                              : AdminSurface.control)
                                )
                        }
                    }

                    // Secondary Name (English/Arabic)
                    if let secondary = store.secondaryName {
                        Text(secondary)
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.9))
                    }

                    // Formatted Street Address with Pin
                    if !store.formattedAddress.isEmpty {
                        HStack(alignment: .center, spacing: 5) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AdminSurface.secondaryText)

                            Text(store.formattedAddress)
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.top, 2)
                    }

                    // Optional Distance or Telephone Metadata
                    if let phone = store.phone, !phone.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 11))
                                .foregroundColor(AdminSurface.secondaryText)

                            Text(phone)
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .padding(.top, 1)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isSelected
                            ? (colorScheme == .dark
                               ? AdminSurface.primarySoft.opacity(0.12)
                               : AdminSurface.primarySoft.opacity(0.08))
                            : AdminSurface.card
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isSelected ? AdminSurface.primary : AdminSurface.hairline,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isSelected
                            ? AdminSurface.primary.opacity(0.12)
                            : Color.black.opacity(colorScheme == .dark ? 0.18 : 0.03),
                        radius: isSelected ? 8 : 4,
                        x: 0,
                        y: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.005 : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: isSelected)
    }

    // MARK: - Diagnostic Recovery Portal (State in User Screenshot)

    private func diagnosticErrorSection(errorMessage: String) -> some View {
        VStack(spacing: 16) {
            // Illuminated Warning Shield
            ZStack {
                Circle()
                    .fill(AdminSurface.amber.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .frame(width: 64, height: 64)

                Circle()
                    .stroke(AdminSurface.amber.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 72, height: 72)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AdminSurface.amber)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(Language.get("PickupStore_ErrorHeader", alter: "تعذر الاتصال بمركز المتاجر"))
                    .font(AdminType.title3Bold)
                    .foregroundColor(AdminSurface.primaryText)

                Text(errorMessage)
                    .font(AdminType.subheadline)
                    .foregroundColor(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            // Diagnostic Diagnostic Badges
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 12))
                    Text(Language.get("Network_Check", alter: "الشبكة / الصلاحيات"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundColor(AdminSurface.amber)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(AdminSurface.amber.opacity(0.12))
                )

                if viewModel.retryCount > 0 {
                    Text(String(format: Language.get("Retry_CountBadge", alter: "%d محاولات"), viewModel.retryCount))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(AdminSurface.control)
                        )
                }
            }

            // Tactile Instant Retry Button
            Button(action: {
                viewModel.retry()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))

                    Text(Language.get("Retry", alter: "إعادة المحاولة الآن"))
                        .font(AdminType.headlineBold)
                }
                .foregroundColor(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(AdminSurface.primary)
                        .shadow(color: AdminSurface.primary.opacity(0.35), radius: 8, x: 0, y: 4)
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AdminSurface.amber.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: AdminSurface.amber.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 14, x: 0, y: 4)
        )
    }

    // MARK: - Skeleton Loading Section

    private var skeletonLoadingSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AdminSurface.primary))
                    .scaleEffect(0.9)

                Text(Language.get("PickupStore_Loading", alter: "جارٍ فحص مراكز التوزيع المصرحة..."))
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.secondaryText)

                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(0..<3) { idx in
                HStack(spacing: 14) {
                    Circle()
                        .fill(AdminSurface.control.opacity(0.7))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AdminSurface.control.opacity(0.8))
                            .frame(width: CGFloat(140 + idx * 30), height: 16)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(AdminSurface.control.opacity(0.5))
                            .frame(width: CGFloat(210 - idx * 20), height: 12)
                    }

                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AdminSurface.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(AdminSurface.hairline, lineWidth: 1)
                        )
                )
                .opacity(0.7 - Double(idx) * 0.15)
            }
        }
    }

    // MARK: - Empty State Section

    private var emptyStateSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "storefront")
                .font(.system(size: 34))
                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                .padding(.top, 12)

            Text(Language.get("PickupStore_Empty", alter: "لا توجد متاجر استلام متاحة حالياً"))
                .font(AdminType.headlineBold)
                .foregroundColor(AdminSurface.primaryText)

            Text(Language.get("PickupStore_EmptyCaption", alter: "يرجى مراجعة إعدادات فروع الشركة أو طلب المساعدة من المشرف."))
                .font(AdminType.caption1)
                .foregroundColor(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )
        )
    }

    // MARK: - Sticky Bottom Action Dock

    private var stickyActionDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline.opacity(0.5))

            HStack(spacing: 12) {
                // Secondary Cancel Button
                Button(action: onCancel) {
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(AdminType.headlineBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(maxWidth: 110)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AdminSurface.control)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AdminSurface.hairline, lineWidth: 1)
                                )
                        )
                }

                // Primary Confirm & Dispatch CTA
                let canConfirm = viewModel.selectedBranchId != nil && !viewModel.isLoading && viewModel.errorMessage == nil

                Button(action: {
                    guard canConfirm, viewModel.validateSession() else { return }
                    let generator = UINotificationFeedbackGenerator()
                    generator.prepare()
                    generator.notificationOccurred(.success)
                    onConfirm(viewModel.selectedBranchId.flatMap { $0.isEmpty ? nil : $0 })
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))

                        Text(Language.get("PickupStore_Confirm", alter: "تأكيد واستدعاء المندوب"))
                            .font(AdminType.headlineBold)
                    }
                    .foregroundColor(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                canConfirm
                                    ? LinearGradient(
                                        colors: [
                                            AdminSurface.primary,
                                            Color(red: 0.93, green: 0.28, blue: 0.44)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [AdminSurface.control, AdminSurface.control],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                            )
                            .shadow(
                                color: canConfirm
                                    ? AdminSurface.primary.opacity(0.38)
                                    : Color.clear,
                                radius: 10,
                                x: 0,
                                y: 4
                            )
                    )
                    .opacity(canConfirm ? 1.0 : 0.45)
                }
                .disabled(!canConfirm)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(
                AdminSurface.card
                    .opacity(0.96)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }
}

// MARK: - Objective-C Launcher Bridge

@objc(PPDeliveryPickupStoreLauncher)
@MainActor
public final class PPDeliveryPickupStoreLauncher: NSObject {
    @objc(presentForRecord:from:completion:) public static func present(
        for record: PPFulfillmentRecord,
        from presenter: UIViewController?,
        completion: @escaping (String?, Bool) -> Void
    ) {
        assert(Thread.isMainThread, "Pickup store presentation must run on the main thread.")

        var targetPresenter = presenter
        if targetPresenter == nil {
            for scene in UIApplication.shared.connectedScenes {
                guard scene.activationState == .foregroundActive,
                      let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows where window.isKeyWindow {
                    targetPresenter = window.rootViewController
                    break
                }
                if targetPresenter != nil { break }
            }
        }

        while let current = targetPresenter {
            if let presented = current.presentedViewController, !presented.isBeingDismissed {
                targetPresenter = presented
            } else if let nav = current as? UINavigationController, let visible = nav.visibleViewController {
                targetPresenter = visible
            } else if let tab = current as? UITabBarController, let selected = tab.selectedViewController {
                targetPresenter = selected
            } else {
                break
            }
        }

        guard let topVC = targetPresenter,
              !topVC.isBeingDismissed,
              !(topVC.presentedViewController?.isBeingDismissed ?? false) else {
            completion(nil, false)
            return
        }

        var isCompleted = false
        weak var hostedController: UIHostingController<PPDeliveryPickupStoreSheet>? = nil

        let sheetView = PPDeliveryPickupStoreSheet(
            record: record,
            onConfirm: { branchId in
                guard !isCompleted else { return }
                isCompleted = true
                hostedController?.dismiss(animated: true) {
                    completion(branchId, true)
                }
            },
            onCancel: {
                guard !isCompleted else { return }
                isCompleted = true
                hostedController?.dismiss(animated: true) {
                    completion(nil, false)
                }
            }
        )

        let hosting = UIHostingController(rootView: sheetView)
        hostedController = hosting
        hosting.isModalInPresentation = true
        hosting.modalPresentationStyle = .pageSheet

        if let sheet = hosting.sheetPresentationController {
            sheet.prefersGrabberVisible = false
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .custom { context in
                        min(680.0, context.maximumDetentValue * 0.90)
                    },
                    .large()
                ]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            if #available(iOS 15.0, *) {
                sheet.preferredCornerRadius = 26
            }
        }

        topVC.present(hosting, animated: true, completion: nil)
    }
}
