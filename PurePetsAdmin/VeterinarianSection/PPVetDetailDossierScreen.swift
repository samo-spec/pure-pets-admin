//
//  PPVetDetailDossierScreen.swift
//  PurePetsAdmin
//
//  First-Principles Invention: Category-Defining Sovereign Clinical Medical Dossier.
//  Reinvented from absolute first principles in SwiftUI with Apple HIG grade craft,
//  bilingual RTL/LTR typography, live vital signs horizon, tactile tele-health dock,
//  and authoritative administrative governance.
//

import SwiftUI
import UIKit

// MARK: - Sovereign Clinical Medical Dossier Screen

@MainActor
public struct PPVetDetailDossierScreen: View {
    // MARK: - State & Callbacks
    @State private var vet: PPVetModel
    private let onDismiss: () -> Void
    private let onEdit: (PPVetModel) -> Void
    private let onSubscription: (PPVetModel) -> Void
    private let onUpdated: ((PPVetModel) -> Void)?

    // Operational Administrative State
    @State private var isTogglingStatus: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showStatusConfirm: Bool = false
    @State private var copyToastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Initializer

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

    // MARK: - Computed Properties

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

    // MARK: - Body

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
                        // Spatial Medical Authority Hero Stage
                        medicalAuthorityHeroCard

                        // Instant Tele-Care Communication Dock (Call, WhatsApp, Share)
                        telehealthCommunicationDock

                        // Clinical Vital Signs Horizon (4 Rich Metrics Deck)
                        vitalSignsHorizonDeck

                        // Medical Qualifications, Bio & Species Covered Card
                        qualificationsDossierCard

                        // Availability & Appointment Readiness Card
                        availabilityScheduleCard

                        // Sovereign Administrative Governance Suite
                        administrativeGovernanceCard

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
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
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
            Text(isDisabled
                 ? Language.get("Vet_Confirm_Enable_Msg", alter: "سيصبح هذا الطبيب أو العيادة متاحاً للعملاء في التطبيق وتفعيل استقبال الاستشارات.")
                 : Language.get("Vet_Confirm_Disable_Msg", alter: "سيتم إخفاء هذا الكيان فوراً من التطبيق وتعليق استقبال أي حجوزات أو استشارات."))
        }
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        HStack(spacing: 12) {
            // Dismiss Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 38, height: 38)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("Back", alter: "رجوع"))

            // Title & ID Pill
            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("AdminVet_Dossier_Action", alter: "الملف الطبي الشامل"))
                    .font(.custom("Beiruti-Bold", size: 19))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("ID:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(vet.vetID.prefix(8) + "...")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(AdminCommandInk.secondary)
            }

            Spacer()

            // Quick Edit Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEdit(vet)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("Edit", alter: "تعديل"))
                        .font(.custom("Beiruti-Bold", size: 14))
                }
                .foregroundStyle(primaryAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(primaryAccent.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(primaryAccent.opacity(0.25), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(AdminSurface.background)
    }

    // MARK: - Spatial Medical Authority Hero Stage

    private var medicalAuthorityHeroCard: some View {
        ZStack {
            // Ambient Glow Gradient
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradientPalette.map { $0.opacity(colorScheme == .dark ? 0.22 : 0.10) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 14) {
                // Top Status Bar: Subscription Tier Badge + License Beacon
                HStack {
                    // Subscription Tier Pill
                    tierRibbonBadge

                    Spacer()

                    // Live Status Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isDisabled ? Color(red: 0.95, green: 0.45, blue: 0.15) : Color(red: 0.16, green: 0.78, blue: 0.48))
                            .frame(width: 7, height: 7)

                        Text(isDisabled
                             ? Language.get("Vet_Status_Suspended_Short", alter: "موقوف مؤقتاً")
                             : Language.get("Vet_Status_Active_Short", alter: "نشط ومعتمد"))
                            .font(AdminType.caption2Bold)
                            .foregroundStyle(isDisabled ? Color(red: 0.95, green: 0.45, blue: 0.15) : Color(red: 0.16, green: 0.78, blue: 0.48))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        (isDisabled ? Color(red: 0.95, green: 0.45, blue: 0.15) : Color(red: 0.16, green: 0.78, blue: 0.48)).opacity(0.14),
                        in: Capsule()
                    )
                }

                // Insignia Avatar & Practitioner Identity
                HStack(spacing: 16) {
                    // Avatar Insignia
                    ZStack {
                        Circle()
                            .fill(primaryAccent.opacity(0.15))
                            .frame(width: 80, height: 80)

                        if let logoURL = vet.logoURL, let url = URL(string: logoURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                default:
                                    Image(systemName: isClinic ? "cross.case.fill" : "stethoscope")
                                        .font(.system(size: 34, weight: .bold))
                                        .foregroundStyle(primaryAccent)
                                }
                            }
                        } else {
                            Image(systemName: isClinic ? "cross.case.fill" : "stethoscope")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(primaryAccent)
                        }

                        // Entity Type Watermark Circle
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Circle()
                                    .fill(primaryAccent)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: isClinic ? "building.2.fill" : "person.badge.shield.checkmark.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                                    .shadow(color: primaryAccent.opacity(0.35), radius: 4, x: 0, y: 2)
                            }
                        }
                        .frame(width: 80, height: 80)
                    }
                    .overlay(Circle().strokeBorder(primaryAccent.opacity(0.4), lineWidth: 2))

                    // Names & Credentials
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vet.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? vet.title! : "—")
                            .font(.custom("Beiruti-Bold", size: 22))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(2)

                        // Verified Badge
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(primaryAccent)
                            Text(isClinic
                                 ? Language.get("AdminVet_VerifiedClinic", alter: "عيادة بيطرية معتمدة")
                                 : Language.get("AdminVet_LicensedDoctor", alter: "طبيب بيطري مرخص"))
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(primaryAccent)
                        }

                        // Hashtag / Category
                        if let desc = vet.descriptionText, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(desc)
                                .font(AdminType.caption)
                                .foregroundStyle(AdminCommandInk.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(primaryAccent.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Tier Ribbon Badge

    private var tierRibbonBadge: some View {
        HStack(spacing: 5) {
            switch vet.subscriptionTier {
            case .premium:
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(Language.get("Vet_Tier_Premium", alter: "باقة متميزة VIP"))
                    .font(AdminType.caption2Bold)
            case .basic:
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(Language.get("Vet_Tier_Basic", alter: "باقة أساسية"))
                    .font(AdminType.caption2Bold)
            case .free:
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                Text(Language.get("Vet_Tier_Free", alter: "باقة مجانية"))
                    .font(AdminType.caption2Bold)
            @unknown default:
                Text(vet.localizedSubscriptionTierName())
                    .font(AdminType.caption2Bold)
            }
        }
        .foregroundStyle(tierColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tierColor.opacity(0.14), in: Capsule())
    }

    private var tierColor: Color {
        switch vet.subscriptionTier {
        case .premium: return Color(red: 0.95, green: 0.65, blue: 0.12)
        case .basic:   return Color(red: 0.12, green: 0.68, blue: 0.88)
        case .free:    return Color(red: 0.08, green: 0.72, blue: 0.65)
        @unknown default: return AdminCommandInk.secondary
        }
    }

    // MARK: - Instant Tele-Care Communication Dock

    private var telehealthCommunicationDock: some View {
        HStack(spacing: 10) {
            // Direct Phone Call
            Button {
                if let phone = vet.phone, !phone.isEmpty {
                    callPhone(phone)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(vet.phone ?? Language.get("Call", alter: "اتصال"))
                        .font(.custom("Beiruti-Bold", size: 15))
                        .lineLimit(1)
                }
                .foregroundStyle(Color(red: 0.14, green: 0.54, blue: 0.98))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(red: 0.14, green: 0.54, blue: 0.98).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(red: 0.14, green: 0.54, blue: 0.98).opacity(0.25), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .disabled(vet.phone?.isEmpty ?? true)

            // Direct WhatsApp Chat
            Button {
                openWhatsApp()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(Language.get("WhatsApp", alter: "واتساب"))
                        .font(.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.25), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .disabled((vet.whatsapp?.isEmpty ?? true) && (vet.phone?.isEmpty ?? true))

            // Quick Copy Card / Share
            Button {
                copyPractitionerInfo()
            } label: {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Language.get("Copy", alter: "نسخ البيانات"))
        }
    }

    private func callPhone(_ number: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let clean = number.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func openWhatsApp() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let number = (vet.whatsapp?.isEmpty == false ? vet.whatsapp : vet.phone) ?? ""
        var clean = number.filter { $0.isNumber }
        if !clean.hasPrefix("974") && clean.count == 8 {
            clean = "974" + clean
        }
        let greeting = Language.get("AdminVet_WhatsAppGreeting", alter: "مرحباً دكتور، نتواصل معك من إدارة منصة بيور بيتس بخصوص حسابكم المهني.")
        let encoded = greeting.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://wa.me/\(clean)?text=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func copyPractitionerInfo() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let info = "\(vet.title ?? "") | \(isClinic ? "عيادة بيطرية" : "طبيب بيطري") | \(vet.phone ?? "")"
        UIPasteboard.general.string = info
        triggerToast(Language.get("Vet_Copied_Toast", alter: "تم نسخ بيانات الطبيب إلى الحافظة"))
    }

    private func triggerToast(_ msg: String) {
        toastTask?.cancel()
        withAnimation { copyToastMessage = msg }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled {
                withAnimation { copyToastMessage = nil }
            }
        }
    }

    // MARK: - Clinical Vital Signs Horizon (4 Rich Metrics Deck)

    private var vitalSignsHorizonDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primaryAccent)
                Text(Language.get("Vet_Vital_Signs_Title", alter: "المؤشرات التشغيلية والسريرية"))
                    .font(.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                // Metric 1: Consultation Rate
                vitalTile(
                    title: Language.get("AdminVet_Consultation_Fee", alter: "رسوم الاستشارة"),
                    value: vet.vetCost > 0 ? "\(String(format: "%.0f", vet.vetCost)) \(Language.get("QAR", alter: "ر.ق"))" : Language.get("AdminVet_FreeConsult", alter: "استشارة مجانية"),
                    caption: feeAssessmentText,
                    iconName: "creditcard.fill",
                    tintColor: Color(red: 0.08, green: 0.72, blue: 0.65)
                )

                // Metric 2: Entity Classification
                vitalTile(
                    title: Language.get("Vet_Entity_Type", alter: "التصنيف المهني"),
                    value: isClinic ? Language.get("Vet_Type_Clinic_Short", alter: "مركز طبي") : Language.get("Vet_Type_Doctor_Short", alter: "طبيب استشاري"),
                    caption: isClinic ? Language.get("Vet_Facility_Certified", alter: "منشأة معتمدة") : Language.get("Vet_Practitioner_Licensed", alter: "ممارس مستقل"),
                    iconName: isClinic ? "cross.case.fill" : "stethoscope",
                    tintColor: primaryAccent
                )

                // Metric 3: Digital Care Readiness
                vitalTile(
                    title: Language.get("Vet_Telecare_Readiness", alter: "الجاهزية الرقمية"),
                    value: (vet.phone?.isEmpty == false && vet.whatsapp?.isEmpty == false) ? Language.get("Vet_Ready_Full", alter: "جاهزية كاملة") : Language.get("Vet_Ready_PhoneOnly", alter: "اتصال هاتفي"),
                    caption: Language.get("Vet_Channels_Active", alter: "قنوات الاتصال المباشر"),
                    iconName: "antenna.radiowaves.left.and.right",
                    tintColor: Color(red: 0.16, green: 0.78, blue: 0.48)
                )

                // Metric 4: Subscription & License Health
                vitalTile(
                    title: Language.get("Vet_License_Health", alter: "صلاحية الترخيص"),
                    value: isExpired ? Language.get("Vet_Expired", alter: "منتهي") : (vet.subscriptionActive ? Language.get("Active", alter: "سارٍ ونشط") : Language.get("Vet_Free_Tier", alter: "مجاني دائم")),
                    caption: expirationDateString,
                    iconName: "shield.lefthalf.filled",
                    tintColor: isExpired ? Color(red: 0.95, green: 0.45, blue: 0.15) : Color(red: 0.12, green: 0.68, blue: 0.88)
                )
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func vitalTile(
        title: String,
        value: String,
        caption: String,
        iconName: String,
        tintColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ZStack {
                    Circle()
                        .fill(tintColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tintColor)
                }
                Spacer()
            }

            Text(title)
                .font(AdminType.caption)
                .foregroundStyle(AdminCommandInk.secondary)
                .lineLimit(1)

            Text(value)
                .font(.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            Text(caption)
                .font(AdminType.caption2)
                .foregroundStyle(AdminCommandInk.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AdminSurface.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private var feeAssessmentText: String {
        if vet.vetCost <= 0 {
            return Language.get("AdminVet_FreeConsult", alter: "استشارة مجانية")
        } else if vet.vetCost < 100 {
            return Language.get("Vet_Below_Avg", alter: "أقل من متوسط السوق")
        } else if vet.vetCost <= 150 {
            return Language.get("Vet_Avg_Rate", alter: "ضمن المتوسط المعتمد")
        } else {
            return Language.get("Vet_Premium_Rate", alter: "فئة استشارية متقدمة")
        }
    }

    private var expirationDateString: String {
        if let end = vet.subscriptionEndDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
            formatter.dateFormat = "yyyy/MM/dd"
            return "\(Language.get("Vet_Until", alter: "حتى")) \(formatter.string(from: end))"
        }
        return Language.get("Vet_Permanent", alter: "غير محدد بانتهاء")
    }

    // MARK: - Qualifications, Bio & Species Dossier Card

    private var qualificationsDossierCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primaryAccent)
                Text(Language.get("Vet_Clinical_Bio_Title", alter: "الملف السريري ومجالات الاختصاص"))
                    .font(.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            // Clinical Biography Text
            if let desc = vet.descriptionText, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(desc)
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineSpacing(4)
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(Language.get("Vet_No_Bio", alter: "لم يتم تدوين ملف تعريفي مفصل بعد."))
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminCommandInk.tertiary)
                    .padding(.vertical, 4)
            }

            // Covered Species Badges
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("Vet_Covered_Species", alter: "الحيوانات المشمولة بالرعاية"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.primaryText)

                HStack(spacing: 8) {
                    speciesPill(name: Language.get("Species_Cats", alter: "القطط"), icon: "pawprint.fill")
                    speciesPill(name: Language.get("Species_Dogs", alter: "الكلاب"), icon: "dog.fill")
                    speciesPill(name: Language.get("Species_Birds", alter: "الطيور"), icon: "bird.fill")
                    speciesPill(name: Language.get("Species_Rodents", alter: "القوارض"), icon: "tortoise.fill")
                }
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func speciesPill(name: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(name)
                .font(.custom("Beiruti-Bold", size: 12))
        }
        .foregroundStyle(primaryAccent)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(primaryAccent.opacity(0.12), in: Capsule())
    }

    // MARK: - Availability Schedule Card

    private var availabilityScheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.12, green: 0.68, blue: 0.88))
                Text(Language.get("AdminVet_Availability", alter: "جدولة المواعيد والجاهزية"))
                    .font(.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            if let available = vet.availableDate {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.12, green: 0.68, blue: 0.88).opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.68, blue: 0.88))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Vet_Next_Available", alter: "أقرب موعد كشف متاح:"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminCommandInk.secondary)

                        Text(formattedFullDate(available))
                            .font(.custom("Beiruti-Bold", size: 16))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AdminSurface.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(AdminCommandInk.secondary)
                    Text(Language.get("Vet_Open_Availability", alter: "المواعيد مفتوحة حسب أوقات دوام العيادة أو الممارس"))
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func formattedFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Sovereign Administrative Governance Suite

    private var administrativeGovernanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primaryAccent)
                Text(Language.get("Vet_Admin_Controls", alter: "لوحة التحكم والقرارات الإدارية"))
                    .font(.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            // Quick Toggle License Status
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDisabled ? Language.get("Vet_Status_Suspended", alter: "الترخيص موقوف مؤقتاً") : Language.get("Vet_Status_Active", alter: "الترخيص سارٍ ومعتمد"))
                        .font(.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(isDisabled ? Color(red: 0.95, green: 0.45, blue: 0.15) : Color(red: 0.16, green: 0.78, blue: 0.48))

                    Text(isDisabled
                         ? Language.get("Vet_Hidden_Notice", alter: "محجوب عن الظهور في التطبيق")
                         : Language.get("Vet_Visible_Notice", alter: "يظهر للعملاء ومتاح للحجز المباشر"))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminCommandInk.secondary)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showStatusConfirm = true
                } label: {
                    Text(isDisabled ? Language.get("Vet_Action_Enable", alter: "تفعيل الآن") : Language.get("Vet_Action_Disable", alter: "تعطيل مؤقت"))
                        .font(.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(isDisabled ? .white : Color(red: 0.95, green: 0.45, blue: 0.15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            isDisabled
                                ? Color(red: 0.16, green: 0.78, blue: 0.48)
                                : Color(red: 0.95, green: 0.45, blue: 0.15).opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(AdminSurface.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Subscription Management Launcher
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSubscription(vet)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.65, blue: 0.12).opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.12))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Vet_Manage_Subscription", alter: "إدارة الباقة والاشتراك المهني"))
                            .font(.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Vet_Manage_Subscription_Sub", alter: "ترقية الباقة، تمديد الصلاحية، وتعديل الميزات"))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminCommandInk.secondary)
                    }

                    Spacer()

                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminCommandInk.secondary)
                }
                .padding(12)
                .background(AdminSurface.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Registry & Audit Metadata Card

    private var registryAuditCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminCommandInk.secondary)
                Text(Language.get("Vet_Audit_Title", alter: "بيانات التوثيق والتدقيق السحابي"))
                    .font(.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
            }

            VStack(spacing: 8) {
                auditRow(
                    label: Language.get("Vet_Document_ID", alter: "معرف المستند (Vet ID)"),
                    value: vet.vetID,
                    canCopy: true
                )

                if let created = vet.createdAt {
                    auditRow(
                        label: Language.get("Vet_Registration_Date", alter: "تاريخ التسجيل بالمنصة"),
                        value: formattedFullDate(created),
                        canCopy: false
                    )
                }

                if let updated = vet.updatedAt {
                    auditRow(
                        label: Language.get("Vet_Last_Updated", alter: "آخر تحديث للبيانات"),
                        value: formattedFullDate(updated),
                        canCopy: false
                    )
                }
            }
            .padding(12)
            .background(AdminSurface.fieldBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func auditRow(label: String, value: String, canCopy: Bool) -> some View {
        HStack {
            Text(label)
                .font(AdminType.caption)
                .foregroundStyle(AdminCommandInk.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AdminSurface.primaryText)
                .lineLimit(1)

            if canCopy {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    UIPasteboard.general.string = value
                    triggerToast(Language.get("Vet_ID_Copied", alter: "تم نسخ المعرف السحابي"))
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(primaryAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Danger Zone Card

    private var dangerZoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AdminSurface.crimson)
                Text(Language.get("Vet_Danger_Zone", alter: "إجراءات الحذف النهائي"))
                    .font(.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.crimson)
                Spacer()
            }

            Text(Language.get("Vet_Delete_Warning", alter: "سيؤدي حذف هذا السجل إلى إزالته نهائياً من قاعدة البيانات وإلغاء ترخيص الطبيب فوراً."))
                .font(AdminType.caption)
                .foregroundStyle(AdminCommandInk.secondary)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if isDeleting {
                        ProgressView().tint(AdminSurface.crimson)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14))
                    }
                    Text(Language.get("Vet_Delete_Action", alter: "حذف السجل البيطري بشكل نهائي"))
                        .font(.custom("Beiruti-Bold", size: 15))
                }
                .foregroundStyle(AdminSurface.crimson)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(AdminSurface.crimson.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.crimson.opacity(0.25), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .padding(14)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.crimson.opacity(0.25), lineWidth: 0.8)
        )
    }

    // MARK: - Operations

    private func toggleLicenseStatus() {
        let newDisabled = !vet.isDisabled
        isTogglingStatus = true
        PPVetManager.shared().setDisabled(newDisabled, forVetID: vet.vetID) { error in
            DispatchQueue.main.async {
                self.isTogglingStatus = false
                if error == nil {
                    self.vet.isDisabled = newDisabled
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.onUpdated?(self.vet)
                    self.triggerToast(newDisabled
                                 ? Language.get("Vet_Suspended_Notice", alter: "تم تعليق الترخيص مؤقتاً")
                                 : Language.get("Vet_Activated_Notice", alter: "تم تفعيل الترخيص واعتماد الكيان"))
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        PPVetManager.shared().deleteVet(vet) { error in
            DispatchQueue.main.async {
                self.isDeleting = false
                if error == nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.onUpdated?(self.vet)
                    self.onDismiss()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - UIKit Hosting Controller Bridge

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
