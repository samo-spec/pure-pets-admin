//
//  PPInventoryActionMenuSheet.swift
//  PurePetsAdmin
//
//  Category-Defining Specimen Action Command Center (NextGen V6)
//  Reinvented from absolute first principles with distinct architectures:
//  - iPhone: One-handed Haptic Action Dock with specimen banner & operational runways.
//  - iPad: Desktop-class Dual-Pane Spatial Inspection Deck with telemetry dossier & keyboard shortcuts.
//

import SwiftUI
import UIKit

public struct PPInventoryActionMenuSheet: View {
    let item: PetAccessory
    let onEdit: () -> Void
    let onRecordDamage: () -> Void
    let onQuarantineStudio: () -> Void
    let onManageLots: () -> Void
    let onShare: () -> Void
    let onToggleStock: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        item: PetAccessory,
        onEdit: @escaping () -> Void,
        onRecordDamage: @escaping () -> Void,
        onQuarantineStudio: @escaping () -> Void,
        onManageLots: @escaping () -> Void,
        onShare: @escaping () -> Void,
        onToggleStock: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.onEdit = onEdit
        self.onRecordDamage = onRecordDamage
        self.onQuarantineStudio = onQuarantineStudio
        self.onManageLots = onManageLots
        self.onShare = onShare
        self.onToggleStock = onToggleStock
        self.onDelete = onDelete
    }

    private var imageURL: URL? {
        PetAccessory.firstImageURL(for: item)
    }

    private var displayQuantity: Int {
        let activeBranch = BranchContextStore.shared.activeBranch?.branchID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let activeBranch, !activeBranch.isEmpty {
            if let branchRecord = PPBranchInventoryService.shared.inventory(for: item.accessoryID) {
                return branchRecord.availableQuantity
            }
            let itemBranch = (item.storeID ?? item.branchID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !itemBranch.isEmpty && itemBranch != "main_store" && itemBranch != activeBranch {
                return 0
            }
        }
        return PPBranchInventoryService.shared.availableStock(for: item.accessoryID, fallback: item.quantity)
    }

    private var itemDisplayName: String {
        if !Language.isRTL(), let nameEn = item.nameEn?.trimmingCharacters(in: .whitespacesAndNewlines), !nameEn.isEmpty {
            return nameEn
        }
        return item.name
    }

    private var stockTone: Color {
        let qty = displayQuantity
        if qty <= 0 || (item.noStock && !item.isLivePet) {
            return Color(uiColor: .ppError)
        } else if qty <= 3 {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppSuccess)
        }
    }

    private var stockStatusText: String {
        let qty = displayQuantity
        if (item.noStock && !item.isLivePet) || qty <= 0 {
            return Language.get("OutOfStock", alter: "نفذ من المخزون")
        } else if qty <= 3 {
            return String(format: Language.get("LowStock_Qty_Format", alter: "وشك النفاذ (%@)"), qty.englishDigits).normalizedEnglishDigits
        } else {
            return String(format: Language.get("InStock_Qty_Format", alter: "متوفر (%@)"), qty.englishDigits).normalizedEnglishDigits
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let isIPad = horizontalSizeClass == .regular || proxy.size.width >= 760

            ZStack {
                AdminSurface.background.ignoresSafeArea()

                if isIPad {
                    iPadSpatialInspectionDeck
                        .frame(maxWidth: 780, maxHeight: 620)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(AdminSurface.surface)
                                .shadow(color: Color.black.opacity(0.10), radius: 30, x: 0, y: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                        )
                        .padding(24)
                } else {
                    iPhoneHapticActionDock
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - 📱 iPhone Haptic Action Dock (One-Handed Operational Cockpit)

    private var iPhoneHapticActionDock: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Drag Pill Handle
                Capsule()
                    .fill(AdminSurface.hairline)
                    .frame(width: 38, height: 4.5)
                    .padding(.top, 10)

                // Specimen Identity Header Card
                specimenIdentityCard(compact: true)

                // The 3 Flagship Inventory Studios
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AdminSurface.primary)
                        Text(Language.get("Inventory_Studios_Section", alter: "استوديوهات الجرد والرقابة النوعية"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 4)

                    // 1. Damage Studio
                    studioFlightDeckCard(
                        title: Language.get("Record_Damage", alter: "تسجيل إتلاف مخزون"),
                        subtitle: Language.get("Damage_Studio_Desc", alter: "تسجيل تالف، هالك، أو عيب مصنعي وخصمه فورياً"),
                        badge: Language.get("Damage_Badge", alter: "إتلاف وركود"),
                        symbol: "exclamationmark.octagon.fill",
                        tintColor: Color(red: 225/255, green: 29/255, blue: 72/255)
                    ) {
                        dismiss()
                        onRecordDamage()
                    }

                    // 2. Quarantine Studio
                    studioFlightDeckCard(
                        title: Language.get("Quarantine_Studio", alter: "استوديو الفحص والتصرف (الحجر)"),
                        subtitle: Language.get("Quarantine_Studio_Desc", alter: "عزل كميات للفحص الطبي أو البيطري أو إعادة الفرز"),
                        badge: Language.get("Quarantine_Badge", alter: "عزل وجودة"),
                        symbol: "shield.lefthalf.filled",
                        tintColor: Color(red: 234/255, green: 88/255, blue: 12/255)
                    ) {
                        dismiss()
                        onQuarantineStudio()
                    }

                    // 3. Lots & FEFO Studio
                    studioFlightDeckCard(
                        title: Language.get("Manage_Lots_FEFO", alter: "إدارة التشغيلات والصلاحية (FEFO)"),
                        subtitle: Language.get("Lots_Studio_Desc", alter: "تتبع الباتشات والتواريخ وقاعدة الصرف الأقرب انتهاءً"),
                        badge: Language.get("Lots_Badge", alter: "تشغيلات FEFO"),
                        symbol: "calendar.badge.clock",
                        tintColor: Color(red: 16/255, green: 185/255, blue: 129/255)
                    ) {
                        dismiss()
                        onManageLots()
                    }
                }

                // Quick Operational Actions Grid
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        // Edit Item Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                            onEdit()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 15, weight: .bold))
                                Text(Language.get("Edit_Specimen", alter: "تعديل الصنف"))
                                    .font(PPBrandFont.bold(size: 15))
                            }
                            .foregroundColor(AdminSurface.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(SpecimenActionPressStyle())

                        // Share Item Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                            onShare()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                Text(Language.get("Share_Specimen", alter: "مشاركة"))
                                    .font(PPBrandFont.bold(size: 15))
                            }
                            .foregroundColor(AdminCommandInk.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(SpecimenActionPressStyle())
                    }

                    // Stock Availability Toggle Row
                    if !item.isLivePet {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onToggleStock()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.noStock ? "xmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.noStock ? Language.get("MarkInStock", alter: "تفعيل التوفر بالمخزون") : Language.get("MarkOutOfStock", alter: "تعيين كنفاذ المخزون"))
                                        .font(PPBrandFont.bold(size: 14))
                                        .foregroundColor(AdminSurface.primaryText)
                                        .multilineTextAlignment(.leading)
                                    Text(item.noStock ? Language.get("Stock_Currently_Out", alter: "الصنف غير متاح للبيع حالياً") : Language.get("Stock_Currently_Active", alter: "الصنف متاح في عمليات البيع والكاشير"))
                                        .font(AdminType.caption2)
                                        .foregroundColor(AdminSurface.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Text(item.noStock ? Language.get("Disabled_Status", alter: "معطل") : Language.get("Active_Status", alter: "نشط"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundColor(item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        (item.noStock ? Color(uiColor: .ppError) : Color(uiColor: .ppSuccess)).opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(SpecimenActionPressStyle())
                    }
                }

                // Guarded Destructive Zone
                Divider()
                    .background(AdminSurface.hairline)
                    .padding(.top, 4)

                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    dismiss()
                    onDelete()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(Language.get("Delete_Specimen_Guarded", alter: "حذف الصنف نهائياً من المخزون"))
                            .font(PPBrandFont.bold(size: 14))
                    }
                    .foregroundColor(Color(uiColor: .ppError))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(SpecimenActionPressStyle())
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - 🖥️ iPad Spatial Inspection Deck (Desktop-Class Dual-Pane Stage)

    private var iPadSpatialInspectionDeck: some View {
        VStack(spacing: 0) {
            // Stage Nav Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Specimen_Action_Center", alter: "مركز عمليات الصنف المخزني"))
                        .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Specimen_Action_Center_Sub", alter: "نظام التحكم الرقابي الشامل والتشغيلات المباشرة"))
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.control, in: Circle())
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().background(AdminSurface.hairline)

            // Dual Pane Body
            HStack(alignment: .top, spacing: 20) {
                // Leading Column: Specimen Dossier & Telemetry (Width: 280)
                VStack(alignment: .leading, spacing: 14) {
                    specimenIdentityCard(compact: false)

                    // Financial Valuation Card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("Financial_Specs", alter: "البيانات المالية"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        HStack {
                            Text(Language.get("Retail_Price", alter: "سعر البيع:"))
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(verbatim: item.inventoryDisplayPrice.normalizedEnglishDigits)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primary)
                                .monospacedDigit()
                        }

                        if let wp = item.wholesalePrice?.doubleValue, wp > 0 {
                            HStack {
                                Text(Language.get("Wholesale_Price", alter: "سعر الجملة:"))
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)
                                Spacer()
                                Text(verbatim: "\(wp.englishDigits(decimals: 2)) \(Language.get("QAR", alter: "ر.ق"))")
                                    .font(AdminType.captionBold)
                                    .foregroundColor(Color(uiColor: .systemTeal))
                                    .monospacedDigit()
                            }
                        }

                        if let cost = item.costPrice?.doubleValue, cost > 0 {
                            HStack {
                                Text(Language.get("Cost_Price", alter: "سعر التكلفة:"))
                                    .font(AdminType.caption)
                                    .foregroundColor(AdminSurface.secondaryText)
                                Spacer()
                                Text(verbatim: "\(cost.englishDigits(decimals: 2)) \(Language.get("QAR", alter: "ر.ق"))")
                                    .font(AdminType.captionBold)
                                    .foregroundColor(AdminCommandInk.tertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(14)
                    .background(AdminSurface.control.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Spacer(minLength: 0)
                }
                .frame(width: 290)

                Divider().background(AdminSurface.hairline)

                // Trailing Column: Studios & Operations Flight Deck
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Language.get("Operational_Studios", alter: "استوديوهات الجرد المتخصصة"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        // 1. Damage Studio
                        studioFlightDeckCard(
                            title: Language.get("Record_Damage", alter: "تسجيل إتلاف مخزون"),
                            subtitle: Language.get("Damage_Studio_Desc", alter: "تسجيل تالف أو هالك أو عيب مصنعي مع حسم فوري من الرصيد"),
                            badge: Language.get("Damage_Badge", alter: "إتلاف وركود"),
                            symbol: "exclamationmark.octagon.fill",
                            tintColor: Color(red: 225/255, green: 29/255, blue: 72/255)
                        ) {
                            dismiss()
                            onRecordDamage()
                        }

                        // 2. Quarantine Studio
                        studioFlightDeckCard(
                            title: Language.get("Quarantine_Studio", alter: "استوديو الفحص والتصرف (الحجر)"),
                            subtitle: Language.get("Quarantine_Studio_Desc", alter: "حجز كميات للفحص الطبي أو البيطري أو فك الحجر للتداول"),
                            badge: Language.get("Quarantine_Badge", alter: "عزل وجودة"),
                            symbol: "shield.lefthalf.filled",
                            tintColor: Color(red: 234/255, green: 88/255, blue: 12/255)
                        ) {
                            dismiss()
                            onQuarantineStudio()
                        }

                        // 3. Lots & FEFO Studio
                        studioFlightDeckCard(
                            title: Language.get("Manage_Lots_FEFO", alter: "إدارة التشغيلات والصلاحية (FEFO)"),
                            subtitle: Language.get("Lots_Studio_Desc", alter: "متابعة الباتشات وتواريخ الصلاحية وقاعدة الصرف الأقرب انتهاءً"),
                            badge: Language.get("Lots_Badge", alter: "تشغيلات FEFO"),
                            symbol: "calendar.badge.clock",
                            tintColor: Color(red: 16/255, green: 185/255, blue: 129/255)
                        ) {
                            dismiss()
                            onManageLots()
                        }

                        // Quick Actions Strip
                        HStack(spacing: 10) {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                dismiss()
                                onEdit()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 14, weight: .bold))
                                    Text(Language.get("Edit_Specimen", alter: "تعديل الصنف"))
                                        .font(PPBrandFont.bold(size: 14))
                                }
                                .foregroundColor(AdminSurface.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(SpecimenActionPressStyle())
                            .keyboardShortcut("e", modifiers: .command)

                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                dismiss()
                                onShare()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .bold))
                                    Text(Language.get("Share_Specimen", alter: "مشاركة"))
                                        .font(PPBrandFont.bold(size: 14))
                                }
                                .foregroundColor(AdminCommandInk.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(SpecimenActionPressStyle())
                            .keyboardShortcut("s", modifiers: .command)

                            if !item.isLivePet {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    onToggleStock()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: item.noStock ? "checkmark.circle" : "xmark.circle")
                                            .font(.system(size: 14, weight: .bold))
                                        Text(item.noStock ? Language.get("MarkInStock", alter: "تفعيل التوفر") : Language.get("MarkOutOfStock", alter: "نفاذ المخزون"))
                                            .font(PPBrandFont.bold(size: 14))
                                    }
                                    .foregroundColor(item.noStock ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(
                                        (item.noStock ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppError)).opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                }
                                .buttonStyle(SpecimenActionPressStyle())
                            }
                        }
                        .padding(.top, 4)

                        // Destructive Danger Strip
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            dismiss()
                            onDelete()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text(Language.get("Delete_Specimen_Guarded", alter: "حذف الصنف نهائياً من المخزون"))
                                    .font(PPBrandFont.bold(size: 13))
                            }
                            .foregroundColor(Color(uiColor: .ppError))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(uiColor: .ppError).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(SpecimenActionPressStyle())
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Reusable Studio Flight Deck Card

    private func studioFlightDeckCard(
        title: String,
        subtitle: String,
        badge: String,
        symbol: String,
        tintColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                // Aura Icon Vault
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tintColor.opacity(0.13))
                        .frame(width: 44, height: 44)

                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(tintColor)
                }

                // Title & Subtitle Stack
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundColor(AdminSurface.primaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)

                        Spacer()

                        Text(badge)
                            .font(AdminType.caption2Bold)
                            .foregroundColor(tintColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tintColor.opacity(0.12), in: Capsule())
                    }

                    Text(subtitle)
                        .font(AdminType.caption)
                        .foregroundColor(AdminSurface.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AdminCommandInk.tertiary)
            }
            .padding(14)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tintColor.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: tintColor.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(SpecimenActionPressStyle())
    }

    // MARK: - Reusable Specimen Identity Card

    private func specimenIdentityCard(compact: Bool) -> some View {
        let aura = CategorySpecimenAuraTheme.resolve(for: item)
        let branchName = item.resolvedBranchName()

        return HStack(spacing: 12) {
            // Specimen Image Box
            ZStack {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .scaledToFill()
                        default:
                            auraGlyphView(aura: aura)
                        }
                    }
                } else {
                    auraGlyphView(aura: aura)
                }
            }
            .frame(width: compact ? 66 : 80, height: compact ? 66 : 80)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AdminSurface.hairline, lineWidth: 1)
            )

            // Specimen Nomenclature & Telemetry
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(aura.categoryName)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(aura.accentTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(aura.accentTint.opacity(0.12), in: Capsule())

                    if !branchName.isEmpty {
                        Text(branchName)
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(stockStatusText)
                        .font(AdminType.caption2Bold)
                        .foregroundColor(stockTone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(stockTone.opacity(0.12), in: Capsule())
                }

                Text(itemDisplayName)
                    .font(Font.custom("Beiruti-Bold", size: compact ? 16 : 18, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(compact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text(verbatim: "SKU: \(sku)")
                            .font(AdminType.caption2.monospaced())
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    if let size = item.size, !size.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "ruler.fill")
                                .font(.system(size: 8))
                            Text(size)
                                .font(AdminType.caption2Bold)
                        }
                        .foregroundColor(AdminSurface.primary)
                    }

                    Spacer()

                    Text(verbatim: item.inventoryDisplayPrice.normalizedEnglishDigits)
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primary)
                        .monospacedDigit()
                }
            }
        }
        .padding(12)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func auraGlyphView(aura: CategorySpecimenAuraTheme) -> some View {
        ZStack {
            LinearGradient(
                colors: aura.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: aura.glyphName)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// MARK: - Tactile Spring Press Style

private struct SpecimenActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
