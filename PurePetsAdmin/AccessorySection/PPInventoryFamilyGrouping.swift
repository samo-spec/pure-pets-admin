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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// A quiet category cue distinguishes a logical colour family from the
    /// concrete stock cards revealed below it without inventing new state.
    private var familyAccent: Color {
        CategorySpecimenAuraTheme.resolve(for: defaultMember).accentTint
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
        VStack(alignment: .leading, spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
            } label: {
                header
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(isExpanded
                ? Language.get("Inventory_Family_Collapse_Hint", alter: "طي الألوان")
                : Language.get("Inventory_Family_Expand_Hint", alter: "اختر لوناً لعرض مخزونه وسعره وإجراءاته"))
            .accessibilityAddTraits(.isButton)

            swatchSummary
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AdminSurface.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [familyAccent.opacity(0.10), familyAccent.opacity(0.025), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(familyAccent.opacity(isExpanded ? 0.34 : 0.22), lineWidth: isExpanded ? 1.25 : 1)
        )
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(familyAccent.opacity(isExpanded ? 0.90 : 0.62))
                .frame(width: 3)
                .padding(.vertical, 14)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            // The hero follows the selected color while expanded and returns to
            // the default marketplace member when the family is collapsed.
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

            VStack(alignment: .leading, spacing: 3) {
                Text(defaultMember.name ?? "")
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(String(
                        format: Language.get("Inventory_Family_ColourCount", alter: "%@ ألوان"),
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
                                Language.get("Inventory_Family_HasOutOfStock", alter: "لون غير متوفر"),
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

            Spacer(minLength: 4)

            // Disclosure points down when collapsed and up when expanded, so it
            // needs no mirroring for Arabic.
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(familyAccent)
                .frame(width: 48, height: 48)
                .background(familyAccent.opacity(0.12), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(familyAccent.opacity(0.22), lineWidth: 0.75)
                }
        }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members, id: \.accessoryID) { member in
                    let colour = member.variantColorDictionary
                        .flatMap { PPAccessoryVariantColor(dictionary: $0) }
                    let quantity = availability(member)
                    let isSelected = member.accessoryID == selectedProductId

                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        if reduceMotion {
                            selectedProductId = member.accessoryID
                            isExpanded = true
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selectedProductId = member.accessoryID
                                isExpanded = true
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(colour.map { Color(uiColor: $0.uiColor) } ?? AdminSurface.control)
                                    .frame(width: 16, height: 16)
                                Circle()
                                    .strokeBorder(
                                        (colour?.requiresContrastBorder ?? true)
                                            ? AdminSurface.primaryText.opacity(0.32)
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                                    .frame(width: 16, height: 16)
                                if isSelected {
                                    Circle()
                                        .strokeBorder(familyAccent, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .frame(width: 22, height: 22)

                            Text(colour?.localizedName ?? (member.sku ?? member.accessoryID))
                                .font(isSelected ? AdminType.caption2Bold : AdminType.caption2)
                                .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminCommandInk.secondary)
                                .lineLimit(1)

                            Text(verbatim: "\(quantity.englishDigits)")
                                .font(AdminType.caption2Bold)
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
                                    .foregroundStyle(AdminCommandInk.tertiary)
                                Text(PetAccessory.formatCurrency(NSNumber(value: price)).normalizedEnglishDigits)
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .lineLimit(1)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(minHeight: 44)
                        .background(
                            isSelected ? familyAccent.opacity(0.16) : familyAccent.opacity(0.07),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    familyAccent.opacity(isSelected ? 0.58 : 0.18),
                                    lineWidth: isSelected ? 1.25 : 0.75
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(member.isArchived ? 0.55 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(colourAccessibilityLabel(
                        colour: colour,
                        member: member,
                        quantity: quantity
                    ))
                    .accessibilityHint(Language.get(
                        "Inventory_Family_SelectColour_Hint",
                        alter: "يعرض سعر ومخزون وإجراءات هذا اللون"
                    ))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .background(
            familyAccent.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(familyAccent.opacity(0.14), lineWidth: 0.75)
        }
    }

    private func colourAccessibilityLabel(
        colour: PPAccessoryVariantColor?,
        member: PetAccessory,
        quantity: Int
    ) -> String {
        var parts: [String] = [colour?.accessibilityName ?? (member.sku ?? member.accessoryID)]
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
            parts.append(Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilitySummary: String {
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
