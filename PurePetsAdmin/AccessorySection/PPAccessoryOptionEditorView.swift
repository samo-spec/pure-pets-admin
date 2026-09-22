//
//  PPAccessoryOptionEditorView.swift
//  PurePetsAdmin
//
//  Product Options Editor — Phase 5 of the Product Variants System.
//  Provides Apple-grade, studio-crafted management of option definitions
//  (Color, Size, Weight, Material, Flavor, Custom) and their localized values.
//

import SwiftUI
import UIKit

// MARK: - Active Sheet Enum

enum PPAccessoryOptionSheetItem: Identifiable {
    case optionPalette
    case addCustomOption
    case addCustomValue(option: PPAccessoryOptionDefinition)
    case colorLibrary(optionId: String)
    case editOption(optionId: String)

    var id: String {
        switch self {
        case .optionPalette:
            return "optionPalette"
        case .addCustomOption:
            return "addCustomOption"
        case .addCustomValue(let option):
            return "addCustomValue-\(option.id)"
        case .colorLibrary(let optionId):
            return "colorLibrary-\(optionId)"
        case .editOption(let optionId):
            return "editOption-\(optionId)"
        }
    }
}

// MARK: - Option Editor View

struct PPAccessoryOptionEditorView: View {
    @ObservedObject var model: PPAccessoryVariantSectionModel
    var showHeader: Bool = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var activeSheet: PPAccessoryOptionSheetItem?
    @State private var optionToDelete: PPAccessoryOptionDefinition?
    @State private var valueToDelete: (optionId: String, value: PPAccessoryOptionValue)?
    @State private var showDeleteValueWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showHeader {
                headerBar
            }

            if let draft = model.draft {
                if draft.optionDefinitions.isEmpty {
                    emptyOptionsState
                } else {
                    optionsList(draft: draft)
                }
            }
        }
        .sheet(item: $activeSheet) { item in
            switch item {
            case .optionPalette:
                if let draft = model.draft {
                    PPOptionPresetActionSheet(
                        draft: draft,
                        onSelectPreset: { preset in
                            model.addOption(preset)
                            activeSheet = nil
                        },
                        onSelectCustom: {
                            activeSheet = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                activeSheet = .addCustomOption
                            }
                        }
                    )
                }
            case .addCustomOption:
                PPAccessoryCustomOptionSheet { newOption in
                    model.addOption(newOption)
                    activeSheet = nil
                }
            case .addCustomValue(let option):
                PPAccessoryCustomValueSheet(option: option) { newValue in
                    model.addOptionValue(newValue, toOptionWithId: option.id)
                    activeSheet = nil
                }
            case .colorLibrary(let optionId):
                PPAccessoryVariantColorEditorSheet(
                    initialColor: nil,
                    usedIdentifiers: Set(model.draft?.optionDefinitions.first(where: { $0.id == optionId })?.values.map(\.id) ?? []),
                    excludingIdentifier: nil
                ) { chosenColor in
                    let value = PPAccessoryOptionValue.fromVariantColor(chosenColor)
                    model.addOptionValue(value, toOptionWithId: optionId)
                    activeSheet = nil
                }
            case .editOption:
                EmptyView()
            }
        }
        .confirmationDialog(
            Language.get("Options_Delete_Confirm_Title", alter: "حذف الخيار"),
            isPresented: Binding(
                get: { optionToDelete != nil },
                set: { if !$0 { optionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                if let opt = optionToDelete {
                    model.removeOption(withId: opt.id)
                }
                optionToDelete = nil
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                optionToDelete = nil
            }
        } message: {
            Text(Language.get(
                "Options_Delete_Confirm_Message",
                alter: "هل أنت متأكد من حذف هذا الخيار؟ لن يتم حذف المنتجات الحالية المرتبطة به."
            ))
        }
        .confirmationDialog(
            Language.get("Delete", alter: "حذف"),
            isPresented: $showDeleteValueWarning,
            titleVisibility: .visible
        ) {
            Button(Language.get("Delete", alter: "حذف"), role: .destructive) {
                if let target = valueToDelete {
                    model.removeOptionValue(valueId: target.value.id, fromOptionWithId: target.optionId)
                }
                valueToDelete = nil
            }
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {
                valueToDelete = nil
            }
        } message: {
            Text(Language.get(
                "Options_Value_Delete_InUse_Warning",
                alter: "هذه القيمة مستخدمة بالفعل في بعض المتغيرات. هل أنت متأكد من حذفها؟"
            ))
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(Language.get("Options_Section_Title", alter: "خيارات المنتج"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    if let draft = model.draft {
                        let count = draft.optionDefinitions.count
                        let max = PPAccessoryVariantContract.maxOptionsPerFamily
                        Text("\(count) / \(max)")
                            .font(AdminType.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.container, in: Capsule())
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Text(Language.get("Options_Section_Subtitle", alter: "عرّف الخيارات مثل الألوان والمقاسات والأوزان وقيم كل خيار."))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let draft = model.draft, model.canManageVariants {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    activeSheet = .optionPalette
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Options_Add_Option", alter: "إضافة خيار"))
                            .font(PPBrandFont.bold(size: 12.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(AdminSurface.primary.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(AdminSurface.primary)
                .disabled(draft.optionDefinitions.count >= PPAccessoryVariantContract.maxOptionsPerFamily)
                .accessibilityLabel(Language.get("Options_Add_Option", alter: "إضافة خيار"))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Preset Option Buttons

    @ViewBuilder
    private func presetOptionButtons(draft: PPAccessoryVariantFamily) -> some View {
        let existingKeys = Set(draft.optionDefinitions.map(\.key))

        if !existingKeys.contains("color") {
            Button {
                model.addOption(.presetColor())
            } label: {
                Label(
                    Language.get("Options_Preset_Color", alter: "اللون"),
                    systemImage: "paintpalette.fill"
                )
            }
        }

        if !existingKeys.contains("size") {
            Button {
                model.addOption(.presetSize())
            } label: {
                Label(
                    Language.get("Options_Preset_Size", alter: "المقاس"),
                    systemImage: "ruler.fill"
                )
            }
        }

        if !existingKeys.contains("weight") {
            Button {
                model.addOption(.presetWeight())
            } label: {
                Label(
                    Language.get("Options_Preset_Weight", alter: "الوزن"),
                    systemImage: "scalemass.fill"
                )
            }
        }

        if !existingKeys.contains("material") {
            Button {
                model.addOption(.presetMaterial())
            } label: {
                Label(
                    Language.get("Options_Preset_Material", alter: "المادة"),
                    systemImage: "cube.box.fill"
                )
            }
        }

        if !existingKeys.contains("flavor") {
            Button {
                model.addOption(.presetFlavor())
            } label: {
                Label(
                    Language.get("Options_Preset_Flavor", alter: "النكهة"),
                    systemImage: "fork.knife"
                )
            }
        }

        Divider()

        Button {
            activeSheet = .addCustomOption
        } label: {
            Label(
                Language.get("Options_Preset_Custom", alter: "خيار مخصص..."),
                systemImage: "slider.horizontal.3"
            )
        }
    }

    // MARK: - Empty State

    private var emptyOptionsState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AdminSurface.container)
                    .frame(width: 48, height: 48)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            VStack(spacing: 4) {
                Text(Language.get("Options_Empty_Title", alter: "لا توجد خيارات بعد"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("Options_Empty_Subtitle", alter: "أضف خيارًا كالألوان أو المقاسات لإنشاء متغيرات متعددة للمنتج."))
                    .font(AdminType.caption1)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if model.canManageVariants {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    activeSheet = .optionPalette
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("Options_Add_Option", alter: "إضافة خيار"))
                            .font(PPBrandFont.bold(size: 13))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(AdminSurface.primary.opacity(0.28), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(AdminSurface.primary)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(AdminSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Options List

    private func optionsList(draft: PPAccessoryVariantFamily) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(draft.optionDefinitions.enumerated()), id: \.element.id) { index, option in
                optionCard(option: option, index: index, totalCount: draft.optionDefinitions.count)
            }
        }
    }

    // MARK: - Single Option Card

    private func optionCard(option: PPAccessoryOptionDefinition, index: Int, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Top Row
            HStack(spacing: 8) {
                // Option Icon
                optionIcon(for: option)

                // Option Title
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.localizedName)
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(String(format: Language.get("Options_Values_Count", alter: "%@ قيم"), NSNumber(value: option.values.count)))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer(minLength: 8)

                // Reorder controls
                if model.canManageVariants && totalCount > 1 {
                    HStack(spacing: 2) {
                        Button {
                            model.moveOptionEarlier(id: option.id)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(AdminSurface.container, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        .foregroundStyle(index == 0 ? AdminSurface.secondaryText.opacity(0.3) : AdminSurface.secondaryText)
                        .accessibilityLabel(Language.get("MoveEarlier", alter: "تحريك للأمام"))

                        Button {
                            model.moveOptionLater(id: option.id)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26)
                                .background(AdminSurface.container, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(index == totalCount - 1)
                        .foregroundStyle(index == totalCount - 1 ? AdminSurface.secondaryText.opacity(0.3) : AdminSurface.secondaryText)
                        .accessibilityLabel(Language.get("MoveLater", alter: "تحريك للخلف"))
                    }
                }

                // Delete option button
                if model.canManageVariants {
                    Button {
                        optionToDelete = option
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .frame(width: 26, height: 26)
                            .background(AdminSurface.danger.opacity(0.1), in: Circle())
                            .foregroundStyle(AdminSurface.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Language.get("Delete", alter: "حذف"))
                }
            }

            Divider()
                .background(AdminSurface.hairline)

            // Values Shelf
            valuesShelf(for: option)

            // Quick Add Presets Shelf
            if model.canManageVariants && option.values.count < PPAccessoryVariantContract.maxValuesPerOption {
                presetsAndAddRow(for: option)
            }
        }
        .padding(14)
        .background(AdminSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    // MARK: - Option Icon

    private func optionIcon(for option: PPAccessoryOptionDefinition) -> some View {
        let (iconName, tint): (String, Color) = {
            if option.isColorOption {
                return ("paintpalette.fill", AdminSurface.primary)
            } else if option.isSizeOption {
                return ("ruler.fill", Color(red: 0.15, green: 0.65, blue: 0.55))
            } else if option.isWeightOption {
                return ("scalemass.fill", Color(red: 0.85, green: 0.55, blue: 0.15))
            } else if option.isMaterialOption {
                return ("cube.box.fill", Color(red: 0.45, green: 0.45, blue: 0.85))
            } else if option.isFlavorOption {
                return ("fork.knife", Color(red: 0.85, green: 0.35, blue: 0.35))
            } else {
                return ("slider.horizontal.3", AdminSurface.secondaryText)
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 32, height: 32)

            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    // MARK: - Values Shelf

    @ViewBuilder
    private func valuesShelf(for option: PPAccessoryOptionDefinition) -> some View {
        if option.values.isEmpty {
            Text(Language.get("Options_No_Values_Yet", alter: "لم يتم إضافة أي قيمة بعد لهذا الخيار."))
                .font(AdminType.caption1)
                .foregroundStyle(AdminSurface.secondaryText)
                .padding(.vertical, 4)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(option.values.enumerated()), id: \.element.id) { index, value in
                        valueChip(value: value, option: option, index: index, total: option.values.count)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Value Chip

    private func valueChip(value: PPAccessoryOptionValue, option: PPAccessoryOptionDefinition, index: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            // Swatch if color
            if option.isColorOption, let uiColor = value.uiColor {
                Circle()
                    .fill(Color(uiColor: uiColor))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                value.requiresContrastBorder
                                    ? AdminSurface.hairline
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
            }

            // Label
            Text(value.localizedName)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            // Remove button
            if model.canManageVariants {
                Button {
                    let inUse = model.isOptionValueInUse(valueId: value.id, optionId: option.id)
                    if inUse {
                        valueToDelete = (optionId: option.id, value: value)
                        showDeleteValueWarning = true
                    } else {
                        model.removeOptionValue(valueId: value.id, fromOptionWithId: option.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 18, height: 18)
                        .background(AdminSurface.container, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Delete", alter: "حذف"))
            }
        }
        .padding(.leading, option.isColorOption ? 8 : 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(AdminSurface.container)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.accessibilityName)
    }

    // MARK: - Presets and Add Row

    @ViewBuilder
    private func presetsAndAddRow(for option: PPAccessoryOptionDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Quick preset pills
                if option.isSizeOption {
                    quickSizePresets(for: option)
                } else if option.isWeightOption {
                    quickWeightPresets(for: option)
                } else if option.isColorOption {
                    Button {
                        activeSheet = .colorLibrary(optionId: option.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paintpalette")
                                .font(.system(size: 11))
                            Text(Language.get("Variant_Library", alter: "مكتبة الألوان"))
                                .font(AdminType.caption2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.container, in: Capsule())
                        .foregroundStyle(AdminSurface.primary)
                    }
                    .buttonStyle(.plain)
                }

                // Add Custom Value Button
                Button {
                    activeSheet = .addCustomValue(option: option)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(Language.get("Options_Value_Add_Custom", alter: "قيمة مخصصة..."))
                            .font(AdminType.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.08), in: Capsule())
                    .foregroundStyle(AdminSurface.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Quick Presets (Size)

    private func quickSizePresets(for option: PPAccessoryOptionDefinition) -> some View {
        let existingIds = Set(option.values.map(\.id))
        let availablePresets = PPAccessoryOptionDefinition.standardSizes.filter { !existingIds.contains($0.id) }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(availablePresets, id: \.id) { preset in
                    Button {
                        model.addOptionValue(preset, toOptionWithId: option.id)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text(preset.canonicalValue)
                                .font(AdminType.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.container, in: Capsule())
                        .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add size \(preset.canonicalValue)")
                }
            }
        }
    }

    // MARK: - Quick Presets (Weight)

    private func quickWeightPresets(for option: PPAccessoryOptionDefinition) -> some View {
        let existingIds = Set(option.values.map(\.id))
        let availablePresets = PPAccessoryOptionDefinition.standardWeights.filter { !existingIds.contains($0.id) }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(availablePresets, id: \.id) { preset in
                    Button {
                        model.addOptionValue(preset, toOptionWithId: option.id)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text(preset.canonicalValue)
                                .font(AdminType.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AdminSurface.container, in: Capsule())
                        .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}


// MARK: - Color Hex Helper

fileprivate extension Color {
    init(hex: String) {
        let ui = PPAccessoryVariantColor.color(fromHex: hex) ?? .systemGray
        self.init(uiColor: ui)
    }
}

// MARK: - Option Translation Dictionary

struct PPOptionTranslationDictionary {
    static let pairs: [(ar: String, en: String, canon: String)] = [
        // Option Dimensions / Axes
        ("المقاس", "Size", "size"),
        ("الحجم", "Size", "size"),
        ("مقاس", "Size", "size"),
        ("حجم", "Size", "size"),
        ("الوزن", "Weight", "weight"),
        ("وزن", "Weight", "weight"),
        ("اللون", "Color", "color"),
        ("لون", "Color", "color"),
        ("النكهة", "Flavor", "flavor"),
        ("نكهة", "Flavor", "flavor"),
        ("المادة", "Material", "material"),
        ("مادة", "Material", "material"),
        ("التعبئة", "Packaging", "packaging"),
        ("تعبئة", "Packaging", "packaging"),
        ("الرائحة", "Scent", "scent"),
        ("رائحة", "Scent", "scent"),
        ("السعة", "Capacity", "capacity"),
        ("سعة", "Capacity", "capacity"),
        ("الموديل", "Model", "model"),
        ("موديل", "Model", "model"),
        ("التصميم", "Design", "design"),
        ("تصميم", "Design", "design"),
        ("الطول", "Length", "length"),
        ("طول", "Length", "length"),
        ("العرض", "Width", "width"),
        ("عرض", "Width", "width"),
        ("الارتفاع", "Height", "height"),
        ("ارتفاع", "Height", "height"),
        ("الفئة العمرية", "Age Group", "age_group"),
        ("فئة عمرية", "Age Group", "age_group"),
        ("حجم السلالة", "Breed Size", "breed_size"),
        ("الكمية", "Quantity", "quantity"),
        ("كمية", "Quantity", "quantity"),
        ("النوع", "Type", "type"),
        ("نوع", "Type", "type"),
        // Sizes
        ("صغير جداً جداً", "XX-Small", "XXS"),
        ("صغير جداً", "Extra Small", "XS"),
        ("صغير", "Small", "S"),
        ("وسط", "Medium", "M"),
        ("متوسط", "Medium", "M"),
        ("كبير", "Large", "L"),
        ("كبير جداً", "Extra Large", "XL"),
        ("كبير جداً جداً", "2X-Large", "2XL"),
        ("مقاس موحد", "One Size", "One Size"),
        // Weights
        ("٥٠ جم", "50g", "50g"),
        ("١٠٠ جم", "100g", "100g"),
        ("٢٠٠ جم", "200g", "200g"),
        ("٢٥٠ جم", "250g", "250g"),
        ("٤٠٠ جم", "400g", "400g"),
        ("٥٠٠ جم", "500g", "500g"),
        ("٨٠٠ جم", "800g", "800g"),
        ("١ كجم", "1kg", "1kg"),
        ("١٫٥ كجم", "1.5kg", "1.5kg"),
        ("٢ كجم", "2kg", "2kg"),
        ("٢٫٥ كجم", "2.5kg", "2.5kg"),
        ("٣ كجم", "3kg", "3kg"),
        ("٥ كجم", "5kg", "5kg"),
        ("٧ كجم", "7kg", "7kg"),
        ("١٠ كجم", "10kg", "10kg"),
        ("١٢ كجم", "12kg", "12kg"),
        ("١٥ كجم", "15kg", "15kg"),
        ("٢٠ كجم", "20kg", "20kg"),
        // Flavors
        ("دجاج", "Chicken", "chicken"),
        ("دجاج وأرز", "Chicken & Rice", "chicken_rice"),
        ("لحم بقر", "Beef", "beef"),
        ("لحم غنم", "Lamb", "lamb"),
        ("لحم ضأن", "Lamb", "lamb"),
        ("سلمون", "Salmon", "salmon"),
        ("تونة", "Tuna", "tuna"),
        ("بط", "Duck", "duck"),
        ("ديك رومي", "Turkey", "turkey"),
        ("أرانب", "Rabbit", "rabbit"),
        ("أسماك المحيط", "Ocean Fish", "ocean_fish"),
        ("خضار", "Vegetables", "vegetables"),
        ("جبنة", "Cheese", "cheese"),
        ("نعناع بري", "Catnip", "catnip"),
        ("كبدة", "Liver", "liver"),
        // Materials
        ("جلد طبيعي", "Genuine Leather", "leather"),
        ("جلد", "Leather", "leather"),
        ("قطن", "Cotton", "cotton"),
        ("قطن عضوي", "Organic Cotton", "organic_cotton"),
        ("سيليكون", "Silicone", "silicone"),
        ("نايلون", "Nylon", "nylon"),
        ("ستانلس ستيل", "Stainless Steel", "stainless_steel"),
        ("فولاذ مقاوم للصدأ", "Stainless Steel", "stainless_steel"),
        ("خشب طبيعي", "Natural Wood", "wood"),
        ("خشب", "Wood", "wood"),
        ("سيراميك", "Ceramic", "ceramic"),
        ("فرو ناعم", "Plush / Fleece", "plush"),
        ("مطاط طبيعي", "Natural Rubber", "rubber"),
        ("مطاط", "Rubber", "rubber"),
        ("بلاستيك مقوى", "Reinforced Plastic", "plastic"),
        ("شبك نفاذ", "Breathable Mesh", "mesh"),
        // Colors
        ("أحمر", "Red", "red"),
        ("أزرق", "Blue", "blue"),
        ("أخضر", "Green", "green"),
        ("أصفر", "Yellow", "yellow"),
        ("أسود", "Black", "black"),
        ("أبيض", "White", "white"),
        ("رمادي", "Grey", "grey"),
        ("وردي", "Pink", "pink"),
        ("بنفسجي", "Purple", "purple"),
        ("برتقالي", "Orange", "orange"),
        ("بني", "Brown", "brown"),
        ("بيج", "Beige", "beige"),
        ("ذهبي", "Gold", "gold"),
        ("فضي", "Silver", "silver"),
        ("كحلي", "Navy Blue", "navy"),
        ("فيروزي", "Turquoise", "turquoise"),
        ("زيتي", "Olive", "olive"),
    ]

    static func translate(text: String, isArabicInput: Bool) -> (counterpart: String, canonical: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        for pair in pairs {
            if isArabicInput {
                if pair.ar.lowercased() == trimmed || pair.ar.contains(trimmed) || trimmed.contains(pair.ar.lowercased()) {
                    return (pair.en, pair.canon)
                }
            } else {
                if pair.en.lowercased() == trimmed || pair.canon.lowercased() == trimmed {
                    return (pair.ar, pair.canon)
                }
            }
        }
        return nil
    }
}

// MARK: - Curated Color Presets

struct PPOptionColorPreset: Identifiable {
    let id: String
    let hex: String
    let nameAr: String
    let nameEn: String

    var color: Color { Color(hex: hex) }

    static let all: [PPOptionColorPreset] = [
        PPOptionColorPreset(id: "black", hex: "#18181B", nameAr: "أسود ليلي", nameEn: "Midnight Black"),
        PPOptionColorPreset(id: "white", hex: "#F8FAFC", nameAr: "أبيض لؤلؤي", nameEn: "Pearl White"),
        PPOptionColorPreset(id: "royal_blue", hex: "#2563EB", nameAr: "أزرق ملكي", nameEn: "Royal Blue"),
        PPOptionColorPreset(id: "emerald", hex: "#059669", nameAr: "أخضر زمردي", nameEn: "Emerald Green"),
        PPOptionColorPreset(id: "coral", hex: "#E11D48", nameAr: "وردي مرجاني", nameEn: "Coral Pink"),
        PPOptionColorPreset(id: "amber", hex: "#D97706", nameAr: "عنبري دافئ", nameEn: "Warm Amber"),
        PPOptionColorPreset(id: "purple", hex: "#7C3AED", nameAr: "أرجواني ملكي", nameEn: "Imperial Purple"),
        PPOptionColorPreset(id: "teal", hex: "#0D9488", nameAr: "تركواز بحري", nameEn: "Ocean Teal"),
        PPOptionColorPreset(id: "charcoal", hex: "#4B5563", nameAr: "رمادي فحمي", nameEn: "Charcoal Grey"),
        PPOptionColorPreset(id: "chocolate", hex: "#78350F", nameAr: "شوكولاتة", nameEn: "Chocolate Brown"),
        PPOptionColorPreset(id: "sand", hex: "#D4B996", nameAr: "رملي بيج", nameEn: "Desert Sand"),
        PPOptionColorPreset(id: "sky", hex: "#38BDF8", nameAr: "سماوي ناعم", nameEn: "Sky Blue"),
    ]
}

// MARK: - Studio Option Preset Action Sheet (Atelier Option Palette Drawer)

struct PPOptionPresetActionSheet: View {
    let draft: PPAccessoryVariantFamily
    let onSelectPreset: (PPAccessoryOptionDefinition) -> Void
    let onSelectCustom: () -> Void

    @Environment(\.dismiss) private var dismiss

    struct OptionPresetItem: Identifiable {
        let id: String
        let key: String
        let icon: String
        let nameAr: String
        let nameEn: String
        let hintAr: String
        let hintEn: String
        let gradientColors: [Color]
        let strokeColor: Color
        let createDefinition: () -> PPAccessoryOptionDefinition
    }

    private var presets: [OptionPresetItem] {
        [
            OptionPresetItem(
                id: "size",
                key: "size",
                icon: "ruler.fill",
                nameAr: "المقاس",
                nameEn: "Size",
                hintAr: "مثل: S، M، L، XL",
                hintEn: "e.g. S, M, L, XL",
                gradientColors: [Color.indigo.opacity(0.22), Color.indigo.opacity(0.08)],
                strokeColor: Color.indigo.opacity(0.30),
                createDefinition: { PPAccessoryOptionDefinition.presetSize() }
            ),
            OptionPresetItem(
                id: "weight",
                key: "weight",
                icon: "scalemass.fill",
                nameAr: "الوزن",
                nameEn: "Weight",
                hintAr: "مثل: 2 كجم، 5 كجم",
                hintEn: "e.g. 2kg, 5kg",
                gradientColors: [Color.orange.opacity(0.22), Color.orange.opacity(0.08)],
                strokeColor: Color.orange.opacity(0.30),
                createDefinition: { PPAccessoryOptionDefinition.presetWeight() }
            ),
            OptionPresetItem(
                id: "material",
                key: "material",
                icon: "cube.box.fill",
                nameAr: "المادة",
                nameEn: "Material",
                hintAr: "مثل: جلد، قماش، معدن",
                hintEn: "e.g. Leather, Nylon, Steel",
                gradientColors: [Color.blue.opacity(0.22), Color.blue.opacity(0.08)],
                strokeColor: Color.blue.opacity(0.30),
                createDefinition: { PPAccessoryOptionDefinition.presetMaterial() }
            ),
            OptionPresetItem(
                id: "flavor",
                key: "flavor",
                icon: "fork.knife",
                nameAr: "النكهة",
                nameEn: "Flavor",
                hintAr: "مثل: دجاج، سلمون، لحم",
                hintEn: "e.g. Chicken, Salmon, Beef",
                gradientColors: [Color.green.opacity(0.22), Color.green.opacity(0.08)],
                strokeColor: Color.green.opacity(0.30),
                createDefinition: { PPAccessoryOptionDefinition.presetFlavor() }
            ),
            OptionPresetItem(
                id: "color",
                key: "color",
                icon: "paintpalette.fill",
                nameAr: "اللون",
                nameEn: "Color",
                hintAr: "مثل: أحمر، أزرق، أسود",
                hintEn: "e.g. Red, Blue, Black",
                gradientColors: [Color.purple.opacity(0.22), Color.purple.opacity(0.08)],
                strokeColor: Color.purple.opacity(0.30),
                createDefinition: { PPAccessoryOptionDefinition.presetColor() }
            )
        ]
    }

    private var remainingCapacity: Int {
        max(0, PPAccessoryVariantContract.maxOptionsPerFamily - draft.optionDefinitions.count)
    }

    private var isAtCapacity: Bool {
        remainingCapacity <= 0
    }

    private func isAlreadyAdded(preset: OptionPresetItem) -> Bool {
        draft.optionDefinitions.contains { $0.key == preset.key || $0.id == preset.key }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Deck
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 14)

                Divider()
                    .overlay(AdminSurface.hairline)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Presets Section Title & Status
                        HStack {
                            Text(Language.isRTL() ? "الخيارات الجاهزة" : "PRESET OPTIONS")
                                .font(PPBrandFont.bold(size: 11.5))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .textCase(.uppercase)

                            Spacer()

                            if isAtCapacity {
                                Text(Language.get("Options_Max_Reached", alter: "تم الوصول للحد الأقصى (3)"))
                                    .font(PPBrandFont.medium(size: 11))
                                    .foregroundStyle(AdminSurface.amber)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                        // 2-Column Preset Grid
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            ForEach(presets) { preset in
                                presetCard(preset: preset)
                            }
                        }
                        .padding(.horizontal, 16)

                        // Custom Option Launchpad
                        customOptionLaunchpad
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 20)
                    }
                }
            }
            .background(AdminSurface.background)
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            .presentationDetents([.height(490), .medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            // Chromatic Studio Jewel Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AdminSurface.primary.opacity(0.18),
                                AdminSurface.primary.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 0.75)
                    )

                Image(systemName: "slider.horizontal.2.square.on.square")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("Options_Add_Modal_Title", alter: "إضافة خيار للمنتج"))
                    .font(PPBrandFont.bold(size: 17))
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isAtCapacity ? AdminSurface.amber : AdminSurface.emerald)
                        .frame(width: 6, height: 6)

                    Text(String(
                        format: Language.get("Options_Remaining_Capacity", alter: "متبقي %d من %d خيارات"),
                        remainingCapacity,
                        PPAccessoryVariantContract.maxOptionsPerFamily
                    ))
                    .font(PPBrandFont.medium(size: 11.5))
                    .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            Spacer(minLength: 8)

            // Close Button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(AdminSurface.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("Common_Close", alter: "إغلاق"))
        }
    }

    // MARK: - Preset Card

    private func presetCard(preset: OptionPresetItem) -> some View {
        let added = isAlreadyAdded(preset: preset)
        let disabled = added || isAtCapacity
        let name = Language.isRTL() ? preset.nameAr : preset.nameEn
        let hint = Language.isRTL() ? preset.hintAr : preset.hintEn

        return Button {
            guard !disabled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSelectPreset(preset.createDefinition())
            dismiss()
        } label: {
            HStack(spacing: 10) {
                // Preset Jewel Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(
                            colors: preset.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(preset.strokeColor, lineWidth: 0.75)
                        )

                    Image(systemName: preset.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(preset.gradientColors.first ?? AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(PPBrandFont.bold(size: 14))
                            .foregroundStyle(disabled ? AdminSurface.secondaryText : AdminSurface.primaryText)
                            .lineLimit(1)

                        if added {
                            Text(Language.get("Options_Already_Added", alter: "مضاف"))
                                .font(PPBrandFont.bold(size: 9))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(AdminSurface.container, in: Capsule())
                        }
                    }

                    Text(hint)
                        .font(PPBrandFont.regular(size: 10.5))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        added ? AdminSurface.hairline.opacity(0.5) : AdminSurface.hairline,
                        lineWidth: 0.75
                    )
            )
            .opacity(disabled ? 0.60 : 1.0)
        }
        .buttonStyle(PPOptionCardPressStyle())
        .disabled(disabled)
        .accessibilityLabel("\(name), \(hint)\(added ? ", " + Language.get("Options_Already_Added", alter: "مضاف") : "")")
    }

    // MARK: - Custom Option Launchpad

    private var customOptionLaunchpad: some View {
        Button {
            guard !isAtCapacity else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
            onSelectCustom()
        } label: {
            HStack(spacing: 12) {
                // Primary Chromatic Jewel
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AdminSurface.primary.opacity(0.18),
                                    AdminSurface.primary.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AdminSurface.primary.opacity(0.30), lineWidth: 0.75)
                        )

                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Options_Preset_Custom", alter: "خيار مخصص..."))
                        .font(PPBrandFont.bold(size: 15))
                        .foregroundStyle(isAtCapacity ? AdminSurface.secondaryText : AdminSurface.primaryText)

                    Text(Language.get("Options_Preset_Custom_Desc", alter: "عرّف خياراً خاصاً كالحجم، الطول، الرائحة، أو التعبئة"))
                        .font(PPBrandFont.regular(size: 11.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: Language.isRTL() ? "chevron.backward" : "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(AdminSurface.control, in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AdminSurface.primary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            .opacity(isAtCapacity ? 0.6 : 1.0)
        }
        .buttonStyle(PPOptionCardPressStyle())
        .disabled(isAtCapacity)
        .accessibilityLabel(Language.get("Options_Preset_Custom", alter: "خيار مخصص..."))
    }
}

fileprivate struct PPOptionCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Studio Custom Option Sheet

struct PPAccessoryCustomOptionSheet: View {
    let onAdd: (PPAccessoryOptionDefinition) -> Void

    @Environment(\.dismiss) private var dismiss

    struct PresetCategory: Identifiable {
        let id: String
        let icon: String
        let nameAr: String
        let nameEn: String
        let tint: Color
    }

    private let categories: [PresetCategory] = [
        PresetCategory(id: "size", icon: "ruler.fill", nameAr: "المقاس", nameEn: "Size", tint: .indigo),
        PresetCategory(id: "weight", icon: "scalemass.fill", nameAr: "الوزن", nameEn: "Weight", tint: .orange),
        PresetCategory(id: "color", icon: "paintpalette.fill", nameAr: "اللون", nameEn: "Color", tint: .purple),
        PresetCategory(id: "flavor", icon: "fork.knife", nameAr: "النكهة", nameEn: "Flavor", tint: .green),
        PresetCategory(id: "material", icon: "cube.fill", nameAr: "المادة", nameEn: "Material", tint: .blue),
        PresetCategory(id: "packaging", icon: "shippingbox.fill", nameAr: "التعبئة", nameEn: "Packaging", tint: .brown),
        PresetCategory(id: "scent", icon: "leaf.fill", nameAr: "الرائحة", nameEn: "Scent", tint: .teal),
        PresetCategory(id: "custom", icon: "slider.horizontal.3", nameAr: "مخصص", nameEn: "Custom", tint: AdminSurface.primary)
    ]

    @State private var selectedCategory: String = "custom"
    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var key: String = ""
    @State private var autoDeriveKey: Bool = true

    var isValid: Bool {
        let ar = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        return !ar.isEmpty || !en.isEmpty
    }

    var activeCategory: PresetCategory {
        categories.first(where: { $0.id == selectedCategory }) ?? categories.last!
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Category Presets Carousel
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Language.isRTL() ? "نوع الخيار • OPTION TYPE" : "OPTION TYPE • نوع الخيار")
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.horizontal, 4)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories) { cat in
                                    let isSelected = (selectedCategory == cat.id)
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                            selectedCategory = cat.id
                                            if cat.id != "custom" {
                                                nameAr = cat.nameAr
                                                nameEn = cat.nameEn
                                                key = cat.id
                                                autoDeriveKey = false
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: cat.icon)
                                                .font(.system(size: 13, weight: .bold))
                                            Text(Language.isRTL() ? cat.nameAr : cat.nameEn)
                                                .font(AdminType.captionBold)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? cat.tint : AdminSurface.card,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 1)
                                        )
                                        .shadow(color: isSelected ? cat.tint.opacity(0.35) : Color.clear, radius: 6, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }

                    // Hero Live Option Preview
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(isValid ? AdminSurface.emerald : AdminSurface.amber)
                                .frame(width: 7, height: 7)
                            Text(Language.get("Options_Studio_OptionPreview", alter: "معاينة الخيار في النظام"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                            Text("AXIS")
                                .font(AdminType.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(activeCategory.tint.opacity(0.12), in: Capsule())
                                .foregroundStyle(activeCategory.tint)
                        }

                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(activeCategory.tint.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: activeCategory.icon)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(activeCategory.tint)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(nameAr.isEmpty ? (Language.isRTL() ? "اسم الخيار" : "Option Name") : nameAr)
                                    .font(AdminType.headline)
                                    .foregroundStyle(AdminSurface.primaryText)

                                Text(nameEn.isEmpty ? "Option Name (English)" : nameEn)
                                    .font(AdminType.footnote)
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("key")
                                    .font(AdminType.caption2)
                                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                                Text(resolvedKey)
                                    .font(AdminType.captionBold.monospaced())
                                    .foregroundStyle(AdminSurface.primaryText)
                            }
                        }
                    }
                    .padding(16)
                    .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(activeCategory.tint.opacity(0.25), lineWidth: 1.2)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)

                    // Studio Bilingual Inputs Deck
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Language.isRTL() ? "بيانات الهوية • IDENTITY" : "IDENTITY • بيانات الهوية")
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .padding(.horizontal, 4)

                        // Arabic Name Field
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "globe.asia.australia.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AdminSurface.emerald)
                                Text(Language.get("Variant_NameAr", alter: "الاسم بالعربية"))
                                    .font(AdminType.captionBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                            }

                            HStack {
                                TextField("مثال: الحجم، النكهة...", text: $nameAr)
                                    .font(AdminType.calloutBold)
                                    .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                                    .onChange(of: nameAr) { newVal in
                                        if autoDeriveKey && !newVal.isEmpty {
                                            if let tr = PPOptionTranslationDictionary.translate(text: newVal, isArabicInput: true) {
                                                if nameEn.isEmpty { nameEn = tr.counterpart }
                                                key = tr.canonical
                                            }
                                        }
                                    }

                                if !nameAr.isEmpty {
                                    Button {
                                        nameAr = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                            )
                        }

                        // Pury Smart Auto-Translate Bridge
                        HStack {
                            Spacer()
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if !nameAr.isEmpty && nameEn.isEmpty {
                                    if let tr = PPOptionTranslationDictionary.translate(text: nameAr, isArabicInput: true) {
                                        nameEn = tr.counterpart
                                        key = tr.canonical
                                    } else {
                                        nameEn = nameAr
                                    }
                                } else if !nameEn.isEmpty && nameAr.isEmpty {
                                    if let tr = PPOptionTranslationDictionary.translate(text: nameEn, isArabicInput: false) {
                                        nameAr = tr.counterpart
                                        key = tr.canonical
                                    } else {
                                        nameAr = nameEn
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(Language.isRTL() ? "ترجمة بيوري الذكية" : "Pury Smart Translate")
                                        .font(AdminType.captionBold)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
                                .foregroundStyle(AdminSurface.emerald)
                            }
                            .buttonStyle(.plain)
                        }

                        // English Name Field
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "globe.americas.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AdminSurface.primary)
                                Text(Language.get("Variant_NameEn", alter: "الاسم بالإنجليزية"))
                                    .font(AdminType.captionBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                            }

                            HStack {
                                TextField("e.g. Size, Flavor, Material...", text: $nameEn)
                                    .font(AdminType.calloutBold)
                                    .multilineTextAlignment(.leading)
                                    .onChange(of: nameEn) { newVal in
                                        if autoDeriveKey && !newVal.isEmpty {
                                            key = PPAccessoryOptionValue.derivedIdentifier(fromName: newVal)
                                        }
                                    }

                                if !nameEn.isEmpty {
                                    Button {
                                        nameEn = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(AdminSurface.secondaryText.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                            )
                        }

                        // Key Identifier Field
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "number.square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                Text(Language.get("Options_Key_Identifier", alter: "المعرف الأساسي"))
                                    .font(AdminType.captionBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                Spacer()
                                Button {
                                    autoDeriveKey.toggle()
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: autoDeriveKey ? "lock.fill" : "lock.open.fill")
                                            .font(.system(size: 9))
                                        Text(autoDeriveKey ? (Language.isRTL() ? "تلقائي" : "Auto") : (Language.isRTL() ? "يدوي" : "Manual"))
                                            .font(AdminType.caption2Bold)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(autoDeriveKey ? AdminSurface.primary.opacity(0.12) : AdminSurface.card, in: Capsule())
                                    .foregroundStyle(autoDeriveKey ? AdminSurface.primary : AdminSurface.secondaryText)
                                }
                                .buttonStyle(.plain)
                            }

                            TextField("e.g. size, flavor, material", text: $key)
                                .font(AdminType.callout.monospaced())
                                .disabled(autoDeriveKey)
                                .padding(12)
                                .background(autoDeriveKey ? AdminSurface.backgroundSecondary : AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                                )
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Options_Studio_CustomOptionTitle", alter: "استوديو إنشاء خيار"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        Text(Language.get("Add", alter: "إضافة"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(isValid ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
                    }
                    .disabled(!isValid)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                        .background(AdminSurface.hairline)

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(Language.isRTL() ? "إنشاء الخيار في الكتالوج" : "Create Option in Catalog")
                                .font(AdminType.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            isValid ? AdminSurface.primary : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .foregroundStyle(isValid ? Color.white : AdminSurface.secondaryText.opacity(0.5))
                        .shadow(color: isValid ? AdminSurface.primary.opacity(0.35) : Color.clear, radius: 8, y: 3)
                    }
                    .disabled(!isValid)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .background(AdminSurface.backgroundSecondary.opacity(0.95))
            }
        }
    }

    private var resolvedKey: String {
        let finalEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (finalEn.isEmpty ? finalAr : finalEn)
            : key
        return PPAccessoryOptionValue.derivedIdentifier(fromName: rawKey)
    }

    private func submit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let finalAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = resolvedKey
        let def = PPAccessoryOptionDefinition.custom(
            id: id,
            key: id,
            nameAr: finalAr.isEmpty ? finalEn : finalAr,
            nameEn: finalEn.isEmpty ? finalAr : finalEn
        )
        onAdd(def)
        dismiss()
    }
}

// MARK: - Category-Defining Studio Custom Value Sheet

struct PPAccessoryCustomValueSheet: View {
    let option: PPAccessoryOptionDefinition?
    let isColor: Bool
    let isWeight: Bool
    let onAdd: (PPAccessoryOptionValue) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        option: PPAccessoryOptionDefinition,
        onAdd: @escaping (PPAccessoryOptionValue) -> Void
    ) {
        self.option = option
        self.isColor = option.isColorOption
        self.isWeight = option.isWeightOption
        self.onAdd = onAdd
    }

    init(
        isColor: Bool = false,
        isWeight: Bool = false,
        option: PPAccessoryOptionDefinition? = nil,
        onAdd: @escaping (PPAccessoryOptionValue) -> Void
    ) {
        self.option = option
        self.isColor = option?.isColorOption ?? isColor
        self.isWeight = option?.isWeightOption ?? isWeight
        self.onAdd = onAdd
    }

    @State private var canonicalValue: String = ""
    @State private var nameAr: String = ""
    @State private var nameEn: String = ""
    @State private var hex: String = "#2563EB"
    @State private var unit: String = "kg"
    @State private var weightAmount: String = ""
    @State private var autoDeriveCanonical: Bool = true
    @State private var selectedPresetId: String? = nil

    private let weightUnits: [(id: String, ar: String, en: String)] = [
        ("g", "جم", "g"),
        ("kg", "كجم", "kg"),
        ("oz", "أونصة", "oz"),
        ("lb", "رطل", "lb"),
        ("ml", "مل", "ml"),
        ("L", "لتر", "L"),
    ]

    var optionTint: Color {
        if let opt = option {
            if opt.isColorOption { return .purple }
            if opt.isSizeOption { return .indigo }
            if opt.isWeightOption { return .orange }
            if opt.isFlavorOption { return .green }
            if opt.isMaterialOption { return .blue }
        }
        if isColor { return .purple }
        if isWeight { return .orange }
        return AdminSurface.primary
    }

    var optionIcon: String {
        if let opt = option {
            if opt.isColorOption { return "paintpalette.fill" }
            if opt.isSizeOption { return "ruler.fill" }
            if opt.isWeightOption { return "scalemass.fill" }
            if opt.isFlavorOption { return "fork.knife" }
            if opt.isMaterialOption { return "cube.fill" }
        }
        if isColor { return "paintpalette.fill" }
        if isWeight { return "scalemass.fill" }
        return "slider.horizontal.3"
    }

    var optionTitle: String {
        if let opt = option {
            return opt.localizedName
        }
        if isColor { return Language.isRTL() ? "اللون" : "Color" }
        if isWeight { return Language.isRTL() ? "الوزن" : "Weight" }
        return Language.isRTL() ? "خيار المنتج" : "Product Option"
    }

    var isValid: Bool {
        let canon = canonicalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let ar = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseValid = !canon.isEmpty || !ar.isEmpty || !en.isEmpty
        if isColor {
            return baseValid && hex.count >= 4 && hex.hasPrefix("#")
        }
        return baseValid
    }

    var isDuplicate: Bool {
        guard let opt = option else { return false }
        let currentId = derivedId.lowercased()
        let currentCanon = canonicalValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return opt.values.contains { val in
            val.id.lowercased() == currentId
                || (!currentCanon.isEmpty && val.canonicalValue.lowercased() == currentCanon)
        }
    }

    var derivedId: String {
        let finalCanon = canonicalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = !finalCanon.isEmpty ? finalCanon : (!finalEn.isEmpty ? finalEn : finalAr)
        return PPAccessoryOptionValue.derivedIdentifier(fromName: fallback.isEmpty ? "custom_val" : fallback)
    }

    // Available smart suggestions filtered to exclude already-added values
    var smartPresets: [(id: String, canon: String, ar: String, en: String, unit: String?, hex: String?)] {
        let existingIds = Set(option?.values.map { $0.id.lowercased() } ?? [])
        let existingCanons = Set(option?.values.map { $0.canonicalValue.lowercased() } ?? [])

        var pool: [(id: String, canon: String, ar: String, en: String, unit: String?, hex: String?)] = []

        if option?.isSizeOption == true {
            let sizes = [
                ("xxs", "XXS", "صغير جداً جداً", "XXS"),
                ("xs", "XS", "صغير جداً", "XS"),
                ("s", "S", "صغير", "Small"),
                ("m", "M", "متوسط", "Medium"),
                ("l", "L", "كبير", "Large"),
                ("xl", "XL", "كبير جداً", "XL"),
                ("2xl", "2XL", "2XL", "2XL"),
                ("3xl", "3XL", "3XL", "3XL"),
                ("4xl", "4XL", "4XL", "4XL"),
                ("one_size", "One Size", "مقاس موحد", "One Size"),
            ]
            for s in sizes { pool.append((s.0, s.1, s.2, s.3, nil, nil)) }
        } else if option?.isWeightOption == true || isWeight {
            let weights = [
                ("50g", "50g", "٥٠ جم", "50g", "g"),
                ("100g", "100g", "١٠٠ جم", "100g", "g"),
                ("250g", "250g", "٢٥٠ جم", "250g", "g"),
                ("400g", "400g", "٤٠٠ جم", "400g", "g"),
                ("500g", "500g", "٥٠٠ جم", "500g", "g"),
                ("800g", "800g", "٨٠٠ جم", "800g", "g"),
                ("1kg", "1kg", "١ كجم", "1kg", "kg"),
                ("1.5kg", "1.5kg", "١٫٥ كجم", "1.5kg", "kg"),
                ("2kg", "2kg", "٢ كجم", "2kg", "kg"),
                ("2.5kg", "2.5kg", "٢٫٥ كجم", "2.5kg", "kg"),
                ("3kg", "3kg", "٣ كجم", "3kg", "kg"),
                ("5kg", "5kg", "٥ كجم", "5kg", "kg"),
                ("7kg", "7kg", "٧ كجم", "7kg", "kg"),
                ("10kg", "10kg", "١٠ كجم", "10kg", "kg"),
                ("15kg", "15kg", "١٥ كجم", "15kg", "kg"),
                ("20kg", "20kg", "٢٠ كجم", "20kg", "kg"),
            ]
            for w in weights { pool.append((w.0, w.1, w.2, w.3, w.4, nil)) }
        } else if option?.isFlavorOption == true {
            let flavors = [
                ("chicken", "chicken", "دجاج طازج", "Fresh Chicken"),
                ("beef", "beef", "لحم بقر", "Tender Beef"),
                ("salmon", "salmon", "سلمون نرويجي", "Wild Salmon"),
                ("tuna", "tuna", "تونة محيطية", "Ocean Tuna"),
                ("duck", "duck", "بط بري", "Wild Duck"),
                ("lamb", "lamb", "لحم ضأن", "Tender Lamb"),
                ("turkey", "turkey", "ديك رومي", "Roast Turkey"),
                ("seafood", "seafood", "مأكولات بحرية", "Seafood Medley"),
                ("cheese", "cheese", "جبنة طبيعية", "Natural Cheese"),
                ("catnip", "catnip", "نعناع بري", "Organic Catnip"),
            ]
            for f in flavors { pool.append((f.0, f.1, f.2, f.3, nil, nil)) }
        } else if option?.isMaterialOption == true {
            let mats = [
                ("leather", "leather", "جلد طبيعي", "Genuine Leather"),
                ("cotton", "cotton", "قطن عضوي", "Organic Cotton"),
                ("silicone", "silicone", "سيليكون آمن", "Food-Grade Silicone"),
                ("nylon", "nylon", "نايلون متين", "Heavy-Duty Nylon"),
                ("stainless_steel", "stainless_steel", "ستانلس ستيل", "Stainless Steel"),
                ("natural_wood", "wood", "خشب طبيعي", "Natural Wood"),
                ("ceramic", "ceramic", "سيراميك مصقول", "Glazed Ceramic"),
                ("plush", "plush", "فرو ناعم", "Ultra-Soft Plush"),
            ]
            for m in mats { pool.append((m.0, m.1, m.2, m.3, nil, nil)) }
        }

        return pool.filter { item in
            !existingIds.contains(item.id.lowercased())
                && !existingCanons.contains(item.canon.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // HERO: Live Holographic Preview Card
                    liveHolographicPreviewCard

                    // SMART PRESETS CAROUSEL (If available)
                    if !smartPresets.isEmpty {
                        smartPresetsCarousel
                    }

                    // CONTEXTUAL SPECIAL CONTROLS: Weight or Color
                    if isWeight {
                        weightUnitSelectorCard
                    } else if isColor {
                        colorPaletteCard
                    }

                    // STUDIO BILINGUAL IDENTITY INPUTS
                    bilingualIdentityInputs

                    // Duplicate Warning Banner
                    if isDuplicate {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AdminSurface.amber)
                            Text(String(format: Language.get("Options_Studio_DuplicateWarning", alter: "هذه القيمة موجودة مسبقاً في هذا الخيار (%@)."), derivedId))
                                .font(AdminType.footnote)
                                .foregroundStyle(AdminSurface.amber)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AdminSurface.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AdminSurface.amber.opacity(0.3), lineWidth: 1))
                    }

                    Spacer(minLength: 50)
                }
                .padding(20)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: optionIcon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(optionTint)
                        Text(String(format: Language.get("Options_Studio_AddValueTo", alter: "إضافة إلى %@"), optionTitle))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        Text(Language.get("Add", alter: "إضافة"))
                            .font(AdminType.calloutBold)
                            .foregroundStyle(isValid && !isDuplicate ? AdminSurface.primary : AdminSurface.secondaryText.opacity(0.4))
                    }
                    .disabled(!isValid || isDuplicate)
                }
            }
            .safeAreaInset(edge: .bottom) {
                stickyActionDock
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Live Holographic Preview Card

    private var liveHolographicPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isValid ? AdminSurface.emerald : AdminSurface.amber)
                        .frame(width: 7, height: 7)
                    Text(Language.get("Options_Studio_ValuePreview", alter: "معاينة حية للقيمة"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Customer Storefront Pill Simulation
                HStack(spacing: 5) {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 9))
                    Text(Language.get("Options_Studio_CustomerView", alter: "عرض المتجر"))
                        .font(AdminType.caption2Bold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                .foregroundStyle(AdminSurface.primary)
            }

            // Main Interactive Stage
            HStack(spacing: 16) {
                // Leading Visual Avatar
                if isColor {
                    ZStack {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 50, height: 50)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 2))
                            .shadow(color: Color(hex: hex).opacity(0.4), radius: 6, y: 2)

                        Circle()
                            .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                            .frame(width: 54, height: 54)
                    }
                } else if isWeight {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 50, height: 50)
                        VStack(spacing: 1) {
                            Image(systemName: "scalemass.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.orange)
                            Text(unit.isEmpty ? "kg" : unit)
                                .font(AdminType.caption2.monospaced())
                                .foregroundStyle(Color.orange)
                        }
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(optionTint.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: optionIcon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(optionTint)
                    }
                }

                // Bilingual Typography Showcase
                VStack(alignment: .leading, spacing: 3) {
                    let displayAr = nameAr.isEmpty ? (Language.isRTL() ? "اسم القيمة" : "Value Name") : nameAr
                    let displayEn = nameEn.isEmpty ? "Value Name (EN)" : nameEn

                    Text(Language.isRTL() ? displayAr : displayEn)
                        .font(AdminType.title3Bold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.isRTL() ? displayEn : displayAr)
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Customer Selection Chip Simulation
                VStack(alignment: .trailing, spacing: 4) {
                    let pillText = !canonicalValue.isEmpty ? canonicalValue : (!nameEn.isEmpty ? nameEn : nameAr)
                    HStack(spacing: 5) {
                        if isColor {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 10, height: 10)
                        }
                        Text(pillText.isEmpty ? "—" : pillText)
                            .font(AdminType.footnoteBold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AdminSurface.primary, in: Capsule())
                    .foregroundStyle(Color.white)
                    .shadow(color: AdminSurface.primary.opacity(0.25), radius: 4, y: 2)

                    Text(derivedId)
                        .font(AdminType.caption2.monospaced())
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                }
            }
        }
        .padding(18)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [optionTint.opacity(0.35), AdminSurface.hairline],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
    }

    // MARK: - Smart Presets Carousel

    private var smartPresetsCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Options_Studio_Presets", alter: "اقتراحات ذكية جاهزة"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(smartPresets, id: \.id) { preset in
                        let isSelected = (selectedPresetId == preset.id)
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedPresetId = preset.id
                                canonicalValue = preset.canon
                                nameAr = preset.ar
                                nameEn = preset.en
                                if let u = preset.unit {
                                    unit = u
                                    weightAmount = preset.canon.replacingOccurrences(of: u, with: "")
                                }
                                if let h = preset.hex { hex = h }
                                autoDeriveCanonical = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(preset.canon)
                                    .font(AdminType.captionBold)
                                Text("•")
                                    .font(.system(size: 8))
                                    .opacity(0.4)
                                Text(Language.isRTL() ? preset.ar : preset.en)
                                    .font(AdminType.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? optionTint : AdminSurface.card,
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 1)
                            )
                            .shadow(color: isSelected ? optionTint.opacity(0.3) : Color.clear, radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Weight / Unit Selector Card

    private var weightUnitSelectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                Text(Language.get("Options_Studio_QuickUnits", alter: "الوحدة والكمية القياسية"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            // Quick Units Chips
            HStack(spacing: 8) {
                ForEach(weightUnits, id: \.id) { u in
                    let isSelected = (unit == u.id)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            unit = u.id
                            updateWeightFields()
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(Language.isRTL() ? u.ar : u.en)
                                .font(AdminType.captionBold)
                            Text(u.id)
                                .font(AdminType.caption2.monospaced())
                                .opacity(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? Color.orange : AdminSurface.control,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Numeric Stepper / Direct Weight Input
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "scalemass")
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField(Language.isRTL() ? "الوزن بالأرقام (مثال: 500 أو 2)" : "Numeric weight (e.g. 500, 2)", text: $weightAmount)
                        .font(AdminType.calloutBold)
                        .keyboardType(.decimalPad)
                        .onChange(of: weightAmount) { _ in
                            updateWeightFields()
                        }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))

                // Quick Increment Buttons
                HStack(spacing: 6) {
                    ForEach(["+100", "+500", "+1k"], id: \.self) { inc in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            applyWeightIncrement(inc)
                        } label: {
                            Text(inc)
                                .font(AdminType.caption2Bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .foregroundStyle(AdminSurface.primaryText)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
    }

    private func updateWeightFields() {
        let clean = weightAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        canonicalValue = "\(clean)\(unit)"
        nameEn = "\(clean)\(unit)"
        if unit == "kg" {
            nameAr = "\(clean) كجم"
        } else if unit == "g" {
            nameAr = "\(clean) جم"
        } else {
            nameAr = "\(clean) \(unit)"
        }
    }

    private func applyWeightIncrement(_ inc: String) {
        let cur = Double(weightAmount) ?? 0
        let addition: Double = inc == "+100" ? 100 : (inc == "+500" ? 500 : 1000)
        let newVal = cur + addition
        weightAmount = (newVal.truncatingRemainder(dividingBy: 1) == 0) ? String(Int(newVal)) : String(newVal)
        updateWeightFields()
    }

    // MARK: - Color Palette Card

    private var colorPaletteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.purple)
                Text(Language.get("Options_Studio_ColorPicker", alter: "لوحة الألوان المعتمدة"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
                Spacer()
                Text(hex)
                    .font(AdminType.captionBold.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: hex).opacity(0.15), in: Capsule())
                    .foregroundStyle(Color(hex: hex))
            }

            // 12 Curated Colors Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(PPOptionColorPreset.all) { cp in
                    let isSelected = (hex.uppercased() == cp.hex.uppercased())
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            hex = cp.hex
                            nameAr = cp.nameAr
                            nameEn = cp.nameEn
                            canonicalValue = cp.id
                            autoDeriveCanonical = false
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(cp.color)
                                .frame(width: 38, height: 38)
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
                                .shadow(color: cp.color.opacity(0.4), radius: isSelected ? 5 : 1, y: 1)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.white)
                            }
                        }
                        .padding(2)
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? AdminSurface.primary : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Manual Hex Input Bar
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AdminSurface.hairline, lineWidth: 1))

                HStack {
                    Text("#")
                        .font(AdminType.calloutBold.monospaced())
                        .foregroundStyle(AdminSurface.secondaryText)
                    TextField("RRGGBB", text: Binding(
                        get: { hex.replacingOccurrences(of: "#", with: "") },
                        set: { hex = "#\($0.trimmingCharacters(in: .whitespacesAndNewlines))" }
                    ))
                    .font(AdminType.calloutBold.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
        }
        .padding(16)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
    }

    // MARK: - Bilingual Identity Inputs

    private var bilingualIdentityInputs: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Language.isRTL() ? "بيانات القيمة • VALUE IDENTITY" : "VALUE IDENTITY • بيانات القيمة")
                .font(AdminType.caption2Bold)
                .foregroundStyle(AdminSurface.secondaryText)
                .padding(.horizontal, 4)

            // Arabic Name Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.emerald)
                    Text(Language.get("Variant_NameAr", alter: "الاسم بالعربية"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                HStack {
                    TextField("مثال: كبير، ٥٠٠ جم، دجاج...", text: $nameAr)
                        .font(AdminType.calloutBold)
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                        .onChange(of: nameAr) { newVal in
                            if autoDeriveCanonical && !newVal.isEmpty {
                                if let tr = PPOptionTranslationDictionary.translate(text: newVal, isArabicInput: true) {
                                    if nameEn.isEmpty { nameEn = tr.counterpart }
                                    canonicalValue = tr.canonical
                                } else if canonicalValue.isEmpty {
                                    canonicalValue = PPAccessoryOptionValue.derivedIdentifier(fromName: newVal)
                                }
                            }
                        }

                    if !nameAr.isEmpty {
                        Button {
                            nameAr = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }

            // Pury Smart Auto-Translate Bridge
            HStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    runSmartTranslate()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text(Language.get("Options_Studio_SmartTranslate", alter: "ترجمة بيوري الذكية"))
                            .font(AdminType.captionBold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
                    .foregroundStyle(AdminSurface.emerald)
                }
                .buttonStyle(.plain)
            }

            // English Name Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Variant_NameEn", alter: "الاسم بالإنجليزية"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                HStack {
                    TextField("e.g. Large, 500g, Chicken...", text: $nameEn)
                        .font(AdminType.calloutBold)
                        .multilineTextAlignment(.leading)
                        .onChange(of: nameEn) { newVal in
                            if autoDeriveCanonical && !newVal.isEmpty {
                                canonicalValue = newVal
                                if nameAr.isEmpty {
                                    if let tr = PPOptionTranslationDictionary.translate(text: newVal, isArabicInput: false) {
                                        nameAr = tr.counterpart
                                    }
                                }
                            }
                        }

                    if !nameEn.isEmpty {
                        Button {
                            nameEn = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }

            // Canonical Value / Identifier Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "number.square")
                        .font(.system(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(Language.get("Options_Canonical_Value", alter: "القيمة الأساسية / المعرف"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                    Spacer()
                    Button {
                        autoDeriveCanonical.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: autoDeriveCanonical ? "lock.fill" : "lock.open.fill")
                                .font(.system(size: 9))
                            Text(autoDeriveCanonical ? (Language.isRTL() ? "تلقائي" : "Auto") : (Language.isRTL() ? "يدوي" : "Manual"))
                                .font(AdminType.caption2Bold)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(autoDeriveCanonical ? AdminSurface.primary.opacity(0.12) : AdminSurface.card, in: Capsule())
                        .foregroundStyle(autoDeriveCanonical ? AdminSurface.primary : AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                TextField("e.g. M, 500g, chicken", text: $canonicalValue)
                    .font(AdminType.callout.monospaced())
                    .disabled(autoDeriveCanonical)
                    .padding(12)
                    .background(autoDeriveCanonical ? AdminSurface.backgroundSecondary : AdminSurface.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }

    // MARK: - Sticky Action Dock

    private var stickyActionDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline)

            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(Language.get("Options_Studio_AddValueAction", alter: "إضافة القيمة إلى الخيار"))
                        .font(AdminType.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isValid && !isDuplicate ? optionTint : AdminSurface.control,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .foregroundStyle(isValid && !isDuplicate ? Color.white : AdminSurface.secondaryText.opacity(0.5))
                .shadow(color: isValid && !isDuplicate ? optionTint.opacity(0.35) : Color.clear, radius: 8, y: 3)
            }
            .disabled(!isValid || isDuplicate)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(AdminSurface.backgroundSecondary.opacity(0.96))
    }

    private func runSmartTranslate() {
        let ar = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)

        if !ar.isEmpty && en.isEmpty {
            if let tr = PPOptionTranslationDictionary.translate(text: ar, isArabicInput: true) {
                nameEn = tr.counterpart
                if canonicalValue.isEmpty || autoDeriveCanonical { canonicalValue = tr.canonical }
            } else {
                nameEn = ar
            }
        } else if !en.isEmpty && ar.isEmpty {
            if let tr = PPOptionTranslationDictionary.translate(text: en, isArabicInput: false) {
                nameAr = tr.counterpart
                if canonicalValue.isEmpty || autoDeriveCanonical { canonicalValue = tr.canonical }
            } else {
                nameAr = en
            }
        }
    }

    private func submit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let finalCanon = canonicalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = !finalCanon.isEmpty ? finalCanon : (!finalEn.isEmpty ? finalEn : finalAr)
        let id = derivedId

        let value = PPAccessoryOptionValue(
            id: id,
            canonicalValue: finalCanon.isEmpty ? fallback : finalCanon,
            nameAr: finalAr.isEmpty ? fallback : finalAr,
            nameEn: finalEn.isEmpty ? fallback : finalEn,
            hex: isColor ? hex : nil,
            unit: isWeight && !unit.isEmpty ? unit : nil
        )
        onAdd(value)
        dismiss()
    }
}
