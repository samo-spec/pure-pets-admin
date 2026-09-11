//
//  PPTactileNumberPadSheet.swift
//  PurePetsAdmin
//
//  Created for PurePets Admin NextGen Platform.
//  Category-defining tactile numeric keypad sheet supporting Numbers,
//  Quantities, Prices, Amounts, Age, Discounts, and Percentages across
//  all Inventory and POS workflows.
//

import SwiftUI
import UIKit

// MARK: - Input Modes

public enum PPTactileNumberPadMode: Equatable {
    /// Integer quantity mode with optional zero out and stock variance badges
    case quantity(unit: String = Language.get("Units", alter: "وحدات"), allowZero: Bool = true, maxLimit: Int? = 999999)

    /// Decimal pricing mode with currency formatting
    case price(currency: String = Language.get("QAR", alter: "ر.ق"), maxLimit: Double? = 999999.99)

    /// General financial or weight/dimension amount
    case amount(currency: String = Language.get("QAR", alter: "ر.ق"), maxLimit: Double? = 999999.99)

    /// Percentage discount or metric mode (0% - 100%)
    case percentage(maxLimit: Double = 100.0)

    /// Monetary or percentage discount mode
    case discount(currency: String = Language.get("QAR", alter: "ر.ق"), isPercentage: Bool = false, maxLimit: Double? = nil)

    /// Specimen age in months, weeks, or years for live pets
    case age(unit: String = Language.get("Months", alter: "أشهر"), maxLimit: Double? = 240)

    /// Generic number input
    case number(allowDecimal: Bool = false, unit: String? = nil, minLimit: Double? = 0, maxLimit: Double? = nil)

    public var allowsDecimal: Bool {
        switch self {
        case .price, .amount, .percentage, .discount:
            return true
        case .number(let allowDecimal, _, _, _):
            return allowDecimal
        case .age:
            return false
        case .quantity:
            return false
        }
    }

    public var defaultUnit: String {
        switch self {
        case .quantity(let unit, _, _):
            return unit
        case .price(let curr, _), .amount(let curr, _):
            return curr
        case .percentage:
            return "%"
        case .discount(let curr, let isPercentage, _):
            return isPercentage ? "%" : curr
        case .age(let unit, _):
            return unit
        case .number(_, let unit, _, _):
            return unit ?? ""
        }
    }

    public var maxDecimalPlaces: Int {
        switch self {
        case .price, .amount:
            return 2
        case .percentage, .discount:
            return 1
        case .number(let allowDecimal, _, _, _):
            return allowDecimal ? 2 : 0
        case .quantity, .age:
            return 0
        }
    }
}

// MARK: - Specimen / Item Identity Context

public struct PPTactileSpecimenInfo: Equatable {
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    public let sku: String?
    public let shelfLocation: String?
    public let barcode: String?
    public let unitCost: Double?

    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL? = nil,
        sku: String? = nil,
        shelfLocation: String? = nil,
        barcode: String? = nil,
        unitCost: Double? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.sku = sku
        self.shelfLocation = shelfLocation
        self.barcode = barcode
        self.unitCost = unitCost
    }
}

// MARK: - Preset Quick Accelerator Chip

public struct PPTactilePresetChip: Identifiable, Equatable {
    public enum ChipAction: Equatable {
        case set(Double)
        case delta(Double)
        case matchReference
        case zeroOut
    }

    public let id: String
    public let title: String
    public let icon: String?
    public let action: ChipAction
    public let tint: Color?

    public init(
        id: String = UUID().uuidString,
        title: String,
        icon: String? = nil,
        action: ChipAction,
        tint: Color? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.action = action
        self.tint = tint
    }
}

// MARK: - Configuration Object

public struct PPTactileNumberPadConfig: Equatable {
    public var title: String
    public var subtitle: String?
    public var mode: PPTactileNumberPadMode
    public var initialValue: Double
    public var referenceValue: Double?
    public var referenceLabel: String?
    public var specimen: PPTactileSpecimenInfo?
    public var customChips: [PPTactilePresetChip]?
    public var primaryActionTitle: String?
    public var allowNegative: Bool
    public var maxDigits: Int

    public init(
        title: String,
        subtitle: String? = nil,
        mode: PPTactileNumberPadMode = .quantity(),
        initialValue: Double = 0,
        referenceValue: Double? = nil,
        referenceLabel: String? = nil,
        specimen: PPTactileSpecimenInfo? = nil,
        customChips: [PPTactilePresetChip]? = nil,
        primaryActionTitle: String? = nil,
        allowNegative: Bool = false,
        maxDigits: Int = 8
    ) {
        self.title = title
        self.subtitle = subtitle
        self.mode = mode
        self.initialValue = initialValue
        self.referenceValue = referenceValue
        self.referenceLabel = referenceLabel
        self.specimen = specimen
        self.customChips = customChips
        self.primaryActionTitle = primaryActionTitle
        self.allowNegative = allowNegative
        self.maxDigits = maxDigits
    }
}

// MARK: - Keypad Button Definition

private enum PPTactileKey: Identifiable, Equatable {
    case digit(String)
    case decimal
    case clear
    case backspace

    var id: String {
        switch self {
        case .digit(let d): return "digit_\(d)"
        case .decimal: return "decimal"
        case .clear: return "clear"
        case .backspace: return "backspace"
        }
    }
}

// MARK: - Reusable Tactile Number Pad Sheet

public struct PPTactileNumberPadSheet: View {
    public let config: PPTactileNumberPadConfig
    public let onCommit: (Double) -> Void
    public let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var inputText: String = ""

    public init(
        config: PPTactileNumberPadConfig,
        onCommit: @escaping (Double) -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.config = config
        self.onCommit = onCommit
        self.onDismiss = onDismiss

        let formattedInitial: String
        if config.mode.allowsDecimal {
            if config.initialValue == floor(config.initialValue) && config.initialValue != 0 {
                formattedInitial = String(format: "%.0f", config.initialValue)
            } else if config.initialValue == 0 {
                formattedInitial = ""
            } else {
                formattedInitial = String(format: "%.\(config.mode.maxDecimalPlaces)f", config.initialValue)
            }
        } else {
            let intVal = Int(config.initialValue)
            formattedInitial = intVal == 0 ? "" : "\(intVal)"
        }
        _inputText = State(initialValue: formattedInitial)
    }

    // MARK: - Computed Properties

    private var parsedValue: Double {
        let cleaned = inputText.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0.0
    }

    private var parsedIntValue: Int {
        Int(parsedValue)
    }

    private var displayDigits: String {
        if inputText.isEmpty {
            return "0"
        }
        return inputText.normalizedEnglishDigits
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var referenceDelta: Double? {
        guard let ref = config.referenceValue else { return nil }
        return parsedValue - ref
    }

    private var financialImpact: Double? {
        guard let delta = referenceDelta, let cost = config.specimen?.unitCost ?? (config.referenceValue != nil ? 0.0 : nil) else { return nil }
        return abs(delta) * cost
    }

    // MARK: - Accelerator Chips Generation

    private var activeChips: [PPTactilePresetChip] {
        if let custom = config.customChips {
            return custom
        }

        var chips: [PPTactilePresetChip] = []

        // 1. Match reference accelerator
        if let ref = config.referenceValue {
            let refText: String
            if config.mode.allowsDecimal {
                refText = String(format: "%.\(config.mode.maxDecimalPlaces)f", ref)
            } else {
                refText = "\(Int(ref))"
            }
            chips.append(
                PPTactilePresetChip(
                    title: String(format: Language.get("TactilePad_Match_Ref", alter: "%@ (%@)"), config.referenceLabel ?? Language.get("Original", alter: "المطابق"), refText),
                    icon: "equal.circle.fill",
                    action: .matchReference,
                    tint: AdminSurface.primary
                )
            )
        }

        // 2. Mode-specific presets
        switch config.mode {
        case .quantity(_, let allowZero, _):
            if allowZero {
                chips.append(
                    PPTactilePresetChip(
                        title: Language.get("CycleCount_Keypad_Zero_Out", alter: "0 (نفاذ الرف)"),
                        icon: "slash.circle.fill",
                        action: .zeroOut,
                        tint: AdminSurface.crimson
                    )
                )
            }
            for d in [1, 5, 10] {
                chips.append(
                    PPTactilePresetChip(
                        title: "+\(d)".normalizedEnglishDigits,
                        action: .delta(Double(d)),
                        tint: AdminSurface.primaryText
                    )
                )
            }
            chips.append(
                PPTactilePresetChip(
                    title: "-1".normalizedEnglishDigits,
                    action: .delta(-1.0),
                    tint: AdminSurface.secondaryText
                )
            )

        case .price, .amount:
            chips.append(
                PPTactilePresetChip(
                    title: "0.00",
                    icon: "arrow.counterclockwise",
                    action: .zeroOut,
                    tint: AdminSurface.crimson
                )
            )
            for p in [5, 10, 50, 100] {
                chips.append(
                    PPTactilePresetChip(
                        title: "+\(p)".normalizedEnglishDigits,
                        action: .delta(Double(p)),
                        tint: AdminSurface.primaryText
                    )
                )
            }

        case .percentage:
            chips.append(
                PPTactilePresetChip(
                    title: "0%",
                    action: .set(0.0),
                    tint: AdminSurface.secondaryText
                )
            )
            for pct in [5, 10, 15, 20, 25, 50] {
                chips.append(
                    PPTactilePresetChip(
                        title: "\(pct)%",
                        action: .set(Double(pct)),
                        tint: AdminSurface.primary
                    )
                )
            }

        case .discount(_, let isPercentage, _):
            chips.append(
                PPTactilePresetChip(
                    title: isPercentage ? "0%" : "0.00",
                    action: .zeroOut,
                    tint: AdminSurface.crimson
                )
            )
            if isPercentage {
                for pct in [5, 10, 15, 20, 25, 50] {
                    chips.append(
                        PPTactilePresetChip(
                            title: "\(pct)%",
                            action: .set(Double(pct)),
                            tint: AdminSurface.primary
                        )
                    )
                }
            } else {
                for amt in [5, 10, 20, 50, 100] {
                    chips.append(
                        PPTactilePresetChip(
                            title: "+\(amt)".normalizedEnglishDigits,
                            action: .delta(Double(amt)),
                            tint: AdminSurface.primaryText
                        )
                    )
                }
            }

        case .age(let unit, _):
            for m in [1, 2, 3, 6, 12, 24] {
                chips.append(
                    PPTactilePresetChip(
                        title: "\(m) \(unit)".normalizedEnglishDigits,
                        action: .set(Double(m)),
                        tint: AdminSurface.primary
                    )
                )
            }
            chips.append(
                PPTactilePresetChip(
                    title: "+1",
                    action: .delta(1.0),
                    tint: AdminSurface.primaryText
                )
            )

        case .number:
            chips.append(
                PPTactilePresetChip(
                    title: Language.get("Reset", alter: "إعادة ضبط (0)"),
                    icon: "arrow.counterclockwise",
                    action: .zeroOut,
                    tint: AdminSurface.secondaryText
                )
            )
            for d in [1, 5, 10] {
                chips.append(
                    PPTactilePresetChip(
                        title: "+\(d)".normalizedEnglishDigits,
                        action: .delta(Double(d)),
                        tint: AdminSurface.primaryText
                    )
                )
            }
        }

        return chips
    }

    // MARK: - Keypad Matrix Setup

    private var keypadKeys: [[PPTactileKey]] {
        if config.mode.allowsDecimal {
            return [
                [.digit("1"), .digit("2"), .digit("3")],
                [.digit("4"), .digit("5"), .digit("6")],
                [.digit("7"), .digit("8"), .digit("9")],
                [.decimal, .digit("0"), .backspace]
            ]
        } else {
            return [
                [.digit("1"), .digit("2"), .digit("3")],
                [.digit("4"), .digit("5"), .digit("6")],
                [.digit("7"), .digit("8"), .digit("9")],
                [.clear, .digit("0"), .backspace]
            ]
        }
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if isPad {
                iPadStageLayout
            } else {
                iPhoneSheetLayout
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - iPhone Bottom Sheet Layout

    private var iPhoneSheetLayout: some View {
        VStack(spacing: 0) {
            // 1. Header Bar
            headerBar
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.top, 16)
                .padding(.bottom, 10)

            // 2. Specimen Info Strip (if provided)
            if let specimen = config.specimen {
                specimenStrip(specimen: specimen)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, 10)
            }

            // 3. Hero Count Readout & Live Variance Pill
            readoutAndVarianceCard
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 10)

            // 4. Horizontal Accelerator Chips Bar
            acceleratorChipsBar
                .padding(.bottom, 12)

            // 5. Tactile Numeric Matrix (3x4 Grid)
            keypadMatrix(buttonHeight: 52)
                .padding(.horizontal, AdminSpacing.screenMargin)

            Spacer(minLength: 8)

            // 6. Sovereign Primary Action Button
            primaryActionButton
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 14)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .presentationDetents([.fraction(0.88), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - iPad Tactical Console Layout

    private var iPadStageLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top iPad Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.title)
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.primaryText)

                        if let subtitle = config.subtitle {
                            Text(subtitle)
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        } else {
                            Text(Language.get("TactilePad_Keyboard_Hint", alter: "يمكنك استخدام لوحة المفاتيح الخارجية للأرقام مباشرة"))
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        handleDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider().background(AdminSurface.hairline)

                // Split Tactical Stage
                HStack(spacing: 24) {
                    // LEFT WING (44%): Specimen Identity, Economics & Accelerator Dock
                    VStack(spacing: 16) {
                        if let specimen = config.specimen {
                            specimenStrip(specimen: specimen)
                        }

                        if let delta = referenceDelta {
                            iPadEconomicsCard(delta: delta)
                        }

                        // Vertical Chips Dock
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Language.get("TactilePad_Quick_Accelerators", alter: "الإجراءات السريعة والمعدلات"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.secondaryText)

                            acceleratorChipsGrid
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                    // Vertical Separator
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(width: 1)

                    // RIGHT WING (56%): Readout, Pro 56pt Matrix & Action Footer
                    VStack(spacing: 14) {
                        readoutAndVarianceCard

                        keypadMatrix(buttonHeight: 58)

                        Spacer()

                        // Dual Action Buttons (Cancel & Commit)
                        HStack(spacing: 12) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                handleDismiss()
                            } label: {
                                Text(Language.get("Cancel", alter: "إلغاء"))
                                    .font(AdminType.headlineBold)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                            }

                            primaryActionButton
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .frame(minWidth: 720, minHeight: 560)
        .onKeyPress { press in
            if press.characters == "\r" || press.key == .return {
                handleCommit()
                return .handled
            } else if press.key == .escape {
                handleDismiss()
                return .handled
            } else if press.characters.count == 1, let char = press.characters.first {
                if char.isNumber {
                    handleKeypadPress(String(char))
                    return .handled
                } else if (char == "." || char == ",") && config.mode.allowsDecimal {
                    handleKeypadPress(".")
                    return .handled
                }
            } else if press.key == .delete || press.key == .deleteForward {
                handleKeypadBackspace()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Subviews: Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(AdminType.headlineBold)
                    .foregroundColor(AdminSurface.primaryText)

                if let subtitle = config.subtitle {
                    Text(subtitle)
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handleDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
            }
        }
    }

    // MARK: - Subviews: Specimen Strip

    private func specimenStrip(specimen: PPTactileSpecimenInfo) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.cardElevated)
                    .frame(width: 52, height: 52)

                if let url = specimen.imageURL {
                    AdminRemoteImage(url: url) {
                        ProgressView().scaleEffect(0.7)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "cube.box.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )

            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(specimen.title)
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let sku = specimen.sku, !sku.isEmpty {
                        Text(verbatim: sku.normalizedEnglishDigits)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let shelf = specimen.shelfLocation, !shelf.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mappin")
                                .font(.system(size: 9))
                            Text(verbatim: shelf.normalizedEnglishDigits)
                        }
                        .font(AdminType.caption2Bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let barcode = specimen.barcode, !barcode.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "barcode")
                                .font(.system(size: 9))
                            Text(verbatim: barcode.normalizedEnglishDigits)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                if let ref = config.referenceValue {
                    HStack(spacing: 4) {
                        Text((config.referenceLabel ?? Language.get("TactilePad_Current_Value", alter: "القيمة المرجعية")) + ":")
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)

                        let refFormatted = config.mode.allowsDecimal ? String(format: "%.2f", ref) : "\(Int(ref))"
                        Text(verbatim: refFormatted.normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(config.mode.defaultUnit)
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Subviews: Readout & Live Variance Pill

    private var readoutAndVarianceCard: some View {
        let delta = referenceDelta

        return VStack(spacing: 6) {
            // Giant Hero Numeric Readout
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(verbatim: displayDigits)
                    .font(.system(size: isPad ? 58 : 46, weight: .heavy, design: .rounded))
                    .foregroundColor(AdminSurface.primaryText)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: inputText)

                Text(config.mode.defaultUnit)
                    .font(AdminType.headlineBold)
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.bottom, 4)

                // Quick clear button when input is not empty
                if !inputText.isEmpty {
                    Button {
                        handleKeypadClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.leading, 4)
                }
            }

            // Live Variance Telemetry Badge (if reference exists)
            if let delta = delta {
                HStack(spacing: 6) {
                    if abs(delta) < 0.001 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.emerald)
                        Text(Language.get("TactilePad_Matched_Badge", alter: "مطابق للقيمة المرجعية (0 فرق)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.emerald)
                    } else if delta < 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.crimson)

                        let deltaStr = config.mode.allowsDecimal ? String(format: "%.2f", abs(delta)) : "\(Int(abs(delta)))"
                        let impactStr = (financialImpact != nil && financialImpact! > 0) ? String(format: " (أثر %.2f ر.ق)", financialImpact!) : ""
                        Text(verbatim: String(format: Language.get("TactilePad_Deficit_Badge", alter: "تخفيض / عجز -%@ %@%@"), deltaStr, config.mode.defaultUnit, impactStr).normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.crimson)
                    } else {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AdminSurface.amber)

                        let deltaStr = config.mode.allowsDecimal ? String(format: "%.2f", delta) : "\(Int(delta))"
                        let impactStr = (financialImpact != nil && financialImpact! > 0) ? String(format: " (أثر +%.2f ر.ق)", financialImpact!) : ""
                        Text(verbatim: String(format: Language.get("TactilePad_Surplus_Badge", alter: "زيادة / فائض +%@ %@%@"), deltaStr, config.mode.defaultUnit, impactStr).normalizedEnglishDigits)
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.amber)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    badgeTone(delta: delta).opacity(0.12),
                    in: Capsule()
                )
                .animation(.easeInOut(duration: 0.2), value: delta)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    badgeTone(delta: delta).opacity(0.3),
                    lineWidth: 1
                )
        )
    }

    private func badgeTone(delta: Double?) -> Color {
        guard let delta = delta else { return AdminSurface.hairline }
        if abs(delta) < 0.001 {
            return AdminSurface.emerald
        } else if delta < 0 {
            return AdminSurface.crimson
        } else {
            return AdminSurface.amber
        }
    }

    // MARK: - Subviews: Accelerator Chips Bar (Horizontal for iPhone)

    private var acceleratorChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeChips) { chip in
                    chipButton(chip: chip)
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
        }
    }

    // MARK: - Subviews: Accelerator Chips Grid (for iPad)

    private var acceleratorChipsGrid: some View {
        VStack(spacing: 8) {
            ForEach(activeChips) { chip in
                chipButton(chip: chip)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func chipButton(chip: PPTactilePresetChip) -> some View {
        Button {
            executeChipAction(chip.action)
        } label: {
            HStack(spacing: 4) {
                if let icon = chip.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(chip.title)
                    .font(AdminType.captionBold)
                    .lineLimit(1)
            }
            .foregroundColor(chip.tint ?? AdminSurface.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                (chip.tint ?? AdminSurface.primaryText).opacity(chip.icon != nil ? 0.12 : 0.06),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke((chip.tint ?? AdminSurface.hairline).opacity(0.3), lineWidth: 0.8)
            )
        }
        .buttonStyle(PPTactilePressFeedbackStyle())
    }

    // MARK: - Subviews: iPad Economics Card

    private func iPadEconomicsCard(delta: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(Language.get("TactilePad_Economics_Title", alter: "تحليل الأثر المحاسبي"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                if let impact = financialImpact {
                    Text(verbatim: String(format: "%@%.2f %@", delta < 0 ? "-" : "+", impact, config.mode.defaultUnit).normalizedEnglishDigits)
                        .font(AdminType.captionBold)
                        .foregroundColor(badgeTone(delta: delta))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: abs(delta) < 0.001 ? "shield.checkmark.fill" : (delta < 0 ? "exclamationmark.triangle.fill" : "chart.line.uptrend.xyaxis.circle.fill"))
                    .font(.system(size: 16))
                    .foregroundColor(badgeTone(delta: delta))

                Text(verbatim: String(format: Language.get("TactilePad_Difference_Formula", alter: "المدخل: %@ | الفرق: %@"), "\(displayDigits) \(config.mode.defaultUnit)", "\(delta >= 0 ? "+" : "")\(config.mode.allowsDecimal ? String(format: "%.2f", delta) : "\(Int(delta))")").normalizedEnglishDigits)
                    .font(AdminType.footnoteBold)
                    .foregroundColor(badgeTone(delta: delta))
                Spacer()
            }
        }
        .padding(14)
        .background(badgeTone(delta: delta).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(badgeTone(delta: delta).opacity(0.3), lineWidth: 0.8))
    }

    // MARK: - Subviews: Tactile Keypad Grid

    private func keypadMatrix(buttonHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            ForEach(0..<keypadKeys.count, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(keypadKeys[row], id: \.id) { keyItem in
                        keypadKeyButton(keyItem: keyItem, height: buttonHeight)
                    }
                }
            }
        }
    }

    private func keypadKeyButton(keyItem: PPTactileKey, height: CGFloat) -> some View {
        Button {
            switch keyItem {
            case .digit(let d):
                handleKeypadPress(d)
            case .decimal:
                handleKeypadDecimal()
            case .clear:
                handleKeypadClear()
            case .backspace:
                handleKeypadBackspace()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(keyBackground(for: keyItem))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 0.8)
                    )

                switch keyItem {
                case .digit(let d):
                    Text(verbatim: d.normalizedEnglishDigits)
                        .font(.system(size: isPad ? 28 : 24, weight: .bold, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)

                case .decimal:
                    Text(verbatim: ".")
                        .font(.system(size: isPad ? 32 : 28, weight: .heavy, design: .rounded))
                        .foregroundColor(AdminSurface.primaryText)

                case .clear:
                    Text(verbatim: "C")
                        .font(.system(size: isPad ? 22 : 20, weight: .heavy, design: .rounded))
                        .foregroundColor(AdminSurface.crimson)

                case .backspace:
                    Image(systemName: "delete.left.fill")
                        .font(.system(size: isPad ? 22 : 20, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(PPTactilePressFeedbackStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                if keyItem == .backspace {
                    handleKeypadClear()
                }
            }
        )
    }

    private func keyBackground(for key: PPTactileKey) -> Color {
        switch key {
        case .digit:
            return AdminSurface.card
        case .decimal:
            return AdminSurface.cardElevated
        case .clear:
            return AdminSurface.crimson.opacity(0.08)
        case .backspace:
            return AdminSurface.cardElevated
        }
    }

    // MARK: - Subviews: Sovereign Primary Action Button

    private var primaryActionButton: some View {
        let delta = referenceDelta

        let buttonColor: Color
        if let d = delta, abs(d) < 0.001 {
            buttonColor = AdminSurface.emerald
        } else if parsedValue <= 0 && !config.allowNegative {
            buttonColor = AdminSurface.primary
        } else {
            buttonColor = AdminSurface.primary
        }

        let buttonTitle: String
        if let custom = config.primaryActionTitle {
            buttonTitle = custom
        } else {
            switch config.mode {
            case .quantity:
                if let d = delta, abs(d) < 0.001 {
                    buttonTitle = String(format: Language.get("TactilePad_Commit_Matched_Qty", alter: "اعتماد الكمية (مطابق %d وحدة)"), parsedIntValue)
                } else {
                    buttonTitle = String(format: Language.get("TactilePad_Commit_Qty", alter: "اعتماد الكمية (%d وحدة)"), parsedIntValue)
                }
            case .price:
                buttonTitle = String(format: Language.get("TactilePad_Commit_Price", alter: "حفظ السعر (%.2f %@)"), parsedValue, config.mode.defaultUnit)
            case .amount:
                buttonTitle = String(format: Language.get("TactilePad_Commit_Amount", alter: "تأكيد المبلغ (%.2f %@)"), parsedValue, config.mode.defaultUnit)
            case .percentage:
                buttonTitle = String(format: Language.get("TactilePad_Commit_Percentage", alter: "تطبيق النسبة (%.1f%%)"), parsedValue)
            case .discount:
                buttonTitle = String(format: Language.get("TactilePad_Commit_Discount", alter: "تطبيق الخصم (%@ %@)"), displayDigits, config.mode.defaultUnit)
            case .age:
                buttonTitle = String(format: Language.get("TactilePad_Commit_Age", alter: "تأكيد العمر (%d %@)"), parsedIntValue, config.mode.defaultUnit)
            case .number:
                buttonTitle = String(format: Language.get("TactilePad_Commit_Number", alter: "اعتماد القيمة (%@)"), displayDigits)
            }
        }

        return Button {
            handleCommit()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: delta != nil && abs(delta!) < 0.001 ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 16, weight: .bold))

                Text(verbatim: buttonTitle.normalizedEnglishDigits)
                    .font(AdminType.headlineBold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(buttonColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: buttonColor.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(PPTactilePressFeedbackStyle())
    }

    // MARK: - Keypad Handlers

    private func handleKeypadPress(_ digit: String) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        // Digits limit check
        if inputText.count >= config.maxDigits { return }

        // Percentage max clamp
        if case .percentage(let maxLimit) = config.mode {
            let prospective = (inputText == "0" ? digit : inputText + digit)
            if let val = Double(prospective), val > maxLimit {
                inputText = "\(Int(maxLimit))"
                return
            }
        }

        if inputText == "0" && digit != "0" {
            inputText = digit
        } else if inputText == "0" && digit == "0" {
            // keep 0
        } else {
            inputText.append(digit)
        }
    }

    private func handleKeypadDecimal() {
        guard config.mode.allowsDecimal else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        if inputText.isEmpty {
            inputText = "0."
        } else if !inputText.contains(".") {
            inputText.append(".")
        }
    }

    private func handleKeypadClear() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        inputText = ""
    }

    private func handleKeypadBackspace() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if !inputText.isEmpty {
            inputText.removeLast()
        }
    }

    private func executeChipAction(_ action: PPTactilePresetChip.ChipAction) {
        switch action {
        case .set(let val):
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            setDirectValue(val)
        case .delta(let delta):
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let current = parsedValue
            let updated: Double
            if config.allowNegative {
                updated = current + delta
            } else {
                updated = max(0.0, current + delta)
            }
            setDirectValue(updated)
        case .matchReference:
            if let ref = config.referenceValue {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                setDirectValue(ref)
            }
        case .zeroOut:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            inputText = "0"
        }
    }

    private func setDirectValue(_ val: Double) {
        if config.mode.allowsDecimal {
            if val == floor(val) {
                inputText = String(format: "%.0f", val)
            } else {
                inputText = String(format: "%.\(config.mode.maxDecimalPlaces)f", val)
            }
        } else {
            inputText = "\(Int(val))"
        }
    }

    private func handleCommit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let finalVal = parsedValue
        onCommit(finalVal)
        dismiss()
        onDismiss?()
    }

    private func handleDismiss() {
        dismiss()
        onDismiss?()
    }
}

// MARK: - Button Press Feedback Style

public struct PPTactilePressFeedbackStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - SwiftUI View Modifiers

public extension View {
    /// Present the reusable tactile number pad sheet bound to an active Boolean flag
    func tactileNumberPad(
        isPresented: Binding<Bool>,
        config: PPTactileNumberPadConfig,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            PPTactileNumberPadSheet(config: config, onCommit: onCommit)
        }
    }

    /// Quantity Pad helper
    func tactileQuantityPad(
        isPresented: Binding<Bool>,
        title: String = Language.get("EditQuantity", alter: "تعديل الكمية"),
        currentQuantity: Int,
        referenceQuantity: Int? = nil,
        specimen: PPTactileSpecimenInfo? = nil,
        onCommit: @escaping (Int) -> Void
    ) -> some View {
        let config = PPTactileNumberPadConfig(
            title: title,
            mode: .quantity(),
            initialValue: Double(currentQuantity),
            referenceValue: referenceQuantity.map(Double.init),
            referenceLabel: Language.get("CycleCount_Keypad_Expected", alter: "الرصيد الدفتري"),
            specimen: specimen
        )
        return self.sheet(isPresented: isPresented) {
            PPTactileNumberPadSheet(config: config) { val in
                onCommit(Int(val))
            }
        }
    }

    /// Price Pad helper
    func tactilePricePad(
        isPresented: Binding<Bool>,
        title: String = Language.get("EditPrice", alter: "تعديل السعر"),
        currentPrice: Double,
        referencePrice: Double? = nil,
        specimen: PPTactileSpecimenInfo? = nil,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        let config = PPTactileNumberPadConfig(
            title: title,
            mode: .price(),
            initialValue: currentPrice,
            referenceValue: referencePrice,
            referenceLabel: Language.get("OriginalPrice", alter: "السعر الأساسي"),
            specimen: specimen
        )
        return self.sheet(isPresented: isPresented) {
            PPTactileNumberPadSheet(config: config, onCommit: onCommit)
        }
    }
}

// MARK: - Objective-C / UIKit Bridge

@objc(PPTactileNumberPadBridge)
@MainActor
public final class PPTactileNumberPadBridge: NSObject {

    @objc(presentQuantityPadFrom:title:currentQuantity:referenceQuantity:specimenName:sku:imageURL:onCommit:)
    public static func presentQuantityPad(
        from viewController: UIViewController,
        title: String,
        currentQuantity: Int,
        referenceQuantity: NSNumber?,
        specimenName: String?,
        sku: String?,
        imageURL: URL?,
        onCommit: @escaping (Int) -> Void
    ) {
        let specimen = specimenName != nil ? PPTactileSpecimenInfo(
            title: specimenName!,
            imageURL: imageURL,
            sku: sku
        ) : nil

        let config = PPTactileNumberPadConfig(
            title: title,
            mode: .quantity(),
            initialValue: Double(currentQuantity),
            referenceValue: referenceQuantity?.doubleValue,
            referenceLabel: Language.get("CycleCount_Keypad_Expected", alter: "الرصيد الدفتري"),
            specimen: specimen
        )

        let sheetView = PPTactileNumberPadSheet(config: config) { val in
            onCommit(Int(val))
        }

        let hosting = UIHostingController(rootView: sheetView)
        hosting.modalPresentationStyle = .pageSheet
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        viewController.present(hosting, animated: true)
    }
}
