//
//  WantedPetDetailView.swift
//  Pure Pets Admin
//
//  Created for Pure Pets Platform.
//  Ultra-responsive, category-defining Apple-grade customer and wanted pet dossier studio.
//  Rebuilt from absolute first principles with tactile customer command deck,
//  dynamic specimen matrix, intelligent store inventory match radar,
//  interactive operational lifecycle runway, and comprehensive audit timeline.
//  Designed to push seamlessly in NavigationStack or present as full-screen cover.
//

import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth

public struct WantedPetDetailView: View {
    public let wantedPetId: String
    public let onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = WantedPetsService.shared

    // MARK: - Core Item & Real-Time Sync State
    @State private var item: CustomerWantedPet? = nil
    @State private var isLoading: Bool = true
    @State private var listenerRegistration: ListenerRegistration? = nil

    // MARK: - Store Inventory Match Radar State
    @State private var matchingInventoryPets: [StoreMatchingPet] = []
    @State private var isScanningRadar: Bool = false
    @State private var hasScannedRadar: Bool = false
    @State private var radarRotationAngle: Double = 0

    // MARK: - Interactive Operational Sheets & Overlays
    @State private var showCloseSheet: Bool = false
    @State private var selectedCloseReasonPreset: String = ""
    @State private var customCloseReasonText: String = ""

    @State private var showFulfillSheet: Bool = false
    @State private var fulfilledPetIdInput: String = ""

    @State private var showChannelSheet: Bool = false
    @State private var showAutoMarkContactedPrompt: Bool = false

    @State private var showCopiedAlert: Bool = false
    @State private var actionNoticeMessage: String? = nil
    @State private var errorMessage: String? = nil

    public init(wantedPetId: String, onDismiss: (() -> Void)? = nil) {
        self.wantedPetId = wantedPetId
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Screen Background
            AdminSurface.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // 1. Apple-Grade Top Command & Navigation Bar
                topNavigationBar

                // Main Scrollable Content
                if isLoading && item == nil {
                    loadingDossierState
                } else if let pet = item {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: AdminSpacing.sectionSpacing) {
                            // 2. Customer Passport & Quick Tactical Command Deck
                            customerCommandDeck(pet)

                            // 3. Pet Specimen Blueprint & Desires Matrix
                            petSpecimenBlueprint(pet)

                            // 4. Intelligent Store Inventory Match Radar
                            storeInventoryMatchRadar(pet)

                            // 5. Interactive Operational Lifecycle Runway (Replaces 4 stacked buttons)
                            lifecyclePipelineRunway(pet)

                            // 6. Dossier Audit & Journey Stream
                            journeyAuditStream(pet)

                            // Bottom Clearance for comfortable scrolling
                            Color.clear.frame(height: 40)
                        }
                        .padding(.horizontal, AdminSpacing.base)
                        .padding(.top, AdminSpacing.md)
                    }
                    .refreshable {
                        loadItemLive()
                        scanStoreRadar(for: pet)
                    }
                } else {
                    notFoundState
                }
            }

            // Floating Floating Toast Notification
            if showCopiedAlert {
                floatingToastHUD(
                    icon: "doc.on.doc.fill",
                    message: Language.get("PhoneCopied", alter: "تم نسخ رقم الهاتف"),
                    tint: Color(uiColor: .ppSuccess)
                )
            } else if let notice = actionNoticeMessage {
                floatingToastHUD(
                    icon: "checkmark.circle.fill",
                    message: notice,
                    tint: Color(uiColor: .ppSuccess)
                )
            } else if let err = errorMessage {
                floatingToastHUD(
                    icon: "exclamationmark.triangle.fill",
                    message: err,
                    tint: Color(uiColor: .ppError)
                )
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .navigationBarHidden(true)
        .onAppear {
            loadItemLive()
        }
        .onDisappear {
            listenerRegistration?.remove()
            listenerRegistration = nil
        }
        // MARK: - Close Reason Bottom Sheet
        .sheet(isPresented: $showCloseSheet) {
            closeReasonSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // MARK: - Fulfill Celebration Bottom Sheet
        .sheet(isPresented: $showFulfillSheet) {
            fulfillConfirmationSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        // MARK: - Contact Channel Selector Sheet
        .sheet(isPresented: $showChannelSheet) {
            contactChannelSheet
                .presentationDetents([.fraction(0.38)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 1. Top Command & Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            // Dismiss / Back Button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handleDismiss()
            } label: {
                Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.surface, in: Circle())
                    .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    .shadow(color: AdminShadow.navigation.color, radius: AdminShadow.navigation.radius, y: AdminShadow.navigation.y)
            }
            .buttonStyle(DossierScaleButtonStyle())

            // Title & Customer Context
            VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                Text(Language.get("WantedPets_Detail_Title", alter: "تفاصيل الطلب"))
                    .font(Font.custom("Beiruti-Bold", size: 19))
                    .foregroundStyle(AdminSurface.primaryText)

                if let pet = item {
                    Text(pet.customerName + " • " + pet.requestedPetTitle)
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status Badge & Context Menu
            if let pet = item {
                HStack(spacing: 6) {
                    Circle()
                        .fill(pet.status.tintColor)
                        .frame(width: 7, height: 7)

                    Text(pet.status.title)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(pet.status.tintColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(pet.status.tintColor.opacity(0.12), in: Capsule())

                // Quick Action Overflow Menu
                Menu {
                    Button {
                        shareDossierSummary(pet)
                    } label: {
                        Label(Language.get("Share", alter: "مشاركة"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        copyCustomerInfo(pet)
                    } label: {
                        Label(Language.get("Copy", alter: "نسخ البيانات"), systemImage: "doc.on.doc")
                    }

                    Divider()

                    if pet.status.isActive {
                        Button(role: .destructive) {
                            showCloseSheet = true
                        } label: {
                            Label(Language.get("WantedPet_Action_ClosePrompt", alter: "إغلاق الطلب"), systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            transitionStatus(to: .waiting)
                        } label: {
                            Label(Language.get("WantedPet_Action_ReopenPrompt", alter: "إعادة فتح الطلب"), systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 38, height: 38)
                        .background(AdminSurface.surface, in: Circle())
                        .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }
            }
        }
        .padding(.horizontal, AdminSpacing.base)
        .padding(.vertical, 10)
        .background(AdminSurface.background)
        .overlay(
            Rectangle()
                .fill(AdminSurface.hairline)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - 2. Customer Passport & Quick Tactical Command Deck

    private func customerCommandDeck(_ pet: CustomerWantedPet) -> some View {
        VStack(spacing: 16) {
            // Customer Identity Header
            HStack(alignment: .center, spacing: 14) {
                // Monogram Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary.opacity(0.20), AdminSurface.primary.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(customerMonogram(pet.customerName))
                        .font(Font.custom("Beiruti-Bold", size: 22))
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 58, height: 58)
                .overlay(
                    Circle()
                        .strokeBorder(AdminSurface.primary.opacity(0.3), lineWidth: 1.5)
                )

                // Name, Phone & Source
                VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(pet.customerName)
                            .font(Font.custom("Beiruti-Bold", size: 22))
                            .foregroundStyle(AdminSurface.primaryText)

                        // Contact source chip
                        HStack(spacing: 4) {
                            Image(systemName: pet.contactSource.iconName)
                                .font(.system(size: 9))
                            Text(pet.contactSource.title)
                                .font(Font.custom("Beiruti-Medium", size: 11))
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AdminSurface.cardElevated, in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.5))
                    }

                    Text(pet.formattedPhoneDisplay)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .environment(\.layoutDirection, .leftToRight)
                }

                Spacer()
            }

            Divider()
                .background(AdminSurface.hairline)

            // Tactical 3-Strike Command Buttons
            HStack(spacing: 10) {
                // 1. WhatsApp Command (Primary High-Converting Strike)
                Button {
                    openWhatsAppConversation(pet)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "message.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(Language.get("WhatsApp", alter: "واتساب"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.15, green: 0.83, blue: 0.44), Color(red: 0.11, green: 0.72, blue: 0.36)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.15, green: 0.83, blue: 0.44).opacity(0.30), radius: 8, y: 3)
                }
                .buttonStyle(DossierScaleButtonStyle())

                // 2. Direct Voice Call Strike
                Button {
                    callCustomerPhone(pet.phoneNumber)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .medium))
                        Text(Language.get("Call", alter: "اتصال"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                    }
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }
                .buttonStyle(DossierScaleButtonStyle())

                // 3. Monospaced Copy Phone Strike
                Button {
                    copyCustomerPhone(pet.phoneNumber)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                }
                .buttonStyle(DossierScaleButtonStyle())
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        .shadow(color: AdminShadow.card.color, radius: AdminShadow.card.radius, y: AdminShadow.card.y)
    }

    // MARK: - 3. Pet Specimen Blueprint & Desires Matrix

    private func petSpecimenBlueprint(_ pet: CustomerWantedPet) -> some View {
        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 14) {
            // Header: Category & Breed
            HStack(spacing: 12) {
                // Species Icon Squircle
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AdminSurface.primary.opacity(0.12))
                    Image(systemName: iconForKind(pet.mainKindName ?? pet.requestedPetTitle))
                        .font(.system(size: 24))
                        .foregroundStyle(AdminSurface.primary)
                }
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(AdminSurface.primary.opacity(0.25), lineWidth: 1)
                )

                VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 3) {
                    Text(pet.requestedPetTitle)
                        .font(Font.custom("Beiruti-Bold", size: 21))
                        .foregroundStyle(AdminSurface.primaryText)

                    if let mainKind = pet.mainKindName, !mainKind.isEmpty, mainKind != pet.requestedPetTitle {
                        Text(mainKind)
                            .font(Font.custom("Beiruti-Regular", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                // Freshness / Waiting Duration Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(freshnessColor(for: pet.createdAt))
                        .frame(width: 6, height: 6)
                    Text(pet.waitingDurationText)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(freshnessColor(for: pet.createdAt))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(freshnessColor(for: pet.createdAt).opacity(0.12), in: Capsule())
            }

            // 4-Quadrant Attribute Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                // Sex Chip
                specimenAttributeTile(
                    title: Language.get("WantedPets_Sex_Label", alter: "الجنس المطلوب"),
                    value: pet.sexPreference.title,
                    icon: pet.sexPreference == .male ? "figure.stand" : (pet.sexPreference == .female ? "figure.stand.dress" : "sparkles"),
                    tint: pet.sexPreference == .male ? Color.blue : (pet.sexPreference == .female ? Color.pink : AdminSurface.primary)
                )

                // Color Chip
                specimenAttributeTile(
                    title: Language.get("WantedPets_Color_Label", alter: "اللون المفضل"),
                    value: pet.colorPreference?.isEmpty == false ? pet.colorPreference! : Language.get("WantedPet_AnySpecimen", alter: "أي لون"),
                    icon: "paintpalette.fill",
                    tint: Color(uiColor: .systemPurple)
                )

                // Budget Ceiling Chip
                specimenAttributeTile(
                    title: Language.get("WantedPets_Budget_Label", alter: "الحد الأقصى للميزانية"),
                    value: (pet.budgetMax != nil && pet.budgetMax! > 0) ? String(format: "≤ %.0f %@", pet.budgetMax!, Language.isRTL() ? "ر.ق" : "QAR") : Language.get("WantedPet_NoBudget", alter: "غير محدد"),
                    icon: "banknote.fill",
                    tint: Color(uiColor: .ppSuccess)
                )

                // Freshness Level
                specimenAttributeTile(
                    title: Language.get("WantedPets_Summary_Waiting", alter: "حالة الطلب"),
                    value: freshnessLabel(for: pet.createdAt),
                    icon: "hourglass",
                    tint: freshnessColor(for: pet.createdAt)
                )
            }

            // Customer Special Notes Quote Box (if available)
            if let notes = pet.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("WantedPet_Notes_Title", alter: "ملاحظات وتفضيلات العميل الخاصة"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(AdminSurface.primary)
                    }

                    Text(notes)
                        .font(Font.custom("Beiruti-Regular", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                        .lineSpacing(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: Language.isRTL() ? .trailing : .leading)
                .background(AdminSurface.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AdminSurface.primary.opacity(0.18), lineWidth: 0.75)
                )
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        .shadow(color: AdminShadow.card.color, radius: AdminShadow.card.radius, y: AdminShadow.card.y)
    }

    private func specimenAttributeTile(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 1) {
                Text(title)
                    .font(Font.custom("Beiruti-Regular", size: 11))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(value)
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.5))
    }

    // MARK: - 4. Intelligent Store Inventory Match Radar

    private func storeInventoryMatchRadar(_ pet: CustomerWantedPet) -> some View {
        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 12) {
            // Header with Radar Scanner Trigger
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 15))
                        .foregroundStyle(AdminSurface.primary)
                        .rotationEffect(.degrees(radarRotationAngle))
                    Text(Language.get("WantedPet_Radar_Title", alter: "رادار المخزون والتوفر"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Rescan Radar Button
                Button {
                    triggerRadarScan(for: pet)
                } label: {
                    HStack(spacing: 4) {
                        if isScanningRadar {
                            ProgressView()
                                .tint(AdminSurface.primary)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(Language.get("WantedPet_Radar_Rescan", alter: "إعادة الفحص"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .foregroundStyle(AdminSurface.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }
                .buttonStyle(DossierScaleButtonStyle())
            }

            if isScanningRadar {
                HStack(spacing: 8) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(Language.get("WantedPet_Radar_Scanning", alter: "جاري فحص المخزون..."))
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            } else if !matchingInventoryPets.isEmpty {
                // Matching Pets Found!
                VStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Text(String(format: Language.get("WantedPet_Radar_MatchesFound", alter: "تم العثور على %d حيوان مطابق في المخزون!"), matchingInventoryPets.count))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Spacer()
                    }

                    ForEach(matchingInventoryPets.prefix(3)) { matchPet in
                        HStack(spacing: 12) {
                            // Pet Icon or Thumbnail
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AdminSurface.cardElevated)
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                                Text(matchPet.name)
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    if let tag = matchPet.ringTag, !tag.isEmpty {
                                        Text("#\(tag)")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                    if let branch = matchPet.branchName, !branch.isEmpty {
                                        Text("• " + branch)
                                            .font(Font.custom("Beiruti-Regular", size: 11))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                }
                            }

                            Spacer()

                            VStack(alignment: Language.isRTL() ? .leading : .trailing, spacing: 4) {
                                if let p = matchPet.price, p > 0 {
                                    Text(String(format: "%.0f %@", p, Language.isRTL() ? "ر.ق" : "QAR"))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(uiColor: .ppSuccess))
                                }

                                Button {
                                    notifyCustomerWithMatch(pet: pet, match: matchPet)
                                } label: {
                                    Text(Language.get("WantedPet_Radar_SendToCustomer", alter: "مراسلة بالتوفر"))
                                        .font(Font.custom("Beiruti-Bold", size: 11))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(uiColor: .ppSuccess), in: Capsule())
                                }
                                .buttonStyle(DossierScaleButtonStyle())
                            }
                        }
                        .padding(10)
                        .background(Color(uiColor: .ppSuccess).opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(uiColor: .ppSuccess).opacity(0.20), lineWidth: 0.75))
                    }
                }
            } else {
                // Radar Active — No Immediate Matches
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 42, height: 42)
                        .background(AdminSurface.cardElevated, in: Circle())

                    VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                        Text(Language.get("WantedPet_Radar_NoMatches", alter: "لا يتوفر حالياً في المخزون — الرادار نشط"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("WantedPets_Card_Subtitle", alter: "سيتم تنبيهك فور إضافة حيوان مطابق في فروع بيور بيتس."))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AdminSurface.cardElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        .shadow(color: AdminShadow.card.color, radius: AdminShadow.card.radius, y: AdminShadow.card.y)
        .onAppear {
            if !hasScannedRadar {
                triggerRadarScan(for: pet)
            }
        }
    }

    // MARK: - 5. Interactive Operational Lifecycle Runway

    private func lifecyclePipelineRunway(_ pet: CustomerWantedPet) -> some View {
        VStack(spacing: 16) {
            // Pipeline Stepper Runway
            HStack(spacing: 0) {
                pipelineStepNode(
                    title: Language.get("WantedPet_Pipeline_Waiting", alter: "انتظار"),
                    step: .waiting,
                    currentStatus: pet.status,
                    icon: "clock.fill"
                )

                pipelineStepConnector(isFilled: isStepFilled(step: .contacted, current: pet.status))

                pipelineStepNode(
                    title: Language.get("WantedPet_Pipeline_Contacted", alter: "تواصل"),
                    step: .contacted,
                    currentStatus: pet.status,
                    icon: "phone.bubble.left.fill"
                )

                pipelineStepConnector(isFilled: isStepFilled(step: .interested, current: pet.status))

                pipelineStepNode(
                    title: Language.get("WantedPet_Pipeline_Interested", alter: "مهتم"),
                    step: .interested,
                    currentStatus: pet.status,
                    icon: "star.fill"
                )

                pipelineStepConnector(isFilled: isStepFilled(step: .fulfilled, current: pet.status))

                pipelineStepNode(
                    title: Language.get("WantedPet_Pipeline_Fulfilled", alter: "مكتمل"),
                    step: .fulfilled,
                    currentStatus: pet.status,
                    icon: "checkmark.seal.fill"
                )
            }
            .padding(.horizontal, 4)

            Divider()
                .background(AdminSurface.hairline)

            // Smart Forward Progression Dock (Context-Aware Action Buttons)
            if pet.status == .waiting {
                // Primary Action: Mark Contacted
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showChannelSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.bubble.left.fill")
                            .font(.system(size: 15))
                        Text(Language.get("WantedPet_Action_AdvanceContacted", alter: "تحديد كـ تم التواصل مع العميل"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .systemBlue), in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                    .shadow(color: Color(uiColor: .systemBlue).opacity(0.3), radius: 8, y: 3)
                }
                .buttonStyle(DossierScaleButtonStyle())
            } else if pet.status == .contacted {
                HStack(spacing: 10) {
                    // Mark as Interested
                    Button {
                        transitionStatus(to: .interested)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                            Text(Language.get("WantedPet_Action_AdvanceInterested", alter: "العميل مهتم بالحيوان"))
                                .font(Font.custom("Beiruti-Bold", size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color(uiColor: .systemPurple), in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                        .shadow(color: Color(uiColor: .systemPurple).opacity(0.28), radius: 8, y: 3)
                    }
                    .buttonStyle(DossierScaleButtonStyle())

                    // Fulfill Directly
                    Button {
                        showFulfillSheet = true
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                            .frame(width: 48, height: 48)
                            .background(Color(uiColor: .ppSuccess).opacity(0.12), in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous).strokeBorder(Color(uiColor: .ppSuccess).opacity(0.3), lineWidth: 0.75))
                    }
                    .buttonStyle(DossierScaleButtonStyle())
                }
            } else if pet.status == .interested {
                // Primary Action: Fulfill Request Celebration
                Button {
                    showFulfillSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                        Text(Language.get("WantedPet_Action_AdvanceFulfilled", alter: "إتمام وتوفير الطلب بنجاح 🎉"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        LinearGradient(
                            colors: [Color(uiColor: .ppSuccess), Color(red: 0.12, green: 0.68, blue: 0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    )
                    .shadow(color: Color(uiColor: .ppSuccess).opacity(0.35), radius: 10, y: 4)
                }
                .buttonStyle(DossierScaleButtonStyle())
            } else if pet.status == .fulfilled {
                // Fulfilled Celebration Card
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Text(Language.get("WantedPet_Fulfilled_Banner_Title", alter: "تم إتمام الطلب بنجاح 🎉"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                    }

                    Text(Language.get("WantedPet_Fulfilled_Banner_Sub", alter: "حصل العميل على الحيوان المطلوب وتم إنهاء دورة الطلب بنجاح."))
                        .font(Font.custom("Beiruti-Regular", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .ppSuccess).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 0.75))
            } else if pet.status == .closed {
                // Closed Request Card
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(uiColor: .systemGray))
                        Text(Language.get("WantedPet_Closed_Banner_Title", alter: "تم إغلاق هذا الطلب"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                    }

                    if let reason = pet.closeReason, !reason.isEmpty {
                        Text(String(format: Language.get("WantedPet_Closed_Reason_Label", alter: "سبب الإغلاق: %@"), reason))
                            .font(Font.custom("Beiruti-Regular", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    Button {
                        transitionStatus(to: .waiting)
                    } label: {
                        Text(Language.get("WantedPet_Action_ReopenPrompt", alter: "إعادة فتح الطلب"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(DossierScaleButtonStyle())
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }

            // Discreet Secondary Close Option for Active Orders
            if pet.status.isActive {
                Button {
                    showCloseSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 13))
                        Text(Language.get("WantedPet_Action_ClosePrompt", alter: "إغلاق الطلب"))
                            .font(Font.custom("Beiruti-Regular", size: 13))
                    }
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        .shadow(color: AdminShadow.card.color, radius: AdminShadow.card.radius, y: AdminShadow.card.y)
    }

    private func pipelineStepNode(title: String, step: WantedPetStatus, currentStatus: WantedPetStatus, icon: String) -> some View {
        let isCurrent = currentStatus == step
        let isPast = isStepFilled(step: step, current: currentStatus)
        let tint = step.tintColor

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCurrent ? tint : (isPast ? tint.opacity(0.20) : AdminSurface.cardElevated))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .strokeBorder(isCurrent ? tint : (isPast ? tint.opacity(0.5) : AdminSurface.hairline), lineWidth: isCurrent ? 2 : 1)
                    )
                    .shadow(color: isCurrent ? tint.opacity(0.35) : Color.clear, radius: 6, y: 2)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.white : (isPast ? tint : AdminSurface.secondaryText))
            }

            Text(title)
                .font(Font.custom("Beiruti-Bold", size: 12))
                .foregroundStyle(isCurrent ? tint : (isPast ? AdminSurface.primaryText : AdminSurface.secondaryText))
        }
        .frame(maxWidth: .infinity)
    }

    private func pipelineStepConnector(isFilled: Bool) -> some View {
        Rectangle()
            .fill(isFilled ? Color(uiColor: .ppSuccess).opacity(0.6) : AdminSurface.hairline)
            .frame(height: 2)
            .offset(y: -10)
    }

    private func isStepFilled(step: WantedPetStatus, current: WantedPetStatus) -> Bool {
        if current == .closed { return false }
        switch step {
        case .waiting:
            return true
        case .contacted:
            return current == .contacted || current == .interested || current == .fulfilled
        case .interested:
            return current == .interested || current == .fulfilled
        case .fulfilled:
            return current == .fulfilled
        case .closed:
            return false
        }
    }

    // MARK: - 6. Dossier Audit & Journey Stream

    private func journeyAuditStream(_ pet: CustomerWantedPet) -> some View {
        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("WantedPet_Timeline_Title", alter: "سجل الرحلة والتدقيق"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                Spacer()
            }

            VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 12) {
                // 1. Creation Timestamp
                timelineNodeRow(
                    title: Language.get("WantedPet_Timeline_Created", alter: "تم تسجيل الطلب في النظام"),
                    date: pet.createdAt,
                    icon: "plus.circle.fill",
                    tint: AdminSurface.primary
                )

                // 2. Last Contacted Timestamp
                if let contacted = pet.lastContactedAt {
                    timelineNodeRow(
                        title: String(format: Language.get("WantedPet_Timeline_Contacted", alter: "تم التواصل مع العميل (%@)"), pet.lastContactChannel ?? "whatsapp"),
                        date: contacted,
                        icon: "phone.bubble.left.fill",
                        tint: Color(uiColor: .systemBlue)
                    )
                }

                // 3. Fulfilled Timestamp
                if let fulfilled = pet.fulfilledAt {
                    timelineNodeRow(
                        title: Language.get("WantedPet_Timeline_Fulfilled", alter: "تم توفير الحيوان للعميل بنجاح"),
                        date: fulfilled,
                        icon: "checkmark.seal.fill",
                        tint: Color(uiColor: .ppSuccess)
                    )
                }

                // 4. Closed Timestamp
                if let closed = pet.closedAt {
                    timelineNodeRow(
                        title: String(format: Language.get("WantedPet_Timeline_Closed", alter: "أُغلق الطلب: %@"), pet.closeReason ?? ""),
                        date: closed,
                        icon: "xmark.circle.fill",
                        tint: Color(uiColor: .systemGray)
                    )
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AdminRadius.large, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
        .shadow(color: AdminShadow.card.color, radius: AdminShadow.card.radius, y: AdminShadow.card.y)
    }

    private func timelineNodeRow(title: String, date: Date, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 2) {
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(2)

                Text(formatDossierDate(date))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()
        }
    }

    // MARK: - Interactive Bottom Sheets

    // Close Reason Sheet
    private var closeReasonSheet: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(Language.get("WantedPet_Close_Sheet_Title", alter: "إغلاق طلب العميل"))
                    .font(Font.custom("Beiruti-Bold", size: 19))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(Language.get("WantedPet_Close_Sheet_Subtitle", alter: "حدد سبب الإغلاق لأرشفة الطلب في سجل التدقيق"))
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(.top, 16)

            // Preset Reason Chips
            VStack(spacing: 8) {
                let presets = [
                    Language.get("WantedPet_Close_Preset_Bought", alter: "اشترى من متجر آخر"),
                    Language.get("WantedPet_Close_Preset_NoLonger", alter: "تراجع / لم يعد مهتماً"),
                    Language.get("WantedPet_Close_Preset_NoReply", alter: "لم يرد على محاولات الاتصال"),
                    Language.get("WantedPet_Close_Preset_Price", alter: "السعر أعلى من ميزانيته"),
                    Language.get("WantedPet_Close_Preset_Other", alter: "سبب آخر")
                ]

                ForEach(presets, id: \.self) { preset in
                    let isSelected = selectedCloseReasonPreset == preset
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedCloseReasonPreset = preset
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.secondaryText)

                            Text(preset)
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)

                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isSelected ? AdminSurface.primary.opacity(0.08) : AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isSelected ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Custom Text Input
            TextField(Language.get("WantedPet_Close_Custom_Placeholder", alter: "اكتب تفاصيل إضافية عن سبب الإغلاق..."), text: $customCloseReasonText)
                .font(Font.custom("Beiruti-Regular", size: 14))
                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

            Spacer()

            // Confirm Close Action
            Button {
                let finalReason = selectedCloseReasonPreset.isEmpty ? customCloseReasonText : (customCloseReasonText.isEmpty ? selectedCloseReasonPreset : "\(selectedCloseReasonPreset): \(customCloseReasonText)")
                guard !finalReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                showCloseSheet = false
                confirmCloseRequest(reason: finalReason)
            } label: {
                Text(Language.get("WantedPet_Action_ConfirmClose", alter: "تأكيد إغلاق الطلب"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .systemGray), in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
            }
            .buttonStyle(DossierScaleButtonStyle())
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // Fulfill Confirmation Sheet
    private var fulfillConfirmationSheet: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(Language.get("WantedPet_Fulfill_Sheet_Title", alter: "إتمام وتوفير الطلب 🎉"))
                    .font(Font.custom("Beiruti-Bold", size: 20))
                    .foregroundStyle(Color(uiColor: .ppSuccess))

                Text(Language.get("WantedPet_Fulfill_Sheet_Subtitle", alter: "تهانينا! تسجيل توفير هذا الحيوان للعميل بنجاح"))
                    .font(Font.custom("Beiruti-Regular", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(.top, 20)

            TextField(Language.get("WantedPet_Fulfill_PetId_Prompt", alter: "رقم تعريف أو حلقة الحيوان (اختياري)"), text: $fulfilledPetIdInput)
                .font(Font.custom("Beiruti-Regular", size: 14))
                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))

            Spacer()

            Button {
                showFulfillSheet = false
                confirmFulfillRequest(petId: fulfilledPetIdInput.trimmingCharacters(in: .whitespacesAndNewlines))
            } label: {
                Text(Language.get("WantedPet_Fulfill_ConfirmAction", alter: "تأكيد إتمام الطلب 🎉"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .ppSuccess), in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous))
                    .shadow(color: Color(uiColor: .ppSuccess).opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(DossierScaleButtonStyle())
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // Contact Channel Picker Sheet
    private var contactChannelSheet: some View {
        VStack(spacing: 16) {
            Text(Language.get("WantedPet_Channel_Picker_Title", alter: "قناة التواصل المستخدمة"))
                .font(Font.custom("Beiruti-Bold", size: 18))
                .foregroundStyle(AdminSurface.primaryText)
                .padding(.top, 16)

            HStack(spacing: 12) {
                channelOptionTile(
                    title: Language.get("WantedPet_Channel_WhatsApp", alter: "واتساب"),
                    channel: "whatsapp",
                    icon: "message.fill",
                    tint: Color(uiColor: .ppSuccess)
                )

                channelOptionTile(
                    title: Language.get("WantedPet_Channel_Phone", alter: "مكالمة"),
                    channel: "phone",
                    icon: "phone.fill",
                    tint: Color(uiColor: .systemBlue)
                )

                channelOptionTile(
                    title: Language.get("WantedPet_Channel_InStore", alter: "في المحل"),
                    channel: "inStore",
                    icon: "storefront.fill",
                    tint: Color(uiColor: .systemPurple)
                )
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private func channelOptionTile(title: String, channel: String, icon: String, tint: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showChannelSheet = false
            transitionStatus(to: .contacted, channel: channel)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(tint)
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(DossierScaleButtonStyle())
    }

    // Floating Toast Pill
    private func floatingToastHUD(icon: String, message: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(Font.custom("Beiruti-Bold", size: 14))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.90), in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
        .padding(.top, 60)
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(99)
    }

    // Loading State
    private var loadingDossierState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(AdminSurface.primary)
                .scaleEffect(1.2)
            Text(Language.get("Loading", alter: "جاري تحميل تفاصيل الطلب..."))
                .font(Font.custom("Beiruti-Regular", size: 14))
                .foregroundStyle(AdminSurface.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Not Found State
    private var notFoundState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(AdminSurface.secondaryText)
            Text(Language.get("WantedPet_NotFound", alter: "لم يتم العثور على هذا الطلب."))
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions & Operational Logic

    private func handleDismiss() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func loadItemLive() {
        // Fast local cache read
        if let existing = service.items.first(where: { $0.id == wantedPetId }) {
            self.item = existing
            self.isLoading = false
        }

        // Live real-time Firestore listener
        listenerRegistration?.remove()
        let docRef = Firestore.firestore().collection("CustomerWantedPets").document(wantedPetId)
        listenerRegistration = docRef.addSnapshotListener { snapshot, error in
            DispatchQueue.main.async {
                self.isLoading = false
                guard let data = snapshot?.data(), let docId = snapshot?.documentID else { return }
                self.item = CustomerWantedPet(documentId: docId, data: data)
            }
        }
    }

    private func triggerRadarScan(for pet: CustomerWantedPet) {
        withAnimation(.linear(duration: 0.8).repeatCount(2, autoreverses: false)) {
            radarRotationAngle += 360
        }
        scanStoreRadar(for: pet)
    }

    private func scanStoreRadar(for pet: CustomerWantedPet) {
        guard pet.mainKindId > 0 else { return }
        isScanningRadar = true

        Firestore.firestore().collection("petAccessories")
            .whereField("petMainCategoryID", isEqualTo: pet.mainKindId)
            .limit(to: 12)
            .getDocuments { snapshot, _ in
                DispatchQueue.main.async {
                    self.isScanningRadar = false
                    self.hasScannedRadar = true
                    guard let docs = snapshot?.documents else { return }

                    var results: [StoreMatchingPet] = []
                    for doc in docs {
                        let d = doc.data()
                        let name = (d["name"] as? String) ?? (d["title"] as? String) ?? ""
                        let price = (d["sellingPrice"] as? Double) ?? (d["price"] as? Double)
                        let ring = (d["ringTag"] as? String) ?? (d["tag"] as? String) ?? (d["code"] as? String)
                        let branch = (d["branchName"] as? String) ?? (d["branchId"] as? String)
                        let image = (d["image"] as? String) ?? (d["imageUrl"] as? String)

                        results.append(
                            StoreMatchingPet(
                                id: doc.documentID,
                                name: name.isEmpty ? pet.requestedPetTitle : name,
                                price: price,
                                ringTag: ring,
                                branchName: branch,
                                imageUrl: image
                            )
                        )
                    }
                    self.matchingInventoryPets = results
                }
            }
    }

    private func notifyCustomerWithMatch(pet: CustomerWantedPet, match: StoreMatchingPet) {
        let digits = pet.normalizedPhoneNumber.isEmpty ? pet.phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression) : pet.normalizedPhoneNumber
        let priceStr = match.price != nil ? String(format: " بسعر %.0f %@", match.price!, Language.isRTL() ? "ر.ق" : "QAR") : ""
        let template = String(
            format: Language.get("WantedPets_WhatsApp_DefaultMessage", alter: "مرحباً %@، معك متجر بيور بيتس. بخصوص طلبك لـ (%@) توفر لدينا حالياً!"),
            pet.customerName,
            match.name + priceStr
        )
        guard let encoded = template.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://wa.me/\(digits)?text=\(encoded)") else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            // Auto transition to contacted
            if pet.status == .waiting {
                transitionStatus(to: .contacted, channel: "whatsapp")
            }
        }
    }

    private func transitionStatus(to status: WantedPetStatus, channel: String? = nil) {
        Task {
            do {
                try await service.transitionStatus(id: wantedPetId, targetStatus: status, contactChannel: channel)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showNotice(Language.get("WantedPet_Interested_Success", alter: "تم تحديث حالة الطلب بنجاح"))
                    loadItemLive()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func confirmCloseRequest(reason: String) {
        Task {
            do {
                try await service.transitionStatus(id: wantedPetId, targetStatus: .closed, closeReason: reason)
                await MainActor.run {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showNotice(Language.get("WantedPets_Close_Request", alter: "تم إغلاق الطلب"))
                    loadItemLive()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func confirmFulfillRequest(petId: String) {
        Task {
            do {
                try await service.transitionStatus(id: wantedPetId, targetStatus: .fulfilled, fulfilledPetId: petId.isEmpty ? nil : petId)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showNotice(Language.get("WantedPet_Fulfilled_Banner_Title", alter: "تم إتمام الطلب بنجاح 🎉"))
                    loadItemLive()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func openWhatsAppConversation(_ pet: CustomerWantedPet) {
        let digits = pet.normalizedPhoneNumber.isEmpty ? pet.phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression) : pet.normalizedPhoneNumber
        let template = String(
            format: Language.get("WantedPets_WhatsApp_DefaultMessage", alter: "مرحباً %@، معك متجر بيور بيتس. بخصوص طلبك لـ (%@) توفر لدينا حالياً!"),
            pet.customerName,
            pet.requestedPetTitle
        )
        guard let encoded = template.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://wa.me/\(digits)?text=\(encoded)") else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            if pet.status == .waiting {
                transitionStatus(to: .contacted, channel: "whatsapp")
            }
        }
    }

    private func callCustomerPhone(_ phone: String) {
        let clean = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard let url = URL(string: "tel://\(clean)") else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIApplication.shared.open(url)
    }

    private func copyCustomerPhone(_ phone: String) {
        UIPasteboard.general.string = phone
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { showCopiedAlert = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showCopiedAlert = false }
        }
    }

    private func copyCustomerInfo(_ pet: CustomerWantedPet) {
        let info = "\(pet.customerName)\n\(pet.phoneNumber)\n\(pet.requestedPetTitle)"
        UIPasteboard.general.string = info
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showNotice(Language.get("Copied", alter: "تم النسخ بنجاح"))
    }

    private func shareDossierSummary(_ pet: CustomerWantedPet) {
        let text = String(format: Language.get("WantedPet_Share_Summary", alter: "طلب عميل: %@ يبحث عن %@ (هاتف: %@)"), pet.customerName, pet.requestedPetTitle, pet.phoneNumber)
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private func showNotice(_ text: String) {
        actionNoticeMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation {
                if actionNoticeMessage == text { actionNoticeMessage = nil }
            }
        }
    }

    // MARK: - Presentation Helpers

    private func customerMonogram(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "C" }
        let components = trimmed.components(separatedBy: .whitespaces)
        if components.count >= 2, let first = components.first?.first, let second = components[1].first {
            return "\(first)\(second)"
        }
        return String(trimmed.prefix(1))
    }

    private func iconForKind(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("قط") || lower.contains("cat") {
            return "cat.fill"
        } else if lower.contains("كلب") || lower.contains("كلاب") || lower.contains("dog") {
            return "dog.fill"
        } else if lower.contains("طير") || lower.contains("طيور") || lower.contains("bird") {
            return "bird.fill"
        } else if lower.contains("سمك") || lower.contains("أسماك") || lower.contains("fish") {
            return "fish.fill"
        } else if lower.contains("أرنب") || lower.contains("rabbit") || lower.contains("hamster") {
            return "hare.fill"
        } else if lower.contains("زواحف") || lower.contains("reptile") {
            return "lizard.fill"
        }
        return "pawprint.fill"
    }

    private func freshnessColor(for date: Date) -> Color {
        let hours = Calendar.current.dateComponents([.hour], from: date, to: Date()).hour ?? 0
        if hours < 24 {
            return Color(uiColor: .ppSuccess)
        } else if hours < 72 {
            return Color(uiColor: .ppWarning)
        } else {
            return Color(uiColor: .ppError)
        }
    }

    private func freshnessLabel(for date: Date) -> String {
        let hours = Calendar.current.dateComponents([.hour], from: date, to: Date()).hour ?? 0
        if hours < 24 {
            return Language.get("WantedPet_Freshness_Fresh", alter: "طلب حديث")
        } else if hours < 72 {
            return Language.get("WantedPet_Freshness_Normal", alter: "قيد الانتظار")
        } else {
            return Language.get("WantedPet_Freshness_Delayed", alter: "متابعة عاجلة")
        }
    }

    private func formatDossierDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Store Matching Pet Model

public struct StoreMatchingPet: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let price: Double?
    public let ringTag: String?
    public let branchName: String?
    public let imageUrl: String?
}

// MARK: - Tactile Scale Button Style

private struct DossierScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
