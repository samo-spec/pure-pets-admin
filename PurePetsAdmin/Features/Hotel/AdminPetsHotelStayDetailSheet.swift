//
//  AdminPetsHotelStayDetailSheet.swift
//  PurePetsAdmin
//
//  Category-defining guest dossier and stay flight deck for Pets Hotel.
//  Reinvented from absolute first principles for iPhone and iPad separately.
//  Strictly governed by Beiruti (PPBrandFont) typography across all states.
//

import SwiftUI
import UIKit

// MARK: - Master Container with Device-Idiom Specialization
public struct AdminPetsHotelStayDetailSheet: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    public var isPushMode: Bool = true
    public var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isLoadingDossier: Bool = false
    @State private var toastMessage: String? = nil
    @State private var selectedCareFilter: CareFilter = .all

    public init(
        stay: AdminHotelStay,
        viewModel: AdminPetsHotelViewModel,
        isPushMode: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        self.stay = stay
        self.viewModel = viewModel
        self.isPushMode = isPushMode
        self.onBack = onBack
    }

    private var activeStay: AdminHotelStay {
        if let current = viewModel.selectedStayDetail, current.id == stay.id {
            return current
        }
        return stay
    }

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    public var body: some View {
        ZStack {
            // Edge-to-Edge Adaptive Background
            AdminSurface.background
                .ignoresSafeArea()

            // Device-Idiom Root View
            Group {
                if isPad {
                    iPadPetsHotelStayCockpit(
                        activeStay: activeStay,
                        viewModel: viewModel,
                        isPushMode: isPushMode,
                        isLoading: isLoadingDossier,
                        selectedCareFilter: $selectedCareFilter,
                        onBack: handleDismiss,
                        onRefresh: reloadDossier,
                        onCopy: showToast
                    )
                } else {
                    iPhonePetsHotelStayDeck(
                        activeStay: activeStay,
                        viewModel: viewModel,
                        isPushMode: isPushMode,
                        isLoading: isLoadingDossier,
                        selectedCareFilter: $selectedCareFilter,
                        onBack: handleDismiss,
                        onRefresh: reloadDossier,
                        onCopy: showToast
                    )
                }
            }

            // High-Craft Toast Notification Capsule
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        Text(toast)
                            .font(PPBrandFont.bold(size: 13.5))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(AdminSurface.control)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 12, y: 5)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.6), lineWidth: 0.8)
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, isPad ? 36 : 90)
                }
                .zIndex(100)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .task {
            if viewModel.canViewCare {
                await reloadDossier()
            }
        }
    }

    private func handleDismiss() {
        if let onBack = onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func reloadDossier() {
        Task {
            isLoadingDossier = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await viewModel.loadStayDossier(stayId: stay.id, updatePresentedDetail: true)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isLoadingDossier = false
            }
        }
    }

    private func showToast(_ text: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.25)) {
                if toastMessage == text {
                    toastMessage = nil
                }
            }
        }
    }
}

// MARK: - Care Filter Segment
public enum CareFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case pending = "pending"
    case completed = "completed"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return Language.get("Common_All", alter: "الكل")
        case .pending: return Language.get("Hotel_Task_Pending", alter: "المتبقية")
        case .completed: return Language.get("Hotel_Task_Completed", alter: "المكتملة")
        }
    }
}

// =================================================================
// MARK: - Category-Defining Pet Category & Species Pill
// =================================================================

public struct AdminPetCategoryPill: View {
    public enum Mode {
        case hero       // Prominent, multi-horizon taxonomy card presentation
        case compact    // Inline chip for lists, tables and summary bars
        case filter(isSelected: Bool) // Dynamic filter pill with glowing ring and tactile selection
    }

    public let species: String
    public let breed: String
    public let wing: HotelWing
    public var mode: Mode
    public var onSelect: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed: Bool = false

    public init(
        species: String,
        breed: String = "",
        wing: HotelWing,
        mode: Mode = .hero,
        onSelect: (() -> Void)? = nil
    ) {
        self.species = species
        self.breed = breed
        self.wing = wing
        self.mode = mode
        self.onSelect = onSelect
    }

    public var resolvedSpeciesText: String {
        let s = species.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "cat" || s == "قط" || s == "قطة" || s == "cats" {
            return Language.get("Pet_Cat", alter: "قط")
        } else if s == "dog" || s == "كلب" || s == "dogs" {
            return Language.get("Pet_Dog", alter: "كلب")
        } else if s == "bird" || s == "طير" || s == "طائر" || s == "birds" {
            return Language.get("Pet_Bird", alter: "طائر")
        } else if s == "rabbit" || s == "أرنب" || s == "rabbits" {
            return Language.get("Pet_Rabbit", alter: "أرنب")
        }
        return species.isEmpty ? wing.title : species
    }

    public var resolvedSpeciesIcon: String {
        let s = species.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.contains("cat") || s.contains("قط") { return "cat.fill" }
        if s.contains("dog") || s.contains("كلب") { return "dog.fill" }
        if s.contains("bird") || s.contains("طير") || s.contains("طائر") { return "bird.fill" }
        if s.contains("rabbit") || s.contains("أرنب") || s.contains("hare") { return "hare.fill" }
        return wing.icon
    }

    public var cleanBreedText: String {
        breed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var speciesTint: Color {
        wing.tint
    }

    public var body: some View {
        Group {
            switch mode {
            case .hero:
                heroPillView
            case .compact:
                compactPillView
            case .filter(let isSelected):
                filterPillView(isSelected: isSelected)
            }
        }
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isPressed)
    }

    // MARK: - 1. Hero Mode (Multi-Horizon Taxonomic Specimen Capsule)
    @ViewBuilder
    private var heroPillView: some View {
        HStack(spacing: 6) {
            // Micro-Jewel Lens
            ZStack {
                Circle()
                    .fill(speciesTint.opacity(colorScheme == .dark ? 0.32 : 0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: resolvedSpeciesIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(speciesTint)
            }

            // Primary Taxonomic Species Horizon
            Text(resolvedSpeciesText)
                .font(PPBrandFont.bold(size: 12))
                .foregroundStyle(AdminSurface.primaryText)

            // Dynamic Breed Horizon (if present)
            if !cleanBreedText.isEmpty {
                Circle()
                    .fill(speciesTint.opacity(0.65))
                    .frame(width: 3.5, height: 3.5)

                Text(cleanBreedText)
                    .font(PPBrandFont.medium(size: 12))
                    .foregroundStyle(AdminSurface.primaryText.opacity(0.88))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            speciesTint.opacity(colorScheme == .dark ? 0.22 : 0.12),
                            speciesTint.opacity(colorScheme == .dark ? 0.10 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            speciesTint.opacity(0.48),
                            speciesTint.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: speciesTint.opacity(colorScheme == .dark ? 0.25 : 0.07), radius: 4, y: 1.5)
    }

    // MARK: - 2. Compact Mode (Inline Taxonomy Tag)
    @ViewBuilder
    private var compactPillView: some View {
        HStack(spacing: 4.5) {
            Image(systemName: resolvedSpeciesIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(speciesTint)

            Text(cleanBreedText.isEmpty ? resolvedSpeciesText : "\(resolvedSpeciesText) • \(cleanBreedText)")
                .font(PPBrandFont.bold(size: 11))
                .foregroundStyle(AdminSurface.primaryText)
        }
        .padding(.horizontal, 7.5)
        .padding(.vertical, 3.5)
        .background(speciesTint.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(speciesTint.opacity(0.32), lineWidth: 0.8)
        )
    }

    // MARK: - 3. Filter Mode (Tactile Interactive Multi-Deck Pill)
    @ViewBuilder
    private func filterPillView(isSelected: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect?()
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.24) : speciesTint.opacity(0.14))
                        .frame(width: 20, height: 20)
                    Image(systemName: resolvedSpeciesIcon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : speciesTint)
                }

                Text(wing.title)
                    .font(PPBrandFont.bold(size: 12.5))
                    .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? speciesTint : AdminSurface.control)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? speciesTint.opacity(0.85) : Color(uiColor: .ppSurfaceBorder).opacity(0.55),
                        lineWidth: isSelected ? 1.2 : 0.8
                    )
            )
            .shadow(
                color: isSelected ? speciesTint.opacity(0.36) : Color.black.opacity(colorScheme == .dark ? 0.2 : 0.03),
                radius: isSelected ? 6 : 2,
                y: isSelected ? 3 : 1
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// =================================================================
// MARK: - 1. iPhone Architecture (`iPhonePetsHotelStayDeck`)
// =================================================================

private struct iPhonePetsHotelStayDeck: View {
    let activeStay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    let isPushMode: Bool
    let isLoading: Bool
    @Binding var selectedCareFilter: CareFilter
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isStayCopied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Apex Navigation Bar
            iPhoneNavigationBar

            // Main Scrollable Dossier Deck
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Species Aura Hero Deck
                    iPhoneSpeciesHeroDeck

                    // Clinical & Special Attention Alert (Conditional)
                    if activeStay.guestStatus != .normal || (activeStay.internalNotes?.isEmpty == false) {
                        clinicalAttentionAlertCard
                    }

                    // Twin Horizon Pillars: Room & Stay Period
                    twinHorizonPillars

                    // Financial Ledger Pill (Gated)
                    if viewModel.canViewBilling && activeStay.grandTotalMinor > 0 {
                        financialLedgerCard
                    }

                    // Daily Care Tasks & Routine (Gated)
                    if viewModel.canViewCare {
                        dailyCareTasksCard
                    }

                    // Belongings & Valuables Inventory (Gated)
                    if viewModel.canViewCare {
                        belongingsInventoryCard
                    }

                    // Pet Owner Contact Flight Deck
                    ownerContactStation

                    // Extra space for the sticky bottom action dock
                    Spacer(minLength: 88)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }

            // Floating Sticky Action Dock (Thumb Zone)
            iPhoneStickyActionDock
        }
    }

    // MARK: - iPhone Top Navigation Bar
    private var iPhoneNavigationBar: some View {
        AdminSovereignNavigationBar(
            title: activeStay.petName,
            subtitle: "\(activeStay.wing.title) • \(activeStay.roomNumber)",
            statusDotColor: activeStay.guestStatus.color,
            isModal: !isPushMode,
            customTopSpacing: 0,
            onBack: onBack
        ) {
            HStack(spacing: 8) {
                // Refresh Button
                Button {
                    onRefresh()
                } label: {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.control)
                            .frame(width: 34, height: 34)
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.primaryText)
                            .rotationEffect(.degrees(isLoading ? 360 : 0))
                            .animation(isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                // Status Capsule with Pulse
                HStack(spacing: 5) {
                    Circle()
                        .fill(activeStay.guestStatus.color)
                        .frame(width: 6, height: 6)
                    Text(activeStay.guestStatus.title)
                        .font(PPBrandFont.bold(size: 12))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(activeStay.guestStatus.color.opacity(0.14), in: Capsule())
                .foregroundStyle(activeStay.guestStatus.color)
            }
        }
    }

    // MARK: - iPhone Species Aura Hero Deck (Reinvented Living Category Sanctuary)
    private var iPhoneSpeciesHeroDeck: some View {
        HStack(spacing: 14) {
            // 1. Living Specimen Emblem (Pet Avatar & Status Pulse Gem)
            ZStack(alignment: .bottomTrailing) {
                // Ambient Radial Glow Backdrop
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [activeStay.wing.tint.opacity(0.32), Color.clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 44
                        )
                    )
                    .frame(width: 82, height: 82)
                    .blur(radius: 6)

                // Sculpted Frosted Squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    activeStay.wing.tint.opacity(colorScheme == .dark ? 0.28 : 0.16),
                                    activeStay.wing.tint.opacity(colorScheme == .dark ? 0.14 : 0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            activeStay.wing.tint.opacity(0.55),
                                            activeStay.wing.tint.opacity(0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        )
                        .shadow(color: activeStay.wing.tint.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 8, y: 3)

                    // Species / Wing Glyph with micro-gradient
                    Image(systemName: activeStay.wing.icon)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [activeStay.wing.tint, activeStay.wing.tint.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                // Active Stay Living Status Gem
                ZStack {
                    Circle()
                        .fill(AdminSurface.card)
                        .frame(width: 20, height: 20)
                        .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)

                    Circle()
                        .fill(activeStay.guestStatus.color)
                        .frame(width: 12, height: 12)

                    Circle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 4, height: 4)
                        .offset(x: -2, y: -2)
                }
                .offset(x: 3, y: 3)
            }

            // 2. Pet Identity, Category Pill & Stay Reference Token
            VStack(alignment: .leading, spacing: 6) {
                // Pet Name Headline
                Text(activeStay.petName)
                    .font(PPBrandFont.bold(size: 23))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)

                // Reinvented Pet Category & Breed Pill
                AdminPetCategoryPill(
                    species: activeStay.petSpecies,
                    breed: activeStay.petBreed,
                    wing: activeStay.wing,
                    mode: .hero
                )

                // Dossier Stay Identifier with Interactive Haptic Copy
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    UIPasteboard.general.string = resolvedStayNumber
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isStayCopied = true
                    }
                    onCopy(Language.get("Hotel_StayCopied", alter: "تم نسخ رقم الإقامة"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isStayCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isStayCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)

                        Text(Language.get("Hotel_StayNo", alter: "رقم الإقامة:"))
                            .font(PPBrandFont.medium(size: 11.5))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(resolvedStayNumber)
                            .font(PPBrandFont.bold(size: 11.5))
                            .foregroundStyle(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.primary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.12) : AdminSurface.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.3) : Color(uiColor: .ppSurfaceBorder).opacity(0.4), lineWidth: 0.7)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer(minLength: 4)

            // 3. Habitat & Room Quick Glance Dock (Eliminates the Dead Space!)
            VStack(alignment: .trailing, spacing: 5) {
                // Wing Habitat Badge
                HStack(spacing: 4) {
                    Image(systemName: activeStay.wing.icon)
                        .font(.system(size: 9.5, weight: .bold))
                    Text(activeStay.wing.title)
                        .font(PPBrandFont.bold(size: 11))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(activeStay.wing.tint.opacity(0.14), in: Capsule())
                .foregroundStyle(activeStay.wing.tint)

                // Room / Suite Key
                HStack(spacing: 4) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("\(Language.get("Hotel_Suite", alter: "جناح")) \(activeStay.roomNumber)")
                        .font(PPBrandFont.bold(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AdminSurface.surface, in: Capsule())
                .foregroundStyle(AdminSurface.secondaryText)
                .overlay(
                    Capsule()
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.7)
                )
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AdminSurface.control)

                // Ambient chromatic species glow in corner
                GeometryReader { proxy in
                    RadialGradient(
                        colors: [activeStay.wing.tint.opacity(0.08), Color.clear],
                        center: Language.isRTL() ? .topLeading : .topTrailing,
                        startRadius: 10,
                        endRadius: proxy.size.width * 0.75
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.04), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .ppSurfaceBorder).opacity(0.7),
                            activeStay.wing.tint.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
    }

    // MARK: - Clinical Attention Banner
    private var clinicalAttentionAlertCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(activeStay.guestStatus.color.opacity(0.2))
                    .frame(width: 36, height: 36)
                Image(systemName: activeStay.guestStatus.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(activeStay.guestStatus.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Hotel_Special_Attention", alter: "عناية خاصة وملاحظات طبية"))
                    .font(PPBrandFont.bold(size: 14.5))
                    .foregroundStyle(activeStay.guestStatus.color)

                if let notes = activeStay.internalNotes, !notes.isEmpty {
                    Text(notes)
                        .font(PPBrandFont.regular(size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(activeStay.guestStatus.title)
                        .font(PPBrandFont.regular(size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            activeStay.guestStatus.color.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(activeStay.guestStatus.color.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Twin Horizon Pillars
    private var twinHorizonPillars: some View {
        HStack(spacing: 12) {
            // Room Pillar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(activeStay.wing.tint)
                    Text(Language.get("Hotel_AssignedRoom", alter: "الغرفة المخصصة"))
                        .font(PPBrandFont.medium(size: 12.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Text(activeStay.roomNumber)
                    .font(PPBrandFont.bold(size: 24))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(activeStay.wing.title)
                    .font(PPBrandFont.bold(size: 12))
                    .foregroundStyle(activeStay.wing.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
            )

            // Horizon / Duration Pillar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_StayPeriod", alter: "فترة الإقامة"))
                        .font(PPBrandFont.medium(size: 12.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Text(formatDateRange(from: activeStay.checkInTime, to: activeStay.expectedCheckOutTime))
                    .font(PPBrandFont.bold(size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                // Stay Progress Track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdminSurface.surface)
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [AdminSurface.primary, Color(red: 0.16, green: 0.72, blue: 0.44)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geo.size.width * CGFloat(activeStay.stayProgress), geo.size.width)), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
            )
        }
    }

    // MARK: - Financial Ledger Card
    private var financialLedgerCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("Hotel_Ledger_Total", alter: "إجمالي الحساب:"))
                    .font(PPBrandFont.medium(size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(String(format: "%.2f %@", Double(activeStay.grandTotalMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                    .font(PPBrandFont.bold(size: 17))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(Language.get("Hotel_Ledger_Balance", alter: "المتبقي للدفع:"))
                    .font(PPBrandFont.medium(size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(String(format: "%.2f %@", Double(activeStay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                    .font(PPBrandFont.bold(size: 17))
                    .foregroundStyle(activeStay.outstandingMinor > 0 ? Color.orange : Color(red: 0.16, green: 0.72, blue: 0.44))
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
        )
    }

    // MARK: - Care Schedule & Daily Tasks
    private var dailyCareTasksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with completion fraction
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_CareSchedule", alter: "جدول الرعاية والمهام اليومية"))
                        .font(PPBrandFont.bold(size: 15.5))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                Text("\(activeStay.dailyCareTasks.filter { $0.isCompleted }.count)/\(activeStay.dailyCareTasks.count)")
                    .font(PPBrandFont.bold(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.surface, in: Capsule())
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            if activeStay.dailyCareTasks.isEmpty {
                // Category-defining empty state
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(AdminSurface.primary.opacity(0.6))
                    Text(Language.get("Hotel_NoTasksScheduled", alter: "لا توجد مهام رعاية متبقية لهذا النزيل"))
                        .font(PPBrandFont.bold(size: 13.5))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Hotel_StandardCareActive", alter: "يتلقى النزيل بروتوكول الرعاية المعياري المعتمد للجناح"))
                        .font(PPBrandFont.regular(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(activeStay.dailyCareTasks) { task in
                        careTaskRow(task: task)
                    }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
                )
            }
        }
    }

    private func careTaskRow(task: AdminHotelCareTask) -> some View {
        Button {
            viewModel.toggleCareTask(stay: activeStay, task: task)
        } label: {
            HStack(spacing: 12) {
                // Status Check Ring
                ZStack {
                    Circle()
                        .strokeBorder(
                            task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color.gray.opacity(0.4),
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)

                    if task.isCompleted {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.72, blue: 0.44))
                            .frame(width: 12, height: 12)
                    }
                }

                // Task Type Icon
                Image(systemName: task.taskType.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.primary)

                // Task Details
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.taskType.title)
                        .strikethrough(task.isCompleted)
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primaryText)

                    if let by = task.completedByStaffName, task.isCompleted {
                        Text("\(Language.get("Hotel_CompletedBy", alter: "بواسطة:")) \(by)")
                            .font(PPBrandFont.regular(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                // Scheduled Time
                Text(task.scheduledTime)
                    .font(PPBrandFont.bold(size: 12))
                    .foregroundStyle(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!viewModel.canTransitionCareTask(task))
    }

    // MARK: - Belongings Inventory
    private var belongingsInventoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_BelongingsInventory", alter: "مقتنيات وأغراض النزيل"))
                        .font(PPBrandFont.bold(size: 15.5))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                Text("\(activeStay.belongings.count)")
                    .font(PPBrandFont.bold(size: 13))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AdminSurface.surface, in: Capsule())
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            if activeStay.belongings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                    Text(Language.get("Hotel_NoBelongings", alter: "لا توجد أغراض شخصية مسجلة عند الدخول"))
                        .font(PPBrandFont.medium(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(activeStay.belongings) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))

                            Text(item.name)
                                .font(PPBrandFont.medium(size: 14))
                                .foregroundStyle(AdminSurface.primaryText)

                            Spacer()

                            Text("x\(item.quantity)")
                                .font(PPBrandFont.bold(size: 13))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(AdminSurface.control, in: Capsule())
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
                )
            }
        }
    }

    // MARK: - Owner Contact Station
    private var ownerContactStation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_PetOwner", alter: "بيانات مالك الحيوان"))
                    .font(PPBrandFont.bold(size: 15.5))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ownerDisplayName)
                        .font(PPBrandFont.bold(size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(ownerDisplayPhone)
                        .font(PPBrandFont.bold(size: 13.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                if hasValidOwnerPhone {
                    // Call Button
                    if let callURL = URL(string: "tel:\(cleanPhoneNumber)") {
                        Button {
                            UIApplication.shared.open(callURL)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.16))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // WhatsApp Button with World-Class Stay Context
                    Button {
                        PetsHotelWhatsAppDispatcher.openChat(
                            for: activeStay,
                            ownerDisplayName: ownerDisplayName,
                            resolvedStayNumber: resolvedStayNumber,
                            cleanPhoneNumber: cleanPhoneNumber,
                            canViewBilling: viewModel.canViewBilling,
                            formatDateRange: { from, to in formatDateRange(from: from, to: to) }
                        )
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.18, green: 0.80, blue: 0.44).opacity(0.16))
                                .frame(width: 42, height: 42)
                            Image("whatsapp")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundStyle(Color(red: 0.18, green: 0.80, blue: 0.44))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
            )
        }
    }

    // MARK: - iPhone Sticky Action Dock
    private var iPhoneStickyActionDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(uiColor: .ppSurfaceBorder).opacity(0.6))

            HStack {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.checkOutModalStay = activeStay
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Language.isRTL() ? "arrow.left.to.line" : "arrow.right.to.line")
                            .font(.system(size: 15, weight: .bold))
                        Text(Language.get("Hotel_Execute_Checkout", alter: "تسجيل المغادرة وتسليم النزيل"))
                            .font(PPBrandFont.bold(size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.84, green: 0.15, blue: 0.35), Color(red: 0.72, green: 0.10, blue: 0.28)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.84, green: 0.15, blue: 0.35).opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!viewModel.canCheckOut)
                .opacity(viewModel.canCheckOut ? 1 : 0.45)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(
            AdminSurface.control
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 14, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Helpers
    private var petBreedSpeciesText: String {
        let breed = activeStay.petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        let species = localizedSpeciesText(activeStay.petSpecies)
        if !breed.isEmpty && !species.isEmpty {
            return "\(species) • \(breed)"
        } else if !species.isEmpty {
            return species
        } else if !breed.isEmpty {
            return breed
        }
        return ""
    }

    private func localizedSpeciesText(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "cat" || s == "قط" || s == "قطة" || s == "cats" {
            return Language.get("Pet_Cat", alter: "قط")
        } else if s == "dog" || s == "كلب" || s == "dogs" {
            return Language.get("Pet_Dog", alter: "كلب")
        } else if s == "bird" || s == "طير" || s == "طائر" || s == "birds" {
            return Language.get("Pet_Bird", alter: "طائر")
        } else if s == "rabbit" || s == "أرنب" || s == "rabbits" {
            return Language.get("Pet_Rabbit", alter: "أرنب")
        }
        return raw
    }

    private var resolvedStayNumber: String {
        let num = activeStay.stayNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !num.isEmpty { return num }
        let resId = activeStay.reservationId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resId.isEmpty { return resId }
        return String(activeStay.id.prefix(8)).uppercased()
    }

    private var ownerDisplayName: String {
        let name = activeStay.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Language.get("Customer_Unknown", alter: "غير محدد") : name
    }

    private var ownerDisplayPhone: String {
        let phone = activeStay.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        return phone.isEmpty ? Language.get("Phone_Unavailable", alter: "لا يوجد رقم مسجل") : phone
    }

    private var hasValidOwnerPhone: Bool {
        !activeStay.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cleanPhoneNumber: String {
        let raw = activeStay.customerPhone.filter("0123456789+".contains)
        return raw.hasPrefix("+") ? String(raw.dropFirst()) : raw
    }

    private func formatDateRange(from: Date, to: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMM"
        return "\(df.string(from: from)) - \(df.string(from: to))"
    }
}

// =================================================================
// MARK: - 2. iPad Architecture (`iPadPetsHotelStayCockpit`)
// =================================================================

private struct iPadPetsHotelStayCockpit: View {
    let activeStay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    let isPushMode: Bool
    let isLoading: Bool
    @Binding var selectedCareFilter: CareFilter
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isStayCopied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // iPad Top Navigation Toolbar with Hover & Shortcuts
            iPadTopNavigationBar

            // Spatial 2-Column Cockpit Studio
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 20) {
                    // Left Column (38%): Guest Dossier & Master Flight Deck
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Master Hero Identity Card
                            iPadGuestHeroCard

                            // Clinical Health & Special Attention Card
                            if activeStay.guestStatus != .normal || (activeStay.internalNotes?.isEmpty == false) {
                                iPadClinicalAttentionCard
                            }

                            // Room & Horizon Pillar Card
                            iPadRoomPillarCard

                            // Financial Ledger Card (Gated)
                            if viewModel.canViewBilling && activeStay.grandTotalMinor > 0 {
                                iPadFinancialLedgerCard
                            }

                            // Pet Owner Dossier & Direct Communication Dock
                            iPadOwnerContactCard

                            // Primary Handover Command Button
                            iPadCheckoutCommandButton
                        }
                        .padding(.vertical, 16)
                    }
                    .frame(width: max(320, geo.size.width * 0.38))

                    // Right Column (62%): Operational Horizon, Care Matrix & Belongings Station
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            // Stay Horizon & Progress Runway
                            iPadStayHorizonRunwayCard

                            // Daily Care Tasks & Protocol Matrix (Gated)
                            if viewModel.canViewCare {
                                iPadCareTasksMatrixCard
                            }

                            // Belongings & Valuables Inventory Station (Gated)
                            if viewModel.canViewCare {
                                iPadBelongingsStationCard
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - iPad Top Navigation Bar
    private var iPadTopNavigationBar: some View {
        HStack(spacing: 14) {
            // Dismiss / Back Button
            Button {
                onBack()
            } label: {
                ZStack {
                    Circle()
                        .fill(AdminSurface.control)
                        .frame(width: 40, height: 40)
                    Image(systemName: isPushMode ? (Language.isRTL() ? "chevron.right" : "chevron.left") : "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .hoverEffect(.lift)
            .keyboardShortcut(.cancelAction)

            // Title & Status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(activeStay.petName)
                        .font(PPBrandFont.bold(size: 22))
                        .foregroundStyle(AdminSurface.primaryText)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(activeStay.guestStatus.color)
                            .frame(width: 7, height: 7)
                        Text(activeStay.guestStatus.title)
                            .font(PPBrandFont.bold(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(activeStay.guestStatus.color.opacity(0.14), in: Capsule())
                    .foregroundStyle(activeStay.guestStatus.color)
                }

                Text("\(activeStay.wing.title) • \(Language.get("Hotel_Suite", alter: "جناح")) \(activeStay.roomNumber)")
                    .font(PPBrandFont.medium(size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()

            // Refresh Dossier Action Button (⌘+R)
            Button {
                onRefresh()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(isLoading ? 360 : 0))
                        .animation(isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                    Text(Language.get("Common_Refresh", alter: "تحديث"))
                        .font(PPBrandFont.bold(size: 13))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(AdminSurface.primaryText)
            }
            .buttonStyle(PlainButtonStyle())
            .hoverEffect(.highlight)
            .keyboardShortcut("r", modifiers: .command)

            // Quick Call Button (⌘+P)
            if hasValidOwnerPhone, let callURL = URL(string: "tel:\(cleanPhoneNumber)") {
                Button {
                    UIApplication.shared.open(callURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Hotel_CallOwner", alter: "اتصال"))
                            .font(PPBrandFont.bold(size: 13))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.highlight)
                .keyboardShortcut("p", modifiers: .command)
            }

            // Quick WhatsApp Button (⌘+W) with World-Class Stay Context
            if hasValidOwnerPhone {
                Button {
                    PetsHotelWhatsAppDispatcher.openChat(
                        for: activeStay,
                        ownerDisplayName: ownerDisplayName,
                        resolvedStayNumber: resolvedStayNumber,
                        cleanPhoneNumber: cleanPhoneNumber,
                        canViewBilling: viewModel.canViewBilling,
                        formatDateRange: { from, to in formatDateRange(from: from, to: to) }
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image("whatsapp")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                        Text("WhatsApp")
                            .font(PPBrandFont.bold(size: 13))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.18, green: 0.80, blue: 0.44).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Color(red: 0.18, green: 0.80, blue: 0.44))
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.highlight)
                .keyboardShortcut("w", modifiers: .command)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            AdminSurface.control
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05), radius: 6, y: 2)
        )
    }

    // MARK: - iPad Left Column: Guest Hero Card (Reinvented Category Sanctuary)
    private var iPadGuestHeroCard: some View {
        VStack(spacing: 14) {
            // Living Specimen Avatar with glowing aura and status gem
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [activeStay.wing.tint.opacity(0.32), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 52
                        )
                    )
                    .frame(width: 96, height: 96)
                    .blur(radius: 8)

                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    activeStay.wing.tint.opacity(colorScheme == .dark ? 0.28 : 0.16),
                                    activeStay.wing.tint.opacity(colorScheme == .dark ? 0.14 : 0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 88, height: 88)
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            activeStay.wing.tint.opacity(0.55),
                                            activeStay.wing.tint.opacity(0.18)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: activeStay.wing.tint.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 10, y: 4)

                    Image(systemName: activeStay.wing.icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [activeStay.wing.tint, activeStay.wing.tint.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                // Active Stay Living Status Gem
                ZStack {
                    Circle()
                        .fill(AdminSurface.card)
                        .frame(width: 22, height: 22)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)

                    Circle()
                        .fill(activeStay.guestStatus.color)
                        .frame(width: 14, height: 14)

                    Circle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 4.5, height: 4.5)
                        .offset(x: -2, y: -2)
                }
                .offset(x: 4, y: 4)
            }

            VStack(spacing: 8) {
                Text(activeStay.petName)
                    .font(PPBrandFont.bold(size: 26))
                    .foregroundStyle(AdminSurface.primaryText)

                // Category & Species Pill
                AdminPetCategoryPill(
                    species: activeStay.petSpecies,
                    breed: activeStay.petBreed,
                    wing: activeStay.wing,
                    mode: .hero
                )

                // Stay ID Pill with Copy & Stateful Confirmation
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    UIPasteboard.general.string = resolvedStayNumber
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isStayCopied = true
                    }
                    onCopy(Language.get("Hotel_StayCopied", alter: "تم نسخ رقم الإقامة"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isStayCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isStayCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)

                        Text(Language.get("Hotel_StayNo", alter: "رقم الإقامة:"))
                            .font(PPBrandFont.medium(size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(resolvedStayNumber)
                            .font(PPBrandFont.bold(size: 12.5))
                            .foregroundStyle(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.12) : AdminSurface.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isStayCopied ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.3) : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.8)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .hoverEffect(.highlight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AdminSurface.control)

                GeometryReader { proxy in
                    RadialGradient(
                        colors: [activeStay.wing.tint.opacity(0.08), Color.clear],
                        center: .top,
                        startRadius: 10,
                        endRadius: proxy.size.width * 0.8
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .ppSurfaceBorder).opacity(0.7),
                            activeStay.wing.tint.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
    }

    // MARK: - iPad Left Column: Clinical Attention Card
    private var iPadClinicalAttentionCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(activeStay.guestStatus.color.opacity(0.2))
                    .frame(width: 38, height: 38)
                Image(systemName: activeStay.guestStatus.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(activeStay.guestStatus.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Hotel_Special_Attention", alter: "عناية خاصة وملاحظات طبية"))
                    .font(PPBrandFont.bold(size: 14.5))
                    .foregroundStyle(activeStay.guestStatus.color)

                if let notes = activeStay.internalNotes, !notes.isEmpty {
                    Text(notes)
                        .font(PPBrandFont.regular(size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            activeStay.guestStatus.color.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(activeStay.guestStatus.color.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - iPad Left Column: Room & Horizon Card
    private var iPadRoomPillarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(activeStay.wing.tint)
                    Text(Language.get("Hotel_AssignedRoom", alter: "الغرفة المخصصة"))
                        .font(PPBrandFont.medium(size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                Text(activeStay.wing.title)
                    .font(PPBrandFont.bold(size: 12))
                    .foregroundStyle(activeStay.wing.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(activeStay.wing.tint.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline) {
                Text(activeStay.roomNumber)
                    .font(PPBrandFont.bold(size: 32))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("Hotel_StayPeriod", alter: "فترة الإقامة"))
                        .font(PPBrandFont.medium(size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatDateRange(from: activeStay.checkInTime, to: activeStay.expectedCheckOutTime))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
        )
    }

    // MARK: - iPad Left Column: Financial Ledger Card
    private var iPadFinancialLedgerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("Hotel_Ledger_Title", alter: "البيان المالي للحساب"))
                    .font(PPBrandFont.bold(size: 14))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text(activeStay.outstandingMinor == 0 ? Language.get("Payment_Status_Paid", alter: "مسدد بالكامل") : Language.get("Payment_Status_Unpaid", alter: "متبقي للدفع"))
                    .font(PPBrandFont.bold(size: 11.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (activeStay.outstandingMinor == 0 ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color.orange).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(activeStay.outstandingMinor == 0 ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color.orange)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_Ledger_Total", alter: "إجمالي الحساب:"))
                        .font(PPBrandFont.medium(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(String(format: "%.2f %@", Double(activeStay.grandTotalMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(PPBrandFont.bold(size: 18))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Language.get("Hotel_Ledger_Balance", alter: "المتبقي:"))
                        .font(PPBrandFont.medium(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(String(format: "%.2f %@", Double(activeStay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                        .font(PPBrandFont.bold(size: 18))
                        .foregroundStyle(activeStay.outstandingMinor > 0 ? Color.orange : Color(red: 0.16, green: 0.72, blue: 0.44))
                }
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
        )
    }

    // MARK: - iPad Left Column: Pet Owner Card
    private var iPadOwnerContactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
                Text(Language.get("Hotel_PetOwner", alter: "بيانات مالك الحيوان"))
                    .font(PPBrandFont.bold(size: 14.5))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ownerDisplayName)
                        .font(PPBrandFont.bold(size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(ownerDisplayPhone)
                        .font(PPBrandFont.bold(size: 13.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                if hasValidOwnerPhone {
                    HStack(spacing: 8) {
                        if let callURL = URL(string: "tel:\(cleanPhoneNumber)") {
                            Button {
                                UIApplication.shared.open(callURL)
                            } label: {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                                    .padding(9)
                                    .background(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.14), in: Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .hoverEffect(.highlight)
                        }

                        Button {
                            PetsHotelWhatsAppDispatcher.openChat(
                                for: activeStay,
                                ownerDisplayName: ownerDisplayName,
                                resolvedStayNumber: resolvedStayNumber,
                                cleanPhoneNumber: cleanPhoneNumber,
                                canViewBilling: viewModel.canViewBilling,
                                formatDateRange: { from, to in formatDateRange(from: from, to: to) }
                            )
                        } label: {
                            Image("whatsapp")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 15, height: 15)
                                .foregroundStyle(Color(red: 0.18, green: 0.80, blue: 0.44))
                                .padding(9)
                                .background(Color(red: 0.18, green: 0.80, blue: 0.44).opacity(0.14), in: Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverEffect(.highlight)

                        Button {
                            UIPasteboard.general.string = cleanPhoneNumber
                            onCopy(Language.get("Common_Copied", alter: "تم النسخ"))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AdminSurface.primary)
                                .padding(9)
                                .background(AdminSurface.surface, in: Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverEffect(.highlight)
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
        )
    }

    // MARK: - iPad Left Column: Primary Checkout Command Button
    private var iPadCheckoutCommandButton: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                viewModel.checkOutModalStay = activeStay
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Language.isRTL() ? "arrow.left.to.line" : "arrow.right.to.line")
                    .font(.system(size: 16, weight: .bold))
                Text(Language.get("Hotel_Execute_Checkout", alter: "تسجيل المغادرة وتسليم النزيل"))
                    .font(PPBrandFont.bold(size: 16))

                Spacer()

                Text("⌘O")
                    .font(PPBrandFont.bold(size: 12))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.84, green: 0.15, blue: 0.35), Color(red: 0.72, green: 0.10, blue: 0.28)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: Color(red: 0.84, green: 0.15, blue: 0.35).opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(.lift)
        .keyboardShortcut("o", modifiers: .command)
        .disabled(!viewModel.canCheckOut)
        .opacity(viewModel.canCheckOut ? 1 : 0.45)
    }

    // MARK: - iPad Right Column: Horizon Runway Card
    private var iPadStayHorizonRunwayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "airplane.arrival")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_StayHorizon", alter: "مدرج الإقامة والجدول الزمني"))
                        .font(PPBrandFont.bold(size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                Text("\(Int(activeStay.stayProgress * 100))% \(Language.get("Hotel_Completed_Percent", alter: "مكتمل"))")
                    .font(PPBrandFont.bold(size: 13))
                    .foregroundStyle(AdminSurface.primary)
            }

            // Dual Date Horizon Cards
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Hotel_CheckIn_Time", alter: "تسجيل الوصول"))
                        .font(PPBrandFont.medium(size: 11.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatDetailedDate(activeStay.checkInTime))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("Hotel_ExpectedCheckOut", alter: "المغادرة المتوقعة"))
                        .font(PPBrandFont.medium(size: 11.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(formatDetailedDate(activeStay.expectedCheckOutTime))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Gradient Progress Runway Track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AdminSurface.surface)
                        .frame(height: 8)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary, Color(red: 0.16, green: 0.72, blue: 0.44)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width * CGFloat(activeStay.stayProgress), geo.size.width)), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(18)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
        )
    }

    // MARK: - iPad Right Column: Care Tasks Matrix
    private var filteredTasks: [AdminHotelCareTask] {
        switch selectedCareFilter {
        case .all:
            return activeStay.dailyCareTasks
        case .pending:
            return activeStay.dailyCareTasks.filter { !$0.isCompleted }
        case .completed:
            return activeStay.dailyCareTasks.filter { $0.isCompleted }
        }
    }

    private var iPadCareTasksMatrixCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_CareSchedule", alter: "جدول الرعاية والمهام اليومية"))
                        .font(PPBrandFont.bold(size: 16.5))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Filter Segment Controls
                HStack(spacing: 4) {
                    ForEach(CareFilter.allCases) { filter in
                        Button {
                            selectedCareFilter = filter
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(filter.title)
                                .font(PPBrandFont.bold(size: 12))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedCareFilter == filter ? AdminSurface.primary : AdminSurface.surface, in: Capsule())
                                .foregroundStyle(selectedCareFilter == filter ? Color.white : AdminSurface.primaryText)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .hoverEffect(.highlight)
                    }
                }
            }

            if filteredTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(AdminSurface.primary.opacity(0.6))
                    Text(Language.get("Hotel_NoTasksScheduled", alter: "لا توجد مهام رعاية مطابقة لهذا التصنيف"))
                        .font(PPBrandFont.bold(size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Hotel_StandardCareActive", alter: "يتلقى النزيل بروتوكول الرعاية المعياري المعتمد للجناح"))
                        .font(PPBrandFont.regular(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredTasks) { task in
                        iPadCareTaskRow(task: task)
                    }
                }
            }
        }
        .padding(18)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
        )
    }

    private func iPadCareTaskRow(task: AdminHotelCareTask) -> some View {
        Button {
            viewModel.toggleCareTask(stay: activeStay, task: task)
        } label: {
            HStack(spacing: 14) {
                // Interactive Status Indicator
                ZStack {
                    Circle()
                        .strokeBorder(
                            task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color.gray.opacity(0.4),
                            lineWidth: 2
                        )
                        .frame(width: 24, height: 24)

                    if task.isCompleted {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.72, blue: 0.44))
                            .frame(width: 14, height: 14)
                    }
                }

                // Task Icon Squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.12) : AdminSurface.primary.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: task.taskType.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.taskType.title)
                        .strikethrough(task.isCompleted)
                        .font(PPBrandFont.bold(size: 14.5))
                        .foregroundStyle(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primaryText)

                    if let by = task.completedByStaffName, task.isCompleted {
                        Text("\(Language.get("Hotel_CompletedBy", alter: "بواسطة:")) \(by)")
                            .font(PPBrandFont.regular(size: 11.5))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                Text(task.scheduledTime)
                    .font(PPBrandFont.bold(size: 12.5))
                    .foregroundStyle(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(.highlight)
        .disabled(!viewModel.canTransitionCareTask(task))
    }

    // MARK: - iPad Right Column: Belongings Station
    private var iPadBelongingsStationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_BelongingsInventory", alter: "محتويات وأغراض النزيل"))
                        .font(PPBrandFont.bold(size: 16.5))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                Text("\(activeStay.belongings.count) \(Language.get("Hotel_Items", alter: "أغراض"))")
                    .font(PPBrandFont.bold(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AdminSurface.surface, in: Capsule())
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            if activeStay.belongings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(AdminSurface.secondaryText.opacity(0.7))
                    Text(Language.get("Hotel_NoBelongings", alter: "لا توجد أغراض شخصية مسجلة عند الدخول"))
                        .font(PPBrandFont.medium(size: 13.5))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(activeStay.belongings) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))

                            Text(item.name)
                                .font(PPBrandFont.medium(size: 14))
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(1)

                            Spacer()

                            Text("x\(item.quantity)")
                                .font(PPBrandFont.bold(size: 13))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(AdminSurface.control, in: Capsule())
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.8)
        )
    }

    // MARK: - Helpers
    private var petBreedSpeciesText: String {
        let breed = activeStay.petBreed.trimmingCharacters(in: .whitespacesAndNewlines)
        let species = localizedSpeciesText(activeStay.petSpecies)
        if !breed.isEmpty && !species.isEmpty {
            return "\(species) • \(breed)"
        } else if !species.isEmpty {
            return species
        } else if !breed.isEmpty {
            return breed
        }
        return ""
    }

    private func localizedSpeciesText(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "cat" || s == "قط" || s == "قطة" || s == "cats" {
            return Language.get("Pet_Cat", alter: "قط")
        } else if s == "dog" || s == "كلب" || s == "dogs" {
            return Language.get("Pet_Dog", alter: "كلب")
        } else if s == "bird" || s == "طير" || s == "طائر" || s == "birds" {
            return Language.get("Pet_Bird", alter: "طائر")
        } else if s == "rabbit" || s == "أرنب" || s == "rabbits" {
            return Language.get("Pet_Rabbit", alter: "أرنب")
        }
        return raw
    }

    private var resolvedStayNumber: String {
        let num = activeStay.stayNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !num.isEmpty { return num }
        let resId = activeStay.reservationId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resId.isEmpty { return resId }
        return String(activeStay.id.prefix(8)).uppercased()
    }

    private var ownerDisplayName: String {
        let name = activeStay.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? Language.get("Customer_Unknown", alter: "غير محدد") : name
    }

    private var ownerDisplayPhone: String {
        let phone = activeStay.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        return phone.isEmpty ? Language.get("Phone_Unavailable", alter: "لا يوجد رقم مسجل") : phone
    }

    private var hasValidOwnerPhone: Bool {
        !activeStay.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cleanPhoneNumber: String {
        let raw = activeStay.customerPhone.filter("0123456789+".contains)
        return raw.hasPrefix("+") ? String(raw.dropFirst()) : raw
    }

    private func formatDateRange(from: Date, to: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMM"
        return "\(df.string(from: from)) - \(df.string(from: to))"
    }

    private func formatDetailedDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMMM, yyyy"
        return df.string(from: date)
    }
}


// =================================================================
// MARK: - World-Class WhatsApp Stay Context Dispatcher (100/100)
// =================================================================

public enum PetsHotelWhatsAppDispatcher {
    public static func openChat(
        for stay: AdminHotelStay,
        ownerDisplayName: String,
        resolvedStayNumber: String,
        cleanPhoneNumber: String,
        canViewBilling: Bool,
        formatDateRange: (Date, Date) -> String
    ) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let digits = cleanPhoneNumber.filter("0123456789".contains)
        guard !digits.isEmpty else { return }

        var targetPhone = digits
        if targetPhone.hasPrefix("00") {
            targetPhone = String(targetPhone.dropFirst(2))
        }
        if targetPhone.count == 8 {
            targetPhone = "974" + targetPhone
        }

        let message = buildStayContextMessage(
            stay: stay,
            ownerDisplayName: ownerDisplayName,
            resolvedStayNumber: resolvedStayNumber,
            canViewBilling: canViewBilling,
            formatDateRange: formatDateRange
        )

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&#=")
        let encodedText = message.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        let nativeURL = URL(string: "whatsapp://send?phone=\(targetPhone)&text=\(encodedText)")
        let webURL = URL(string: "https://wa.me/\(targetPhone)?text=\(encodedText)")

        if let nativeURL = nativeURL, UIApplication.shared.canOpenURL(nativeURL) {
            UIApplication.shared.open(nativeURL, options: [:], completionHandler: nil)
        } else if let webURL = webURL {
            UIApplication.shared.open(webURL, options: [:], completionHandler: nil)
        }
    }

    public static func buildStayContextMessage(
        stay: AdminHotelStay,
        ownerDisplayName: String,
        resolvedStayNumber: String,
        canViewBilling: Bool,
        formatDateRange: (Date, Date) -> String
    ) -> String {
        let isArabic = Language.isRTL()
        let petName = stay.petName.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = ownerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let stayNumber = resolvedStayNumber
        let room = "\(stay.wing.title) • \(Language.get("Hotel_Suite", alter: "جناح")) \(stay.roomNumber)"
        let period = formatDateRange(stay.checkInTime, stay.expectedCheckOutTime)
        let statusTitle = stay.guestStatus.title

        if isArabic {
            let greeting = (owner.isEmpty || owner == Language.get("Customer_Unknown", alter: "غير محدد"))
                ? "مرحباً بك،"
                : "مرحباً أستاذ \(owner)،"

            var lines: [String] = [
                greeting,
                "نتواصل معك من فندق ورعاية بيور بيتس 🐾 بخصوص إقامة أليفك (\(petName)).",
                "",
                "📋 بطاقة الإقامة الحالية:",
                "• رقم الإقامة: \(stayNumber)",
                "• الجناح والغرفة: \(room)",
                "• فترة الإقامة: \(period)",
                "• الحالة الصحية والسلوكية: \(statusTitle)"
            ]

            if let notes = stay.internalNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                lines.append("• ملاحظات الرعاية الخاصة: \(notes)")
            }

            if !stay.dailyCareTasks.isEmpty {
                let completed = stay.dailyCareTasks.filter { $0.isCompleted }.count
                lines.append("• جدول الرعاية: تم إنجاز (\(completed)/\(stay.dailyCareTasks.count)) من المهام اليومية.")
            }

            if canViewBilling && stay.outstandingMinor > 0 {
                let bal = String(format: "%.2f %@", Double(stay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق"))
                lines.append("• الحساب المالي: المتبقي للدفع \(bal)")
            }

            lines.append("")
            lines.append("يسعدنا دائماً خدمتكم والإجابة عن أي استفسار حول راحة وصحة أليفكم ✨")
            lines.append("فندق بيور بيتس - قطر 🇶🇦")

            return lines.joined(separator: "\n")
        } else {
            let greeting = (owner.isEmpty || owner == Language.get("Customer_Unknown", alter: "غير محدد"))
                ? "Hello,"
                : "Hello \(owner),"

            var lines: [String] = [
                greeting,
                "Reaching out from Pure Pets Hotel & Care 🐾 regarding your pet (\(petName))'s stay.",
                "",
                "📋 Current Stay Dossier:",
                "• Stay ID: \(stayNumber)",
                "• Suite & Room: \(room)",
                "• Stay Period: \(period)",
                "• Health & Comfort Status: \(statusTitle)"
            ]

            if let notes = stay.internalNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                lines.append("• Special Care Notes: \(notes)")
            }

            if !stay.dailyCareTasks.isEmpty {
                let completed = stay.dailyCareTasks.filter { $0.isCompleted }.count
                lines.append("• Care Routine: (\(completed)/\(stay.dailyCareTasks.count)) daily tasks completed.")
            }

            if canViewBilling && stay.outstandingMinor > 0 {
                let bal = String(format: "%.2f %@", Double(stay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "QAR"))
                lines.append("• Ledger: Outstanding balance \(bal)")
            }

            lines.append("")
            lines.append("We remain at your service for any questions regarding your pet's comfort ✨")
            lines.append("Pure Pets Hotel - Qatar 🇶🇦")

            return lines.joined(separator: "\n")
        }
    }
}
