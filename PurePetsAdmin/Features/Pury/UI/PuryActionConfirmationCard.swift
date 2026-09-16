//
//  PuryActionConfirmationCard.swift
//  PurePetsAdmin
//
//  Authoritative confirmation UI card for Tier-3 sensitive Pury operations.
//  Presents operator-useful information: affected record, what will change,
//  before/proposed diff, required permission, and explicit Confirm/Cancel choices.
//

import SwiftUI

@available(iOS 16.0, *)
public struct PuryActionConfirmationCard: View {
    public let action: PuryConfirmationAction
    public let onConfirm: () -> Void
    public let onCancel: () -> Void

    public init(
        action: PuryConfirmationAction,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.action = action
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Pury_Confirm_Title", alter: "مطلوب تأكيد العملية"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Pury_Confirm_Subtitle", alter: "تعديل محمي يتطلب موافقتك الصريحة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                if let perm = action.permissionRequired {
                    Text(perm)
                        .font(PPBrandFont.bold(size: 10, relativeTo: .caption2))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 6))
                        .environment(\.layoutDirection, .leftToRight)
                }
            }

            // Target Entity ID
            if let entityId = action.entityId, !entityId.isEmpty {
                HStack(spacing: 6) {
                    Text(Language.get("Target_Record", alter: "السجل المستهدف:"))
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(entityId)
                        .font(PPBrandFont.medium(size: 11, relativeTo: .caption))
                        .foregroundStyle(AdminSurface.primaryText)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 8))
            }

            // Warnings list
            if let warnings = action.warnings, !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { warning in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                            Text(warning)
                                .font(AdminType.caption1)
                                .foregroundStyle(Color(red: 239/255, green: 68/255, blue: 68/255))
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            // Before / After State Diff
            if let updates = action.updates, !updates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Language.get("Pury_Proposed_Changes", alter: "التعديلات المقترحة:"))
                        .font(AdminType.caption2Bold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    VStack(spacing: 4) {
                        ForEach(Array(updates.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(PPBrandFont.medium(size: 11, relativeTo: .caption2))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .environment(\.layoutDirection, .leftToRight)

                                Spacer()

                                if let beforeVal = action.beforeState?[key] {
                                    Text(beforeVal)
                                        .font(AdminType.caption2)
                                        .foregroundStyle(AdminSurface.secondaryText)
                                        .strikethrough()

                                    Image(systemName: "arrow.left")
                                        .font(.system(size: 9))
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }

                                Text(updates[key] ?? "")
                                    .font(AdminType.caption1Bold)
                                    .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                            .background(AdminSurface.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(10)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10))
            }

            // Buttons
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onConfirm()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text(Language.get("Pury_Confirm_Btn", alter: "تأكيد وتنفيذ"))
                            .font(AdminType.subheadlineBold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color(red: 16/255, green: 185/255, blue: 129/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    onCancel()
                } label: {
                    Text(Language.get("Cancel", alter: "إلغاء"))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: 90)
                        .padding(.vertical, 12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.4), lineWidth: 1)
        )
    }
}
