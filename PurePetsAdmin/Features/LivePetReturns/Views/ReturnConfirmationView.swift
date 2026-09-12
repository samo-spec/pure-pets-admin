//
//  ReturnConfirmationView.swift
//  PurePetsAdmin
//
//  World-Class Live Pet Return & Refund Architecture
//  Authoritative return confirmation card with case number, decoupled states, and dossier link.
//

import SwiftUI

public struct ReturnConfirmationView: View {
    public let returnCase: LivePetReturnCase
    public let onOpenDossier: () -> Void
    public let onDismiss: () -> Void
    public let onProceedToMerchandiseRefund: (() -> Void)?

    @State private var hasCopiedCaseNumber: Bool = false

    public init(
        returnCase: LivePetReturnCase,
        onOpenDossier: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onProceedToMerchandiseRefund: (() -> Void)? = nil
    ) {
        self.returnCase = returnCase
        self.onOpenDossier = onOpenDossier
        self.onDismiss = onDismiss
        self.onProceedToMerchandiseRefund = onProceedToMerchandiseRefund
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Success Icon Animation / Graphic
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .systemGreen).opacity(0.12))
                            .frame(width: 80, height: 80)

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 42))
                            .foregroundColor(Color(uiColor: .systemGreen))
                    }
                    .padding(.top, 16)

                    // Title & Subtitle
                    VStack(spacing: 6) {
                        Text(Language.get("LivePet_Confirm_SuccessTitle", alter: "تم تسجيل استرجاع الحيوان بنجاح"))
                            .font(AdminType.title3Bold)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("LivePet_Confirm_SuccessSub", alter: "تم فتح ملف الاسترجاع ونقل الحيوان للعهدة المخصصة"))
                            .font(AdminType.caption)
                            .foregroundColor(AdminSurface.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Case Number Card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("LivePet_CaseNumberLabel", alter: "رقم ملف الاسترجاع"))
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)

                            Text(returnCase.caseNumber)
                                .font(AdminType.headline)
                                .foregroundColor(AdminSurface.primaryText)
                                .monospacedDigit()
                        }

                        Spacer()

                        Button {
                            UIPasteboard.general.string = returnCase.caseNumber
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            hasCopiedCaseNumber = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                hasCopiedCaseNumber = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hasCopiedCaseNumber ? "checkmark" : "doc.on.doc")
                                Text(hasCopiedCaseNumber ? Language.get("Copied", alter: "تم النسخ") : Language.get("Copy", alter: "نسخ"))
                            }
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Independent States Grid
                    HStack(spacing: 12) {
                        // Case Workflow Status Card
                        VStack(alignment: .leading, spacing: 6) {
                            Label(Language.get("LivePet_WorkflowStateLabel", alter: "حالة الملف"), systemImage: "doc.text.fill")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)

                            Text(returnCase.status.localizedTitle)
                                .font(AdminType.headline)
                                .foregroundColor(returnCase.status.badgeColor)

                            Text(Language.get("LivePet_UnderInspection_Notice", alter: "العهدة: مكتب استلام الفرع"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        // Financial Refund State Card
                        VStack(alignment: .leading, spacing: 6) {
                            Label(Language.get("LivePet_RefundStateLabel", alter: "حالة الاسترداد"), systemImage: "creditcard.fill")
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)

                            Text(returnCase.refundStatus.localizedTitle)
                                .font(AdminType.headline)
                                .foregroundColor(returnCase.refundStatus.badgeColor)

                            let scale = LivePetMoney.minorUnitScale(for: returnCase.currency)
                            Text(verbatim: "\(returnCase.totalRefundAmountMajor.formatted(.number.precision(.fractionLength(scale)))) \(returnCase.currency)")
                                .font(AdminType.caption2Bold)
                                .foregroundColor(AdminSurface.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Units Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("LivePet_ReturnedUnitsHeader", alter: "الحيوانات المسترجعة:"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        ForEach(returnCase.units) { unit in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(AdminSurface.primary)

                                Text(unit.displayIdentification)
                                    .font(AdminType.body)
                                    .foregroundColor(AdminSurface.primaryText)

                                Spacer()

                                Text(unit.conditionAtReturn.localizedTitle)
                                    .font(AdminType.caption)
                                    .foregroundColor(unit.conditionAtReturn.tintColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(unit.conditionAtReturn.tintColor.opacity(0.12), in: Capsule())
                            }
                            .padding(10)
                            .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, AdminSpacing.screenMargin)
                .padding(.bottom, 16)
            }

            // Fixed Action Buttons Footer
            VStack(spacing: 10) {
                if let onProceed = onProceedToMerchandiseRefund {
                    Button(action: onProceed) {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.and.arrow.backward.fill")
                            Text(Language.get("LivePet_ProceedToMerchandiseRefund", alter: "استكمال استرداد المنتجات والأكسسوارات"))
                                .font(AdminType.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(uiColor: .systemOrange), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onOpenDossier) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                        Text(Language.get("LivePet_OpenDossierButton", alter: "فتح ملف الاسترجاع والمتابعة"))
                            .font(onProceedToMerchandiseRefund != nil ? AdminType.subheadlineBold : AdminType.headline)
                    }
                    .foregroundColor(onProceedToMerchandiseRefund != nil ? AdminSurface.primary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: onProceedToMerchandiseRefund != nil ? 44 : 50)
                    .background(
                        onProceedToMerchandiseRefund != nil ? AdminSurface.primary.opacity(0.1) : AdminSurface.primary,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text(Language.get("Done", alter: "تم الإغلاق"))
                        .font(AdminType.subheadlineBold)
                        .foregroundColor(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(AdminSurface.card.ignoresSafeArea(edges: .bottom))
        }
        .background(AdminSurface.background.ignoresSafeArea())
    }
}
