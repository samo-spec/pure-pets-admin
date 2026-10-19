//
//  PPVetDetailDossierScreen.swift
//  PurePetsAdmin
//
//  First-Principles Invention: Category-Defining Sovereign Clinical Medical Dossier.
//  Reinvented from absolute first principles in SwiftUI with Apple HIG grade craft,
//  bilingual RTL/LTR typography, live vital signs, tactile haptics, and administrative controls.
//

import SwiftUI
import UIKit

// MARK: - Sovereign Clinical Medical Dossier Screen

@MainActor
public struct PPVetDetailDossierScreen: View {
    @State private var vet: PPVetModel
    private let onDismiss: () -> Void
    private let onEdit: (PPVetModel) -> Void
    private let onSubscription: (PPVetModel) -> Void
    private let onUpdated: ((PPVetModel) -> Void)?

    @State private var isTogglingStatus: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showStatusConfirm: Bool = false
    @State private var copyToastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    @Environment(\.colorScheme) private var colorScheme

    public init(
        vet: PPVetModel,
        onDismiss: @escaping () -> Void,
        onEdit: @escaping (PPVetModel) -> Void,
        onSubscription: @escaping (PPVetModel) -> Void,
        onUpdated: ((PPVetModel) -> Void)? = nil
    ) {
        _vet = State(initialValue: vet)
        self.onDismiss = onDismiss
        self.onEdit = onEdit
        self.onSubscription = onSubscription
        self.onUpdated = onUpdated
    }

    private var isClinic: Bool { vet.type == .company }
    private var isDisabled: Bool { vet.isDisabled }
    private var isExpired: Bool { vet.isSubscriptionExpired() }

    private var primaryAccent: Color {
        isClinic ? Color(red: 0.12, green: 0.68, blue: 0.88) : Color(red: 0.08, green: 0.72, blue: 0.65)
    }

    private var gradientPalette: [Color] {
        isClinic
            ? [Color(red: 0.12, green: 0.68, blue: 0.88), Color(red: 0.06, green: 0.52, blue: 0.78)]
            : [Color(red: 0.08, green: 0.72, blue: 0.65), Color(red: 0.04, green: 0.56, blue: 0.50)]
    }

    public var body: some View {
        ZStack {
            // Ambient Backdrop
            AdminSurface.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sovereign Navigation Bar
                navigationHeader

                // Scrollable Dossier Body
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Medical Authority Hero Stage
                        medicalAuthorityHeroCard

                        // Clinical Vital Signs Horizon (4 Metrics Deck)
                        vitalSignsHorizonDeck

                        // Medical Qualifications & Bio Dossier Card
                        qualificationsDossierCard

                        // Communication & Telehealth Channels
                        telehealthChannelsCard

                        // Subscription & Licensing Health Card
                        subscriptionGovernanceCard

                        // System Audit & Registry Metadata Card
                        registryAuditCard

                        // Danger Zone: Deletion & Revocation
                        dangerZoneCard

                        // Bottom Spacing
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }

            // Quick Copy HUD Toast
            if let toast = copyToastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                        Text(toast)
                            .font(AdminType.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: copyToastMessage)
            }
        }
        .alert(Language.get("Vet_Confirm_Delete_Title", alter: "حذف السجل البيطري؟"), isPresented: $showDeleteConfirm) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("Delete", alter: "حذف نهائي"), role: .destructive) {
                performDelete()
            }
        } message: {
            Text(Language.get("Vet_Confirm_Delete_Msg", alter: "هل أنت متأكد من حذف هذا السجل بشكل نهائي؟ لا يمكن التراجع عن هذا الإجراء."))
        }
        .alert(
            isDisabled ? Language.get("Vet_Confirm_Enable_Title", alter: "تفعيل الترخيص؟") : Language.get("Vet_Confirm_Disable_Title", alter: "تعطيل الترخيص؟"),
            isPresented: $showStatusConfirm
        ) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(isDisabled ? Language.get("Vet_Action_Enable", alter: "تفعيل الآن") : Language.get("Vet_Action_Disable", alter: "تعطيل مؤقت"), role: isDisabled ? .none : .destructive) {
                toggleLicenseStatus()
            }
        } message: {
            Text(isDisabled ? Language.get("Vet_Confirm_Enable_Msg", alter: "سيظهر هذا الطبيب أو العيادة للمستخدمين في التطبيق مرة أخرى.") : Language.get("Vet_Confirm_Disable_Msg", alter: "سيتم إخفاء هذا الكيان عن نتائج البحث وتطبيق المستخدمين."))
        }
    }

    // MARK: - Navigation Bar Header

    private var navigationHeader: some View {
        AdminSovereignNavigationBar(
            title: vet.title ?? Language.get("AdminVet_Dossier_Action", alter: "الملف الطبي"),
            subtitle: isClinic ? Language.get("AdminVet_VerifiedClinic", alter: "منشأة طبية معتمدة") : Language.get("AdminVet_LicensedDoctor", alter: "طبيب بيطري مرخص"),
            statusDotColor: isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48),
            onBack: onDismiss
        ) {
            HStack(spacing: 8) {
                // Subscription Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSubscription(vet)
                } label: {
                    Image(systemName: "creditcard.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Vet_Subscription", alter: "إدارة باقة الاشتراك"))

                // Edit Button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onEdit(vet)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Edit", alter: "تعديل"))

                // More Menu
                Menu {
                    Button {
                        showStatusConfirm = true
                    } label: {
                        Label(
                            isDisabled ? Language.get("Vet_Action_Enable", alter: "تفعيل الترخيص") : Language.get("Vet_Action_Disable", alter: "إيقاف مؤقت للترخيص"),
                            systemImage: isDisabled ? "checkmark.circle.fill" : "nosign"
                        )
                    }

                    Button {
                        shareDossier()
                    } label: {
                        Label(Language.get("Share", alter: "مشاركة الملف"), systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(Language.get("Delete", alter: "حذف نهائي"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 36, height: 36)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                        )
                }
            }
        }
    }

    // MARK: - Medical Authority Hero Stage

    private var medicalAuthorityHeroCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Entity Avatar / Logo
                avatarView

                // Name & Archetype Badge
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: isClinic ? "building.2.fill" : "stethoscope")
                            .font(.system(size: 11, weight: .bold))
                        Text(isClinic ? Language.get("AdminVet_VerifiedClinic", alter: "عيادة بيطرية معتمدة") : Language.get("AdminVet_LicensedDoctor", alter: "طبيب بيطري مرخص"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(primaryAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(primaryAccent.opacity(0.12), in: Capsule())

                    Text(vet.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? vet.title! : "—")
                        .font(.custom("Beiruti-Bold", size: 22))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(2)

                    // Tier Pill + Status Beacon
                    HStack(spacing: 8) {
                        tierBadgeView

                        HStack(spacing: 4) {
                            Circle()
                                .fill(isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48))
                                .frame(width: 6, height: 6)
                            Text(isDisabled ? Language.get("Vet_Status_Disabled", alter: "معطّل") : Language.get("Vet_Status_Active", alter: "نشط"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48))
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            Divider()
                .overlay(AdminSurface.hairline)

            // Direct Communication Action Island
            HStack(spacing: 10) {
                // Phone Call CTA
                if let phone = vet.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        callPhone(phone)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Call", alter: "اتصال هاتفي"))
                                .font(AdminType.caption1Bold)
                        }
                        .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                // WhatsApp CTA
                if let wa = vet.whatsapp ?? vet.phone, !wa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        openWhatsApp(wa)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("WhatsApp", alter: "واتساب"))
                                .font(AdminType.caption1Bold)
                        }
                        .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                // Subscription Manager CTA
                Button {
                    onSubscription(vet)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(Language.get("Vet_Subscription", alter: "الباقة"))
                            .font(AdminType.caption1Bold)
                    }
                    .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 10, x: 0, y: 3)
    }

    // MARK: - Vital Signs Horizon (4 Metrics Deck)

    private var vitalSignsHorizonDeck: some View {
        HStack(spacing: 10) {
            // Metric 1: Consultation Fee
            vitalMetricTile(
                title: Language.get("AdminVet_Consultation_Fee", alter: "رسوم الكشف"),
                value: vet.vetCost > 0 ? "\(Int(vet.vetCost)) \(Language.get("QAR", alter: "ر.ق"))" : Language.get("AdminVet_FreeConsult", alter: "مجاناً"),
                icon: "tag.fill",
                accent: Color(red: 0.08, green: 0.72, blue: 0.65)
            )

            // Metric 2: License Status
            vitalMetricTile(
                title: Language.get("Vet_Field_Status", alter: "حالة الترخيص"),
                value: isDisabled ? Language.get("Vet_Status_Disabled", alter: "موقوف") : Language.get("Vet_Status_Active", alter: "مرخص"),
                icon: isDisabled ? "xmark.shield.fill" : "checkmark.shield.fill",
                accent: isDisabled ? Color(red: 0.92, green: 0.35, blue: 0.28) : Color(red: 0.16, green: 0.78, blue: 0.48)
            )

            // Metric 3: Subscription Tier
            vitalMetricTile(
                title: Language.get("Vet_Subscription", alter: "الباقة"),
                value: vet.localizedSubscriptionTierName() ?? Language.get("Free", alter: "مجانية"),
                icon: "crown.fill",
                accent: Color(red: 0.95, green: 0.65, blue: 0.15)
            )
        }
    }

    private func vitalMetricTile(title: String, value: String, icon: String, accent: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(AdminType.caption2)
            }
            .foregroundStyle(AdminSurface.secondaryText)

            Text(value)
                .font(.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Qualifications & Bio Dossier Card

    private var qualificationsDossierCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            dossierSectionHeader(
                title: Language.get("pet_care_vet_about_section", alter: "نبذة عن الطبيب والخبرات"),
                icon: "doc.text.fill",
                accent: primaryAccent
            )

            if let desc = vet.descriptionText, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(desc)
                    .font(AdminType.body)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(Language.get("NoDescription", alter: "لا يوجد وصف أو نبذة مسجلة حتى الآن."))
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Telehealth & Communication Channels

    private var telehealthChannelsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            dossierSectionHeader(
                title: Language.get("Vet_Section_Contact", alter: "قنوات التواصل والاستشارات"),
                icon: "phone.bubble.left.fill",
                accent: Color(red: 0.16, green: 0.78, blue: 0.48)
            )

            VStack(spacing: 8) {
                // Phone Row
                if let phone = vet.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contactChannelRow(
                        label: Language.get("Vet_Field_Phone", alter: "الهاتف الرسمي"),
                        value: phone,
                        icon: "phone.fill",
                        color: Color(red: 0.08, green: 0.72, blue: 0.65),
                        onAction: { callPhone(phone) },
                        onCopy: { copyToClipboard(phone, label: "تم نسخ رقم الهاتف") }
                    )
                }

                // WhatsApp Row
                if let wa = vet.whatsapp, !wa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contactChannelRow(
                        label: Language.get("Vet_Field_Whatsapp", alter: "واتساب الاستشارات"),
                        value: wa,
                        icon: "message.fill",
                        color: Color(red: 0.16, green: 0.78, blue: 0.48),
                        onAction: { openWhatsApp(wa) },
                        onCopy: { copyToClipboard(wa, label: "تم نسخ رقم الواتساب") }
                    )
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func contactChannelRow(
        label: String,
        value: String,
        icon: String,
        color: Color,
        onAction: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            Spacer()

            // Copy Button
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            // Trigger Button
            Button(action: onAction) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Subscription & Licensing Health Card

    private var subscriptionGovernanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                dossierSectionHeader(
                    title: Language.get("Vet_Subscription", alter: "باقة الاشتراك والتراخيص"),
                    icon: "crown.fill",
                    accent: Color(red: 0.95, green: 0.65, blue: 0.15)
                )

                Spacer()

                Button {
                    onSubscription(vet)
                } label: {
                    Text(Language.get("Manage", alter: "إدارة الباقة"))
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))
                }
            }

            VStack(spacing: 8) {
                // Tier Row
                HStack {
                    Text(Language.get("Vet_Subscription_Tier", alter: "المستوى الحالي"))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    tierBadgeView
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Expiry Date Row
                if let end = vet.subscriptionEndDate {
                    HStack {
                        Text(Language.get("Vet_Sub_EndDate", alter: "تاريخ انتهاء الباقة"))
                            .font(AdminType.subheadline)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(formattedDate(end))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(isExpired ? Color(red: 0.92, green: 0.35, blue: 0.28) : AdminSurface.primaryText)

                            if isExpired {
                                Text(Language.get("Vet_Sub_Expired", alter: "منتهية"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.92, green: 0.35, blue: 0.28), in: Capsule())
                            }
                        }
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Available Date Row
                if let available = vet.availableDate {
                    HStack {
                        Text(Language.get("Vet_Field_AvailableDate", alter: "تاريخ بدء التوافر"))
                            .font(AdminType.subheadline)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        Text(formattedDate(available))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Registry Audit Card

    private var registryAuditCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            dossierSectionHeader(
                title: Language.get("AuditLog_Title", alter: "سجل التدقيق والمعرّفات"),
                icon: "shield.lefthalf.filled",
                accent: Color(red: 0.58, green: 0.44, blue: 0.88)
            )

            VStack(spacing: 8) {
                // Firestore ID Row
                HStack {
                    Text("Firestore ID")
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(vet.vetID.isEmpty ? "—" : vet.vetID)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminSurface.primaryText)
                    Button {
                        if !vet.vetID.isEmpty {
                            copyToClipboard(vet.vetID, label: "تم نسخ المعرّف")
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Creation Date Row
                if let created = vet.createdAt {
                    HStack {
                        Text(Language.get("Vet_Field_CreatedAt", alter: "تاريخ التسجيل بالمنصة"))
                            .font(AdminType.caption1)
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        Text(formattedDate(created))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Danger Zone Card

    private var dangerZoneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            dossierSectionHeader(
                title: Language.get("AdminVet_AdministrativeActions", alter: "إدارة التراخيص والإلغاء"),
                icon: "exclamationmark.triangle.fill",
                accent: Color(red: 0.92, green: 0.35, blue: 0.28)
            )

            HStack(spacing: 12) {
                // Toggle Suspend / Activate Button
                Button {
                    showStatusConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isDisabled ? "checkmark.circle.fill" : "nosign")
                            .font(.system(size: 13, weight: .bold))
                        Text(isDisabled ? Language.get("Vet_Action_Enable", alter: "تفعيل الترخيص") : Language.get("Vet_Action_Disable", alter: "تعطيل مؤقت"))
                            .font(AdminType.caption1Bold)
                    }
                    .foregroundStyle(isDisabled ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.95, green: 0.55, blue: 0.20))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        (isDisabled ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.95, green: 0.55, blue: 0.20)).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                // Delete Button
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Delete", alter: "حذف السجل"))
                            .font(AdminType.caption1Bold)
                    }
                    .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.28))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.92, green: 0.35, blue: 0.28).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Subviews & Helpers

    private var avatarView: some View {
        ZStack {
            if let logo = vet.logoURL, !logo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let url = URL(string: logo) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        avatarPlaceholder
                    @unknown default:
                        avatarPlaceholder
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 64, height: 64)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(primaryAccent.opacity(0.25), lineWidth: 1)
        )
    }

    private var avatarPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(primaryAccent.opacity(0.12))
                .frame(width: 64, height: 64)
            Image(systemName: isClinic ? "building.2.fill" : "stethoscope")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(primaryAccent)
        }
    }

    private var tierBadgeView: some View {
        let (title, color, icon) = tierVisuals(for: vet.subscriptionTier)
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(AdminType.caption2Bold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func tierVisuals(for tier: PPVetSubscriptionTier) -> (String, Color, String) {
        switch tier {
        case .free:
            return (Language.get("Vet_Sub_Free", alter: "مجاني"), Color(red: 0.50, green: 0.55, blue: 0.60), "checkmark.circle")
        case .basic:
            return (Language.get("Vet_Sub_Basic", alter: "باقة أساسية"), Color(red: 0.12, green: 0.68, blue: 0.88), "checkmark.seal.fill")
        case .premium:
            return (Language.get("Vet_Sub_Premium", alter: "باقة مميزة VIP"), Color(red: 0.95, green: 0.65, blue: 0.15), "crown.fill")
        @unknown default:
            return ("", .gray, "circle")
        }
    }

    private func dossierSectionHeader(title: String, icon: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
            Text(title)
                .font(AdminType.subheadlineBold)
                .foregroundStyle(AdminSurface.primaryText)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func callPhone(_ phone: String) {
        let cleaned = phone.filter { "0123456789+".contains($0) }
        guard let url = URL(string: "tel://\(cleaned)"), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    private func openWhatsApp(_ whatsapp: String) {
        var cleaned = whatsapp.filter { "0123456789".contains($0) }
        if cleaned.hasPrefix("00") {
            cleaned.removeFirst(2)
        }
        let greeting = Language.get("AdminVet_WhatsAppGreeting", alter: "مرحباً دكتور، نتواصل معك من إدارة منصة بيور بيتس بخصوص حسابكم المهني.")
        let encodedGreeting = greeting.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "whatsapp://send?phone=\(cleaned)&text=\(encodedGreeting)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let webURL = URL(string: "https://wa.me/\(cleaned)?text=\(encodedGreeting)") {
            UIApplication.shared.open(webURL)
        }
    }

    private func shareDossier() {
        guard let title = vet.title else { return }
        let text = "\(title) - \(isClinic ? "عيادة بيطرية" : "طبيب بيطري") عبر منصة بيور بيتس"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }

    private func copyToClipboard(_ text: String, label: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        toastTask?.cancel()
        withAnimation {
            copyToastMessage = label
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                copyToastMessage = nil
            }
        }
    }

    private func toggleLicenseStatus() {
        let vetID = vet.vetID
        guard !vetID.isEmpty else { return }
        let newStatus = !vet.isDisabled
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        PPVetManager.shared().setDisabled(newStatus, forVetID: vetID) { error in
            if error == nil {
                vet.isDisabled = newStatus
                onUpdated?(vet)
            }
        }
    }

    private func performDelete() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        PPVetManager.shared().deleteVet(vet) { error in
            if error == nil {
                onDismiss()
            }
        }
    }
}

// MARK: - Hosting Controller Bridge (for UIKit push/present)

@objc(PPVetDetailDossierHostingController)
public class PPVetDetailDossierHostingController: UIViewController {
    private let vet: PPVetModel

    @objc public init(vet: PPVetModel) {
        self.vet = vet
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.ppBackground
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all
        navigationController?.setNavigationBarHidden(true, animated: false)

        let swiftUIView = PPVetDetailDossierScreen(
            vet: vet,
            onDismiss: { [weak self] in
                if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true)
                }
            },
            onEdit: { [weak self] currentVet in
                let editVC = PPVetEditorHostingController(vetToEdit: currentVet)
                self?.navigationController?.pushViewController(editVC, animated: true)
            },
            onSubscription: { [weak self] currentVet in
                let subVC = PPVetSubscriptionHostingController(vet: currentVet)
                self?.navigationController?.pushViewController(subVC, animated: true)
            }
        )

        let hostingController = UIHostingController(rootView: swiftUIView.ignoresSafeArea())
        hostingController.view.backgroundColor = .clear
        hostingController.extendedLayoutIncludesOpaqueBars = true
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
}
