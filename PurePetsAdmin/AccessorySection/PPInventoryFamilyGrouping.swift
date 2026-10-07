//
//  PPInventoryFamilyGrouping.swift
//  PurePetsAdmin
//
//  Collapses the accessories inventory list so one logical product appears once
//  instead of once per colour.
//
//  ── Why grouping, not replacing ────────────────────────────────────────────
//  A family row is a navigation wrapper around the same exact per-colour
//  `PetAccessory` records the inventory list already owns. Expanding selects ONE
//  color and shows a compact child inspector rather than stacking full duplicate
//  product cards. The safety argument is unchanged:
//
//    • every stock action (adjust, lots, damage, cycle count, quarantine,
//      transfer, POS hand-off, delete) stays bound to the exact `PetAccessory`;
//    • an ambiguous "which colour did you mean?" mutation is not representable,
//      because family-level UI only selects a member and never mutates stock;
//    • a product with no family renders through the identical code path it used
//      before, so existing behaviour is untouched.
//
//  ── Why no family document read ────────────────────────────────────────────
//  Everything the row needs — colour, ordering, default flag, family id — is
//  already stamped on each member product by the server. Grouping therefore
//  costs zero extra Firestore reads and cannot introduce an N+1 fetch. The
//  family document remains the ordering authority for the *editor*, which loads
//  it explicitly.
//

import SwiftUI

// MARK: - Grouping

enum PPInventoryDisplayGroup: Identifiable {
    /// A product with no colour family. Renders exactly as it always has.
    case single(PetAccessory)
    /// Two or more colours of one logical product, in server sort order.
    case family(familyId: String, members: [PetAccessory])

    var id: String {
        switch self {
        case .single(let item): return "item:\(item.accessoryID)"
        case .family(let familyId, _): return "family:\(familyId)"
        }
    }

    var members: [PetAccessory] {
        switch self {
        case .single(let item): return [item]
        case .family(_, let members): return members
        }
    }

    /// Groups a filtered list, preserving the incoming order.
    ///
    /// A family takes the list position of its first-appearing member, so the
    /// active sort (newest, name, stock) still decides where the product sits.
    /// A family with only one member visible — because a filter or search
    /// excluded its siblings — is deliberately rendered as a plain row: showing
    /// a "3 colours" header while two are filtered out would be a lie.
    static func grouped(_ items: [PetAccessory]) -> [PPInventoryDisplayGroup] {
        var order: [String] = []
        var byFamily: [String: [PetAccessory]] = [:]
        var singles: [String: PetAccessory] = [:]

        for item in items {
            let familyId = (item.productFamilyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if familyId.isEmpty {
                let key = "item:\(item.accessoryID)"
                order.append(key)
                singles[key] = item
            } else {
                let key = "family:\(familyId)"
                if byFamily[familyId] == nil {
                    order.append(key)
                    byFamily[familyId] = []
                }
                byFamily[familyId]?.append(item)
            }
        }

        return order.compactMap { key in
            if let item = singles[key] { return .single(item) }
            let familyId = String(key.dropFirst("family:".count))
            guard let members = byFamily[familyId], !members.isEmpty else { return nil }
            if members.count == 1 { return .single(members[0]) }
            let sorted = members.sorted { lhs, rhs in
                lhs.variantSortOrder == rhs.variantSortOrder
                    ? lhs.accessoryID < rhs.accessoryID
                    : lhs.variantSortOrder < rhs.variantSortOrder
            }
            return .family(familyId: familyId, members: sorted)
        }
    }
}

// MARK: - Family row

/// The same displayed quantity and stock context as the exact-product inspector.
/// A missing quantity is unresolved state, never stock zero.
struct PPInventoryFamilyStockSnapshot {
    let quantity: Int?
    let caption: String?
}

/// One inventory family and its exact sellable options.
///
/// The family overview never mutates stock. Selecting an option opens the
/// existing exact-product inspector owned by the inventory list.
struct PPInventoryFamilyRow: View {
    private struct PositionedMember: Identifiable {
        let member: PetAccessory
        let index: Int
        var id: String { member.accessoryID }
    }

    let members: [PetAccessory]
    @Binding var isExpanded: Bool
    @Binding var selectedProductId: String
    /// Availability for one option, supplied by the list from the inspector's
    /// branch projection or its catalog quantity when no branch is selected.
    let availability: (PetAccessory) -> PPInventoryFamilyStockSnapshot
    /// Branch-effective default retail price for this exact product.
    /// Returning nil means the price is unresolved and must not be invented.
    let retailPrice: (PetAccessory) -> Double?
    let lowStockThreshold: Int
    var showsAccentLine: Bool = true

    @ObservedObject private var branchInventory = PPBranchInventoryService.shared
    @ObservedObject private var branchContext = BranchContextStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var defaultMember: PetAccessory {
        members.first { $0.isDefaultVariant } ?? members[0]
    }

    private var positionedMembers: [PositionedMember] {
        members.enumerated().map { PositionedMember(member: $0.element, index: $0.offset) }
    }

    /// While expanded, the parent image follows the selected sellable product.
    /// Collapsed families return to the default marketplace member so the list
    /// remains stable and immediately recognizable.
    private var heroMember: PetAccessory {
        guard isExpanded else { return defaultMember }
        return members.first { $0.accessoryID == selectedProductId } ?? defaultMember
    }

    /// A quiet brand cue distinguishes a logical family from the exact stock
    /// inspector revealed below it without inventing new state.
    private var familyAccent: Color {
        AdminSurface.primary
    }

    private var familyDimension: PPAccessoryVariantDimensionType {
        PetAccessory.detectFamilyDimension(members: members)
    }

    private var activeMembers: [PetAccessory] {
        members.filter { !$0.isArchived }
    }

    private var totalAvailable: Int? {
        guard !activeMembers.isEmpty else { return 0 }
        let quantities = activeMembers.map { availability($0).quantity }
        guard quantities.allSatisfy({ $0 != nil }) else { return nil }
        return quantities.reduce(0) { $0 + ($1 ?? 0) }
    }

    private var stockContextCaption: String? {
        for member in activeMembers {
            if let caption = availability(member).caption { return caption }
        }
        return nil
    }

    private var archivedCount: Int {
        members.count - activeMembers.count
    }

    private var resolvedPrices: [Double] {
        activeMembers.compactMap(retailPrice).filter { $0.isFinite && $0 >= 0 }.sorted()
    }

    private var priceSummary: String? {
        guard !activeMembers.isEmpty, resolvedPrices.count == activeMembers.count else { return nil }
        guard let minimum = resolvedPrices.first, let maximum = resolvedPrices.last else { return nil }
        if abs(maximum - minimum) < 0.005 {
            return PetAccessory.formatCurrency(NSNumber(value: minimum))
        }
        return String(
            format: Language.get("Inventory_Family_PriceRange_Format", alter: "%@ – %@"),
            PetAccessory.formatCurrency(NSNumber(value: minimum)),
            PetAccessory.formatCurrency(NSNumber(value: maximum))
        )
    }

    private var hasLowStockOption: Bool {
        activeMembers.contains { member in
            guard let quantity = availability(member).quantity else { return false }
            return quantity > 0 && quantity <= lowStockThreshold
        }
    }

    private var hasOutOfStockOption: Bool {
        activeMembers.contains { (availability($0).quantity ?? Int.max) <= 0 }
    }

    private var familyOptionsSummary: String? {
        let titles = activeMembers.compactMap { member -> String? in
            let title = (member.resolvedOptionDisplayTitle ?? member.pos_variantDisplayName).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }
        guard !titles.isEmpty else { return nil }
        var unique: [String] = []
        for t in titles where !unique.contains(t) {
            unique.append(t)
        }
        guard !unique.isEmpty else { return nil }
        if unique.count <= 4 {
            return unique.joined(separator: " • ")
        }
        let head = unique.prefix(3).joined(separator: " • ")
        let remaining = unique.count - 3
        return "\(head) +\(remaining)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // Single source of truth for the disclosure curve. The list used to
                // wrap this same binding in a different spring, so one tap drove two
                // competing animations.
                withAnimation(AdminAnimation.motion(AdminAnimation.disclosure, reduceMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                header
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(AdminSpacing.base)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(isExpanded
                ? familyDimension.collapseHint
                : familyDimension.expandHint)
            .accessibilityAddTraits(.isButton)

            swatchSummary
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isExpanded ? Color.clear : AdminSurface.surface)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isExpanded ? Color.clear : AdminSurface.borderSubtle.opacity(0.65), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(isExpanded ? 0 : 0.03), radius: 8, x: 0, y: 3)
        .overlay(alignment: .leading) {
            if isExpanded && showsAccentLine {
                FamilyExpandedAccentSpineView(color: familyAccent)
                    .padding(.vertical, AdminSpacing.base)
                    .transition(.opacity)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onChange(of: members.map(\.accessoryID), initial: true) { _, productIds in
            // Commit the visible fallback so clearing a filter cannot silently
            // restore a previously hidden product beneath the inspector controls.
            guard isExpanded, !productIds.contains(selectedProductId) else { return }
            selectedProductId = defaultMember.accessoryID
        }
    }

    private var metricsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AdminSpacing.md))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .top, spacing: AdminSpacing.md) {
                if !dynamicTypeSize.isAccessibilitySize {
                    AdminRemoteImage(
                        url: PetAccessory.firstImageURL(for: heroMember),
                        contentMode: .fill,
                        targetSize: CGSize(width: 68, height: 68)
                    ) {
                        ZStack {
                            AdminSurface.control
                            Image(systemName: "photo")
                                .foregroundStyle(AdminCommandInk.tertiary)
                        }
                    }
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: AdminStroke.hairline)
                    }
                    .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: AdminSpacing.sm) {
                    Text(expandedFamilyTitle)
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: AdminSpacing.xs) {
                        Text(String(format: familyDimension.shortCountFormat,
                                    NSNumber(value: activeMembers.count)))
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, AdminSpacing.sm)
                            .padding(.vertical, AdminSpacing.xs)
                            .background(AdminSurface.primarySoft, in: Capsule())

                        if let summary = familyOptionsSummary {
                            Text(summary)
                                .font(AdminType.caption)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(AdminAnimation.motion(AdminAnimation.disclosure,
                                                     reduceMotion: reduceMotion), value: isExpanded)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.control, in: Circle())
                    .accessibilityHidden(true)
            }

            metricsLayout {
                HStack(spacing: AdminSpacing.xs) {
                    Circle()
                        .fill(totalAvailable == nil ? AdminCommandInk.secondary
                              : totalAvailable == 0 ? AdminSurface.crimson : AdminSurface.emerald)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    if let totalAvailable {
                        Text(String(format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                                    NSNumber(value: totalAvailable)))
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(stockContextCaption ?? Language.get("InventoryCell_Unconfirmed", alter: "الرصيد غير مؤكد · اسحب للتحديث"))
                            .font(AdminType.footnoteBold)
                            .foregroundStyle(AdminCommandInk.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }

                if let priceSummary {
                    Text(priceSummary.normalizedEnglishDigits)
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    Text(Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminCommandInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if (totalAvailable != nil && stockContextCaption != nil)
                || hasOutOfStockOption || hasLowStockOption || archivedCount > 0 {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    if totalAvailable != nil, let stockContextCaption {
                        statusNote(stockContextCaption, color: AdminCommandInk.secondary)
                    }
                    if hasOutOfStockOption {
                        statusNote(familyDimension.outOfStockBadgeText, color: AdminSurface.crimson)
                    }
                    if hasLowStockOption {
                        statusNote(Language.get("Inventory_Family_HasLowStock", alter: "مخزون منخفض"),
                                   color: AdminSurface.amber)
                    }
                    if archivedCount > 0 {
                        statusNote(String(format: Language.get("Inventory_Family_ArchivedCount", alter: "%@ مؤرشف"),
                                          NSNumber(value: archivedCount)),
                                   color: AdminCommandInk.secondary)
                    }
                }
            }
        }
        .multilineTextAlignment(.leading)
    }

    private func statusNote(_ text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var expandedFamilyTitle: String {
        let primary = (defaultMember.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let english = (defaultMember.nameEn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = Language.isRTL() ? primary : english
        let fallback = Language.isRTL() ? english : primary
        return !preferred.isEmpty ? preferred : (!fallback.isEmpty ? fallback
            : Language.get("InventoryCell_Unnamed", alter: "صنف بدون اسم"))

    }

    /// One continuous option shelf in both row states. Selecting a tile opens
    /// the exact product inspector; the shelf never writes inventory itself.
    private var swatchSummary: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: AdminStroke.hairline)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AdminSpacing.sm) {
                    ForEach(positionedMembers) { position in
                        optionTile(position.member, index: position.index)
                    }
                }
                .padding(AdminSpacing.base)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: AdminSpacing.sm) {
                            ForEach(positionedMembers) { position in
                                optionTile(position.member, index: position.index)
                                    .frame(width: horizontalSizeClass == .compact ? 190 : 210)
                                    .id(position.id)
                            }
                        }
                        .padding(.horizontal, AdminSpacing.base)
                        .padding(.vertical, AdminSpacing.md)
                    }
                    .onAppear {
                        if isExpanded {
                            proxy.scrollTo(heroMember.accessoryID, anchor: .center)
                        }
                    }
                    .onChange(of: heroMember.accessoryID) { productId in
                        guard isExpanded else { return }
                        withAnimation(AdminAnimation.motion(AdminAnimation.fast, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(productId, anchor: .center)
                        }
                    }
                    .onChange(of: isExpanded) { expanded in
                        if expanded { proxy.scrollTo(heroMember.accessoryID, anchor: .center) }
                    }
                }
            }
        }
        .background(AdminSurface.backgroundSecondary.opacity(0.55))
        .accessibilityElement(children: .contain)
    }

    private func optionTile(_ member: PetAccessory, index: Int) -> some View {
        // Filtering can remove a selected member. The inspector then falls back
        // to the default product; the rail must follow that same exact identity.
        let selected = isExpanded && member.accessoryID == heroMember.accessoryID
        let stock = availability(member)
        let colour = member.pos_hasRealColor ? member.pos_variantColor : nil
        let stateColor: Color = {
            guard !member.isArchived, stock.caption == nil,
                  let quantity = stock.quantity else { return AdminCommandInk.secondary }
            if quantity <= 0 { return AdminSurface.crimson }
            if quantity <= lowStockThreshold { return AdminSurface.amber }
            return AdminSurface.emerald
        }()
        let shape = RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)

        return Button {
            guard !selected || selectedProductId != member.accessoryID else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(AdminAnimation.motion(AdminAnimation.fast, reduceMotion: reduceMotion)) {
                selectedProductId = member.accessoryID
                isExpanded = true
            }
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.md) {
                HStack(alignment: .top, spacing: AdminSpacing.sm) {
                    Group {
                        if let colour {
                            Circle()
                                .fill(Color(uiColor: colour.uiColor))
                                .overlay {
                                    Circle()
                                        .strokeBorder(AdminSurface.primaryText.opacity(
                                            colour.requiresContrastBorder ? 0.4 : 0.15
                                        ), lineWidth: 1)
                                }
                                .frame(width: 18, height: 18)
                        } else {
                            let badge = member.pos_variantShortBadge.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !badge.isEmpty && badge.count <= 4 {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(AdminSurface.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            } else {
                                Image(systemName: member.pos_variantDimension.sfSymbolName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AdminSurface.primary)
                            }
                        }
                    }
                    .frame(width: 28, height: 28)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                    Text(member.pos_variantDisplayName)
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay(alignment: .bottom) {
                    // Draw within the existing gap without affecting tile height.
                    Rectangle()
                        .fill(selected ? AdminSurface.primary : AdminSurface.hairline)
                        .frame(height: AdminStroke.hairline)
                        .offset(y: (AdminSpacing.md + AdminStroke.hairline) / 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                metricsLayout {
                    HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.xs) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)

                        Text(optionStockText(member: member, stock: stock))
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: AdminSpacing.xs)
                    }

                    if let price = retailPrice(member) {
                        Text(PetAccessory.formatCurrency(NSNumber(value: price)).normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.layoutDirection, .leftToRight)
                    } else {
                        Text(Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح"))
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminCommandInk.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .padding(AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(selected ? AdminSurface.primarySoft : AdminSurface.surface, in: shape)
            .overlay {
                shape.strokeBorder(selected ? AdminSurface.primary : AdminSurface.hairline,
                                   lineWidth: selected || colorSchemeContrast == .increased ? 1.5 : 0.75)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(selected ? AdminSurface.primary : stateColor)
                    .frame(width: 28, height: 3)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(optionAccessibilityLabel(member: member, stock: stock))
        .accessibilityHint(familyDimension.selectHint)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("inventory.family.option.\(member.accessoryID)")
    }

    private func optionStockText(member: PetAccessory, stock: PPInventoryFamilyStockSnapshot) -> String {
        if stock.quantity == nil, let caption = stock.caption { return caption }
        if member.isArchived { return Language.get("Variant_State_Archived", alter: "مؤرشف") }
        guard let quantity = stock.quantity else {
            return stock.caption ?? Language.get("InventoryCell_Unconfirmed", alter: "الرصيد غير مؤكد · اسحب للتحديث")
        }
        if quantity <= 0 { return Language.get("Variant_State_OutOfStock", alter: "غير متوفر") }
        return String(format: Language.get("Variant_State_AvailableCount", alter: "%@ متوفر"),
                      NSNumber(value: quantity))
    }

    private func optionAccessibilityLabel(
        member: PetAccessory,
        stock: PPInventoryFamilyStockSnapshot
    ) -> String {
        var parts: [String] = [member.pos_variantDisplayName]
        parts.append(optionStockText(member: member, stock: stock))
        if stock.quantity != nil, let caption = stock.caption { parts.append(caption) }
        if let price = retailPrice(member) {
            parts.append(String(
                format: Language.get("Variant_Price_A11y", alter: "السعر %@"),
                PetAccessory.formatCurrency(NSNumber(value: price))
            ))
        } else {
            parts.append(Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح"))
        }
        if member.isDefaultVariant {
            parts.append(Language.get("Inventory_Family_DefaultOption", alter: "الخيار الافتراضي"))
        }
        return parts.joined(separator: Language.isRTL() ? "، " : ", ")
    }

    private var accessibilitySummary: String {
        var parts = [expandedFamilyTitle,
                     String(format: familyDimension.shortCountFormat, NSNumber(value: activeMembers.count))]
        if let familyOptionsSummary {
            parts.append(String(format: Language.get("Inventory_Family_OptionsSummary_A11y", alter: "الخيارات: %@"), familyOptionsSummary))
        }
        if let totalAvailable {
            parts.append(String(format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                                NSNumber(value: totalAvailable)))
        } else {
            parts.append(stockContextCaption ?? Language.get("InventoryCell_Unconfirmed", alter: "الرصيد غير مؤكد · اسحب للتحديث"))
        }
        if totalAvailable != nil, let stockContextCaption { parts.append(stockContextCaption) }
        if let priceSummary {
            parts.append(String(format: Language.get("Inventory_Family_Price_A11y", alter: "نطاق السعر: %@"),
                                priceSummary))
        } else {
            parts.append(Language.get("Inventory_Price_Unavailable", alter: "السعر غير متاح"))
        }
        if hasOutOfStockOption { parts.append(familyDimension.outOfStockBadgeText) }
        if hasLowStockOption { parts.append(Language.get("Inventory_Family_HasLowStock", alter: "مخزون منخفض")) }
        if archivedCount > 0 {
            parts.append(String(format: Language.get("Inventory_Family_ArchivedCount", alter: "%@ مؤرشف"),
                                NSNumber(value: archivedCount)))
        }
        return parts.joined(separator: Language.isRTL() ? "، " : ", ")
    }
}

// MARK: - Family Grouping Shapes & Geometry

/// An UnevenRoundedRectangle that correctly mirrors leading and trailing radii
/// for RTL layouts (e.g. Arabic), where leading is on the right.
func PPFamilyCardShape(
    topLeading: CGFloat,
    bottomLeading: CGFloat,
    bottomTrailing: CGFloat,
    topTrailing: CGFloat,
    isRTL: Bool = Language.isRTL(),
    style: RoundedCornerStyle = .continuous
) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(
            topLeading: isRTL ? topTrailing : topLeading,
            bottomLeading: isRTL ? bottomTrailing : bottomLeading,
            bottomTrailing: isRTL ? bottomLeading : bottomTrailing,
            topTrailing: isRTL ? topLeading : topTrailing
        ),
        style: style
    )
}

/// Continuous accent spine tracing the edge of an expanded product family.
/// Wraps around the corner of the parent card, runs straight down the edge
/// bridging parent and child, and wraps around the corner of the child inspector.
struct FamilyExpandedAccentSpineShape: Shape {
    var topArmLength: CGFloat = 20
    var bottomArmLength: CGFloat = 18
    var topRadius: CGFloat = 18
    var bottomRadius: CGFloat = 16
    var lineWidth: CGFloat = 1.5
    var onRightSide: Bool = true

    init(
        topArmLength: CGFloat = 20,
        bottomArmLength: CGFloat = 18,
        topRadius: CGFloat = 18,
        bottomRadius: CGFloat = 16,
        lineWidth: CGFloat = 1.5,
        onRightSide: Bool = true,
        layoutDirection: LayoutDirection? = nil
    ) {
        self.topArmLength = topArmLength
        self.bottomArmLength = bottomArmLength
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.lineWidth = lineWidth
        self.onRightSide = onRightSide
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let halfLine = lineWidth / 2.0

        if onRightSide {
            let rightX = rect.maxX - halfLine
            let topY = rect.minY + halfLine
            let bottomY = rect.maxY - halfLine

            let safeTopRadius = max(0, min(topRadius - halfLine, (rect.height / 2) - halfLine))
            let safeBottomRadius = max(0, min(bottomRadius - halfLine, (rect.height / 2) - halfLine))

            let topStartX = max(rect.minX + halfLine, rightX - topArmLength)
            let bottomEndX = max(rect.minX + halfLine, rightX - bottomArmLength)

            // Start at top arm (left of top-right corner)
            path.move(to: CGPoint(x: topStartX, y: topY))
            // Horizontal segment to the top arc start
            path.addLine(to: CGPoint(x: rightX - safeTopRadius, y: topY))
            // Arc around top-right corner
            path.addArc(
                center: CGPoint(x: rightX - safeTopRadius, y: topY + safeTopRadius),
                radius: safeTopRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            // Vertical spine down the right edge bridging parent and child
            path.addLine(to: CGPoint(x: rightX, y: bottomY - safeBottomRadius))
            // Arc around bottom-right corner
            path.addArc(
                center: CGPoint(x: rightX - safeBottomRadius, y: bottomY - safeBottomRadius),
                radius: safeBottomRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            // Horizontal segment along bottom of child card
            path.addLine(to: CGPoint(x: bottomEndX, y: bottomY))
        } else {
            let leftX = rect.minX + halfLine
            let topY = rect.minY + halfLine
            let bottomY = rect.maxY - halfLine

            let safeTopRadius = max(0, min(topRadius - halfLine, (rect.height / 2) - halfLine))
            let safeBottomRadius = max(0, min(bottomRadius - halfLine, (rect.height / 2) - halfLine))

            let topStartX = min(rect.maxX - halfLine, leftX + topArmLength)
            let bottomEndX = min(rect.maxX - halfLine, leftX + bottomArmLength)

            // Start at top arm
            path.move(to: CGPoint(x: topStartX, y: topY))
            // Horizontal segment to top arc start
            path.addLine(to: CGPoint(x: leftX + safeTopRadius, y: topY))
            // Arc around top-left corner
            path.addArc(
                center: CGPoint(x: leftX + safeTopRadius, y: topY + safeTopRadius),
                radius: safeTopRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(180),
                clockwise: true
            )
            // Vertical spine down left edge
            path.addLine(to: CGPoint(x: leftX, y: bottomY - safeBottomRadius))
            // Arc around bottom-left corner
            path.addArc(
                center: CGPoint(x: leftX + safeBottomRadius, y: bottomY - safeBottomRadius),
                radius: safeBottomRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
            // Horizontal segment along bottom of child card
            path.addLine(to: CGPoint(x: bottomEndX, y: bottomY))
        }

        return path
    }
}

/// A quiet binding edge for the one expanded family workspace. Placement is
/// semantic leading at the call site; no physical coordinates or second RTL flip.
/// The round origin and short foot make the extent legible without outlining cards.
struct FamilyExpandedAccentSpineView: View {
    let color: Color
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    private var spineColor: Color {
        colorScheme == .dark || colorSchemeContrast == .increased ? AdminSurface.primary : color
    }

    var body: some View {
        VStack(spacing: AdminSpacing.xs) {
            Circle()
                .fill(spineColor)
                .overlay { Circle().strokeBorder(AdminSurface.primaryText.opacity(0.24), lineWidth: 0.5) }
                .frame(width: 6, height: 6)

            Capsule(style: .continuous)
                .fill(spineColor.opacity(colorSchemeContrast == .increased ? 0.8 : 0.35))
                .frame(width: colorSchemeContrast == .increased ? 2 : 1)
                .frame(maxHeight: .infinity)

            Capsule(style: .continuous)
                .fill(spineColor)
                .frame(width: 3, height: AdminSpacing.lg)
        }
        .frame(width: AdminSpacing.sm)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
