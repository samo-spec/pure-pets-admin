//
//  ReturnUnitSelectionView.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Exact animal selection studio with ring tag verification, species details, and condition capture.
//  Dedicated native architectures for iPhone (iOS) and iPad (iPadOS).
//

import SwiftUI

public struct ReturnUnitSelectionView: View {
    @ObservedObject var viewModel: ReturnUnitSelectionViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(viewModel: ReturnUnitSelectionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            if viewModel.isLoading {
                LivePetSelectionSkeletonView()
            } else if viewModel.availableUnits.isEmpty {
                LivePetSelectionEmptyView()
            } else if horizontalSizeClass == .regular {
                ReturnUnitSelectionViewiPad(viewModel: viewModel)
            } else {
                ReturnUnitSelectionViewiPhone(viewModel: viewModel)
            }
        }
    }
}

// MARK: - iPhone Handheld Tactical Cockpit

private struct ReturnUnitSelectionViewiPhone: View {
    @ObservedObject var viewModel: ReturnUnitSelectionViewModel
    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme

    private var returnableUnits: [LivePetReturnUnit] {
        viewModel.availableUnits.filter { !$0.isAlreadyReturned }
    }

    private var filteredUnits: [LivePetReturnUnit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.availableUnits }
        return viewModel.availableUnits.filter { unit in
            unit.ringTag.lowercased().contains(query) ||
            unit.unitId.lowercased().contains(query) ||
            unit.productName.lowercased().contains(query) ||
            (unit.speciesName?.lowercased().contains(query) ?? false) ||
            (unit.breedName?.lowercased().contains(query) ?? false)
        }
    }

    private var allReturnableSelected: Bool {
        let returnableIds = Set(returnableUnits.map { $0.unitId })
        return !returnableIds.isEmpty && returnableIds.isSubset(of: viewModel.selectedUnitIds)
    }

    private func toggleSelectAll() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if allReturnableSelected {
                viewModel.selectedUnitIds.removeAll()
            } else {
                for unit in returnableUnits {
                    viewModel.selectedUnitIds.insert(unit.unitId)
                    if viewModel.unitConditions[unit.unitId] == nil {
                        viewModel.unitConditions[unit.unitId] = .appearsNormal
                    }
                }
            }
            viewModel.syncDraft()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Section with Live Telemetry
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("LivePet_Return_SelectUnitsTitle", alter: "تحديد الحيوان الأليف بدقة"))
                        .font(PPBeirutiFont.bold(17, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("LivePet_Return_SelectUnitsSub", alter: "اختر الحيوان المطابق لرقم الحجل أو الشريحة"))
                        .font(PPBeirutiFont.regular(12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer(minLength: 4)

                // Selection Counter Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.selectedUnitIds.isEmpty ? AdminSurface.secondaryText : Color(red: 0.05, green: 0.65, blue: 0.52))
                        .frame(width: 6, height: 6)

                    Text(String(format: Language.get("LivePet_SelectionTelemetry", alter: "%d من %d محدد"), viewModel.selectedUnitIds.count, returnableUnits.count))
                        .font(PPBeirutiFont.bold(11.5, relativeTo: .caption2))
                        .foregroundStyle(viewModel.selectedUnitIds.isEmpty ? AdminSurface.secondaryText : Color(red: 0.05, green: 0.65, blue: 0.52))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(viewModel.selectedUnitIds.isEmpty ? AdminSurface.backgroundSecondary : Color(red: 0.05, green: 0.65, blue: 0.52).opacity(0.12))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(viewModel.selectedUnitIds.isEmpty ? AdminSurface.hairline : Color(red: 0.05, green: 0.65, blue: 0.52).opacity(0.28), lineWidth: 0.75)
                )
            }

            // Tactical Utility Bar: Search Field + Select All Toggle
            HStack(spacing: 8) {
                // Search Input Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)

                    TextField(Language.get("LivePet_SearchPlaceholder", alter: "البحث برقم الحجل، الشريحة، أو اسم الحيوان..."), text: $searchText)
                        .font(PPBeirutiFont.regular(12.5, relativeTo: .subheadline))
                        .foregroundStyle(AdminSurface.primaryText)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )

                // Select All / Deselect All Action Pill
                if !returnableUnits.isEmpty {
                    Button(action: toggleSelectAll) {
                        HStack(spacing: 4) {
                            Image(systemName: allReturnableSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(allReturnableSelected ? Color(red: 0.05, green: 0.65, blue: 0.52) : AdminSurface.secondaryText)

                            Text(allReturnableSelected ? Language.get("LivePet_DeselectAll", alter: "إلغاء التحديد") : String(format: Language.get("LivePet_SelectAll", alter: "تحديد الكل (%d)"), returnableUnits.count))
                                .font(PPBeirutiFont.bold(11.5, relativeTo: .caption2))
                                .foregroundStyle(allReturnableSelected ? Color(red: 0.05, green: 0.65, blue: 0.52) : AdminSurface.primaryText)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(allReturnableSelected ? Color(red: 0.05, green: 0.65, blue: 0.52).opacity(colorScheme == .dark ? 0.18 : 0.09) : AdminSurface.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(allReturnableSelected ? Color(red: 0.05, green: 0.65, blue: 0.52).opacity(0.35) : AdminSurface.hairline, lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Cards Deck
            if filteredUnits.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(Language.get("LivePet_NoSearchResults", alter: "لا توجد نتائج مطابقة لبحثك."))
                        .font(PPBeirutiFont.regular(12, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 11) {
                    ForEach(filteredUnits) { unit in
                        LivePetUnitCardiPhone(
                            unit: unit,
                            currency: viewModel.receipt.currency,
                            isSelected: viewModel.selectedUnitIds.contains(unit.unitId),
                            condition: viewModel.unitConditions[unit.unitId] ?? .appearsNormal,
                            notes: viewModel.unitNotes[unit.unitId] ?? "",
                            onToggle: {
                                viewModel.toggleUnitSelection(unit)
                            },
                            onConditionChange: { newCondition in
                                viewModel.setCondition(newCondition, for: unit.unitId)
                            },
                            onNotesChange: { newNotes in
                                viewModel.setNotes(newNotes, for: unit.unitId)
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - iPhone Animal Vault Card

private struct LivePetUnitCardiPhone: View {
    let unit: LivePetReturnUnit
    let currency: String
    let isSelected: Bool
    let condition: ReturnPhysicalCondition
    let notes: String
    let onToggle: () -> Void
    let onConditionChange: (ReturnPhysicalCondition) -> Void
    let onNotesChange: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let emeraldAccent = Color(red: 0.05, green: 0.65, blue: 0.52)

    private var speciesIconName: String {
        let s = (unit.speciesName ?? unit.productName).lowercased()
        if s.contains("قط") || s.contains("cat") { return "cat.fill" }
        if s.contains("كلب") || s.contains("dog") { return "dog.fill" }
        if s.contains("طير") || s.contains("عصفور") || s.contains("bird") || s.contains("ببغاء") { return "bird.fill" }
        if s.contains("أرنب") || s.contains("rabbit") || s.contains("hare") { return "hare.fill" }
        if s.contains("سمك") || s.contains("fish") { return "fish.fill" }
        if s.contains("سلحفاة") || s.contains("turtle") { return "tortoise.fill" }
        return "pawprint.fill"
    }

    private var speciesSquircle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            emeraldAccent.opacity(colorScheme == .dark ? 0.26 : 0.14),
                            emeraldAccent.opacity(colorScheme == .dark ? 0.08 : 0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: speciesIconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(emeraldAccent)
        }
        .frame(width: 38, height: 38)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(emeraldAccent.opacity(colorScheme == .dark ? 0.35 : 0.18), lineWidth: 0.75)
        )
    }

    private var ringTagChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "number.square.fill")
                .font(.system(size: 8))
                .foregroundStyle(emeraldAccent)

            Text(unit.displayIdentification)
                .font(PPBeirutiFont.bold(12.5, relativeTo: .caption))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(emeraldAccent.opacity(colorScheme == .dark ? 0.16 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(emeraldAccent.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var formattedRefundPrice: String {
        let scale = LivePetMoney.minorUnitScale(for: currency)
        let amount = unit.refundAmountMajor.formatted(.number.precision(.fractionLength(scale)))
        let symbol = currency == "QAR" ? (Language.isRTL() ? "ر.ق" : "QAR") : currency
        return "\(amount) \(symbol)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Touch Bar
            Button(action: {
                guard !unit.isAlreadyReturned else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onToggle()
            }) {
                HStack(alignment: .center, spacing: 10) {
                    speciesSquircle

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            ringTagChip

                            if let species = unit.speciesName, !species.isEmpty {
                                Text(species)
                                    .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        // Product Name / Breed / Sex
                        HStack(spacing: 4) {
                            Text(unit.productName)
                                .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                                .foregroundStyle(unit.isAlreadyReturned ? AdminSurface.secondaryText : AdminSurface.primaryText)
                                .lineLimit(1)

                            if let breed = unit.breedName, !breed.isEmpty {
                                Text("• \(breed)")
                                    .font(PPBeirutiFont.regular(11, relativeTo: .caption2))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }

                            if let sex = unit.sex, !sex.isEmpty {
                                Text("(\(sex))")
                                    .font(PPBeirutiFont.medium(10, relativeTo: .caption2))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }

                        // Price & Discount Telemetry
                        HStack(spacing: 6) {
                            Text(formattedRefundPrice)
                                .font(PPBeirutiFont.bold(14, relativeTo: .subheadline))
                                .foregroundStyle(unit.isAlreadyReturned ? AdminSurface.secondaryText : emeraldAccent)

                            if unit.allocatedDiscountMinor > 0 {
                                let scale = LivePetMoney.minorUnitScale(for: currency)
                                let discountFactor = LivePetMoney.scaleFactor(for: currency)
                                let discountFormatted = (Double(unit.allocatedDiscountMinor) / discountFactor).formatted(.number.precision(.fractionLength(scale)))
                                let symbol = currency == "QAR" ? (Language.isRTL() ? "ر.ق" : "QAR") : currency

                                HStack(spacing: 2) {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 7))
                                    Text("-\(discountFormatted) \(symbol)")
                                        .font(PPBeirutiFont.medium(10, relativeTo: .caption2))
                                }
                                .foregroundStyle(Color(uiColor: .systemOrange))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color(uiColor: .systemOrange).opacity(0.12), in: Capsule())
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    // Trailing Checkmark or Already Returned Seal
                    if unit.isAlreadyReturned {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 9))
                            Text(Language.get("LivePet_AlreadyReturned_Badge", alter: "مسترجع سابقاً"))
                                .font(PPBeirutiFont.bold(10, relativeTo: .caption2))
                        }
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .systemRed).opacity(0.12), in: Capsule())
                    } else {
                        ZStack {
                            Circle()
                                .strokeBorder(isSelected ? emeraldAccent : AdminSurface.hairline, lineWidth: isSelected ? 2 : 1.2)
                                .background(isSelected ? emeraldAccent : Color.clear, in: Circle())
                                .frame(width: 24, height: 24)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(LivePetReturnPressStyle())
            .disabled(unit.isAlreadyReturned)

            // Expandable Clinical Condition & Handover Assessment Drawer
            if isSelected && !unit.isAlreadyReturned {
                Divider()
                    .background(AdminSurface.hairline)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(emeraldAccent)

                        Text(Language.get("LivePet_ConditionSummaryTitle", alter: "الفحص الصحي المبدئي عند الاستلام:"))
                            .font(PPBeirutiFont.bold(11.5, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    // 5-Token Physical Condition Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ReturnPhysicalCondition.allCases) { item in
                                let isCondActive = condition == item
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onConditionChange(item)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: item.iconName)
                                            .font(.system(size: 10, weight: .bold))
                                        Text(item.localizedTitle)
                                            .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                                    }
                                    .foregroundStyle(isCondActive ? .white : AdminSurface.primaryText)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        isCondActive ? item.tintColor : AdminSurface.backgroundSecondary,
                                        in: Capsule(style: .continuous)
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(isCondActive ? item.tintColor : AdminSurface.hairline, lineWidth: 0.6)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Clinical Recommendation Filament
                    HStack(spacing: 4) {
                        Image(systemName: condition.suggestedHealthDisposition.iconName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(condition.suggestedHealthDisposition.tintColor)

                        Text(String(format: Language.get("LivePet_InspectionAdvice_Prefix", alter: "توجيه الاستلام: %@"), condition.suggestedHealthDisposition.localizedTitle))
                            .font(PPBeirutiFont.medium(10.5, relativeTo: .caption2))
                            .foregroundStyle(condition.suggestedHealthDisposition.tintColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(condition.suggestedHealthDisposition.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    // Handover Remarks Notes Field
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 10))
                            .foregroundStyle(AdminSurface.secondaryText)

                        TextField(
                            Language.get("LivePet_UnitNotes_Placeholder", alter: "ملاحظات إضافية حول سلوك أو مظهر الحيوان..."),
                            text: Binding(
                                get: { notes },
                                set: { onNotesChange($0) }
                            )
                        )
                        .font(PPBeirutiFont.regular(11.5, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? AdminSurface.cardElevated : (colorScheme == .dark ? Color(white: 0.12) : Color.white))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? emeraldAccent : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.75)
        )
        .shadow(color: isSelected ? emeraldAccent.opacity(colorScheme == .dark ? 0.20 : 0.06) : Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03), radius: 5, y: 2)
        .opacity(unit.isAlreadyReturned ? 0.60 : 1.0)
    }
}

// MARK: - iPadOS Widescreen Dual-Horizon Clinical Studio

private struct ReturnUnitSelectionViewiPad: View {
    @ObservedObject var viewModel: ReturnUnitSelectionViewModel
    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme
    private let emeraldAccent = Color(red: 0.05, green: 0.65, blue: 0.52)

    private var returnableUnits: [LivePetReturnUnit] {
        viewModel.availableUnits.filter { !$0.isAlreadyReturned }
    }

    private var filteredUnits: [LivePetReturnUnit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.availableUnits }
        return viewModel.availableUnits.filter { unit in
            unit.ringTag.lowercased().contains(query) ||
            unit.unitId.lowercased().contains(query) ||
            unit.productName.lowercased().contains(query) ||
            (unit.speciesName?.lowercased().contains(query) ?? false) ||
            (unit.breedName?.lowercased().contains(query) ?? false)
        }
    }

    private var allReturnableSelected: Bool {
        let returnableIds = Set(returnableUnits.map { $0.unitId })
        return !returnableIds.isEmpty && returnableIds.isSubset(of: viewModel.selectedUnitIds)
    }

    private func toggleSelectAll() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            if allReturnableSelected {
                viewModel.selectedUnitIds.removeAll()
            } else {
                for unit in returnableUnits {
                    viewModel.selectedUnitIds.insert(unit.unitId)
                    if viewModel.unitConditions[unit.unitId] == nil {
                        viewModel.unitConditions[unit.unitId] = .appearsNormal
                    }
                }
            }
            viewModel.syncDraft()
        }
    }

    private var formattedTotalRefund: String {
        let scale = LivePetMoney.minorUnitScale(for: viewModel.receipt.currency)
        let amount = viewModel.maximumRefundAmountMajor.formatted(.number.precision(.fractionLength(scale)))
        let symbol = viewModel.receipt.currency == "QAR" ? (Language.isRTL() ? "ر.ق" : "QAR") : viewModel.receipt.currency
        return "\(amount) \(symbol)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Leading Horizon (58%): Animal Custody Verification Vault
            VStack(alignment: .leading, spacing: 14) {
                // Horizon Header
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(emeraldAccent)
                            Text(Language.get("LivePet_Studio_LeadingVault", alter: "سجل الحيوانات المحجلة المعتمدة"))
                                .font(PPBeirutiFont.bold(17.5, relativeTo: .headline))
                                .foregroundStyle(AdminSurface.primaryText)
                        }

                        Text(Language.get("LivePet_Return_SelectUnitsSub", alter: "اختر الحيوان المطابق لرقم الحجل أو الشريحة"))
                            .font(PPBeirutiFont.regular(12, relativeTo: .caption))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Spacer()

                    // Selection Counter Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(viewModel.selectedUnitIds.isEmpty ? AdminSurface.secondaryText : emeraldAccent)
                            .frame(width: 6, height: 6)

                        Text(String(format: Language.get("LivePet_SelectionTelemetry", alter: "%d من %d محدد"), viewModel.selectedUnitIds.count, returnableUnits.count))
                            .font(PPBeirutiFont.bold(12, relativeTo: .caption))
                            .foregroundStyle(viewModel.selectedUnitIds.isEmpty ? AdminSurface.secondaryText : emeraldAccent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(viewModel.selectedUnitIds.isEmpty ? AdminSurface.backgroundSecondary : emeraldAccent.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(viewModel.selectedUnitIds.isEmpty ? AdminSurface.hairline : emeraldAccent.opacity(0.28), lineWidth: 0.75)
                    )
                }

                // Search & Quick Batch Action Row
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdminSurface.secondaryText)

                        TextField(Language.get("LivePet_SearchPlaceholder", alter: "البحث برقم الحجل، الشريحة، أو اسم الحيوان..."), text: $searchText)
                            .font(PPBeirutiFont.regular(13, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )

                    if !returnableUnits.isEmpty {
                        Button(action: toggleSelectAll) {
                            HStack(spacing: 5) {
                                Image(systemName: allReturnableSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(allReturnableSelected ? emeraldAccent : AdminSurface.secondaryText)

                                Text(allReturnableSelected ? Language.get("LivePet_DeselectAll", alter: "إلغاء التحديد") : String(format: Language.get("LivePet_SelectAll", alter: "تحديد الكل (%d)"), returnableUnits.count))
                                    .font(PPBeirutiFont.bold(12.5, relativeTo: .caption))
                                    .foregroundStyle(allReturnableSelected ? emeraldAccent : AdminSurface.primaryText)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(allReturnableSelected ? emeraldAccent.opacity(colorScheme == .dark ? 0.20 : 0.10) : AdminSurface.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(allReturnableSelected ? emeraldAccent.opacity(0.38) : AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("a", modifiers: .command)
                    }
                }

                // Grid of Widescreen Animals
                let columns = [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ]

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredUnits) { unit in
                        LivePetUnitCardiPad(
                            unit: unit,
                            currency: viewModel.receipt.currency,
                            isSelected: viewModel.selectedUnitIds.contains(unit.unitId),
                            onToggle: {
                                viewModel.toggleUnitSelection(unit)
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Trailing Horizon (42%): Clinical & Settlement Inspector
            VStack(alignment: .leading, spacing: 14) {
                // Inspector Header
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.2.square.on.square")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.18, green: 0.52, blue: 0.96))

                    Text(Language.get("LivePet_Studio_TrailingInspector", alter: "استوديو الفحص والتسوية المالية"))
                        .font(PPBeirutiFont.bold(16, relativeTo: .headline))
                        .foregroundStyle(AdminSurface.primaryText)

                    Spacer()
                }

                if viewModel.selectedUnitIds.isEmpty {
                    // Empty Selection Guide Prompt
                    VStack(spacing: 12) {
                        Spacer(minLength: 16)

                        ZStack {
                            Circle()
                                .fill(emeraldAccent.opacity(0.10))
                                .frame(width: 56, height: 56)

                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(emeraldAccent)
                        }

                        Text(Language.get("LivePet_PickAnimalPrompt_Title", alter: "اختر الحيوان من السجل للبدء"))
                            .font(PPBeirutiFont.bold(14.5, relativeTo: .subheadline))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("LivePet_PickAnimalPrompt_Sub", alter: "حدد الحيوان المطابق لرقم الحجل لتسجيل حالته الصحية عند الاستلام واحتساب التسوية المالية."))
                            .font(PPBeirutiFont.regular(11.5, relativeTo: .caption))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        Spacer(minLength: 16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 240)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AdminSurface.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                    )
                } else {
                    // Active Inspector Deck
                    VStack(alignment: .leading, spacing: 12) {
                        // Section 1: Selected Animals Clinical Intake Accordion
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(format: Language.get("LivePet_SelectedAnimalsCarouselTitle", alter: "الحيوانات المختارة للاستلام (%d)"), viewModel.selectedUnitsList.count))
                                .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                                .foregroundStyle(AdminSurface.primaryText)

                            ForEach(viewModel.selectedUnitsList) { selectedUnit in
                                let currentCondition = viewModel.unitConditions[selectedUnit.unitId] ?? .appearsNormal
                                let currentNotes = viewModel.unitNotes[selectedUnit.unitId] ?? ""

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(selectedUnit.displayIdentification)
                                            .font(PPBeirutiFont.bold(13, relativeTo: .subheadline))
                                            .foregroundStyle(AdminSurface.primaryText)

                                        Spacer()

                                        Text(selectedUnit.productName)
                                            .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }

                                    // Condition Chips
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 5) {
                                            ForEach(ReturnPhysicalCondition.allCases) { item in
                                                let isActive = currentCondition == item
                                                Button {
                                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                    viewModel.setCondition(item, for: selectedUnit.unitId)
                                                } label: {
                                                    HStack(spacing: 3.5) {
                                                        Image(systemName: item.iconName)
                                                            .font(.system(size: 9, weight: .bold))
                                                        Text(item.localizedTitle)
                                                            .font(PPBeirutiFont.medium(10.5, relativeTo: .caption2))
                                                    }
                                                    .foregroundStyle(isActive ? .white : AdminSurface.primaryText)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 4)
                                                    .background(
                                                        isActive ? item.tintColor : AdminSurface.backgroundSecondary,
                                                        in: Capsule()
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }

                                    // Intake Protocol Guidance Pill
                                    HStack(spacing: 4) {
                                        Image(systemName: currentCondition.suggestedHealthDisposition.iconName)
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(currentCondition.suggestedHealthDisposition.tintColor)

                                        Text(String(format: Language.get("LivePet_InspectionAdvice_Prefix", alter: "توجيه الاستلام: %@"), currentCondition.suggestedHealthDisposition.localizedTitle))
                                            .font(PPBeirutiFont.medium(10, relativeTo: .caption2))
                                            .foregroundStyle(currentCondition.suggestedHealthDisposition.tintColor)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(currentCondition.suggestedHealthDisposition.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                    // Handover Notes Input
                                    TextField(
                                        Language.get("LivePet_UnitNotes_Placeholder", alter: "ملاحظات إضافية حول سلوك أو مظهر الحيوان..."),
                                        text: Binding(
                                            get: { currentNotes },
                                            set: { viewModel.setNotes($0, for: selectedUnit.unitId) }
                                        )
                                    )
                                    .font(PPBeirutiFont.regular(11, relativeTo: .caption2))
                                    .padding(7)
                                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .padding(11)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(AdminSurface.card)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.7)
                                )
                            }
                        }

                        // Section 2: Financial Telemetry Dossier Card
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(Language.get("LivePet_FinancialSettlement", alter: "التسوية المالية المستحقة"))
                                    .font(PPBeirutiFont.bold(12.5, relativeTo: .subheadline))
                                    .foregroundStyle(AdminSurface.secondaryText)

                                Spacer()

                                Text(formattedTotalRefund)
                                    .font(PPBeirutiFont.bold(17, relativeTo: .headline))
                                    .foregroundStyle(emeraldAccent)
                            }

                            Divider()
                                .background(AdminSurface.hairline)

                            // Controlled Custody Invariant Notice
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(uiColor: .systemOrange))

                                Text(Language.get("LivePet_Notice_NoAutoRestockSub", alter: "لن يتم إرجاع الحيوان لمخزون البيع تلقائياً بعد الاسترداد المالي، بل يدخل في عهدة (قيد الفحص) لحين تقييمه واعتماده يدوياً."))
                                    .font(PPBeirutiFont.regular(10.5, relativeTo: .caption2))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .background(Color(uiColor: .systemOrange).opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .padding(13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AdminSurface.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                        )
                    }
                }
            }
            .frame(width: 340)
        }
    }
}

// MARK: - iPad Animal Vault Card

private struct LivePetUnitCardiPad: View {
    let unit: LivePetReturnUnit
    let currency: String
    let isSelected: Bool
    let onToggle: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let emeraldAccent = Color(red: 0.05, green: 0.65, blue: 0.52)

    private var speciesIconName: String {
        let s = (unit.speciesName ?? unit.productName).lowercased()
        if s.contains("قط") || s.contains("cat") { return "cat.fill" }
        if s.contains("كلب") || s.contains("dog") { return "dog.fill" }
        if s.contains("طير") || s.contains("عصفور") || s.contains("bird") || s.contains("ببغاء") { return "bird.fill" }
        if s.contains("أرنب") || s.contains("rabbit") || s.contains("hare") { return "hare.fill" }
        if s.contains("سمك") || s.contains("fish") { return "fish.fill" }
        if s.contains("سلحفاة") || s.contains("turtle") { return "tortoise.fill" }
        return "pawprint.fill"
    }

    private var formattedRefundPrice: String {
        let scale = LivePetMoney.minorUnitScale(for: currency)
        let amount = unit.refundAmountMajor.formatted(.number.precision(.fractionLength(scale)))
        let symbol = currency == "QAR" ? (Language.isRTL() ? "ر.ق" : "QAR") : currency
        return "\(amount) \(symbol)"
    }

    var body: some View {
        Button(action: {
            guard !unit.isAlreadyReturned else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onToggle()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(emeraldAccent.opacity(colorScheme == .dark ? 0.24 : 0.12))
                            .frame(width: 36, height: 36)

                        Image(systemName: speciesIconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(emeraldAccent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit.displayIdentification)
                            .font(PPBeirutiFont.bold(13.5, relativeTo: .subheadline))
                            .foregroundStyle(unit.isAlreadyReturned ? AdminSurface.secondaryText : AdminSurface.primaryText)
                            .lineLimit(1)

                        Text(unit.productName)
                            .font(PPBeirutiFont.regular(11.5, relativeTo: .caption))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    if unit.isAlreadyReturned {
                        Text(Language.get("LivePet_AlreadyReturned_Badge", alter: "مسترجع سابقاً"))
                            .font(PPBeirutiFont.bold(9.5, relativeTo: .caption2))
                            .foregroundStyle(Color(uiColor: .systemRed))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(uiColor: .systemRed).opacity(0.12), in: Capsule())
                    } else {
                        ZStack {
                            Circle()
                                .strokeBorder(isSelected ? emeraldAccent : AdminSurface.hairline, lineWidth: isSelected ? 2 : 1.2)
                                .background(isSelected ? emeraldAccent : Color.clear, in: Circle())
                                .frame(width: 22, height: 22)

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(formattedRefundPrice)
                        .font(PPBeirutiFont.bold(15, relativeTo: .subheadline))
                        .foregroundStyle(unit.isAlreadyReturned ? AdminSurface.secondaryText : emeraldAccent)

                    Spacer()

                    if let breed = unit.breedName, !breed.isEmpty {
                        Text(breed)
                            .font(PPBeirutiFont.medium(11, relativeTo: .caption2))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isSelected ? AdminSurface.cardElevated : (colorScheme == .dark ? Color(white: 0.12) : Color.white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(isSelected ? emeraldAccent : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.75)
            )
            .shadow(color: isSelected ? emeraldAccent.opacity(colorScheme == .dark ? 0.20 : 0.05) : Color.black.opacity(colorScheme == .dark ? 0.14 : 0.03), radius: 5, y: 2)
            .opacity(unit.isAlreadyReturned ? 0.60 : 1.0)
        }
        .buttonStyle(LivePetReturnPressStyle())
        .hoverEffect(.lift)
        .disabled(unit.isAlreadyReturned)
    }
}

// MARK: - 6-State Visual Architecture: Shimmer Loading & Empty States

private struct LivePetSelectionSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 120, height: 14)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 85, height: 11)
                    }

                    Spacer()

                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 24, height: 24)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                )
            }
        }
    }
}

private struct LivePetSelectionEmptyView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemOrange).opacity(0.12))
                    .frame(width: 68, height: 68)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color(uiColor: .systemOrange))
            }

            Text(Language.get("LivePet_EmptyTitle", alter: "لا توجد حيوانات قابلة للاسترجاع"))
                .font(PPBeirutiFont.bold(17, relativeTo: .headline))
                .foregroundStyle(AdminSurface.primaryText)

            Text(Language.get("LivePet_EmptySub", alter: "تم استرجاع كافة الحيوانات المرتبطة بهذه الفاتورة مسبقاً، أو لم تتضمن الفاتورة سجلات حجل فردية."))
                .font(PPBeirutiFont.regular(12.5, relativeTo: .subheadline))
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }
}

// MARK: - Tactile Press Style

private struct LivePetReturnPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
