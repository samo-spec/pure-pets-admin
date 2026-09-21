//
//  PPInventoryFamilyGrouping.swift
//  PurePetsAdmin
//
//  Collapses the accessories inventory list so one logical product appears once
//  instead of once per colour.
//
//  ── Why grouping, not replacing ────────────────────────────────────────────
//  A family row is a *wrapper* around the same per-colour cards the list already
//  renders. That is deliberate and it is the whole safety argument:
//
//    • every stock action (adjust, lots, damage, cycle count, quarantine,
//      transfer, POS hand-off, delete) stays bound to the exact `PetAccessory`
//      it was already bound to, so none of those call sites change;
//    • an ambiguous "which colour did you mean?" mutation is not representable,
//      because no action is ever offered on the family row itself;
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
/// deliberately exposes **no** stock action: expanding reveals the real
/// per-colour cards, which own every mutation.
struct PPInventoryFamilyRow: View {
    let members: [PetAccessory]
    @Binding var isExpanded: Bool
    /// Live availability for one colour, supplied by the list so the family row
    /// uses the same branch projection as every other row rather than a second
    /// source of truth.
    let availability: (PetAccessory) -> Int
    let lowStockThreshold: Int

    private var defaultMember: PetAccessory {
        members.first { $0.isDefaultVariant } ?? members[0]
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
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(isExpanded
                ? Language.get("Inventory_Family_Collapse_Hint", alter: "طي الألوان")
                : Language.get("Inventory_Family_Expand_Hint", alter: "إظهار كل لون لإدارة مخزونه"))
            .accessibilityAddTraits(.isButton)

            swatchSummary
        }
        .padding(12)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Family hero image is the default colour's primary image — the same
            // asset the marketplace shows for the product.
            AsyncImage(url: PetAccessory.firstImageURL(for: defaultMember)) { phase in
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
                .foregroundStyle(AdminCommandInk.secondary)
                .frame(width: 44, height: 44)
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

    /// Per-colour availability. Swatch plus text, never swatch alone.
    private var swatchSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(members, id: \.accessoryID) { member in
                    let colour = member.variantColorDictionary
                        .flatMap { PPAccessoryVariantColor(dictionary: $0) }
                    let quantity = availability(member)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(colour.map { Color(uiColor: $0.uiColor) } ?? AdminSurface.control)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(
                                    (colour?.requiresContrastBorder ?? true)
                                        ? AdminSurface.primaryText.opacity(0.3)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                            )

                        Text(colour?.localizedName ?? (member.sku ?? member.accessoryID))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminCommandInk.secondary)
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
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())
                    .opacity(member.isArchived ? 0.5 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(colourAccessibilityLabel(
                        colour: colour,
                        member: member,
                        quantity: quantity
                    ))
                }
            }
            .padding(.vertical, 1)
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
        if member.isDefaultVariant {
            parts.append(Language.get("Variant_State_Default", alter: "اللون الافتراضي"))
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilitySummary: String {
        String(
            format: Language.get(
                "Inventory_Family_Summary_A11y",
                alter: "%@، %@ ألوان، %@ متوفر إجمالاً"
            ),
            defaultMember.name ?? "",
            NSNumber(value: activeMembers.count),
            NSNumber(value: totalAvailable)
        )
    }
}
