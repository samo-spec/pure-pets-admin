//
//  ReturnUnitSelectionView.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Exact animal selection card with ring tag verification, species details, and condition capture.
//

import SwiftUI

public struct ReturnUnitSelectionView: View {
    @ObservedObject var viewModel: ReturnUnitSelectionViewModel

    public init(viewModel: ReturnUnitSelectionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("LivePet_Return_SelectUnitsTitle", alter: "تحديد الحيوان الأليف بدقة"))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)

                    Text(Language.get("LivePet_Return_SelectUnitsSub", alter: "اختر الحيوان المطابق لرقم الحجل أو الشريحة"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }
                Spacer()

                Text(verbatim: "\(viewModel.selectedUnitIds.count)/\(viewModel.availableUnits.count)")
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AdminSurface.primary.opacity(0.12), in: Capsule())
            }

            if viewModel.availableUnits.isEmpty {
                emptyUnitsCard
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.availableUnits) { unit in
                        unitCard(for: unit)
                    }
                }
            }
        }
    }

    // MARK: - Unit Card

    private func unitCard(for unit: LivePetReturnUnit) -> some View {
        let isSelected = viewModel.selectedUnitIds.contains(unit.unitId)
        let isReturned = unit.isAlreadyReturned

        return VStack(alignment: .leading, spacing: 10) {
            // Unit Main Header Row
            HStack(alignment: .top, spacing: 12) {
                // Selection Checkbox Button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.toggleUnitSelection(unit)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? AdminSurface.primary : Color.gray.opacity(0.4), lineWidth: 2)
                            .background(isSelected ? AdminSurface.primary : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(width: 26, height: 26)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        } else if isReturned {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color.gray)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isReturned)
                .accessibilityLabel(unit.displayIdentification)
                .accessibilityValue(isSelected
                    ? Language.get("Selected", alter: "محدد")
                    : Language.get("NotSelected", alter: "غير محدد"))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)

                // Unit Identity & Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(unit.displayIdentification)
                            .font(AdminType.headline)
                            .foregroundColor(isReturned ? AdminSurface.secondaryText : AdminSurface.primaryText)

                        if isReturned {
                            Text(Language.get("LivePet_AlreadyReturned_Badge", alter: "مسترجع سابقاً"))
                                .font(AdminType.caption2Bold)
                                .foregroundColor(Color(uiColor: .systemRed))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(uiColor: .systemRed).opacity(0.12), in: Capsule())
                        } else {
                            Text(unit.productName)
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    // Breed, Species, Sex Snippet
                    HStack(spacing: 6) {
                        if let species = unit.speciesName, !species.isEmpty {
                            Label(species, systemImage: "pawprint.fill")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        if let breed = unit.breedName, !breed.isEmpty {
                            Text("• \(breed)")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        if let sex = unit.sex, !sex.isEmpty {
                            Text("(\(sex))")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }

                    // Price & Discount breakdown
                    let scale = LivePetMoney.minorUnitScale(for: unit.currency)
                    HStack(spacing: 8) {
                        Text(verbatim: "\(unit.refundAmountMajor.formatted(.number.precision(.fractionLength(scale)))) \(unit.currency)")
                            .font(AdminType.bodyBold)
                            .foregroundColor(isReturned ? AdminSurface.secondaryText : AdminSurface.primary)

                        if unit.allocatedDiscountMinor > 0 {
                            let discountFactor = LivePetMoney.scaleFactor(for: unit.currency)
                            let discountFormatted = (Double(unit.allocatedDiscountMinor) / discountFactor).formatted(.number.precision(.fractionLength(scale)))
                            Text(verbatim: "(\(Language.get("POS_Discount", alter: "خصم")): -\(discountFormatted) \(unit.currency))")
                                .font(AdminType.caption)
                                .foregroundColor(Color(uiColor: .systemOrange))
                        }
                    }
                }

                Spacer()
            }

            // Expanded Condition Selection for Selected Unit
            if isSelected {
                Divider().background(AdminSurface.hairline)

                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("LivePet_IntakeConditionTitle", alter: "حالة الحيوان عند الاستلام:"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ReturnPhysicalCondition.allCases) { condition in
                                let isCondSelected = (viewModel.unitConditions[unit.unitId] ?? .appearsNormal) == condition
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    viewModel.setCondition(condition, for: unit.unitId)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: condition.iconName)
                                            .font(.system(size: 11, weight: .bold))
                                        Text(condition.localizedTitle)
                                            .font(AdminType.caption)
                                    }
                                    .foregroundColor(isCondSelected ? .white : AdminSurface.primaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        isCondSelected ? condition.tintColor : AdminSurface.backgroundSecondary,
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Optional Notes Field
                    TextField(
                        Language.get("LivePet_UnitNotes_Placeholder", alter: "ملاحظات إضافية حول سلوك أو مظهر الحيوان..."),
                        text: Binding(
                            get: { viewModel.unitNotes[unit.unitId] ?? "" },
                            set: { viewModel.setNotes($0, for: unit.unitId) }
                        )
                    )
                    .font(AdminType.caption)
                    .padding(10)
                    .background(AdminSurface.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? AdminSurface.cardElevated : AdminSurface.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.8)
                )
        )
        .opacity(isReturned ? 0.65 : 1.0)
    }

    private var emptyUnitsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(uiColor: .systemOrange))
            Text(Language.get("LivePet_NoUnitsFound", alter: "لم يتم العثور على سجلات حيوانات مفردة في هذه الفاتورة."))
                .font(AdminType.caption)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
