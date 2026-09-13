//
//  ReturnConfirmationView.swift
//  PurePetsAdmin
//
//  Native post-return confirmation experience.
//  iPhone prioritizes one-handed completion; iPad uses a two-column operations workspace.
//

import SwiftUI
import UIKit

public enum ReturnConfirmationSurfaceState {
    case loading
    case empty
    case failure(message: String)
    case ready(LivePetReturnCase)
}

public struct ReturnConfirmationView: View {
    private let surfaceState: ReturnConfirmationSurfaceState
    public let onOpenDossier: () -> Void
    public let onDismiss: () -> Void
    public let onProceedToMerchandiseRefund: (() -> Void)?
    public let onRetry: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var hasCopiedCaseNumber = false
    @State private var successAppeared = false
    @State private var actionFeedbackToken = 0

    public init(
        returnCase: LivePetReturnCase,
        onOpenDossier: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onProceedToMerchandiseRefund: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.surfaceState = .ready(returnCase)
        self.onOpenDossier = onOpenDossier
        self.onDismiss = onDismiss
        self.onProceedToMerchandiseRefund = onProceedToMerchandiseRefund
        self.onRetry = onRetry
    }

    public init(
        state: ReturnConfirmationSurfaceState,
        onOpenDossier: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void,
        onProceedToMerchandiseRefund: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.surfaceState = state
        self.onOpenDossier = onOpenDossier
        self.onDismiss = onDismiss
        self.onProceedToMerchandiseRefund = onProceedToMerchandiseRefund
        self.onRetry = onRetry
    }

    public var body: some View {
        Group {
            switch surfaceState {
            case .loading:
                loadingState
            case .empty:
                emptyState
            case .failure(let message):
                failureState(message: message)
            case .ready(let returnCase):
                readyState(returnCase)
            }
        }
        .frame(maxWidth: .infinity)
        .background(AdminSurface.background)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sensoryFeedback(.success, trigger: hasCopiedCaseNumber) { oldValue, newValue in
            !oldValue && newValue
        }
        .sensoryFeedback(.selection, trigger: actionFeedbackToken)
    }

    // MARK: - Ready Architecture

    @ViewBuilder
    private func readyState(_ returnCase: LivePetReturnCase) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadReadyState(returnCase)
        } else {
            iPhoneReadyState(returnCase)
        }
    }

    private func iPhoneReadyState(_ returnCase: LivePetReturnCase) -> some View {
        VStack(spacing: 20) {
            closeRail

            hero(returnCase, compact: true)

            outcomeLane(returnCase)

            caseIdentity(returnCase)

            unitsSection(returnCase, compact: true)

            nextStepNote(returnCase)

            phoneActions(returnCase)
        }
        .frame(maxWidth: 620)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .onAppear(perform: revealSuccess)
    }

    private func iPadReadyState(_ returnCase: LivePetReturnCase) -> some View {
        VStack(spacing: 22) {
            iPadCommandRail(returnCase)

            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 22) {
                    hero(returnCase, compact: false)
                    outcomeLane(returnCase)
                    unitsSection(returnCase, compact: false)
                }
                .frame(maxWidth: 650, alignment: .top)

                iPadInspector(returnCase)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 430 : 390)
            }
            .frame(maxWidth: 1100, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear(perform: revealSuccess)
    }

    // MARK: - Global Rails

    private var closeRail: some View {
        Button {
            actionFeedbackToken += 1
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(AdminSurface.primaryText)
                .frame(width: 44, height: 44)
                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(ReturnConfirmationPressStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(text("LivePet_Confirm_Close", ar: "إغلاق", en: "Close"))
    }

    private func iPadCommandRail(_ returnCase: LivePetReturnCase) -> some View {
        HStack(spacing: 16) {
            caseIdentityInline(returnCase)

            Spacer(minLength: 20)

            Label(
                text("LivePet_Confirm_ProtectedRecord", ar: "سجل استرجاع موثّق", en: "Verified return record"),
                systemImage: "checkmark.shield.fill"
            )
            .font(AdminType.captionBold)
            .foregroundStyle(AdminSurface.emerald)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(AdminSurface.emerald.opacity(0.09), in: Capsule())
            .accessibilityElement(children: .combine)

            Button {
                actionFeedbackToken += 1
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(ReturnConfirmationPressStyle())
            .hoverEffect(.highlight)
            .keyboardShortcut("w", modifiers: [.command])
            .accessibilityLabel(text("LivePet_Confirm_Close", ar: "إغلاق", en: "Close"))
        }
        .frame(maxWidth: 1100)
    }

    // MARK: - Hero

    private func hero(_ returnCase: LivePetReturnCase, compact: Bool) -> some View {
        VStack(spacing: compact ? 14 : 18) {
            ZStack {
                Circle()
                    .fill(AdminSurface.emerald.opacity(0.10))
                    .frame(width: compact ? 88 : 104, height: compact ? 88 : 104)

                Circle()
                    .stroke(AdminSurface.emerald.opacity(0.18), lineWidth: 1)
                    .frame(width: compact ? 70 : 84, height: compact ? 70 : 84)

                Image(systemName: "checkmark")
                    .font(.system(size: compact ? 31 : 37, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 54 : 64, height: compact ? 54 : 64)
                    .background(AdminSurface.emerald, in: Circle())
            }
            .scaleEffect(successAppeared ? 1 : 0.84)
            .opacity(successAppeared ? 1 : 0)
            .accessibilityHidden(true)

            VStack(spacing: 7) {
                Text(text(
                    "LivePet_Confirm_SuccessTitle",
                    ar: "تم تسجيل استرجاع الحيوان بنجاح",
                    en: "Animal return recorded successfully"
                ))
                .font(compact ? AdminType.title2 : AdminType.title)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Text(text(
                    "LivePet_Confirm_SuccessSub",
                    ar: "اكتمل الاسترداد المالي وبدأت متابعة الحيوان ضمن مسار الفحص الآمن.",
                    en: "The financial refund is complete and the animal is now in the protected inspection workflow."
                ))
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: compact ? 470 : 560)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            text(
                "LivePet_Confirm_A11ySummary",
                ar: "تم تسجيل الاسترجاع بنجاح. الاسترداد المالي مكتمل، وملف الحيوان مستمر للفحص والمتابعة.",
                en: "Return recorded successfully. The financial refund is complete and the animal case remains active for inspection and follow-up."
            )
        )
    }

    // MARK: - Outcome Lane

    @ViewBuilder
    private func outcomeLane(_ returnCase: LivePetReturnCase) -> some View {
        let financial = outcomeItem(
            icon: "checkmark.circle.fill",
            eyebrow: text("LivePet_RefundStateLabel", ar: "الاسترداد المالي", en: "Financial refund"),
            value: returnCase.refundStatus.localizedTitle,
            supporting: localizedMoney(returnCase),
            tint: returnCase.refundStatus.badgeColor,
            isComplete: true
        )
        let workflow = outcomeItem(
            icon: "cross.case.fill",
            eyebrow: text("LivePet_WorkflowStateLabel", ar: "متابعة الحيوان", en: "Animal follow-up"),
            value: returnCase.status.localizedTitle,
            supporting: text(
                "LivePet_Confirm_WorkflowSupport",
                ar: "يبقى الحيوان خارج البيع حتى إغلاق الفحص",
                en: "The animal remains unavailable for sale until inspection closes"
            ),
            tint: returnCase.status.badgeColor,
            isComplete: returnCase.status.isFinal
        )

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                financial
                workflow
            }
        } else {
            HStack(spacing: 10) {
                financial
                workflow
            }
        }
    }

    private func outcomeItem(
        icon: String,
        eyebrow: String,
        value: String,
        supporting: String,
        tint: Color,
        isComplete: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(eyebrow)
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Image(systemName: isComplete ? "checkmark" : "clock")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }

                Text(value)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(supporting)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Case Identity

    private func caseIdentity(_ returnCase: LivePetReturnCase) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 40, height: 40)
                .background(AdminSurface.primary.opacity(0.09), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(text("LivePet_CaseNumberLabel", ar: "رقم ملف الاسترجاع", en: "Return case number"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)

                Text(verbatim: returnCase.caseNumber)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            copyCaseButton(returnCase)
        }
        .padding(14)
        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
    }

    private func caseIdentityInline(_ returnCase: LivePetReturnCase) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(text("LivePet_CaseNumberLabel", ar: "ملف الاسترجاع", en: "Return case"))
                    .font(AdminType.caption2Medium)
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(verbatim: returnCase.caseNumber)
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .textSelection(.enabled)
            }

            copyCaseButton(returnCase)
        }
        .accessibilityElement(children: .contain)
    }

    private func copyCaseButton(_ returnCase: LivePetReturnCase) -> some View {
        Button {
            UIPasteboard.general.string = returnCase.caseNumber
            hasCopiedCaseNumber = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                hasCopiedCaseNumber = false
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: hasCopiedCaseNumber ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)

                Text(hasCopiedCaseNumber
                     ? text("LivePet_Confirm_Copied", ar: "تم النسخ", en: "Copied")
                     : text("LivePet_Confirm_Copy", ar: "نسخ", en: "Copy"))
                    .font(AdminType.captionBold)
            }
            .foregroundStyle(hasCopiedCaseNumber ? AdminSurface.emerald : AdminSurface.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 38)
            .background(
                (hasCopiedCaseNumber ? AdminSurface.emerald : AdminSurface.primary).opacity(0.09),
                in: Capsule()
            )
        }
        .buttonStyle(ReturnConfirmationPressStyle())
        .accessibilityLabel(
            hasCopiedCaseNumber
            ? text("LivePet_Confirm_Copied", ar: "تم نسخ رقم الملف", en: "Case number copied")
            : text("LivePet_Confirm_CopyCaseA11y", ar: "نسخ رقم ملف الاسترجاع", en: "Copy return case number")
        )
        .accessibilityHint(
            text("LivePet_Confirm_CopyCaseHint", ar: "ينسخ رقم الملف إلى الحافظة", en: "Copies the case number to the clipboard")
        )
    }

    // MARK: - Units

    private func unitsSection(_ returnCase: LivePetReturnCase, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(text("LivePet_ReturnedUnitsHeader", ar: "الحيوانات المسترجعة", en: "Returned animals"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(verbatim: "\(returnCase.units.count)")
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.primary.opacity(0.09), in: Capsule())

                Spacer(minLength: 0)
            }

            if returnCase.units.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "pawprint")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .accessibilityHidden(true)

                    Text(text(
                        "LivePet_Confirm_NoUnits",
                        ar: "لا توجد بيانات حيوانات مرتبطة بهذا الملف حالياً.",
                        en: "No animal records are currently attached to this case."
                    ))
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(returnCase.units.enumerated()), id: \.element.id) { index, unit in
                        unitRow(unit)

                        if index < returnCase.units.count - 1 {
                            Divider()
                                .overlay(AdminSurface.hairline)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                )
            }
        }
    }

    private func unitRow(_ unit: LivePetReturnUnit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 38, height: 38)
                .background(AdminSurface.primary.opacity(0.08), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(unit.displayIdentification)
                    .font(AdminType.bodyBold)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(text(
                    "LivePet_Confirm_ProtectedCustody",
                    ar: "مسجل ضمن عهدة الاسترجاع",
                    en: "Recorded in return custody"
                ))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)

                Text(unit.conditionAtReturn.localizedTitle)
                    .font(AdminType.captionBold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(unit.conditionAtReturn.tintColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(unit.conditionAtReturn.tintColor.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(unit.displayIdentification), \(unit.conditionAtReturn.localizedTitle)")
    }

    // MARK: - Safety / Next Step

    private func nextStepNote(_ returnCase: LivePetReturnCase) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: returnCase.status.isFinal ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(returnCase.status.isFinal ? AdminSurface.emerald : returnCase.status.badgeColor)
                .frame(width: 36, height: 36)
                .background(
                    (returnCase.status.isFinal ? AdminSurface.emerald : returnCase.status.badgeColor).opacity(0.09),
                    in: Circle()
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(text(
                    "LivePet_Confirm_NextStepTitle",
                    ar: "ما الذي يحدث الآن؟",
                    en: "What happens next?"
                ))
                .font(AdminType.subheadlineBold)
                .foregroundStyle(AdminSurface.primaryText)

                Text(returnCase.status.isFinal
                     ? text(
                        "LivePet_Confirm_FinalCaseNote",
                        ar: "أُغلق مسار المتابعة لهذا الملف. يمكنك فتح الملف لمراجعة السجل الكامل.",
                        en: "This case workflow is closed. Open the case to review the complete record."
                     )
                     : text(
                        "LivePet_Confirm_InspectionNote",
                        ar: "يبقى الحيوان غير متاح للبيع حتى اكتمال الفحص واتخاذ قرار الحالة النهائية.",
                        en: "The animal remains unavailable for sale until inspection is complete and a final disposition is recorded."
                     ))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - iPhone Actions

    private func phoneActions(_ returnCase: LivePetReturnCase) -> some View {
        VStack(spacing: 10) {
            if let onProceedToMerchandiseRefund {
                actionButton(
                    title: text(
                        "LivePet_Confirm_RefundRemainingItems",
                        ar: "استرداد بقية المنتجات",
                        en: "Refund remaining products"
                    ),
                    subtitle: text(
                        "LivePet_Confirm_RefundRemainingItemsSub",
                        ar: "العودة للفاتورة واختيار العناصر المؤهلة المتبقية",
                        en: "Return to the sale and choose other eligible items"
                    ),
                    icon: "arrow.uturn.backward.circle.fill",
                    style: .primary
                ) {
                    actionFeedbackToken += 1
                    onProceedToMerchandiseRefund()
                }
            }

            actionButton(
                title: text("LivePet_OpenDossierButton", ar: "فتح ملف الاسترجاع", en: "Open return case"),
                subtitle: text(
                    "LivePet_Confirm_OpenDossierSub",
                    ar: "متابعة الفحص والعهدة وسجل القرارات",
                    en: "Review inspection, custody, and decision history"
                ),
                icon: "folder.fill",
                style: onProceedToMerchandiseRefund == nil ? .primary : .secondary
            ) {
                actionFeedbackToken += 1
                onOpenDossier()
            }

            Button {
                actionFeedbackToken += 1
                onDismiss()
            } label: {
                Text(text("LivePet_Confirm_Done", ar: "تم", en: "Done"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(ReturnConfirmationPressStyle())
        }
        .padding(.top, 2)
    }

    // MARK: - iPad Inspector

    private func iPadInspector(_ returnCase: LivePetReturnCase) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(text("LivePet_Confirm_NextActions", ar: "الخطوة التالية", en: "Next action"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)

                Text(onProceedToMerchandiseRefund == nil
                     ? text("LivePet_Confirm_ContinueCase", ar: "تابع ملف الحيوان", en: "Continue the animal case")
                     : text("LivePet_Confirm_ContinueSale", ar: "أكمل معالجة الفاتورة", en: "Continue processing the sale"))
                    .font(AdminType.title3Bold)
                    .foregroundStyle(AdminSurface.primaryText)

                Text(onProceedToMerchandiseRefund == nil
                     ? text(
                        "LivePet_Confirm_ContinueCaseSub",
                        ar: "الاسترداد المالي انتهى. افتح الملف لمتابعة مسار الفحص والعهدة.",
                        en: "The refund is complete. Open the case to continue inspection and custody follow-up."
                     )
                     : text(
                        "LivePet_Confirm_ContinueSaleSub",
                        ar: "تم استرداد الحيوان. يمكنك الآن استرداد أي منتجات أخرى مؤهلة من نفس الفاتورة.",
                        en: "The animal refund is complete. You can now refund other eligible products from the same sale."
                     ))
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(AdminSurface.hairline)

            nextStepNote(returnCase)

            caseIdentity(returnCase)

            VStack(spacing: 10) {
                if let onProceedToMerchandiseRefund {
                    actionButton(
                        title: text("LivePet_Confirm_RefundRemainingItems", ar: "استرداد بقية المنتجات", en: "Refund remaining products"),
                        subtitle: text("LivePet_Confirm_ShortcutRefund", ar: "⌘R", en: "⌘R"),
                        icon: "arrow.uturn.backward.circle.fill",
                        style: .primary
                    ) {
                        actionFeedbackToken += 1
                        onProceedToMerchandiseRefund()
                    }
                    .hoverEffect(.highlight)
                    .keyboardShortcut("r", modifiers: [.command])
                }

                actionButton(
                    title: text("LivePet_OpenDossierButton", ar: "فتح ملف الاسترجاع", en: "Open return case"),
                    subtitle: text("LivePet_Confirm_ShortcutOpen", ar: "⌘O", en: "⌘O"),
                    icon: "folder.fill",
                    style: onProceedToMerchandiseRefund == nil ? .primary : .secondary
                ) {
                    actionFeedbackToken += 1
                    onOpenDossier()
                }
                .hoverEffect(.highlight)
                .keyboardShortcut("o", modifiers: [.command])

                Button {
                    actionFeedbackToken += 1
                    onDismiss()
                } label: {
                    Text(text("LivePet_Confirm_Done", ar: "تم", en: "Done"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(ReturnConfirmationPressStyle())
                .hoverEffect(.highlight)
            }
        }
        .padding(20)
        .background(AdminSurface.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.035), radius: 18, y: 8)
    }

    // MARK: - Actions

    private enum ActionStyle {
        case primary
        case secondary
    }

    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        style: ActionStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AdminType.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(AdminType.caption)
                        .opacity(style == .primary ? 0.84 : 0.74)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(style == .primary ? Color.white : AdminSurface.primaryText)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(
                style == .primary ? AdminSurface.primary : AdminSurface.cardElevated,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AdminSurface.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(ReturnConfirmationPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    // MARK: - Loading / Empty / Failure

    private var loadingState: some View {
        VStack(spacing: 18) {
            HStack {
                skeleton(width: 44, height: 44, radius: 15)
                Spacer()
            }

            VStack(spacing: 12) {
                skeleton(width: 88, height: 88, radius: 44)
                skeleton(width: 260, height: 28, radius: 10)
                skeleton(width: 310, height: 16, radius: 8)
            }

            HStack(spacing: 10) {
                skeleton(width: nil, height: 108, radius: 18)
                skeleton(width: nil, height: 108, radius: 18)
            }

            skeleton(width: nil, height: 72, radius: 18)
            skeleton(width: nil, height: 132, radius: 20)
            skeleton(width: nil, height: 62, radius: 18)
        }
        .frame(maxWidth: 720)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text("LivePet_Confirm_Loading", ar: "جارٍ تجهيز ملخص الاسترجاع", en: "Preparing return summary"))
    }

    private var emptyState: some View {
        stateMessage(
            icon: "folder.badge.questionmark",
            title: text("LivePet_Confirm_EmptyTitle", ar: "لا توجد تفاصيل استرجاع لعرضها", en: "No return details to show"),
            message: text(
                "LivePet_Confirm_EmptyMessage",
                ar: "لم يتم العثور على ملف استرجاع مكتمل لهذه العملية. أغلق الشاشة وراجع الفاتورة مرة أخرى.",
                en: "No completed return case was found for this operation. Close this screen and review the sale again."
            ),
            tint: AdminSurface.secondaryText,
            primaryTitle: text("LivePet_Confirm_Done", ar: "تم", en: "Done"),
            primaryAction: onDismiss
        )
    }

    private func failureState(message: String) -> some View {
        stateMessage(
            icon: "arrow.clockwise.circle.fill",
            title: text("LivePet_Confirm_ErrorTitle", ar: "تعذر تحميل ملخص الاسترجاع", en: "Couldn’t load the return summary"),
            message: message.isEmpty
                ? text(
                    "LivePet_Confirm_ErrorMessage",
                    ar: "بيانات الاسترجاع محفوظة، لكن تعذر عرض الملخص الآن. حاول مرة أخرى.",
                    en: "The return data is saved, but the summary can’t be displayed right now. Try again."
                )
                : message,
            tint: AdminSurface.crimson,
            primaryTitle: onRetry == nil
                ? text("LivePet_Confirm_Done", ar: "تم", en: "Done")
                : text("LivePet_Confirm_Retry", ar: "إعادة المحاولة", en: "Try again"),
            primaryAction: onRetry ?? onDismiss
        )
    }

    private func stateMessage(
        icon: String,
        title: String,
        message: String,
        tint: Color,
        primaryTitle: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 18) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(ReturnConfirmationPressStyle())
                .accessibilityLabel(text("LivePet_Confirm_Close", ar: "إغلاق", en: "Close"))

                Spacer()
            }

            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 80, height: 80)
                    .background(tint.opacity(0.09), in: Circle())
                    .accessibilityHidden(true)

                Text(title)
                    .font(AdminType.title2)
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            .padding(.vertical, 22)

            Button {
                actionFeedbackToken += 1
                primaryAction()
            } label: {
                Text(primaryTitle)
                    .font(AdminType.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(ReturnConfirmationPressStyle())
        }
        .frame(maxWidth: 620)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func skeleton(width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(AdminSurface.cardElevated)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AdminSurface.hairline.opacity(0.75), lineWidth: 1)
            )
            .opacity(reduceMotion ? 0.78 : (successAppeared ? 0.58 : 0.9))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    successAppeared = true
                }
            }
    }

    // MARK: - Formatting / Localization / Motion

    private func localizedMoney(_ returnCase: LivePetReturnCase) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = returnCase.currency
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")
        let scale = LivePetMoney.minorUnitScale(for: returnCase.currency)
        formatter.minimumFractionDigits = scale
        formatter.maximumFractionDigits = scale
        return formatter.string(from: NSNumber(value: returnCase.totalRefundAmountMajor))
            ?? "\(returnCase.totalRefundAmountMajor.formatted(.number.precision(.fractionLength(scale)))) \(returnCase.currency)"
    }

    private func text(_ key: String, ar: String, en: String) -> String {
        Language.get(key, alter: Language.isRTL() ? ar : en)
    }

    private func revealSuccess() {
        guard !successAppeared else { return }
        if reduceMotion {
            successAppeared = true
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
                successAppeared = true
            }
        }
    }
}

private struct ReturnConfirmationPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82),
                value: configuration.isPressed
            )
    }
}
