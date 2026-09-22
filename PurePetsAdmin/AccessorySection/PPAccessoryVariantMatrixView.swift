//
//  PPAccessoryVariantMatrixView.swift
//  PurePetsAdmin
//
//  Variant Matrix — Phase 6 of the Product Variants System.
//  Provides Apple-grade, studio-crafted matrix management for all sellable
//  combinations (Cartesian product of option definitions), supporting:
//  - Grouping by primary option (e.g. Color with nested Size rows).
//  - Clear status distinction: In Stock, Out of Stock, Inactive (Archived), Unconfigured (Not Created).
//  - Inline pricing, SKU, barcode, active state, and default variant controls.
//  - Bulk pricing across all combinations or per option group.
//  - Incomplete variant warnings and strict identity preservation.
//

import SwiftUI
import UIKit

// MARK: - Active Matrix Sheet Enum

enum PPAccessoryMatrixSheetItem: Identifiable {
    case bulkPricing(group: PPAccessoryMatrixGroup?)
    case createCombination(combination: PPAccessoryMatrixCombination)
    case editVariant(variant: PPAccessoryVariant)
    case manageLots(variant: PPAccessoryVariant, accessory: PetAccessory)

    var id: String {
        switch self {
        case .bulkPricing(let group):
            return "bulkPricing-\(group?.id ?? "all")"
        case .createCombination(let combination):
            return "createCombination-\(combination.combinationKey)"
        case .editVariant(let variant):
            return "editVariant-\(variant.productId)"
        case .manageLots(let variant, _):
            return "manageLots-\(variant.productId)"
        }
    }
}

// MARK: - Main Matrix View

struct PPAccessoryVariantMatrixView: View {
    @ObservedObject var model: PPAccessoryVariantSectionModel
    var onOpenVariantProduct: ((String) -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeSheet: PPAccessoryMatrixSheetItem?
    @State private var collapsedGroupIds: Set<String> = []
    @State private var copiedTextBanner: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            matrixHeaderBar

            if let banner = copiedTextBanner {
                copiedToast(banner)
            }

            if let draft = model.draft {
                let groups = draft.generateMatrixGroups()
                if groups.isEmpty {
                    emptyMatrixState
                } else {
                    matrixGroupsStack(groups: groups, draft: draft)
                }
            }
        }
        .sheet(item: $activeSheet) { item in
            switch item {
            case .bulkPricing(let group):
                PPAccessoryBulkPricingSheet(
                    group: group,
                    allVariants: model.draft?.variants ?? [],
                    onApply: { retail, wholesale, productIds in
                        Task {
                            _ = await model.applyBulkPricing(
                                retailPrice: retail,
                                wholesalePrice: wholesale,
                                forProductIds: productIds
                            )
                            activeSheet = nil
                        }
                    }
                )
            case .createCombination(let combination):
                PPAccessoryCreateCombinationSheet(
                    combination: combination,
                    family: model.draft,
                    onCreate: { sku, barcode, retail, wholesale, quantity, images in
                        Task {
                            let resolvedColor = combination.colorValue.flatMap { PPAccessoryVariantColor(optionValue: $0) }
                            _ = await model.createAndAttachCombinationVariant(
                                selectedOptions: combination.selectedOptions,
                                color: resolvedColor,
                                sku: sku,
                                barcode: barcode,
                                retailPrice: retail,
                                wholesalePrice: wholesale,
                                quantity: quantity,
                                images: images
                            )
                            activeSheet = nil
                        }
                    }
                )
            case .editVariant(let variant):
                PPAccessoryVariantStudioSheet(
                    mode: .edit(variant),
                    usedColorIdentifiers: model.usedColorIdentifiers,
                    isSubmitting: model.isCreatingVariant || model.isSaving,
                    existingStagedImages: (model.stagedImages[variant.productId] ?? []).map(\.image),
                    existingVariants: model.draft?.variants ?? [],
                    onCreate: { _, _, _, _, _, _, _ in false },
                    onUpdate: { productId, color, sku, barcode, retail, wholesale, quantity, newImages, retainedURLs in
                        await model.updateVariant(
                            productId: productId,
                            color: color,
                            sku: sku,
                            barcode: barcode,
                            retailPrice: retail,
                            wholesalePrice: wholesale,
                            quantity: quantity,
                            newImages: newImages,
                            retainedURLs: retainedURLs
                        )
                    },
                    onOpenFullRecord: { productId in
                        activeSheet = nil
                        onOpenVariantProduct?(productId)
                    },
                    errorMessage: {
                        model.failure?.message
                    }
                )
            case .manageLots(let variant, let accessory):
                InventoryLotsSheet(
                    item: accessory,
                    branchId: BranchContextStore.shared.activeBranch?.branchID ?? accessory.resolvedBranchID(),
                    onLotsChanged: {
                        Task {
                            await model.reload()
                        }
                    }
                )
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }
        }
    }

    // MARK: - Header & Telemetry Bar

    private var matrixHeaderBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Variant_Matrix_Title", alter: "مصفوفة المتغيرات"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Variant_Matrix_Subtitle", alter: "إدارة أسعار ورموز وحالات التوليفات الناتجة عن الخيارات."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Spacer(minLength: 8)

                if model.canManageVariants, let draft = model.draft, !draft.variants.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeSheet = .bulkPricing(group: nil)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 13, weight: .bold))
                            Text(Language.get("Variant_Bulk_Pricing_Action", alter: "تسعير جماعي"))
                                .font(AdminType.caption1Bold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AdminSurface.primary)
                    .accessibilityLabel(Language.get("Variant_Bulk_Pricing_Action", alter: "تسعير جماعي لكافة المتغيرات"))
                }
            }

            if let draft = model.draft {
                matrixTelemetryStrip(for: draft)
            }
        }
    }

    private func matrixTelemetryStrip(for draft: PPAccessoryVariantFamily) -> some View {
        let allCombinations = draft.generateMatrixCombinations()
        let totalCount = allCombinations.count
        let configuredCount = allCombinations.filter(\.isCreated).count
        let isFullyConfigured = totalCount > 0 && configuredCount == totalCount

        return HStack(spacing: 8) {
            // Combinations Count Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(isFullyConfigured ? AdminSurface.emerald : AdminSurface.amber)
                    .frame(width: 7, height: 7)

                Text(String(
                    format: Language.get("Variant_Matrix_Combinations_Count", alter: "%@ / %@ مهيأة"),
                    NSNumber(value: configuredCount),
                    NSNumber(value: totalCount)
                ))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.primaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AdminSurface.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

            // Total Available Stock Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(draft.totalAvailableQuantity > 0 ? AdminSurface.emerald : AdminSurface.crimson)
                    .frame(width: 7, height: 7)

                Text(String(
                    format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                    NSNumber(value: draft.totalAvailableQuantity)
                ))
                .font(AdminType.caption2Bold)
                .foregroundStyle(draft.totalAvailableQuantity > 0 ? AdminSurface.emerald : AdminSurface.crimson)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AdminSurface.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

            // Price Range Pill
            if let summary = familyPriceSummary(draft) {
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(AdminSurface.amber)
                    Text(summary)
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AdminSurface.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }
        }
    }

    private func familyPriceSummary(_ family: PPAccessoryVariantFamily) -> String? {
        let prices = family.activeVariants.compactMap { v -> Double? in
            guard v.hasResolvedRetailPrice, let p = v.retailPrice?.doubleValue, p >= 0 else { return nil }
            return p
        }.sorted()
        guard let minimum = prices.first, let maximum = prices.last else { return nil }
        if abs(maximum - minimum) < 0.005 {
            return PetAccessory.formatCurrency(NSNumber(value: minimum))
        }
        return String(
            format: Language.get("Inventory_Family_PriceRange_Format", alter: "%@ – %@"),
            PetAccessory.formatCurrency(NSNumber(value: minimum)),
            PetAccessory.formatCurrency(NSNumber(value: maximum))
        )
    }

    // MARK: - Groups Stack

    private func matrixGroupsStack(groups: [PPAccessoryMatrixGroup], draft: PPAccessoryVariantFamily) -> some View {
        VStack(spacing: 14) {
            ForEach(groups) { group in
                matrixGroupCard(group: group, isSingleGroup: groups.count == 1)
            }
        }
    }

    private func matrixGroupCard(group: PPAccessoryMatrixGroup, isSingleGroup: Bool) -> some View {
        let isCollapsed = collapsedGroupIds.contains(group.id) && !isSingleGroup

        return VStack(alignment: .leading, spacing: 0) {
            // Group Header
            if !isSingleGroup {
                groupHeaderView(group: group, isCollapsed: isCollapsed)
                    .padding(14)
            }

            // Combinations List
            if !isCollapsed {
                if !isSingleGroup {
                    Divider().overlay(AdminSurface.hairline)
                }

                VStack(spacing: 10) {
                    ForEach(group.combinations) { combination in
                        matrixCombinationRow(combination: combination)
                    }
                }
                .padding(14)
            }
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func groupHeaderView(group: PPAccessoryMatrixGroup, isCollapsed: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Color Swatch or Option Glyph
            if let colorVal = group.colorValue {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: colorVal.uiColor ?? .gray))
                        .frame(width: 32, height: 32)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Circle()
                        .strokeBorder(
                            colorVal.requiresContrastBorder
                                ? AdminSurface.primaryText.opacity(0.30)
                                : Color.white.opacity(0.20),
                            lineWidth: 1
                        )
                        .frame(width: 32, height: 32)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AdminSurface.control)
                        .frame(width: 32, height: 32)

                    Image(systemName: "circle.grid.2x1.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.localizedTitle)
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 6) {
                    Text(String(
                        format: Language.get("Variant_Matrix_Group_Configured", alter: "%@ / %@ مهيأة"),
                        NSNumber(value: group.configuredCount),
                        NSNumber(value: group.totalCombinationsCount)
                    ))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminCommandInk.secondary)

                    Text("•")
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.tertiary)

                    Text(String(
                        format: Language.get("Inventory_Family_TotalAvailable", alter: "%@ متوفر"),
                        NSNumber(value: group.totalStock)
                    ))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(group.totalStock > 0 ? AdminSurface.emerald : AdminSurface.crimson)
                }
            }

            Spacer(minLength: 8)

            // Group-level Bulk Pricing Action
            if model.canManageVariants && group.configuredCount > 0 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    activeSheet = .bulkPricing(group: group)
                } label: {
                    Image(systemName: "tag.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    format: Language.get("Variant_Group_BulkPrice_A11y", alter: "تسعير متغيرات %@"),
                    group.localizedTitle
                ))
            }

            // Collapse/Expand Toggle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
                    if isCollapsed {
                        collapsedGroupIds.remove(group.id)
                    } else {
                        collapsedGroupIds.insert(group.id)
                    }
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminCommandInk.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                    .frame(width: 32, height: 32)
                    .background(AdminSurface.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed
                ? Language.get("Expand", alter: "توسيع")
                : Language.get("Collapse", alter: "طي")
            )
        }
    }

    // MARK: - Combination Row

    private func matrixCombinationRow(combination: PPAccessoryMatrixCombination) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Combination attributes / chips
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(combination.localizedTitle)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    if combination.isDefault {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text(Language.get("Variant_Default_Badge", alter: "الافتراضي"))
                                .font(AdminType.caption2Bold)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.orange)
                    }
                }

                // Subtitle: SKU / Barcode or Unconfigured Hint
                if let variant = combination.existingVariant {
                    HStack(spacing: 8) {
                        if !variant.sku.isEmpty {
                            Button {
                                copyToClipboard(variant.sku, hint: Language.get("SKU_Copied", alter: "تم نسخ SKU"))
                            } label: {
                                HStack(spacing: 3) {
                                    Text("SKU: \(variant.sku)")
                                        .font(AdminType.caption2)
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 8))
                                }
                                .foregroundStyle(AdminCommandInk.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if !variant.barcode.isEmpty {
                            Button {
                                copyToClipboard(variant.barcode, hint: Language.get("Barcode_Copied", alter: "تم نسخ الباركود"))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "barcode")
                                        .font(.system(size: 8))
                                    Text(variant.barcode)
                                        .font(AdminType.caption2)
                                }
                                .foregroundStyle(AdminCommandInk.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if variant.sku.isEmpty && variant.barcode.isEmpty {
                            Text(Language.get("Variant_No_Identifiers", alter: "بدون باركود أو SKU"))
                                .font(AdminType.caption2)
                                .foregroundStyle(AdminSurface.amber)
                        }
                    }
                } else {
                    Text(Language.get("Variant_Not_Created_Yet", alter: "لم يتم إنشاء الصنف بعد في المخزون."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.tertiary)
                }
            }

            Spacer(minLength: 8)

            // Price & Stock Display
            if let variant = combination.existingVariant {
                VStack(alignment: .trailing, spacing: 3) {
                    if let retail = variant.retailPrice {
                        Text(PetAccessory.formatCurrency(retail))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }

                    statusBadge(for: combination)
                }
            } else {
                statusBadge(for: combination)
            }

            // Action Buttons
            if let variant = combination.existingVariant {
                HStack(spacing: 6) {
                    // Quick Active / Inactive Toggle
                    if model.canManageVariants {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            model.toggleArchive(forProductId: variant.productId)
                        } label: {
                            Image(systemName: variant.isArchived ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(variant.isArchived ? AdminCommandInk.tertiary : AdminSurface.primary)
                                .frame(width: 34, height: 34)
                                .background(AdminSurface.control, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(variant.isArchived
                            ? Language.get("Variant_Activate", alter: "تفعيل المتغير")
                            : Language.get("Variant_Deactivate", alter: "تعطيل المتغير")
                        )

                        // Set Default Variant Action
                        if !variant.isDefault && !variant.isArchived {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                model.setDefault(productId: variant.productId)
                            } label: {
                                Image(systemName: "star")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AdminCommandInk.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(AdminSurface.control, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Language.get("Variant_Set_Default", alter: "تعيين كافتراضي"))
                        }
                    }

                    // Edit in Studio Button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeSheet = .editVariant(variant: variant)
                    } label: {
                        Image(systemName: "slider.horizontal.2.square")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                            .frame(width: 34, height: 34)
                            .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(
                        format: Language.get("Variant_Edit_A11y", alter: "تعديل متغير %@"),
                        combination.localizedTitle
                    ))

                    // Lots & Inventory Studio Button
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            if let accessory = try? await model.loadAccessory(forProductId: variant.productId) {
                                activeSheet = .manageLots(variant: variant, accessory: accessory)
                            }
                        }
                    } label: {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                            .frame(width: 34, height: 34)
                            .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(
                        format: Language.get("Variant_Lots_A11y", alter: "تشغيلات ومخزون متغير %@"),
                        combination.localizedTitle
                    ))
                }
            } else {
                // Create Combination Button
                if model.canManageVariants {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeSheet = .createCombination(combination: combination)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Variant_Create_Combination", alter: "إنشاء"))
                                .font(AdminType.caption1Bold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AdminSurface.primary, in: Capsule())
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(
                        format: Language.get("Variant_Create_Combination_A11y", alter: "إنشاء متغير جديد للتوليفة %@"),
                        combination.localizedTitle
                    ))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(combination.isCreated ? AdminSurface.control.opacity(0.6) : AdminSurface.control.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    combination.isCreated ? AdminSurface.hairline : AdminSurface.hairline.opacity(0.6),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func statusBadge(for combination: PPAccessoryMatrixCombination) -> some View {
        switch combination.status {
        case .inStock:
            Text(String(
                format: Language.get("Variant_Stock_InStock_Count", alter: "%@ متوفر"),
                NSNumber(value: combination.quantity)
            ))
            .font(AdminType.caption2Bold)
            .foregroundStyle(AdminSurface.emerald)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(AdminSurface.emerald.opacity(0.12), in: Capsule())

        case .outOfStock:
            Text(Language.get("Variant_Stock_OutOfStock", alter: "نفد من المخزون"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.crimson)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(AdminSurface.crimson.opacity(0.12), in: Capsule())

        case .inactive:
            Text(Language.get("Variant_Status_Inactive", alter: "معطل"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminCommandInk.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(AdminSurface.control, in: Capsule())

        case .unconfigured:
            Text(Language.get("Variant_Status_Unconfigured", alter: "غير مهيأ"))
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.amber)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(AdminSurface.amber.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(AdminSurface.amber.opacity(0.4), lineWidth: 0.75))
        }
    }

    // MARK: - Empty State

    private var emptyMatrixState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 40))
                .foregroundStyle(AdminCommandInk.tertiary)

            Text(Language.get("Variant_Matrix_Empty_Title", alter: "لا توجد خيارات لتوليد المصفوفة"))
                .font(AdminType.headlineBold)
                .foregroundStyle(AdminSurface.primaryText)

            Text(Language.get("Variant_Matrix_Empty_Subtitle", alter: "أضف خيارات للمنتج (مثل الألوان أو المقاسات) من تبويب الخيارات أولاً."))
                .font(AdminType.subheadline)
                .foregroundStyle(AdminCommandInk.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Toast / Feedback

    private func copiedToast(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AdminSurface.emerald)
            Text(message)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AdminSurface.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(AdminSurface.emerald.opacity(0.3), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func copyToClipboard(_ text: String, hint: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            copiedTextBanner = hint
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { copiedTextBanner = nil }
        }
    }
}

// MARK: - Bulk Pricing Sheet

struct PPAccessoryBulkPricingSheet: View {
    let group: PPAccessoryMatrixGroup?
    let allVariants: [PPAccessoryVariant]
    let onApply: (Double, Double?, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var retailPriceText = ""
    @State private var wholesalePriceText = ""
    @State private var isSubmitting = false

    private var targetVariants: [PPAccessoryVariant] {
        if let group {
            return group.combinations.compactMap(\.existingVariant)
        }
        return allVariants
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(Language.get("Variant_BulkPricing_Scope", alter: "نطاق التطبيق"))) {
                    HStack {
                        Text(Language.get("Variant_BulkPricing_Target", alter: "المتغيرات المستهدفة"))
                        Spacer()
                        Text(group?.localizedTitle ?? Language.get("Variant_BulkPricing_All", alter: "كافة المتغيرات"))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }

                    HStack {
                        Text(Language.get("Variant_BulkPricing_Count", alter: "عدد الأصناف"))
                        Spacer()
                        Text("\(targetVariants.count)")
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                }

                Section(header: Text(Language.get("Variant_BulkPricing_Values", alter: "الأسعار الجديدة"))) {
                    HStack {
                        Text(Language.get("Price_Retail", alter: "سعر البيع"))
                        Spacer()
                        TextField("0.00", text: $retailPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Language.get("QAR", alter: "ر.ق"))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }

                    HStack {
                        Text(Language.get("Price_Wholesale", alter: "سعر الجملة (اختياري)"))
                        Spacer()
                        TextField("0.00", text: $wholesalePriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(Language.get("QAR", alter: "ر.ق"))
                            .foregroundStyle(AdminCommandInk.secondary)
                    }
                }
            }
            .navigationTitle(Language.get("Variant_Bulk_Pricing_Title", alter: "تسعير جماعي"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Language.get("Apply", alter: "تطبيق")) {
                        guard let retail = Double(retailPriceText), retail > 0 else { return }
                        let wholesale = Double(wholesalePriceText)
                        isSubmitting = true
                        onApply(retail, wholesale, targetVariants.map(\.productId))
                    }
                    .disabled(Double(retailPriceText) == nil || (Double(retailPriceText) ?? 0) <= 0 || isSubmitting)
                }
            }
        }
    }
}

// MARK: - Category-Defining Variant Studio Workbench

struct PPAccessoryCreateCombinationSheet: View {
    let combination: PPAccessoryMatrixCombination
    let family: PPAccessoryVariantFamily?
    let onCreate: (String, String, Double, Double?, Int, [UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var skuText = ""
    @State private var barcodeText = ""
    @State private var retailPriceText = ""
    @State private var wholesalePriceText = ""
    @State private var quantity = 0
    @State private var stagedImages: [UIImage] = []
    @State private var isPresentingPhotoPicker = false
    @State private var isSubmitting = false
    @State private var showSkuCopiedToast = false
    @State private var showBarcodeCopiedToast = false

    private var retailPrice: Double {
        Double(retailPriceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private var wholesalePrice: Double? {
        let trimmed = wholesalePriceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var isPriceValid: Bool {
        retailPrice > 0
    }

    private var isWholesaleExceedingRetail: Bool {
        if let wholesale = wholesalePrice, wholesale > retailPrice && retailPrice > 0 {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                AdminSurface.background
                    .ignoresSafeArea()

                // Main Scrollable Canvas
                ScrollView {
                    VStack(spacing: 20) {
                        // 1. Luminous Combination Identity Card (Hero DNA)
                        combinationHeroDNASurface

                        // 2. Commercial Pricing & Live Profit Engine
                        commercialPricingSurface

                        // 3. Tactile Stock & Inventory Vault
                        inventoryVaultSurface

                        // 4. Studio Identification & Barcode Lab
                        identificationBarcodeSurface

                        // 5. Variant Media Atelier
                        mediaAtelierSurface

                        // Extra bottom clearance for floating action dock
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                // Sticky Frosted Studio Action Dock
                studioActionDock
            }
            .navigationTitle(Language.get("Variant_Studio_Hero_Title", alter: "إنشاء وتثبيت المتغير"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(AdminType.callout)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .sheet(isPresented: $isPresentingPhotoPicker) {
                let remaining = max(1, 6 - stagedImages.count)
                PPVariantImagePickerSheet(maxSelection: remaining) { picked in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        stagedImages.append(contentsOf: picked)
                    }
                    isPresentingPhotoPicker = false
                }
            }
            .onAppear {
                setupDefaults()
            }
        }
    }

    // MARK: - 1. Luminous Combination Identity Card (Hero DNA)

    private var combinationHeroDNASurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Parent Family Context Header
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(family?.name ?? Language.get("Variant_Combination_Details", alter: "تفاصيل التوليفة"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text(Language.get("Variant_Studio_Option_Capsule", alter: "خصائص التوليفة"))
                    .font(AdminType.captionRegular)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            // Hero Combination Representation
            HStack(spacing: 14) {
                // Swatch / Glyph Halo
                if let colorValue = combination.colorValue,
                   let hex = colorValue.hex {
                    ZStack {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 44, height: 44)
                            .shadow(color: Color(hex: hex).opacity(0.35), radius: 8, x: 0, y: 4)
                        Circle()
                            .strokeBorder(Color.white.opacity(0.8), lineWidth: 2)
                            .frame(width: 44, height: 44)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AdminSurface.control)
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }

                // Combination Title & Subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(combination.localizedTitle)
                        .font(AdminType.title3Bold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)

                    if !combination.secondaryOptionsSummary.isEmpty {
                        Text(combination.secondaryOptionsSummary)
                            .font(AdminType.captionRegular)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()
            }

            // Option Pills Grid
            if !combination.optionValues.isEmpty {
                Divider()
                    .background(AdminSurface.hairline)

                FlowLayout(spacing: 8) {
                    ForEach(combination.optionValues) { optionValue in
                        HStack(spacing: 6) {
                            if let hex = optionValue.hex {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 10, height: 10)
                            } else {
                                Image(systemName: iconForOptionValue(optionValue))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AdminSurface.primary)
                            }

                            Text(optionValue.localizedName)
                                .font(AdminType.captionRegular)
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - 2. Commercial Pricing & Live Profit Engine

    private var commercialPricingSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with Match Base Price Chip
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Pricing_Stock", alter: "السعر والمخزون"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                if let baseRetail = family?.variants.first?.retailPrice?.doubleValue, baseRetail > 0 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        retailPriceText = String(format: "%.2f", baseRetail)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("Variant_Studio_Match_Base_Price", alter: "مطابقة سعر الأساس"))
                                .font(AdminType.captionRegular)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.control, in: Capsule())
                        .foregroundStyle(AdminSurface.primary)
                    }
                }
            }

            // Retail Price Field (Hero Input)
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Price_Retail", alter: "سعر البيع"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack(spacing: 8) {
                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primary)

                    TextField("0.00", text: $retailPriceText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(layoutDirection == .rightToLeft ? .leading : .leading)

                    if !retailPriceText.isEmpty {
                        Button {
                            retailPriceText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
            }

            // Wholesale Price Field (Cost)
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Price_Wholesale", alter: "سعر الجملة (اختياري)"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack(spacing: 8) {
                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField("0.00", text: $wholesalePriceText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(layoutDirection == .rightToLeft ? .leading : .leading)

                    if !wholesalePriceText.isEmpty {
                        Button {
                            wholesalePriceText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
            }

            // Live Profit Engine Card
            if let wholesale = wholesalePrice, wholesale > 0 && retailPrice > 0 {
                if isWholesaleExceedingRetail {
                    // Warning Pill
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AdminSurface.amber)
                        Text(Language.get("Variant_Studio_Margin_Warning", alter: "تنبيه: سعر الجملة أعلى من سعر البيع!"))
                            .font(AdminType.captionRegular)
                            .foregroundStyle(AdminSurface.amber)
                        Spacer()
                    }
                    .padding(10)
                    .background(AdminSurface.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.amber.opacity(0.3), lineWidth: 1))
                } else {
                    let profit = retailPrice - wholesale
                    let marginPct = (profit / retailPrice) * 100
                    let markup = retailPrice / wholesale

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Variant_Studio_Margin_Profit", alter: "هامش الربح"))
                                .font(AdminType.captionRegular)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(String(format: "+%.2f %@", profit, Language.get("QAR", alter: "ر.ق")))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(AdminSurface.emerald)
                        }

                        Spacer()

                        VStack(alignment: .center, spacing: 2) {
                            Text("%")
                                .font(AdminType.captionRegular)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(String(format: "%.1f%%", marginPct))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(AdminSurface.emerald)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Language.get("Variant_Studio_Margin_Markup", alter: "مضاعف التكلفة"))
                                .font(AdminType.captionRegular)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(String(format: "%.2fx", markup))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.emerald.opacity(0.2), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - 3. Tactile Stock & Inventory Vault

    private var inventoryVaultSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Inventory_Initial_Quantity", alter: "الكمية الأولية"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Health Badge
                if quantity == 0 {
                    Text(Language.get("Variant_Studio_Stock_Out", alter: "غير متوفر بالمخزن"))
                        .font(AdminType.captionRegular)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdminSurface.control, in: Capsule())
                        .foregroundStyle(AdminSurface.secondaryText)
                } else if quantity <= 5 {
                    Text(Language.get("Variant_Studio_Stock_Low", alter: "مخزون محدود"))
                        .font(AdminType.captionRegular)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdminSurface.amber.opacity(0.15), in: Capsule())
                        .foregroundStyle(AdminSurface.amber)
                } else {
                    Text(Language.get("Variant_Studio_Stock_Good", alter: "مخزون وافر"))
                        .font(AdminType.captionRegular)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdminSurface.emerald.opacity(0.15), in: Capsule())
                        .foregroundStyle(AdminSurface.emerald)
                }
            }

            // Stepper Counter Row
            HStack(spacing: 16) {
                // Minus Button
                Button {
                    if quantity > 0 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        quantity -= 1
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(quantity > 0 ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.control, in: Circle())
                }
                .disabled(quantity <= 0)

                Spacer()

                // Display
                Text("\(quantity)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                // Plus Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    quantity += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.control, in: Circle())
                }
            }
            .padding(.horizontal, 12)

            // Quick Stock Increment Chips
            HStack(spacing: 8) {
                ForEach([0, 5, 10, 25, 50, 100], id: \.self) { amount in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if amount == 0 {
                            quantity = 0
                        } else {
                            quantity += amount
                        }
                    } label: {
                        Text(amount == 0 ? "0" : "+\(amount)")
                            .font(AdminType.captionRegular)
                            .foregroundStyle(amount == 0 && quantity == 0 ? AdminSurface.primary : AdminSurface.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(amount == 0 && quantity == 0 ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - 4. Studio Identification & Barcode Lab

    private var identificationBarcodeSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Identifiers", alter: "الرموز والباركود"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Generate PP Barcode Action
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    barcodeText = "PP\(Int(Date().timeIntervalSince1970))"
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("CatalogIntake_GeneratePPBarcode", alter: "توليد باركود PP"))
                            .font(AdminType.captionRegular)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }
            }

            // SKU Input Row
            VStack(alignment: .leading, spacing: 6) {
                Text("SKU")
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("SKU_Placeholder", alter: "رمز الصنف"), text: $skuText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(layoutDirection == .rightToLeft ? .leading : .leading)

                    if !skuText.isEmpty {
                        Button {
                            UIPasteboard.general.string = skuText
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showSkuCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showSkuCopiedToast = false
                            }
                        } label: {
                            Image(systemName: showSkuCopiedToast ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundStyle(showSkuCopiedToast ? AdminSurface.emerald : AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
            }

            // International Barcode Input Row
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Barcode", alter: "الباركود"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                        .font(.system(size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("Barcode_Placeholder", alter: "الباركود الدولي"), text: $barcodeText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(layoutDirection == .rightToLeft ? .leading : .leading)

                    if !barcodeText.isEmpty {
                        Button {
                            UIPasteboard.general.string = barcodeText
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showBarcodeCopiedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showBarcodeCopiedToast = false
                            }
                        } label: {
                            Image(systemName: showBarcodeCopiedToast ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundStyle(showBarcodeCopiedToast ? AdminSurface.emerald : AdminSurface.secondaryText)
                        }
                    }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
            }

            // Simulated Barcode Hologram
            if !barcodeText.isEmpty {
                VStack(spacing: 6) {
                    SimulatedBarcodeGraphic(barcode: barcodeText)
                        .frame(height: 38)
                        .padding(.top, 4)

                    Text(barcodeText)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                        .tracking(2)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - 5. Variant Media Atelier

    private var mediaAtelierSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Studio_Media_Title", alter: "صور المتغير"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Add Photo Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isPresentingPhotoPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(Language.get("Variant_Studio_Media_Add", alter: "إضافة صور"))
                            .font(AdminType.captionRegular)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }
            }

            // Image Thumbnails Scroll
            if !stagedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(stagedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(AdminSurface.hairline, lineWidth: 1)
                                    )

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        _ = stagedImages.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(AdminSurface.crimson, Color.white)
                                }
                                .offset(x: 6, y: -6)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                // Empty Media Strip / Add Prompt
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isPresentingPhotoPicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(Language.get("Variant_Studio_Media_Add", alter: "إضافة صور للمتغير (اختياري)"))
                            .font(AdminType.footnote)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                    }
                    .padding(14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - 6. Sticky Studio Action Dock

    private var studioActionDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline)

            HStack(spacing: 12) {
                // Confirmation / Create Button
                Button {
                    guard isPriceValid && !isSubmitting else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isSubmitting = true
                    onCreate(skuText, barcodeText, retailPrice, wholesalePrice, quantity, stagedImages)
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }

                        Text(Language.get("Variant_Studio_Create_Action", alter: "إنشاء المتغير وتثبيته في المصفوفة"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        isPriceValid
                            ? AdminSurface.primary
                            : AdminSurface.primary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .shadow(
                        color: isPriceValid ? AdminSurface.primary.opacity(0.3) : Color.clear,
                        radius: 8, x: 0, y: 4
                    )
                }
                .disabled(!isPriceValid || isSubmitting)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func setupDefaults() {
        if let first = family?.variants.first {
            if let retail = first.retailPrice?.doubleValue, retailPriceText.isEmpty {
                retailPriceText = String(format: "%.2f", retail)
            }
            if let wholesale = first.wholesalePrice?.doubleValue, wholesalePriceText.isEmpty {
                wholesalePriceText = String(format: "%.2f", wholesale)
            }
            if !first.sku.isEmpty && skuText.isEmpty {
                let suffix = combination.optionValues.map(\.canonicalValue).joined(separator: "-")
                skuText = "\(first.sku)-\(suffix)"
            }
        }

        if barcodeText.isEmpty {
            barcodeText = "PP\(Int(Date().timeIntervalSince1970))"
        }
    }

    private func iconForOptionValue(_ value: PPAccessoryOptionValue) -> String {
        let canonical = value.canonicalValue.lowercased()
        if canonical.contains("size") || ["xs", "s", "m", "l", "xl", "xxl"].contains(canonical) {
            return "ruler"
        }
        if canonical.contains("kg") || canonical.contains("g") || canonical.contains("lb") {
            return "scalemass"
        }
        if value.unit != nil {
            return "scalemass"
        }
        return "slider.horizontal.2.square"
    }
}

// MARK: - FlowLayout & Simulated Barcode Visualizer

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct SimulatedBarcodeGraphic: View {
    let barcode: String

    var body: some View {
        GeometryReader { proxy in
            let bars = generateBars(width: proxy.size.width)
            HStack(spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, width in
                    Rectangle()
                        .fill(Color.black.opacity(0.85))
                        .frame(width: max(1, width))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func generateBars(width: CGFloat) -> [CGFloat] {
        var seed: UInt64 = 5381
        for byte in barcode.utf8 {
            seed = ((seed << 5) &+ seed) &+ UInt64(byte)
        }

        var result: [CGFloat] = []
        var total: CGFloat = 0
        var state = seed

        while total < width - 10 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let barWidth: CGFloat = CGFloat((state % 3) + 1)
            result.append(barWidth)
            total += barWidth + 2
        }
        return result
    }
}

private extension Color {
    init(hex: String) {
        let ui = PPAccessoryVariantColor.color(fromHex: hex) ?? .systemGray
        self.init(uiColor: ui)
    }
}
