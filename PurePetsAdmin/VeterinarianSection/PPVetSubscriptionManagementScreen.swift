//
//  PPVetSubscriptionManagementScreen.swift
//  PurePetsAdmin
//
//  First-Principles Invention: Category-Defining Sovereign Tier & Subscription Control Tower.
//  Reinvented from absolute first principles in SwiftUI with holographic tier selection,
//  vital duration accelerators, subscription health horizon dials, and instant Firestore sync.
//

import SwiftUI
import UIKit

// MARK: - Sovereign Subscription Management Screen

@MainActor
public struct PPVetSubscriptionManagementScreen: View {
    @State private var vet: PPVetModel
    private let onDismiss: () -> Void
    private let onSaved: (PPVetModel) -> Void

    @State private var selectedTier: PPVetSubscriptionTier
    @State private var subscriptionActive: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSuccessHUD: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    public init(
        vet: PPVetModel,
        onDismiss: @escaping () -> Void,
        onSaved: @escaping (PPVetModel) -> Void
    ) {
        _vet = State(initialValue: vet)
        self.onDismiss = onDismiss
        self.onSaved = onSaved

        _selectedTier = State(initialValue: vet.subscriptionTier)
        _subscriptionActive = State(initialValue: vet.subscriptionActive)
        _startDate = State(initialValue: vet.subscriptionStartDate ?? Date())
        _endDate = State(initialValue: vet.subscriptionEndDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
    }

    private var isExpired: Bool {
        endDate.compare(Date()) == .orderedAscending
    }

    private var daysRemaining: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: start, to: end)
        return components.day ?? 0
    }

    private var primaryAccent: Color {
        switch selectedTier {
        case .free: return Color(red: 0.50, green: 0.55, blue: 0.60)
        case .basic: return Color(red: 0.12, green: 0.68, blue: 0.88)
        case .premium: return Color(red: 0.95, green: 0.65, blue: 0.15)
        @unknown default: return Color.accentColor
        }
    }

    public var body: some View {
        ZStack {
            // Background
            AdminSurface.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sovereign Navigation Bar
                navigationHeader

                // Scrollable Content
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Error Banner
                        if let err = errorMessage {
                            errorBanner(err)
                        }

                        // Subscription Health Horizon Hero Card
                        subscriptionHealthCard

                        // Holographic Tier Selection Deck
                        tierSelectionDeck

                        // Quick Duration Accelerators (+1M, +3M, +6M, +1Y)
                        durationAcceleratorsCard

                        // Precise Dates & Toggle Settings
                        lifecycleDatesCard

                        // Privileges Matrix Breakdown
                        tierPrivilegesMatrixCard

                        // Save Trigger
                        saveTriggerCard

                        // Bottom Spacing
                        Color.clear.frame(height: 36)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }

            // Saving HUD Overlay
            if isSaving {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(.white)
                        Text(Language.get("Vet_Updating", alter: "جارٍ تحديث وتفعيل الباقة..."))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Vet_Subscription", alter: "إدارة باقة الاشتراك"),
            subtitle: vet.title,
            isModal: true,
            onBack: onDismiss
        ) {
            Button {
                saveAction()
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 36, height: 36)
                        .background(primaryAccent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(primaryAccent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .accessibilityLabel(Language.get("Save", alter: "حفظ"))
        }
    }

    // MARK: - Subscription Health Horizon Hero Card

    private var subscriptionHealthCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                // Tier Icon Orb
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: tierGradientColors(for: selectedTier),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: primaryAccent.opacity(0.35), radius: 8, x: 0, y: 3)

                    Image(systemName: tierIcon(for: selectedTier))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tierTitle(for: selectedTier))
                            .font(.custom("Beiruti-Bold", size: 20))
                            .foregroundStyle(AdminSurface.primaryText)

                        // Status Pill
                        HStack(spacing: 4) {
                            Circle()
                                .fill(subscriptionActive && !isExpired ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.92, green: 0.35, blue: 0.28))
                                .frame(width: 6, height: 6)
                            Text(subscriptionActive ? (!isExpired ? Language.get("Vet_Sub_Active", alter: "نشطة") : Language.get("Vet_Sub_Expired", alter: "منتهية")) : Language.get("Disabled", alter: "معطلة"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(subscriptionActive && !isExpired ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.92, green: 0.35, blue: 0.28))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((subscriptionActive && !isExpired ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.92, green: 0.35, blue: 0.28)).opacity(0.12), in: Capsule())
                    }

                    // Remaining Days Meter
                    if isExpired {
                        Text(Language.get("Vet_Sub_Expired_Notice", alter: "انتهت فترة الاشتراك الحالية، يُرجى التجديد لتفعيل المزايا"))
                            .font(AdminType.caption2)
                            .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.28))
                    } else {
                        Text(String(format: Language.get("Vet_Sub_DaysRemaining_Format", alter: "متبقي %ld يوماً في دورة الاشتراك الحالية"), max(daysRemaining, 0)))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer(minLength: 0)
            }

            Divider()
                .overlay(AdminSurface.hairline)

            // Timeline Metric Bar
            HStack(spacing: 8) {
                timelineMetric(
                    title: Language.get("StartDate", alter: "تاريخ البدء"),
                    value: formattedDate(startDate)
                )

                Spacer()

                timelineMetric(
                    title: Language.get("Vet_Sub_EndDate", alter: "تاريخ الانتهاء"),
                    value: formattedDate(endDate),
                    highlight: isExpired ? Color(red: 0.92, green: 0.35, blue: 0.28) : nil
                )
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

    private func timelineMetric(title: String, value: String, highlight: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AdminType.caption2)
                .foregroundStyle(AdminSurface.secondaryText)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ?? AdminSurface.primaryText)
        }
    }

    // MARK: - Holographic Tier Selection Deck

    private var tierSelectionDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Language.get("Vet_Select_Tier_Title", alter: "اختر مستوى وباقة الاشتراك"))
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.secondaryText)

            VStack(spacing: 10) {
                // Tier 1: Free
                tierCardRow(
                    tier: .free,
                    title: Language.get("Vet_Sub_Free", alter: "الباقة المجانية"),
                    tagline: Language.get("Vet_Tier_Free_Tag", alter: "ظهور أساسي مجاني في نتائج البحث"),
                    icon: "checkmark.circle",
                    colors: [Color(red: 0.50, green: 0.55, blue: 0.60), Color(red: 0.38, green: 0.42, blue: 0.46)]
                )

                // Tier 2: Basic
                tierCardRow(
                    tier: .basic,
                    title: Language.get("Vet_Sub_Basic", alter: "الباقة الاحترافية (Basic)"),
                    tagline: Language.get("Vet_Tier_Basic_Tag", alter: "شارة توثيق + أولوية بحث + أزرار التواصل المباشر"),
                    icon: "checkmark.seal.fill",
                    colors: [Color(red: 0.12, green: 0.68, blue: 0.88), Color(red: 0.06, green: 0.52, blue: 0.78)]
                )

                // Tier 3: Premium VIP
                tierCardRow(
                    tier: .premium,
                    title: Language.get("Vet_Sub_Premium", alter: "باقة النخبة المميزة (VIP)"),
                    tagline: Language.get("Vet_Tier_Premium_Tag", alter: "شارة ذهبية + تصدر النتائج + بانر الشاشة الرئيسية"),
                    icon: "crown.fill",
                    colors: [Color(red: 0.95, green: 0.65, blue: 0.15), Color(red: 0.90, green: 0.45, blue: 0.10)]
                )
            }
        }
    }

    private func tierCardRow(
        tier: PPVetSubscriptionTier,
        title: String,
        tagline: String,
        icon: String,
        colors: [Color]
    ) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                selectedTier = tier
            }
        } label: {
            HStack(spacing: 12) {
                // Tier Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Beiruti-Bold", size: 17))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(tagline)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                // Selection Radio Ring
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? colors[0] : AdminSurface.hairline, lineWidth: isSelected ? 2 : 1)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(colors[0])
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(14)
            .background(
                isSelected ? colors[0].opacity(0.08) : AdminSurface.surface,
                in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                    .strokeBorder(isSelected ? colors[0] : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Duration Accelerators

    private var durationAcceleratorsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("Vet_Quick_Extend_Title", alter: "تمديد سريع لمدة الاشتراك"))
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.secondaryText)

            HStack(spacing: 8) {
                acceleratorChip(label: "+ 1 شهر", months: 1)
                acceleratorChip(label: "+ 3 أشهر", months: 3)
                acceleratorChip(label: "+ 6 أشهر", months: 6)
                acceleratorChip(label: "+ 1 سنة", months: 12)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func acceleratorChip(label: String, months: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let baseDate = isExpired ? Date() : endDate
            if let newEnd = Calendar.current.date(byAdding: .month, value: months, to: baseDate) {
                withAnimation {
                    endDate = newEnd
                    subscriptionActive = true
                }
            }
        } label: {
            Text(label)
                .font(AdminType.caption1Bold)
                .foregroundStyle(primaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(primaryAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lifecycle Dates & Toggle Settings

    private var lifecycleDatesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primaryAccent)
                Text(Language.get("SubscriptionSettings", alter: "تواريخ وضوابط الاشتراك"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
            }

            // Subscription Active Switch
            Toggle(isOn: $subscriptionActive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionActive ? Language.get("Vet_Sub_Active_Toggle", alter: "الاشتراك نشط ومفعّل") : Language.get("Vet_Sub_Inactive_Toggle", alter: "الاشتراك معطّل مؤقتاً"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(subscriptionActive ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.92, green: 0.35, blue: 0.28))
                    Text(Language.get("Vet_Sub_Active_Sub", alter: "التحكم في سريان صلاحيات الباقة ومزايا الظهور"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .tint(Color(red: 0.16, green: 0.78, blue: 0.48))

            Divider()
                .overlay(AdminSurface.hairline)

            // Start Date Picker
            DatePicker(
                Language.get("StartDate", alter: "تاريخ بدء الاشتراك"),
                selection: $startDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)

            Divider()
                .overlay(AdminSurface.hairline)

            // End Date Picker
            DatePicker(
                Language.get("Vet_Sub_EndDate", alter: "تاريخ انتهاء الصلاحية"),
                selection: $endDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Privileges Matrix Breakdown

    private var tierPrivilegesMatrixCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(primaryAccent)
                Text(Language.get("Vet_Privileges_Title", alter: "المزايا الممنوحة لهذه الباقة"))
                    .font(AdminType.subheadlineBold)
                    .foregroundStyle(AdminSurface.primaryText)
            }

            VStack(spacing: 8) {
                privilegeRow(text: "إدراج وتوثيق في دليل الأطباء والعيادات", enabled: true)
                privilegeRow(text: "أزرار الاتصال الهاتفي والمحادثة المباشرة", enabled: selectedTier != .free)
                privilegeRow(text: "شارة التحقق والاعتماد الطبي الرسمي", enabled: selectedTier != .free)
                privilegeRow(text: "أولوية الترتيب في نتائج البحث والتصفية", enabled: selectedTier == .premium)
                privilegeRow(text: "تثبيت في الواجهة الرئيسية واستشارات الطوارئ", enabled: selectedTier == .premium)
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private func privilegeRow(text: String, enabled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? Color(red: 0.16, green: 0.78, blue: 0.48) : AdminSurface.secondaryText.opacity(0.4))

            Text(text)
                .font(AdminType.caption1)
                .foregroundStyle(enabled ? AdminSurface.primaryText : AdminSurface.secondaryText.opacity(0.6))

            Spacer()
        }
    }

    // MARK: - Save Trigger Card

    private var saveTriggerCard: some View {
        Button {
            saveAction()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(Language.get("Vet_Save_Subscription", alter: "اعتماد وتحديث باقة الاشتراك"))
                    .font(AdminType.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: tierGradientColors(for: selectedTier),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: primaryAccent.opacity(0.3), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    // MARK: - Helpers

    private func tierGradientColors(for tier: PPVetSubscriptionTier) -> [Color] {
        switch tier {
        case .free:
            return [Color(red: 0.50, green: 0.55, blue: 0.60), Color(red: 0.38, green: 0.42, blue: 0.46)]
        case .basic:
            return [Color(red: 0.12, green: 0.68, blue: 0.88), Color(red: 0.06, green: 0.52, blue: 0.78)]
        case .premium:
            return [Color(red: 0.95, green: 0.65, blue: 0.15), Color(red: 0.90, green: 0.45, blue: 0.10)]
        @unknown default:
            return [Color.gray, Color.black]
        }
    }

    private func tierIcon(for tier: PPVetSubscriptionTier) -> String {
        switch tier {
        case .free: return "checkmark.circle"
        case .basic: return "checkmark.seal.fill"
        case .premium: return "crown.fill"
        @unknown default: return "circle"
        }
    }

    private func tierTitle(for tier: PPVetSubscriptionTier) -> String {
        switch tier {
        case .free: return Language.get("Vet_Sub_Free", alter: "الباقة المجانية")
        case .basic: return Language.get("Vet_Sub_Basic", alter: "الباقة الأساسية")
        case .premium: return Language.get("Vet_Sub_Premium", alter: "باقة النخبة المميزة")
        @unknown default: return ""
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode())
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.28))
            Text(message)
                .font(AdminType.caption1Bold)
                .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.28))
            Spacer()
        }
        .padding(12)
        .background(Color(red: 0.92, green: 0.35, blue: 0.28).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func saveAction() {
        let vetID = vet.vetID
        guard !vetID.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        errorMessage = nil
        isSaving = true

        PPVetManager.shared().updateSubscription(
            forVetID: vetID,
            tier: selectedTier.rawValue,
            active: subscriptionActive,
            startDate: startDate,
            endDate: endDate
        ) { error in
            isSaving = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                vet.subscriptionTier = selectedTier
                vet.subscriptionActive = subscriptionActive
                vet.subscriptionStartDate = startDate
                vet.subscriptionEndDate = endDate
                onSaved(vet)
                onDismiss()
            }
        }
    }
}

// MARK: - Hosting Controller Bridge (for UIKit push/present)

@objc(PPVetSubscriptionHostingController)
public class PPVetSubscriptionHostingController: UIViewController {
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

        let swiftUIView = PPVetSubscriptionManagementScreen(
            vet: vet,
            onDismiss: { [weak self] in
                if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true)
                }
            },
            onSaved: { _ in }
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
