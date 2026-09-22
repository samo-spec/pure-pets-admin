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
    @State private var variantToDelete: PPAccessoryVariant? = nil

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
            Group {
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
                        errorMessage: { model.failure?.message },
                        onCreate: { sku, barcode, retail, wholesale, quantity, images in
                                let resolvedColor = combination.colorValue.flatMap { PPAccessoryVariantColor(optionValue: $0) }
                                let succeeded = await model.createAndAttachCombinationVariant(
                                    selectedOptions: combination.selectedOptions,
                                    color: resolvedColor,
                                    sku: sku,
                                    barcode: barcode,
                                    retailPrice: retail,
                                    wholesalePrice: wholesale,
                                    quantity: quantity,
                                    images: images
                                )
                                if succeeded { activeSheet = nil }
                                return succeeded
                        }
                    )
                case .editVariant(let variant):
                    PPAccessoryVariantStudioSheet(
                        mode: .edit(variant),
                        usedColorIdentifiers: model.usedColorIdentifiers,
                        isSubmitting: model.isCreatingVariant || model.isSaving,
                        existingStagedImages: (model.stagedImages[variant.productId] ?? []).map(\.image),
                        existingVariants: model.draft?.variants ?? [],
                        onCreate: { _, _, _, _, _, _, _, _ in false },
                        onUpdate: { productId, color, options, sku, barcode, retail, wholesale, quantity, newImages, retainedURLs in
                            await model.updateVariant(
                                productId: productId,
                                color: color,
                                selectedOptions: options,
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
                        },
                        optionDefinitions: model.draft?.optionDefinitions ?? []
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
                }
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
        .confirmationDialog(
            Language.get("Variant_Delete_Confirm_Title", alter: "حذف المتغير من المجموعة"),
            isPresented: Binding(
                get: { variantToDelete != nil },
                set: { if !$0 { variantToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                if let v = variantToDelete {
                    model.removeVariant(productId: v.productId)
                }
                variantToDelete = nil
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                variantToDelete = nil
            }
        } message: {
            Text(Language.get(
                "Variant_Delete_Confirm_Message",
                alter: "هل أنت متأكد من إزالة هذا المتغير من مجموعة المنتج؟ لن يتم حذف المنتج نفسه من النظام بل سيفك ارتباطه بالمجموعة."
            ))
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
                    Image(systemName: "plus.circle")
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
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title & Default on Leading, Price & Stock on Trailing
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    if let color = combination.colorValue, let uiColor = color.uiColor {
                        Circle()
                            .fill(Color(uiColor: uiColor))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(color.requiresContrastBorder ? AdminSurface.primaryText.opacity(0.25) : Color.clear, lineWidth: 0.5))
                    }

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

                Spacer(minLength: 8)

                // Price & Stock Display
                if let variant = combination.existingVariant {
                    HStack(spacing: 6) {
                        if let retail = variant.retailPrice {
                            Text(PetAccessory.formatCurrency(retail))
                                .font(AdminType.calloutBold)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)
                                .environment(\.layoutDirection, .leftToRight)
                        }

                        statusBadge(for: combination)
                    }
                } else {
                    statusBadge(for: combination)
                }
            }

            // Identifiers & Actions Row
            if let variant = combination.existingVariant {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 8) {
                        matrixIdentifiersStrip(variant: variant)
                        Spacer(minLength: 6)
                        matrixActionsToolbar(combination: combination, variant: variant)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        matrixIdentifiersStrip(variant: variant)
                        HStack {
                            Spacer()
                            matrixActionsToolbar(combination: combination, variant: variant)
                        }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    Text(Language.get("Variant_Not_Created_Yet", alter: "لم يتم إنشاء الصنف بعد في المخزون."))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminCommandInk.tertiary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

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
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
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
    private func matrixIdentifiersStrip(variant: PPAccessoryVariant) -> some View {
        HStack(spacing: 6) {
            if !variant.sku.isEmpty {
                Button {
                    copyToClipboard(variant.sku, hint: Language.get("SKU_Copied", alter: "تم نسخ SKU"))
                } label: {
                    HStack(spacing: 4) {
                        Text("SKU")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminCommandInk.tertiary)
                        Text(variant.sku)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8))
                            .foregroundStyle(AdminCommandInk.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .environment(\.layoutDirection, .leftToRight)
            }

            if !variant.barcode.isEmpty {
                Button {
                    copyToClipboard(variant.barcode, hint: Language.get("Barcode_Copied", alter: "تم نسخ الباركود"))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "barcode")
                            .font(.system(size: 10))
                            .foregroundStyle(AdminCommandInk.tertiary)
                        Text(variant.barcode)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8))
                            .foregroundStyle(AdminCommandInk.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .environment(\.layoutDirection, .leftToRight)
            }

            if variant.sku.isEmpty && variant.barcode.isEmpty {
                Text(Language.get("Variant_No_Identifiers", alter: "بدون باركود أو SKU"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(AdminSurface.amber.opacity(0.12), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private func matrixActionsToolbar(combination: PPAccessoryMatrixCombination, variant: PPAccessoryVariant) -> some View {
        HStack(spacing: 5) {
            // Quick Active / Inactive Toggle
            if model.canManageVariants {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.toggleArchive(forProductId: variant.productId)
                } label: {
                    Image(systemName: variant.isArchived ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(variant.isArchived ? AdminCommandInk.tertiary : AdminSurface.primary)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.surface, in: Circle())
                        .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.6))
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdminCommandInk.secondary)
                            .frame(width: 32, height: 32)
                            .background(AdminSurface.surface, in: Circle())
                            .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.6))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 32, height: 32)
                    .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AdminSurface.primary.opacity(0.2), lineWidth: 0.6))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
                    .frame(width: 32, height: 32)
                    .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AdminSurface.primary.opacity(0.2), lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                format: Language.get("Variant_Lots_A11y", alter: "تشغيلات ومخزون متغير %@"),
                combination.localizedTitle
            ))

            // Delete / Detach Variant from Family
            if model.canManageVariants && (model.draft?.variants.count ?? 0) > 1 && !variant.isDefault {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    variantToDelete = variant
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdminSurface.crimson)
                        .frame(width: 32, height: 32)
                        .background(AdminSurface.crimson.opacity(0.10), in: Circle())
                        .overlay(Circle().strokeBorder(AdminSurface.crimson.opacity(0.2), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Variant_Delete_From_Family", alter: "حذف المتغير من المجموعة"))
            }
        }
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

// MARK: - Category-Defining Bulk Pricing Command Studio

struct PPAccessoryBulkPricingSheet: View {
    let group: PPAccessoryMatrixGroup?
    let allVariants: [PPAccessoryVariant]
    let onApply: (Double, Double?, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var retailPriceText: String = ""
    @State private var wholesalePriceText: String = ""
    @State private var isSubmitting: Bool = false

    private var targetVariants: [PPAccessoryVariant] {
        if let group {
            let found = group.combinations.compactMap(\.existingVariant)
            if !found.isEmpty {
                return found
            }
        }
        return allVariants
    }

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

    private var totalStockImpacted: Int {
        targetVariants.reduce(0) { $0 + max(0, $1.quantity) }
    }

    private var currentAvgRetailPrice: Double {
        let priced = targetVariants.compactMap { $0.retailPrice?.doubleValue }.filter { $0 > 0 }
        guard !priced.isEmpty else { return 0 }
        return priced.reduce(0, +) / Double(priced.count)
    }

    private var currentAvgWholesalePrice: Double {
        let costed = targetVariants.compactMap { $0.wholesalePrice?.doubleValue }.filter { $0 > 0 }
        guard !costed.isEmpty else { return 0 }
        return costed.reduce(0, +) / Double(costed.count)
    }

    private var isWholesaleExceedingRetail: Bool {
        guard let wholesale = wholesalePrice, wholesale > retailPrice && retailPrice > 0 else {
            return false
        }
        return true
    }

    private var unitProfit: Double {
        guard let wholesale = wholesalePrice else { return 0 }
        return retailPrice - wholesale
    }

    private var grossMarginPct: Double {
        guard retailPrice > 0, let wholesale = wholesalePrice else { return 0 }
        return ((retailPrice - wholesale) / retailPrice) * 100.0
    }

    private var costMarkup: Double {
        guard let wholesale = wholesalePrice, wholesale > 0 else { return 0 }
        return retailPrice / wholesale
    }

    private var avgPriceShift: Double {
        guard retailPrice > 0, currentAvgRetailPrice > 0 else { return 0 }
        return retailPrice - currentAvgRetailPrice
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                AdminSurface.background
                    .ignoresSafeArea()

                // Main Scrollable Atelier Canvas
                ScrollView {
                    VStack(spacing: 18) {
                        // 1. Hero Scope & Command Identity Surface
                        scopeIdentitySurface

                        // 2. Target Variants Horizon Carousel
                        targetVariantsHorizonSurface

                        // 3. Sculpted Commercial Pricing Engine
                        commercialPricingEngineSurface

                        // 4. Valuation Shift Projection Card
                        batchValuationProjectionSurface

                        // Clearance for pinned bottom dock
                        Spacer()
                            .frame(height: 110)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                // 5. Frosted Glass Action Dock
                studioActionDock
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Variant_Bulk_Pricing_Title", alter: "تسعير جماعي"))
                        .font(PPBrandFont.bold(size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(PPBrandFont.medium(size: 15, relativeTo: .callout))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .onAppear {
                PPBrandFont.registerIfNeeded()
                setupInitialValues()
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - 1. Scope & Command Identity Surface

    private var scopeIdentitySurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // Chromatic Halo
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: AdminSurface.primary.opacity(0.3), radius: 8, x: 0, y: 4)

                    Image(systemName: group != nil ? "slider.horizontal.2.square" : "tag.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group?.localizedTitle ?? Language.get("Variant_BulkPricing_All", alter: "كافة المتغيرات"))
                            .font(AdminType.title3Bold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(1)

                        if let hex = group?.colorValue?.hex {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5))
                                .shadow(color: Color(hex: hex).opacity(0.4), radius: 4, x: 0, y: 2)
                        }
                    }

                    Text(Language.get("Variant_Bulk_Subtitle", alter: "تسعير ذكي موحد للمتغيرات مع تحليل فوري للهوامش والأرباح."))
                        .font(AdminType.captionRegular)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(2)
                }

                Spacer()
            }

            Divider()
                .background(AdminSurface.hairline)

            // Telemetry Badges Row
            HStack(spacing: 8) {
                // Target Count Pill
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(String(format: Language.get("Variant_Bulk_Target_Count_Format", alter: "%d صنف مستهدف"), targetVariants.count))
                        .font(AdminType.captionRegular)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())

                // Impacted Stock Pill
                HStack(spacing: 5) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.emerald)
                    Text(String(format: Language.get("Variant_Bulk_Total_Stock_Format", alter: "%d وحدة متأثرة"), totalStockImpacted))
                        .font(AdminType.captionRegular)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.control, in: Capsule())

                Spacer()

                // Benchmark average if available
                if currentAvgRetailPrice > 0 {
                    HStack(spacing: 4) {
                        Text(String(format: Language.get("Variant_Bulk_Current_Avg_Format", alter: "متوسط: %.2f %@"), currentAvgRetailPrice, Language.get("QAR", alter: "ر.ق")))
                            .font(AdminType.captionRegular)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.control.opacity(0.6), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - 2. Target Variants Horizon Carousel

    private var targetVariantsHorizonSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Bulk_Target_List_Header", alter: "الأصناف المشمولة بالتسعير"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                Text("\(targetVariants.count)")
                    .font(AdminType.captionRegular)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.control, in: Capsule())
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            if targetVariants.isEmpty {
                HStack {
                    Spacer()
                    Text(Language.get("Variant_Matrix_Empty_Title", alter: "لا توجد أصناف في هذا النطاق"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                }
                .padding(20)
                .background(AdminSurface.control.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(targetVariants, id: \.productId) { variant in
                            variantHorizonCard(variant)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    private func variantHorizonCard(_ variant: PPAccessoryVariant) -> some View {
        let currentPrice = variant.retailPrice?.doubleValue ?? 0
        let qar = Language.get("QAR", alter: "ر.ق")

        return VStack(alignment: .leading, spacing: 8) {
            // Swatch & Label
            HStack(spacing: 6) {
                let hex = variant.color.hex
                if !hex.isEmpty {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                } else {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 12, height: 12)
                }

                Text(variant.color.localizedName)
                    .font(AdminType.captionRegular)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                Spacer()

                // Stock Badge
                Text("\(variant.quantity)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(variant.quantity > 0 ? AdminSurface.control : AdminSurface.amber.opacity(0.15), in: Capsule())
                    .foregroundStyle(variant.quantity > 0 ? AdminSurface.secondaryText : AdminSurface.amber)
            }

            // SKU if present
            if !variant.sku.isEmpty {
                Text(variant.sku)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Divider()
                .background(AdminSurface.hairline)

            // Price Transition Live Display
            VStack(alignment: .leading, spacing: 3) {
                // Previous price
                HStack(spacing: 4) {
                    Text(currentPrice > 0 ? String(format: "%.0f %@", currentPrice, qar) : Language.get("Price_Unset", alter: "غير محدد"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .strikethrough(retailPrice > 0 && currentPrice > 0)

                    if retailPrice > 0 {
                        Image(systemName: layoutDirection == .rightToLeft ? "arrow.backward" : "arrow.forward")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)

                        Text(String(format: "%.0f %@", retailPrice, qar))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminSurface.primary)
                    }
                }

                // Delta tag
                if retailPrice > 0 && currentPrice > 0 {
                    let delta = retailPrice - currentPrice
                    if abs(delta) > 0.01 {
                        Text(String(format: "%@%.0f %@", delta > 0 ? "+" : "", delta, qar))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(delta >= 0 ? AdminSurface.emerald : AdminSurface.amber)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 148)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - 3. Sculpted Commercial Pricing Engine

    private var commercialPricingEngineSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_BulkPricing_Values", alter: "الأسعار الجديدة"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                if currentAvgRetailPrice > 0 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        retailPriceText = String(format: "%.2f", currentAvgRetailPrice)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("Variant_Studio_Match_Base_Price", alter: "مطابقة متوسط السعر"))
                                .font(AdminType.captionRegular)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.control, in: Capsule())
                        .foregroundStyle(AdminSurface.primary)
                    }
                }
            }

            // Hero Retail Price Input Card
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("Price_Retail", alter: "سعر البيع"))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primary)

                    TextField("0.00", text: $retailPriceText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)

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

                // Micro-Stepper Touch Buttons Row
                HStack(spacing: 8) {
                    ForEach([-5.0, -1.0, 1.0, 5.0], id: \.self) { step in
                        Button {
                            applyPriceStep(step)
                        } label: {
                            Text(String(format: "%@%.0f", step > 0 ? "+" : "", step))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AdminSurface.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.5))
                        }
                    }
                }
                .padding(.top, 2)

                // Quick Commercial Percentage Presets
                HStack(spacing: 6) {
                    ForEach([5, 10, 15, 20], id: \.self) { pct in
                        Button {
                            applyPercentagePreset(Double(pct))
                        } label: {
                            Text("+\(pct)%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(AdminSurface.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                        }
                    }

                    Spacer()

                    // .99 Ending Button
                    Button {
                        applyPsychologicalEnding(0.99)
                    } label: {
                        Text(".99")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AdminSurface.control, in: Capsule())
                    }

                    // .00 Ending Button
                    Button {
                        applyPsychologicalEnding(0.00)
                    } label: {
                        Text(".00")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AdminSurface.control, in: Capsule())
                    }
                }
                .padding(.top, 4)
            }

            // Wholesale Price Section (Optional Cost Basis)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Language.get("Price_Wholesale", alter: "سعر الجملة (اختياري)"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    if currentAvgWholesalePrice > 0 && wholesalePriceText.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            wholesalePriceText = String(format: "%.2f", currentAvgWholesalePrice)
                        } label: {
                            Text(Language.get("Variant_Studio_Match_Base_Price", alter: "مطابقة التكلفة"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AdminSurface.primary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField("0.00", text: $wholesalePriceText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)

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

            // Live Profit & Margin Telemetry Deck
            liveProfitTelemetryDeck
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - Live Profit Telemetry Deck

    @ViewBuilder
    private var liveProfitTelemetryDeck: some View {
        if let wholesale = wholesalePrice, wholesale > 0 && retailPrice > 0 {
            if isWholesaleExceedingRetail {
                // Hazard Warning Pill
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Variant_Bulk_Wholesale_Warning_Title", alter: "تنبيه: سعر الجملة يتجاوز سعر البيع!"))
                            .font(AdminType.captionRegular)
                            .foregroundStyle(AdminSurface.amber)
                        Text(String(format: Language.get("Variant_Bulk_Wholesale_Loss_Format", alter: "خسارة لكل وحدة: -%.2f %@"), wholesale - retailPrice, Language.get("QAR", alter: "ر.ق")))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AdminSurface.amber)
                    }
                    Spacer()
                }
                .padding(10)
                .background(AdminSurface.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.amber.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 12) {
                    // Margin Pct
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("Variant_Bulk_Margin_Percent", alter: "نسبة الهامش"))
                                .font(AdminType.captionRegular)
                        }
                        .foregroundStyle(AdminSurface.secondaryText)

                        Text(String(format: "%.1f%%", grossMarginPct))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.emerald)
                    }

                    Spacer()

                    // Unit Profit
                    VStack(alignment: .center, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("Variant_Bulk_Unit_Profit", alter: "الربح الصافي"))
                                .font(AdminType.captionRegular)
                        }
                        .foregroundStyle(AdminSurface.secondaryText)

                        Text(String(format: "+%.2f %@", unitProfit, Language.get("QAR", alter: "ر.ق")))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.emerald)
                    }

                    Spacer()

                    // Markup Multiplier
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "multiply.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(Language.get("Variant_Bulk_Cost_Multiplier", alter: "مضاعف التكلفة"))
                                .font(AdminType.captionRegular)
                        }
                        .foregroundStyle(AdminSurface.secondaryText)

                        Text(String(format: "%.2fx", costMarkup))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                }
                .padding(12)
                .background(AdminSurface.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.emerald.opacity(0.2), lineWidth: 1))
            }
        } else if retailPrice > 0 {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(Language.get("Variant_Bulk_Cost_Tip", alter: "أدخل سعر الجملة لعرض هامش الربح والتحليلات المالية فورياً."))
                    .font(AdminType.captionRegular)
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - 4. Valuation Shift Projection Card

    @ViewBuilder
    private var batchValuationProjectionSurface: some View {
        if retailPrice > 0 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_Bulk_Projection_Title", alter: "أثر التسعير على المحفظة"))
                        .font(AdminType.headlineBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                HStack(spacing: 12) {
                    // Average Price Shift
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Variant_Bulk_Shift_Title", alter: "التغير في متوسط السعر"))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AdminSurface.secondaryText)

                        let delta = avgPriceShift
                        Text(String(format: "%@%.2f %@", delta >= 0 ? "+" : "", delta, Language.get("QAR", alter: "ر.ق")))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(delta >= 0 ? AdminSurface.emerald : AdminSurface.amber)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Total Valuation
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Language.get("Variant_Bulk_Total_Value_Title", alter: "إجمالي قيمة المخزون"))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AdminSurface.secondaryText)

                        let totalValuation = retailPrice * Double(totalStockImpacted)
                        Text(String(format: "%.0f %@", totalValuation, Language.get("QAR", alter: "ر.ق")))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(16)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
        }
    }

    // MARK: - 5. Frosted Glass Action Dock

    private var studioActionDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline)

            HStack(spacing: 12) {
                // Secondary Cancel Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 84, height: 52)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 1))
                }

                // Primary Apply Button
                Button {
                    guard isPriceValid && !isSubmitting else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isSubmitting = true
                    onApply(retailPrice, wholesalePrice, targetVariants.map(\.productId))
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                            Text(Language.get("Variant_Bulk_Applying", alter: "جاري تطبيق الأسعار..."))
                                .font(AdminType.calloutBold)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))

                            let title = targetVariants.count > 1
                                ? String(format: Language.get("Variant_Bulk_Apply_Action_Format", alter: "تطبيق السعر على %d أصناف"), targetVariants.count)
                                : Language.get("Variant_Bulk_Apply_Single", alter: "تطبيق السعر على الصنف المستهدف")

                            Text(title)
                                .font(AdminType.calloutBold)
                        }
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

    // MARK: - Business Logic & Helpers

    private func setupInitialValues() {
        if currentAvgRetailPrice > 0 && retailPriceText.isEmpty {
            retailPriceText = String(format: "%.2f", currentAvgRetailPrice)
        }
        if currentAvgWholesalePrice > 0 && wholesalePriceText.isEmpty {
            wholesalePriceText = String(format: "%.2f", currentAvgWholesalePrice)
        }
    }

    private func applyPriceStep(_ step: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let current = retailPrice > 0 ? retailPrice : (currentAvgRetailPrice > 0 ? currentAvgRetailPrice : 10.0)
        let newPrice = max(1.0, current + step)
        retailPriceText = String(format: "%.2f", newPrice)
    }

    private func applyPercentagePreset(_ percent: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let base = currentAvgRetailPrice > 0 ? currentAvgRetailPrice : (retailPrice > 0 ? retailPrice : 50.0)
        let newPrice = base * (1.0 + (percent / 100.0))
        retailPriceText = String(format: "%.2f", newPrice)
    }

    private func applyPsychologicalEnding(_ ending: Double) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let current = retailPrice > 0 ? retailPrice : (currentAvgRetailPrice > 0 ? currentAvgRetailPrice : 50.0)
        let whole = floor(current)
        let newPrice = whole + ending
        retailPriceText = String(format: "%.2f", newPrice)
    }
}


// MARK: - Category-Defining Variant Studio Workbench

struct PPAccessoryCreateCombinationSheet: View {
    let combination: PPAccessoryMatrixCombination
    let family: PPAccessoryVariantFamily?
    let errorMessage: () -> String?
    let onCreate: (String, String, Double, Double?, Int, [UIImage]) async -> Bool

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

                        if let message = errorMessage() {
                            Label(message, systemImage: "exclamationmark.circle")
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityIdentifier("options.create.failure")
                        }

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("Variant_Studio_Hero_Title", alter: "إنشاء وتثبيت المتغير"))
                        .font(PPBrandFont.bold(size: 18, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(PPBrandFont.medium(size: 15, relativeTo: .callout))
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
                PPBrandFont.registerIfNeeded()
                setupDefaults()
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primary)

                    TextField("0.00", text: $retailPriceText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)

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
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField("0.00", text: $wholesalePriceText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)

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
                VStack(spacing: 2) {
                    Text(verbatim: "\(quantity.englishDigits)")
                        .font(PPBrandFont.bold(size: 30, relativeTo: .title))
                        .foregroundStyle(quantity > 0 ? AdminSurface.primaryText : AdminSurface.secondaryText)
                        .monospacedDigit()
                    Text(Language.get("Piece", alter: "حبة"))
                        .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

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
                        Text(verbatim: amount == 0 ? "0" : "+\(amount.englishDigits)")
                            .font(PPBrandFont.medium(size: 13, relativeTo: .caption))
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
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("SKU_Placeholder", alter: "رمز الصنف"), text: $skuText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)

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
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Image(systemName: "barcode")
                        .font(.system(size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("Barcode_Placeholder", alter: "الباركود الدولي"), text: $barcodeText)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.leading)

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
                    Task {
                        _ = await onCreate(skuText, barcodeText, retailPrice, wholesalePrice, quantity, stagedImages)
                        isSubmitting = false
                    }
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
