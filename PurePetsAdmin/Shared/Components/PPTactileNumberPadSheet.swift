//
//  PPTactileNumberPadSheet.swift
//  PurePetsAdmin
//
//  Created for PurePets Admin NextGen Platform.
//  Category-defining tactile numeric keypad sheet supporting Numbers,
//  Quantities, Prices, Amounts, Age, Discounts, and Percentages across
//  all Inventory and POS workflows.
//
//  Completely redesigned from first principles with separate, dedicated
//  architectures for iPhone (iOS) and iPad (iPadOS).
//  STRICT MANDATE: 100% of all typography uses the Beiruti brand font family.
//

import SwiftUI
import UIKit

// MARK: - Brand Typography Tokens (Strict Beiruti Only)

private enum PPTactileType {
    static func heroReadout(isPad: Bool) -> Font {
        Font.custom("Beiruti-Bold", size: isPad ? 60 : 48)
    }

    static func heroUnit(isPad: Bool) -> Font {
        Font.custom("Beiruti-Bold", size: isPad ? 22 : 18)
    }

    static func keypadDigit(isPad: Bool) -> Font {
        Font.custom("Beiruti-Bold", size: isPad ? 28 : 24)
    }

    static func keypadAction(isPad: Bool) -> Font {
        Font.custom("Beiruti-Bold", size: isPad ? 22 : 18)
    }

    static let title = Font.custom("Beiruti-Bold", size: 19)
    static let subtitle = Font.custom("Beiruti-Regular", size: 13)
    static let specimenTitle = Font.custom("Beiruti-Bold", size: 16)
    static let specimenSubtitle = Font.custom("Beiruti-Regular", size: 12)
    static let badgeBold = Font.custom("Beiruti-Bold", size: 13)
    static let badgeCaption = Font.custom("Beiruti-Medium", size: 12)
    static let chipLabel = Font.custom("Beiruti-SemiBold", size: 13)
    static let ledgerLabel = Font.custom("Beiruti-Regular", size: 13)
    static let ledgerValue = Font.custom("Beiruti-Bold", size: 14)
    static let actionButton = Font.custom("Beiruti-Bold", size: 17)
    static let secondaryButton = Font.custom("Beiruti-Bold", size: 16)
    static let hint = Font.custom("Beiruti-Regular", size: 11)
    static let tagMono = Font.custom("Beiruti-Bold", size: 12)
}

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
        case .age, .quantity:
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
    public var showsVarianceTelemetry: Bool
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
        showsVarianceTelemetry: Bool = true,
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
        self.showsVarianceTelemetry = showsVarianceTelemetry
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inputText: String = ""
    @State private var dragScrubOffset: CGFloat = 0
    @State private var isScrubbing: Bool = false
    @State private var showZeroWarning: Bool = false
    @State private var keypadBounceTrigger: Bool = false

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
        guard let delta = referenceDelta, let cost = config.specimen?.unitCost, cost > 0 else { return nil }
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
                    id: "chip_match_ref",
                    title: String(format: Language.get("TactilePad_Match_Ref", alter: "%@ (%@)"), config.referenceLabel ?? Language.get("TactilePad_Book_Stock", alter: "الرصيد الدفتري"), refText),
                    icon: "equal.circle.fill",
                    action: .matchReference,
                    tint: AdminSurface.emerald
                )
            )
        }

        // 2. Mode-specific presets
        switch config.mode {
        case .quantity(_, let allowZero, _):
            if allowZero {
                chips.append(
                    PPTactilePresetChip(
                        id: "chip_zero_out",
                        title: Language.get("TactilePad_Zero_Shelf", alter: "0 (نفاذ الرف)"),
                        icon: "slash.circle.fill",
                        action: .zeroOut,
                        tint: AdminSurface.crimson
                    )
                )
            }
            chips.append(
                PPTactilePresetChip(
                    id: "chip_plus_1",
                    title: "+1".normalizedEnglishDigits,
                    action: .delta(1.0),
                    tint: AdminSurface.primaryText
                )
            )

        case .price, .amount:
            chips.append(
                PPTactilePresetChip(
                    id: "chip_zero_price",
                    title: "0.00",
                    icon: "arrow.counterclockwise",
                    action: .zeroOut,
                    tint: AdminSurface.crimson
                )
            )
            for p in [5, 10, 50, 100] {
                chips.append(
                    PPTactilePresetChip(
                        id: "chip_price_\(p)",
                        title: "+\(p)".normalizedEnglishDigits,
                        action: .delta(Double(p)),
                        tint: AdminSurface.primaryText
                    )
                )
            }

        case .percentage:
            chips.append(
                PPTactilePresetChip(
                    id: "chip_pct_0",
                    title: "0%",
                    action: .set(0.0),
                    tint: AdminSurface.secondaryText
                )
            )
            for pct in [5, 10, 15, 20, 25, 50] {
                chips.append(
                    PPTactilePresetChip(
                        id: "chip_pct_\(pct)",
                        title: "\(pct)%",
                        action: .set(Double(pct)),
                        tint: AdminSurface.primary
                    )
                )
            }

        case .discount(_, let isPercentage, _):
            chips.append(
                PPTactilePresetChip(
                    id: "chip_disc_zero",
                    title: isPercentage ? "0%" : "0.00",
                    action: .zeroOut,
                    tint: AdminSurface.crimson
                )
            )
            if isPercentage {
                for pct in [5, 10, 15, 20, 25, 50] {
                    chips.append(
                        PPTactilePresetChip(
                            id: "chip_disc_pct_\(pct)",
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
                            id: "chip_disc_amt_\(amt)",
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
                        id: "chip_age_\(m)",
                        title: "\(m) \(unit)".normalizedEnglishDigits,
                        action: .set(Double(m)),
                        tint: AdminSurface.primary
                    )
                )
            }
            chips.append(
                PPTactilePresetChip(
                    id: "chip_age_plus_1",
                    title: "+1",
                    action: .delta(1.0),
                    tint: AdminSurface.primaryText
                )
            )

        case .number:
            chips.append(
                PPTactilePresetChip(
                    id: "chip_num_zero",
                    title: Language.get("Reset", alter: "إعادة ضبط (0)"),
                    icon: "arrow.counterclockwise",
                    action: .zeroOut,
                    tint: AdminSurface.secondaryText
                )
            )
            chips.append(
                PPTactilePresetChip(
                    id: "chip_num_1",
                    title: "+1".normalizedEnglishDigits,
                    action: .delta(1.0),
                    tint: AdminSurface.primaryText
                )
            )
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

    // MARK: - Main Body

    public var body: some View {
        Group {
            if isPad {
                iPadStudioLayout
            } else {
                iPhoneCapsuleLayout
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - ════════════════════════════════════════════════════════════════
    // MARK: iPhone (iOS) Tactile Capsule Layout
    // MARK: ════════════════════════════════════════════════════════════════

    private var compactSheetHeight: CGFloat {
        let base: CGFloat = config.specimen != nil ? 585 : 510
        return min(base, UIScreen.main.bounds.height * 0.90)
    }

    private var iPhoneCapsuleLayout: some View {
        VStack(spacing: 0) {
            // Grabber Handle
            Capsule()
                .fill(AdminSurface.hairline.opacity(0.8))
                .frame(width: 36, height: 4.5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Header Bar
            iPhoneHeaderBar
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 8)

            // Specimen Identity Deck
            if let specimen = config.specimen {
                specimenGlassDeck(specimen: specimen)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .padding(.bottom, 8)
            }

            // Hero Interactive Readout & Variance Sentinel
            heroReadoutAndVarianceSentinel
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 8)

            // Multi-Tier Quick Accelerator Ribbon
            acceleratorChipsRibbon
                .padding(.bottom, 8)

            // Sculpted Tactile Numeric Matrix
            keypadMatrix(buttonHeight: 48)
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 12)

            // Sovereign Primary Action Command
            primaryActionButton
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 14)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .presentationDetents([.height(compactSheetHeight)])
        .presentationDragIndicator(.hidden)
    }

    private var iPhoneHeaderBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.title)
                    .font(PPTactileType.title)
                    .foregroundColor(AdminSurface.primaryText)

                if let subtitle = config.subtitle {
                    Text(subtitle)
                        .font(PPTactileType.subtitle)
                        .foregroundColor(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handleDismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(AdminSurface.cardElevated)
                        .frame(width: 32, height: 32)
                    Image(systemName: "xmark")
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(AdminSurface.secondaryText)
                }
                .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.8))
            }
            .accessibilityLabel(Language.get("Cancel", alter: "إلغاء"))
        }
    }

    // MARK: - Specimen Glass Deck

    private func specimenGlassDeck(specimen: PPTactileSpecimenInfo) -> some View {
        HStack(spacing: 12) {
            // Thumbnail / Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AdminSurface.cardElevated)
                    .frame(width: 48, height: 48)

                if let url = specimen.imageURL {
                    AdminRemoteImage(url: url) {
                        ProgressView().scaleEffect(0.7)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "cube.box.fill")
                        .font(Font.custom("Beiruti-Bold", size: 20))
                        .foregroundColor(AdminSurface.primary.opacity(0.8))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AdminSurface.hairline, lineWidth: 0.8)
            )

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(specimen.title)
                    .font(PPTactileType.specimenTitle)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let sku = specimen.sku, !sku.isEmpty {
                        Text(verbatim: sku.normalizedEnglishDigits)
                            .font(PPTactileType.tagMono)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let shelf = specimen.shelfLocation, !shelf.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mappin")
                                .font(Font.custom("Beiruti-Bold", size: 9))
                            Text(verbatim: shelf.normalizedEnglishDigits)
                        }
                        .font(PPTactileType.tagMono)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let ref = config.referenceValue {
                        HStack(spacing: 3) {
                            Text((config.referenceLabel ?? Language.get("TactilePad_Book_Stock", alter: "الرصيد الدفتري")) + ":")
                                .font(PPTactileType.specimenSubtitle)
                                .foregroundColor(AdminSurface.secondaryText)
                            let refFormatted = config.mode.allowsDecimal ? String(format: "%.2f", ref) : "\(Int(ref))"
                            Text(verbatim: refFormatted.normalizedEnglishDigits)
                                .font(PPTactileType.badgeBold)
                                .foregroundColor(AdminSurface.primaryText)
                            Text(config.mode.defaultUnit)
                                .font(PPTactileType.specimenSubtitle)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AdminSurface.cardElevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Hero Interactive Readout & Variance Sentinel

    private var heroReadoutAndVarianceSentinel: some View {
        let delta = referenceDelta

        return VStack(spacing: 6) {
            // Numeric Readout with Interactive Scrub Gestures
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(verbatim: displayDigits)
                    .font(PPTactileType.heroReadout(isPad: isPad))
                    .foregroundColor(AdminSurface.primaryText)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? .none : .spring(response: 0.22, dampingFraction: 0.8), value: inputText)

                Text(config.mode.defaultUnit)
                    .font(PPTactileType.heroUnit(isPad: isPad))
                    .foregroundColor(AdminSurface.secondaryText)
                    .padding(.bottom, 4)

                if !inputText.isEmpty {
                    Button {
                        handleKeypadClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Font.custom("Beiruti-Bold", size: 16))
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.5))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.leading, 4)
                    .accessibilityLabel(Language.get("TactilePad_Clear", alter: "مسح"))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { gesture in
                        let translation = gesture.translation.width
                        let stepDelta = Int(translation / 30)
                        if stepDelta != 0 && !isScrubbing {
                            isScrubbing = true
                            let dir = Language.isRTL() ? -1 : 1
                            let deltaToAdd = Double(stepDelta * dir)
                            executeChipAction(.delta(deltaToAdd))
                        }
                    }
                    .onEnded { _ in
                        isScrubbing = false
                    }
            )

            // Dynamic Variance Telemetry Badge
            if config.showsVarianceTelemetry, let delta = delta {
                HStack(spacing: 6) {
                    if abs(delta) < 0.001 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundColor(AdminSurface.emerald)
                        Text(Language.get("TactilePad_Matched_Badge", alter: "مطابق تماماً للرصيد الدفتري (0 فرق)"))
                            .font(PPTactileType.badgeBold)
                            .foregroundColor(AdminSurface.emerald)
                    } else if delta < 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundColor(AdminSurface.crimson)

                        let deltaStr = config.mode.allowsDecimal ? String(format: "%.2f", abs(delta)) : "\(Int(abs(delta)))"
                        let impactStr = formattedFinancialImpact(isDeficit: true)
                        Text(verbatim: String(format: Language.get("TactilePad_Deficit_Badge", alter: "عجز / نقص -%@ %@%@"), deltaStr, config.mode.defaultUnit, impactStr).normalizedEnglishDigits)
                            .font(PPTactileType.badgeBold)
                            .foregroundColor(AdminSurface.crimson)
                    } else {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundColor(AdminSurface.amber)

                        let deltaStr = config.mode.allowsDecimal ? String(format: "%.2f", delta) : "\(Int(delta))"
                        let impactStr = formattedFinancialImpact(isDeficit: false)
                        Text(verbatim: String(format: Language.get("TactilePad_Surplus_Badge", alter: "فائض / زيادة +%@ %@%@"), deltaStr, config.mode.defaultUnit, impactStr).normalizedEnglishDigits)
                            .font(PPTactileType.badgeBold)
                            .foregroundColor(AdminSurface.amber)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    badgeTone(delta: delta).opacity(0.12),
                    in: Capsule()
                )
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: delta)
            } else if parsedValue == 0 && !config.mode.allowsDecimal {
                HStack(spacing: 5) {
                    Image(systemName: "slash.circle.fill")
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundColor(AdminSurface.crimson)
                    Text(config.showsVarianceTelemetry
                        ? Language.get("TactilePad_Zero_Stock_Warning", alter: "تم تصفير الكمية. سيتم وسم الصنف بأنه نافذ من الرف.")
                        : Language.get("POS_Zero_Quantity_Remove_Warning", alter: "الكمية 0: سيتم حذف الصنف من السلة عند التأكيد."))
                        .font(PPTactileType.hint)
                        .foregroundColor(AdminSurface.crimson)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AdminSurface.crimson.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(badgeTone(delta: delta).opacity(0.35), lineWidth: 1)
        )
    }

    private func badgeTone(delta: Double?) -> Color {
        guard config.showsVarianceTelemetry, let delta = delta else { return AdminSurface.hairline }
        if abs(delta) < 0.001 {
            return AdminSurface.emerald
        } else if delta < 0 {
            return AdminSurface.crimson
        } else {
            return AdminSurface.amber
        }
    }

    private func formattedFinancialImpact(isDeficit: Bool) -> String {
        guard let impact = financialImpact, impact > 0 else { return "" }
        let formattedImpact = String(format: "%.2f", impact)
        let key = isDeficit ? "TactilePad_Financial_Impact_Minus" : "TactilePad_Financial_Impact_Plus"
        let fallback = isDeficit ? " (أثر -%@ ر.ق)" : " (أثر +%@ ر.ق)"
        return String(format: Language.get(key, alter: fallback), formattedImpact)
    }

    // MARK: - Accelerator Ribbon (iPhone Horizontal Scroll)

    private var acceleratorChipsRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeChips) { chip in
                    chipButton(chip: chip)
                }
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.vertical, 6)
        }
        .frame(height: 48)
    }

    private func chipButton(chip: PPTactilePresetChip) -> some View {
        Button {
            executeChipAction(chip.action)
        } label: {
            HStack(spacing: 4) {
                if let icon = chip.icon {
                    Image(systemName: icon)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                }
                Text(chip.title)
                    .font(PPTactileType.chipLabel)
                    .lineLimit(1)
            }
            .foregroundColor(chip.tint ?? AdminSurface.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                (chip.tint ?? AdminSurface.primaryText).opacity(chip.icon != nil ? 0.12 : 0.06),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke((chip.tint ?? AdminSurface.hairline).opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(PPTactilePressFeedbackStyle())
        .hoverEffect(isPad ? .highlight : .automatic)
        .accessibilityLabel(chip.title)
    }

    // MARK: - Tactile Numeric Matrix (Keypad)

    private func keypadMatrix(buttonHeight: CGFloat) -> some View {
        VStack(spacing: 7) {
            ForEach(0..<keypadKeys.count, id: \.self) { row in
                HStack(spacing: 7) {
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
                        .font(PPTactileType.keypadDigit(isPad: isPad))
                        .foregroundColor(AdminSurface.primaryText)

                case .decimal:
                    Text(verbatim: ".")
                        .font(PPTactileType.keypadDigit(isPad: isPad))
                        .foregroundColor(AdminSurface.primaryText)

                case .clear:
                    Text(verbatim: "C")
                        .font(PPTactileType.keypadAction(isPad: isPad))
                        .foregroundColor(AdminSurface.crimson)

                case .backspace:
                    Image(systemName: "delete.left.fill")
                        .font(Font.custom("Beiruti-Bold", size: isPad ? 22 : 18))
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        }
        .buttonStyle(PPTactilePressFeedbackStyle())
        .hoverEffect(isPad ? .highlight : .automatic)
        .accessibilityLabel(accessibilityLabel(for: keyItem))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
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

    private func accessibilityLabel(for key: PPTactileKey) -> String {
        switch key {
        case .digit(let d):
            return String(format: Language.get("TactilePad_A11y_Key", alter: "مفتاح %@"), d)
        case .decimal:
            return Language.get("TactilePad_A11y_Decimal", alter: "فاصلة عشرية")
        case .clear:
            return Language.get("TactilePad_A11y_Clear", alter: "مسح القيمة")
        case .backspace:
            return Language.get("TactilePad_A11y_Backspace", alter: "حذف آخر رقم")
        }
    }

    // MARK: - Sovereign Primary Action Button

    private var primaryActionButton: some View {
        let delta = referenceDelta

        let buttonColor: Color
        if let d = delta, abs(d) < 0.001 {
            buttonColor = AdminSurface.emerald
        } else if parsedValue <= 0 && !config.allowNegative {
            buttonColor = AdminSurface.crimson
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
                    .font(Font.custom("Beiruti-Bold", size: 16))

                Text(verbatim: buttonTitle.normalizedEnglishDigits)
                    .font(PPTactileType.actionButton)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(buttonColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: buttonColor.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(PPTactilePressFeedbackStyle())
        .hoverEffect(isPad ? .lift : .automatic)
    }

    // MARK: - ════════════════════════════════════════════════════════════════
    // MARK: iPad (iPadOS) Studio Tactical Console Layout
    // MARK: ════════════════════════════════════════════════════════════════

    private var iPadStudioLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top iPad Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(config.title)
                            .font(PPTactileType.title)
                            .foregroundColor(AdminSurface.primaryText)

                        if let subtitle = config.subtitle {
                            Text(subtitle)
                                .font(PPTactileType.subtitle)
                                .foregroundColor(AdminSurface.secondaryText)
                        } else {
                            Text(Language.get("TactilePad_Keyboard_Hint", alter: "يمكنك استخدام لوحة المفاتيح الخارجية للأرقام مباشرة"))
                                .font(PPTactileType.subtitle)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        handleDismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.cardElevated)
                                .frame(width: 36, height: 36)
                            Image(systemName: "xmark")
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.8))
                    }
                    .accessibilityLabel(Language.get("Cancel", alter: "إلغاء"))
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 14)

                Divider().background(AdminSurface.hairline)

                // Asymmetric Dual-Wing Studio Canvas
                HStack(spacing: 24) {
                    // LEFT WING (42%): Specimen Telemetry, Stock Meter & Accounting Ledger
                    VStack(spacing: 14) {
                        if let specimen = config.specimen {
                            iPadSpecimenStudioCard(specimen: specimen)
                        }

                        if config.showsVarianceTelemetry, let delta = referenceDelta {
                            iPadStockComparisonGauge(delta: delta)
                            iPadValuationLedgerCard(delta: delta)
                        }

                        // Presets Grid
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Language.get("TactilePad_Quick_Accelerators", alter: "المعدلات السريعة"))
                                .font(PPTactileType.badgeBold)
                                .foregroundColor(AdminSurface.secondaryText)

                            acceleratorChipsGrid
                        }

                        Spacer()
                    }
                    .frame(maxWidth: 340)

                    // Vertical Separator
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(width: 1)

                    // RIGHT WING (58%): Readout Canvas, Pro Keypad & Dual Action Footer
                    VStack(spacing: 14) {
                        heroReadoutAndVarianceSentinel

                        keypadMatrix(buttonHeight: 56)

                        Spacer()

                        // Dual Action Buttons (Cancel & Commit)
                        HStack(spacing: 12) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                handleDismiss()
                            } label: {
                                Text(Language.get("Cancel", alter: "إلغاء"))
                                    .font(PPTactileType.secondaryButton)
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                            }
                            .buttonStyle(PPTactilePressFeedbackStyle())

                            primaryActionButton
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(AdminSurface.background.ignoresSafeArea())
        }
        .frame(minWidth: 740, minHeight: 560)
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
                    handleKeypadDecimal()
                    return .handled
                }
            } else if press.key == .delete || press.key == .deleteForward {
                handleKeypadBackspace()
                return .handled
            }
            return .ignored
        }
    }

    private func iPadSpecimenStudioCard(specimen: PPTactileSpecimenInfo) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AdminSurface.cardElevated)
                    .frame(width: 64, height: 64)

                if let url = specimen.imageURL {
                    AdminRemoteImage(url: url) {
                        ProgressView().scaleEffect(0.8)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: "cube.box.fill")
                        .font(Font.custom("Beiruti-Bold", size: 28))
                        .foregroundColor(AdminSurface.primary.opacity(0.8))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

            VStack(alignment: .leading, spacing: 4) {
                Text(specimen.title)
                    .font(PPTactileType.specimenTitle)
                    .foregroundColor(AdminSurface.primaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let sku = specimen.sku, !sku.isEmpty {
                        Text(verbatim: sku.normalizedEnglishDigits)
                            .font(PPTactileType.tagMono)
                            .foregroundColor(AdminSurface.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 4))
                    }

                    if let shelf = specimen.shelfLocation, !shelf.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mappin")
                                .font(Font.custom("Beiruti-Bold", size: 9))
                            Text(verbatim: shelf.normalizedEnglishDigits)
                        }
                        .font(PPTactileType.tagMono)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private func iPadStockComparisonGauge(delta: Double) -> some View {
        guard let ref = config.referenceValue else { return AnyView(EmptyView()) }
        let maxVal = max(ref, parsedValue, 1.0)
        let bookRatio = CGFloat(ref / maxVal)
        let newRatio = CGFloat(parsedValue / maxVal)

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(config.referenceLabel ?? Language.get("TactilePad_Book_Stock", alter: "الرصيد الدفتري"))
                        .font(PPTactileType.badgeCaption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(verbatim: "\(Int(ref)) \(config.mode.defaultUnit)".normalizedEnglishDigits)
                        .font(PPTactileType.badgeBold)
                        .foregroundColor(AdminSurface.primaryText)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AdminSurface.cardElevated)
                        Capsule()
                            .fill(AdminSurface.primary.opacity(0.6))
                            .frame(width: max(8, geo.size.width * bookRatio))
                    }
                }
                .frame(height: 7)

                HStack {
                    Text(Language.get("TactilePad_New_Valuation", alter: "الكمية المدخلة"))
                        .font(PPTactileType.badgeCaption)
                        .foregroundColor(AdminSurface.secondaryText)
                    Spacer()
                    Text(verbatim: "\(displayDigits) \(config.mode.defaultUnit)".normalizedEnglishDigits)
                        .font(PPTactileType.badgeBold)
                        .foregroundColor(badgeTone(delta: delta))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AdminSurface.cardElevated)
                        Capsule()
                            .fill(badgeTone(delta: delta))
                            .frame(width: max(8, geo.size.width * newRatio))
                    }
                }
                .frame(height: 7)
            }
            .padding(12)
            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        )
    }

    private func iPadValuationLedgerCard(delta: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(Language.get("TactilePad_Economics_Title", alter: "تحليل الأثر المالي والمحاسبي"))
                    .font(PPTactileType.badgeBold)
                    .foregroundColor(AdminSurface.secondaryText)
                Spacer()
                if let impact = financialImpact {
                    Text(verbatim: String(format: "%@%.2f %@", delta < 0 ? "-" : "+", impact, Language.get("QAR", alter: "ر.ق")).normalizedEnglishDigits)
                        .font(PPTactileType.badgeBold)
                        .foregroundColor(badgeTone(delta: delta))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: abs(delta) < 0.001 ? "shield.checkmark.fill" : (delta < 0 ? "exclamationmark.triangle.fill" : "chart.line.uptrend.xyaxis.circle.fill"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundColor(badgeTone(delta: delta))

                Text(verbatim: String(format: Language.get("TactilePad_Difference_Formula", alter: "المدخل: %@ | الفرق: %@"), "\(displayDigits) \(config.mode.defaultUnit)", "\(delta >= 0 ? "+" : "")\(config.mode.allowsDecimal ? String(format: "%.2f", delta) : "\(Int(delta))")").normalizedEnglishDigits)
                    .font(PPTactileType.ledgerValue)
                    .foregroundColor(badgeTone(delta: delta))
                Spacer()
            }
        }
        .padding(12)
        .background(badgeTone(delta: delta).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(badgeTone(delta: delta).opacity(0.3), lineWidth: 0.8))
    }

    private var acceleratorChipsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(activeChips) { chip in
                chipButton(chip: chip)
            }
        }
    }

    // MARK: - Keypad Handlers

    private func handleKeypadPress(_ digit: String) {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        if inputText.count >= config.maxDigits {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

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
            // keep single zero
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
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.16, dampingFraction: 0.65), value: configuration.isPressed)
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
            referenceLabel: Language.get("TactilePad_Book_Stock", alter: "الرصيد الدفتري"),
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
            referenceLabel: Language.get("TactilePad_Book_Stock", alter: "الرصيد الدفتري"),
            specimen: specimen
        )

        let sheetView = PPTactileNumberPadSheet(config: config) { val in
            onCommit(Int(val))
        }

        let hosting = UIHostingController(rootView: sheetView)
        hosting.modalPresentationStyle = .pageSheet
        if let sheet = hosting.sheetPresentationController {
            let targetHeight: CGFloat = (config.specimen != nil ? 585.0 : 510.0)
            if #available(iOS 16.0, *) {
                sheet.detents = [
                    .custom { _ in min(targetHeight, UIScreen.main.bounds.height * 0.90) }
                ]
            } else {
                sheet.detents = [.medium()]
            }
            sheet.prefersGrabberVisible = false
        }
        viewController.present(hosting, animated: true)
    }
}
