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

/// Collapsed header for one colour family.
///
/// Presents merchandising identity and a per-colour availability summary. It
/// deliberately exposes **no** family-level stock mutation: a color selection
/// expands one exact sellable member into the compact child inspector owned by
/// the inventory list.
struct PPInventoryFamilyRow: View {
    let members: [PetAccessory]
    @Binding var isExpanded: Bool
    @Binding var selectedProductId: String
    /// Live availability for one colour, supplied by the list so the family row
    /// uses the same branch projection as every other row rather than a second
    /// source of truth.
    let availability: (PetAccessory) -> Int
    /// Branch-effective default retail price for this exact color product.
    /// Returning nil means the price is unresolved and must not be invented.
    let retailPrice: (PetAccessory) -> Double?
    let lowStockThreshold: Int
    var showsAccentLine: Bool = true

    @ObservedObject private var branchInventory = PPBranchInventoryService.shared
    @ObservedObject private var branchContext = BranchContextStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var defaultMember: PetAccessory {
        members.first { $0.isDefaultVariant } ?? members[0]
    }

    /// While expanded, the parent vitrine follows the selected sellable color.
    /// Collapsed families return to the default marketplace member so the list
    /// remains stable and immediately recognizable.
    private var heroMember: PetAccessory {
        guard isExpanded else { return defaultMember }
        return members.first { $0.accessoryID == selectedProductId } ?? defaultMember
    }

    /// A quiet brand cue distinguishes a logical colour family from the
    /// concrete stock cards revealed below it without inventing new state.
    private var familyAccent: Color {
        AdminSurface.primary
    }

    private var familyDimension: PPAccessoryVariantDimensionType {
        PetAccessory.detectFamilyDimension(members: members)
    }

    private var activeMembers: [PetAccessory] {
        members.filter { !$0.isArchived }
    }

    private var totalAvailable: Int {
        activeMembers.reduce(0) { $0 + availability($1) }
    }

    private var archivedCount: Int {
        members.count - activeMembers.count
    }

    private var resolvedPrices: [Double] {
        activeMembers.compactMap(retailPrice).filter { $0.isFinite && $0 >= 0 }.sorted()
    }

    private var priceSummary: String? {
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

    private var hasLowStockColour: Bool {
        activeMembers.contains { member in
            let quantity = availability(member)
            return quantity > 0 && quantity <= lowStockThreshold
        }
    }

    private var hasOutOfStockColour: Bool {
        activeMembers.contains { availability($0) <= 0 }
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
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(isExpanded
                ? familyDimension.collapseHint
                : familyDimension.expandHint)
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                expandedOptions
            } else {
                swatchSummary
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isExpanded ? Color.clear : Color.white)
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
    }

    // The open family is a single workspace. Options become readable tabs;
    // only the closed row keeps the original compact summary chips.
    private var expandedOptions: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AdminSpacing.xs) {
                    ForEach(members, id: \.accessoryID) { member in
                        expandedOption(member)
                    }
                }
                .padding(.horizontal, AdminSpacing.base)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: AdminSpacing.xs) {
                            ForEach(members, id: \.accessoryID) { member in
                                expandedOption(member)
                                    .frame(width: 156)
                                    .id(member.accessoryID)
                            }
                        }
                        .padding(.horizontal, AdminSpacing.base)
                    }
                    .onAppear { proxy.scrollTo(heroMember.accessoryID, anchor: .center) }
                    .onChange(of: heroMember.accessoryID) { productId in
                        withAnimation(AdminAnimation.motion(AdminAnimation.fast, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(productId, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.bottom, AdminSpacing.md)
        .accessibilityElement(children: .contain)
    }

    private func expandedOption(_ member: PetAccessory) -> some View {
        let colour = member.pos_hasRealColor ? member.pos_variantColor : nil
        // Filtering can remove a previously selected member. The list inspector
        // then displays the default; the visible selection must follow it too.
        let selected = member.accessoryID == heroMember.accessoryID
        let quantity = availability(member)
        let shape = RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)

        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(AdminAnimation.motion(AdminAnimation.fast, reduceMotion: reduceMotion)) {
                selectedProductId = member.accessoryID
            }
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.sm) {
                    if let colour {
                        Circle()
                            .fill(Color(uiColor: colour.uiColor))
                            .overlay {
                                Circle().strokeBorder(AdminSurface.primaryText.opacity(0.25), lineWidth: 1)
                            }
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: member.pos_variantDimension.outlineSymbolName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                            .accessibilityHidden(true)
                    }

                    Text(member.pos_variantDisplayName)
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                        .opacity(selected ? 1 : 0)
                        .accessibilityHidden(true)
                }

                Text(member.isArchived
                     ? Language.get("Variant_State_Archived", alter: "مؤرشف")
                     : String(format: Language.get("Variant_State_AvailableCount", alter: "%@ متوفر"),
                              NSNumber(value: quantity)))
                    .font(AdminType.caption)
                    .foregroundStyle(member.isArchived ? AdminCommandInk.secondary
                                     : quantity <= 0 ? AdminSurface.crimson : AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let price = retailPrice(member) {
                    Text(PetAccessory.formatCurrency(NSNumber(value: price)).normalizedEnglishDigits)
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(AdminSpacing.md)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
            .background(selected ? AdminSurface.control : Color.clear, in: shape)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(AdminSurface.primary)
                    .frame(height: colorSchemeContrast == .increased ? 3 : 2)
                    .padding(.horizontal, AdminSpacing.md)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(colourAccessibilityLabel(colour: colour, member: member, quantity: quantity))
        .accessibilityHint(familyDimension.selectHint)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("inventory.family.option.\(member.accessoryID)")
    }

    private var header: some View {
        HStack(spacing: 12) {
            // The hero follows the selected color while expanded and returns to
            // the default marketplace member when the family is collapsed.
            if !isExpanded || !dynamicTypeSize.isAccessibilitySize {
                AsyncImage(url: PetAccessory.firstImageURL(for: heroMember)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(AdminCommandInk.tertiary)
                    default:
                        ProgressView()
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if isExpanded {
                expandedHeaderDetails
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(defaultMember.name ?? "")
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(String(
                            format: familyDimension.shortCountFormat,
                            NSNumber(value: activeMembers.count)
                        ))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primary)

                        Text(verbatim: "·")
                            .foregroundStyle(AdminCommandInk.tertiary)

                        Text(String(
                            format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                            NSNumber(value: totalAvailable)
                        ))
                        .font(AdminType.caption2)
                        .foregroundStyle(totalAvailable <= 0 ? AdminSurface.crimson : AdminCommandInk.secondary)
                    }

                    if let priceSummary {
                        HStack(spacing: 4) {
                            Image(systemName: resolvedPrices.count > 1 && (resolvedPrices.last ?? 0) != (resolvedPrices.first ?? 0)
                                ? "arrow.left.and.right"
                                : "tag.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(priceSummary.normalizedEnglishDigits)
                                .font(AdminType.caption2Bold)
                                .lineLimit(1)
                        }
                        .foregroundStyle(AdminCommandInk.secondary)
                        .accessibilityLabel(String(
                            format: Language.get("Inventory_Family_Price_A11y", alter: "نطاق السعر: %@"),
                            priceSummary
                        ))
                    }

                    if hasLowStockColour || hasOutOfStockColour || archivedCount > 0 {
                        HStack(spacing: 6) {
                            if hasOutOfStockColour {
                                badge(
                                    familyDimension.outOfStockBadgeText,
                                    systemImage: "exclamationmark.octagon.fill",
                                    tint: AdminSurface.crimson
                                )
                            }
                            if hasLowStockColour {
                                badge(
                                    Language.get("Inventory_Family_HasLowStock", alter: "مخزون منخفض"),
                                    systemImage: "exclamationmark.triangle.fill",
                                    tint: AdminSurface.amber
                                )
                            }
                            if archivedCount > 0 {
                                badge(
                                    String(
                                        format: Language.get("Inventory_Family_ArchivedCount", alter: "%@ مؤرشف"),
                                        NSNumber(value: archivedCount)
                                    ),
                                    systemImage: "archivebox.fill",
                                    tint: AdminCommandInk.tertiary
                                )
                            }
                        }
                    }
                }

            }

            Spacer(minLength: 4)

            // A single glyph that rotates, rather than two glyphs swapped. Swapping
            // `chevron.down` for `chevron.up` pops — there is no intermediate state,
            // so the indicator teleports while the panel below it animates. Rotating
            // one chevron ties the indicator to the same spring as the disclosure.
            //
            // `chevron.down` rotated 180° is visually identical to `chevron.up`, and
            // a vertical chevron needs no RTL mirroring.
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AdminCommandInk.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(
                    AdminAnimation.motion(AdminAnimation.disclosure, reduceMotion: reduceMotion),
                    value: isExpanded
                )
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
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

    private var expandedHeaderDetails: some View {
        return VStack(alignment: .leading, spacing: AdminSpacing.xs) {
            Text(expandedFamilyTitle)
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(format: familyDimension.shortCountFormat, NSNumber(value: activeMembers.count))
                 + " · " + String(format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                                  NSNumber(value: totalAvailable)))
                .font(AdminType.caption)
                .foregroundStyle(AdminCommandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let priceSummary {
                Text(priceSummary.normalizedEnglishDigits)
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminCommandInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasOutOfStockColour {
                expandedFlag(familyDimension.outOfStockBadgeText,
                             symbol: "exclamationmark.circle.fill", color: AdminSurface.crimson)
            }
            if hasLowStockColour {
                expandedFlag(Language.get("Inventory_Family_HasLowStock", alter: "مخزون منخفض"),
                             symbol: "exclamationmark.triangle.fill", color: AdminSurface.amber)
            }
            if archivedCount > 0 {
                expandedFlag(String(format: Language.get("Inventory_Family_ArchivedCount", alter: "%@ مؤرشف"),
                                    NSNumber(value: archivedCount)),
                             symbol: "archivebox.fill", color: AdminCommandInk.secondary)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expandedFlag(_ title: String, symbol: String, color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(AdminType.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func badge(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 8))
            Text(text).font(AdminType.caption2Bold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }

    /// Per-colour selector. The rail is the family navigation surface: tapping
    /// a color selects that exact product and opens its compact child inspector.
    /// Swatch plus text is always used; color is never the only identifier.
    private var swatchSummary: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AdminSurface.borderSubtle.opacity(0.55))
                .frame(height: 0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(members, id: \.accessoryID) { member in
                        let hasRealColor = member.pos_hasRealColor
                        let colour = hasRealColor ? member.pos_variantColor : nil
                        let productAccentColor: Color = colour.map { Color(uiColor: $0.uiColor) } ?? AdminSurface.primary
                        let requiresContrast = colour?.requiresContrastBorder ?? false
                        let quantity = availability(member)
                        let isSelected = !selectedProductId.isEmpty && member.accessoryID == selectedProductId
                        let shortBadge = member.pos_variantShortBadge

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            if reduceMotion {
                                selectedProductId = member.accessoryID
                                isExpanded = true
                            } else {
                                withAnimation(AdminAnimation.motion(AdminAnimation.fast, reduceMotion: reduceMotion)) {
                                    selectedProductId = member.accessoryID
                                    isExpanded = true
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if hasRealColor, let colour = colour {
                                    ZStack {
                                        Circle()
                                            .fill(Color(uiColor: colour.uiColor))
                                            .frame(width: 14, height: 14)
                                        Circle()
                                            .strokeBorder(
                                                colour.requiresContrastBorder
                                                    ? AdminSurface.primaryText.opacity(0.32)
                                                    : Color.clear,
                                                lineWidth: 1
                                            )
                                            .frame(width: 14, height: 14)
                                        if isSelected {
                                            Circle()
                                                .strokeBorder(
                                                    requiresContrast ? AdminSurface.primaryText : productAccentColor,
                                                    lineWidth: 1.5
                                                )
                                                .frame(width: 18.5, height: 18.5)
                                        }
                                    }
                                    .frame(width: 18.5, height: 18.5)
                                } else if !shortBadge.isEmpty {
                                    Text(shortBadge)
                                        .font(Font.custom("Beiruti-Bold", size: 10, relativeTo: .caption2))
                                        .foregroundStyle(isSelected ? AdminSurface.primary : AdminCommandInk.secondary)
                                        .padding(.horizontal, 4.5)
                                        .padding(.vertical, 2)
                                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSelected ? 1 : 0.5)
                                        )
                                } else {
                                    Image(systemName: member.pos_variantDimension.outlineSymbolName)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(isSelected ? AdminSurface.primary : AdminCommandInk.secondary)
                                        .frame(width: 16, height: 16)
                                }

                                Text(member.pos_variantDisplayName)
                                    .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 13, relativeTo: .caption))
                                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminCommandInk.secondary)
                                    .lineLimit(1)

                                Text(verbatim: "\(quantity.englishDigits)")
                                    .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                    .foregroundStyle(
                                        member.isArchived
                                            ? AdminCommandInk.tertiary
                                            : quantity <= 0
                                                ? AdminSurface.crimson
                                                : quantity <= lowStockThreshold
                                                    ? AdminSurface.amber
                                                    : AdminSurface.emerald
                                    )

                                if let price = retailPrice(member) {
                                    Text(verbatim: "·")
                                        .font(Font.custom("Beiruti-Medium", size: 11, relativeTo: .caption2))
                                        .foregroundStyle(AdminCommandInk.tertiary)
                                    Text(PetAccessory.formatCurrency(NSNumber(value: price)).normalizedEnglishDigits)
                                        .font(Font.custom("Beiruti-Bold", size: 13, relativeTo: .caption))
                                        .foregroundStyle(AdminSurface.primaryText)
                                        .lineLimit(1)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isSelected
                                    ? (requiresContrast ? AdminSurface.control : productAccentColor.opacity(0.16))
                                    : (requiresContrast ? Color.white : productAccentColor.opacity(0.06)),
                                in: RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                                    .strokeBorder(
                                        isSelected
                                            ? (requiresContrast ? AdminSurface.primaryText.opacity(0.65) : productAccentColor.opacity(0.75))
                                            : (requiresContrast ? AdminSurface.hairline : productAccentColor.opacity(0.22)),
                                        lineWidth: isSelected ? 1.5 : 0.75
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: 9.5, style: .continuous))
                        .animation(
                            AdminAnimation.motion(AdminAnimation.fast, reduceMotion: reduceMotion),
                            value: isSelected
                        )
                        .opacity(member.isArchived ? 0.55 : 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(colourAccessibilityLabel(
                            colour: colour,
                            member: member,
                            quantity: quantity
                        ))
                        .accessibilityHint(familyDimension.selectHint)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7.5)
            }
        }
        .background(AdminSurface.control.opacity(0.35))
    }

    private func colourAccessibilityLabel(
        colour: PPAccessoryVariantColor?,
        member: PetAccessory,
        quantity: Int
    ) -> String {
        var parts: [String] = [member.pos_variantDisplayName]
        if member.isArchived {
            parts.append(Language.get("Variant_State_Archived", alter: "مؤرشف"))
        } else if quantity <= 0 {
            parts.append(Language.get("Variant_State_OutOfStock", alter: "غير متوفر"))
        } else {
            parts.append(String(
                format: Language.get("Variant_State_AvailableCount", alter: "%@ متوفر"),
                NSNumber(value: quantity)
            ))
        }
        if let price = retailPrice(member) {
            parts.append(String(
                format: Language.get("Variant_Price_A11y", alter: "السعر %@"),
                PetAccessory.formatCurrency(NSNumber(value: price))
            ))
        }
        if member.isDefaultVariant {
            parts.append(isExpanded
                ? Language.get("Inventory_Family_DefaultOption", alter: "الخيار الافتراضي")
                : Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilitySummary: String {
        if isExpanded {
            var parts = [
                expandedFamilyTitle,
                String(format: familyDimension.shortCountFormat, NSNumber(value: activeMembers.count)),
                String(format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                       NSNumber(value: totalAvailable))
            ]
            if let priceSummary { parts.append(priceSummary) }
            return parts.joined(separator: Language.isRTL() ? "، " : ", ")
        }
        var text = String(
            format: Language.get(
                "Inventory_Family_Summary_A11y",
                alter: "%@، %@ ألوان، %@ متوفر إجمالاً"
            ),
            defaultMember.name ?? "",
            NSNumber(value: activeMembers.count),
            NSNumber(value: totalAvailable)
        )
        if let priceSummary {
            text += String(
                format: Language.get("Inventory_Family_Price_A11y_Suffix", alter: "، نطاق السعر %@"),
                priceSummary
            )
        }
        return text
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
