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

    private var canManageRequests: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        return staff.isActive() && staff.hasPermission("stock.manage")
    }

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
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeToPop {
            handleDismiss()
        }
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
        .confirmationDialog(
            Language.get("WantedPet_WhatsApp_AutoMarkPrompt", alter: "هل تواصلت مع العميل؟"),
            isPresented: $showAutoMarkContactedPrompt
        ) {
            Button(Language.get("WantedPet_WhatsApp_AutoMarkConfirm", alter: "نعم، تم التواصل")) {
                transitionStatus(to: .contacted, channel: "whatsapp")
            }
            Button(Language.get("WantedPet_WhatsApp_AutoMarkSkip", alter: "الإبقاء على الحالة"), role: .cancel) {}
        } message: {
            Text(Language.get("WantedPet_WhatsApp_AutoMarkSub", alter: "حدّث الحالة فقط بعد التواصل الفعلي."))
        }
    }

    // MARK: - 1. Top Command & Navigation Bar

    private var topNavigationBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("WantedPets_Detail_Title", alter: "تفاصيل الطلب"),
            subtitle: item.map { $0.customerName + " • " + $0.requestedPetTitle },
            statusDotColor: item?.status.tintColor,
            isModal: false,
            customTopSpacing: 0,
            onBack: {
                handleDismiss()
            }
        ) {
            if let pet = item {
                HStack(spacing: 8) {
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

                        if canManageRequests {
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
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AdminSurface.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.8), lineWidth: 0.8)
                                )
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AdminSurface.primaryText)
                        }
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    }
                }
            }
        }
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
                let accentColor = pet.kindAccentColor
                let petSymbol = pet.kindPetSymbol

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.18), accentColor.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: petSymbol)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.28), lineWidth: 1)
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
        VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 14) {
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.primary.opacity(0.10), in: Capsule())
                }
                .buttonStyle(DossierScaleButtonStyle())
            }

            if isScanningRadar {
                HStack(spacing: 8) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(Language.get("WantedPet_Radar_Scanning", alter: "جاري فحص مخزون الحيوانات الحية..."))
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            } else if !matchingInventoryPets.isEmpty {
                // Matching Live Animals Found!
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Text(String(format: Language.get("WantedPet_Radar_MatchesFound", alter: "تم العثور على %d حيوان مطابق في المخزون!"), matchingInventoryPets.count))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(Color(uiColor: .ppSuccess))
                        Spacer()
                    }

                    ForEach(matchingInventoryPets.prefix(6)) { matchPet in
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                // Thumbnail with AdminRemoteImage
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(AdminSurface.cardElevated)
                                    AdminRemoteImage(
                                        urlString: matchPet.imageUrl,
                                        contentMode: .fill,
                                        targetSize: CGSize(width: 52, height: 52)
                                    ) {
                                        Image(systemName: iconForKind(matchPet.name))
                                            .font(.system(size: 20))
                                            .foregroundStyle(AdminSurface.primary)
                                    }
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .frame(width: 52, height: 52)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.5))

                                VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(matchPet.name)
                                            .font(Font.custom("Beiruti-Bold", size: 15))
                                            .foregroundStyle(AdminSurface.primaryText)
                                            .lineLimit(1)

                                        if matchPet.isExactBreedMatch && matchPet.isGenderMatch {
                                            Text(Language.get("WantedPet_ExactMatchPill", alter: "تطابق تام"))
                                                .font(Font.custom("Beiruti-Bold", size: 10))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(uiColor: .ppSuccess), in: Capsule())
                                        } else if matchPet.isExactBreedMatch {
                                            Text(Language.get("WantedPet_BreedMatchPill", alter: "مطابق للنوع"))
                                                .font(Font.custom("Beiruti-Bold", size: 10))
                                                .foregroundStyle(AdminSurface.primary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        if let tag = matchPet.ringTag, !tag.isEmpty {
                                            Text("#\(tag)")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundStyle(AdminSurface.primaryText)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                        }

                                        if let g = matchPet.gender, !g.isEmpty {
                                            HStack(spacing: 3) {
                                                Image(systemName: g.contains("أنثى") ? "arrow.down.circle.fill" : "arrow.up.right.circle.fill")
                                                    .font(.system(size: 10))
                                                Text(g)
                                                    .font(Font.custom("Beiruti-Medium", size: 11))
                                            }
                                            .foregroundStyle(g.contains("أنثى") ? Color.pink : Color.blue)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background((g.contains("أنثى") ? Color.pink : Color.blue).opacity(0.12), in: Capsule())
                                        }

                                        if let branch = matchPet.branchName, !branch.isEmpty {
                                            Text("• " + branch)
                                                .font(Font.custom("Beiruti-Regular", size: 11))
                                                .foregroundStyle(AdminSurface.secondaryText)
                                        }
                                    }
                                }

                                Spacer()

                                VStack(alignment: Language.isRTL() ? .leading : .trailing, spacing: 2) {
                                    if let p = matchPet.price, p > 0 {
                                        Text(String(format: "%.0f %@", p, Language.isRTL() ? "ر.ق" : "QAR"))
                                            .font(Font.custom("Beiruti-Bold", size: 15))
                                            .foregroundStyle(Color(uiColor: .ppSuccess))
                                    }
                                }
                            }

                            // Action buttons row for this match
                            HStack(spacing: 8) {
                                Button {
                                    notifyCustomerWithMatch(pet: pet, match: matchPet)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 11))
                                        Text(Language.get("WantedPet_Radar_SendToCustomer", alter: "مراسلة بالتوفر عبر واتساب"))
                                            .font(Font.custom("Beiruti-Bold", size: 12))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(red: 0.16, green: 0.78, blue: 0.40), Color(red: 0.11, green: 0.69, blue: 0.34)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .shadow(color: Color(red: 0.11, green: 0.69, blue: 0.34).opacity(0.25), radius: 3, y: 1.5)
                                }
                                .buttonStyle(DossierScaleButtonStyle())

                                if canManageRequests && pet.status.isActive {
                                    Button {
                                        confirmFulfillRequest(petId: matchPet.unitId ?? matchPet.productId)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 11))
                                            Text(Language.get("WantedPet_Fulfill_Short", alter: "إتمام بهذا الحيوان"))
                                                .font(Font.custom("Beiruti-Bold", size: 12))
                                        }
                                        .foregroundStyle(AdminSurface.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(DossierScaleButtonStyle())
                                }
                            }
                        }
                        .padding(12)
                        .background(AdminSurface.cardElevated.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    matchPet.isExactBreedMatch && matchPet.isGenderMatch
                                        ? Color(uiColor: .ppSuccess).opacity(0.40)
                                        : AdminSurface.hairline,
                                    lineWidth: matchPet.isExactBreedMatch && matchPet.isGenderMatch ? 1.0 : 0.5
                                )
                        )
                    }
                }
            } else {
                // Radar Active — No Immediate Matches
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.cardElevated, in: Circle())

                    VStack(alignment: Language.isRTL() ? .trailing : .leading, spacing: 3) {
                        Text(Language.get("WantedPet_Radar_NoMatches", alter: "لا يتوفر حالياً في المخزون — الرادار نشط"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text(Language.get("WantedPets_Card_Subtitle", alter: "سيتم تنبيهك فور إضافة حيوان مطابق في فروع بيور بيتس."))
                            .font(Font.custom("Beiruti-Regular", size: 12))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    Spacer()
                }
                .padding(14)
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
            if pet.status == .waiting && canManageRequests {
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
            } else if pet.status == .contacted && canManageRequests {
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
            } else if pet.status == .interested && canManageRequests {
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

                    if canManageRequests {
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
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
            }

            // Discreet Secondary Close Option for Active Orders
            if pet.status.isActive && canManageRequests {
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
            Text(Language.get("WantedPet_Detail_Loading", alter: "جارٍ تحميل تفاصيل الطلب..."))
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
        let targetKindId = pet.mainKindId
        let targetSubkindId = pet.subkindId
        let targetSex = pet.sexPreference
        let fallbackTitle = pet.requestedPetTitle
        isScanningRadar = true

        // Strict query on petAccessories filtering only for live pets (accessKindType == 3)
        Firestore.firestore().collection("petAccessories")
            .whereField("accessKindType", isEqualTo: 3)
            .getDocuments { snapshot, error in
                guard let docs = snapshot?.documents, !docs.isEmpty else {
                    DispatchQueue.main.async {
                        self.isScanningRadar = false
                        self.hasScannedRadar = true
                        self.matchingInventoryPets = []
                    }
                    return
                }

                // Filter docs that match targetKindId and are active/not deleted
                let matchingCatalogDocs = docs.filter { doc in
                    let d = doc.data()
                    let isDeleted = (d["isDeleted"] as? Bool) ?? false
                    let isBlocked = (d["isBlocked"] as? Bool) ?? false
                    let active = (d["active"] as? Bool) ?? true
                    guard !isDeleted, !isBlocked, active else { return false }

                    let mainId = (d["petMainCategoryID"] as? Int) ?? ((d["petMainCategoryID"] as? NSNumber)?.intValue ?? 0)
                    let mainIds = (d["petMainCategoryIDs"] as? [Int]) ?? ((d["petMainCategoryIDs"] as? [NSNumber])?.map { $0.intValue } ?? [])
                    return mainId == targetKindId || mainIds.contains(targetKindId)
                }

                if matchingCatalogDocs.isEmpty {
                    DispatchQueue.main.async {
                        self.isScanningRadar = false
                        self.hasScannedRadar = true
                        self.matchingInventoryPets = []
                    }
                    return
                }

                let group = DispatchGroup()
                var collectedMatches: [StoreMatchingPet] = []
                let lock = NSLock()

                for doc in matchingCatalogDocs {
                    let d = doc.data()
                    let docId = doc.documentID
                    let catalogName = (d["name"] as? String) ?? (d["title"] as? String) ?? fallbackTitle
                    let catalogPrice = (d["sellingPrice"] as? Double) ?? (d["price"] as? Double)
                    let catalogImage: String? = {
                        if let arr = d["imageURLsArray"] as? [String], let first = arr.first, !first.isEmpty {
                            return first
                        }
                        return (d["image"] as? String) ?? (d["imageUrl"] as? String)
                    }()
                    let branchId = (d["branchID"] as? String) ?? (d["storeID"] as? String) ?? ""
                    let branchName: String = {
                        if !branchId.isEmpty {
                            return PPBranchContextManager.shared().localizedBranchName(forID: branchId, fallback: "بيور بيتس")
                        }
                        return (d["branchName"] as? String) ?? "بيور بيتس"
                    }()
                    let catalogSubkindId = (d["petSubCategoryID"] as? Int) ?? ((d["petSubCategoryID"] as? NSNumber)?.intValue ?? 0)
                    let isBreedMatch = (targetSubkindId != nil && targetSubkindId! > 0 && catalogSubkindId == targetSubkindId!)
                    let inventoryMode = (d["inventoryMode"] as? String) ?? ""

                    if inventoryMode == "INDIVIDUAL_TRACKED" {
                        group.enter()
                        doc.reference.collection("inventoryUnits")
                            .whereField("status", isEqualTo: "AVAILABLE")
                            .limit(to: 10)
                            .getDocuments { unitsSnap, _ in
                                defer { group.leave() }
                                let unitDocs = unitsSnap?.documents ?? []
                                lock.lock()
                                defer { lock.unlock() }

                                if !unitDocs.isEmpty {
                                    for uDoc in unitDocs {
                                        let uData = uDoc.data()
                                        let ring = (uData["ringTag"] as? String) ?? (uData["tag"] as? String)
                                        let unitPrice = (uData["sellingPrice"] as? Double) ?? catalogPrice
                                        let rawGender = ((uData["gender"] as? String) ?? "").uppercased()
                                        let genderDisplay: String? = {
                                            switch rawGender {
                                            case "FEMALE": return Language.get("LivePetUnit_Gender_Female", alter: "أنثى")
                                            case "MALE": return Language.get("LivePetUnit_Gender_Male", alter: "ذكر")
                                            case "PAIR": return Language.get("LivePetUnit_Gender_Pair", alter: "زوج")
                                            default: return nil
                                            }
                                        }()
                                        let isGenderMatch: Bool = {
                                            switch targetSex {
                                            case .female: return rawGender == "FEMALE"
                                            case .male: return rawGender == "MALE"
                                            case .pair: return rawGender == "PAIR"
                                            case .any: return true
                                            }
                                        }()

                                        var score = 50
                                        if isBreedMatch { score += 40 }
                                        if isGenderMatch { score += 20 }
                                        if let p = unitPrice {
                                            if let bMax = pet.budgetMax, p <= bMax { score += 10 }
                                            if let bMin = pet.budgetMin, p < bMin { score -= 10 }
                                        }

                                        collectedMatches.append(
                                            StoreMatchingPet(
                                                id: uDoc.documentID,
                                                name: catalogName,
                                                price: unitPrice,
                                                ringTag: ring,
                                                branchName: branchName,
                                                imageUrl: catalogImage,
                                                gender: genderDisplay,
                                                isExactBreedMatch: isBreedMatch,
                                                isGenderMatch: isGenderMatch,
                                                unitId: uDoc.documentID,
                                                productId: docId,
                                                matchScore: score
                                            )
                                        )
                                    }
                                } else {
                                    let availableCount = (d["availableUnitPricedCount"] as? Int) ?? (d["quantity"] as? Int) ?? 0
                                    let noStock = (d["noStock"] as? Bool) ?? false
                                    if availableCount > 0 && !noStock {
                                        var score = 40
                                        if isBreedMatch { score += 40 }
                                        collectedMatches.append(
                                            StoreMatchingPet(
                                                id: docId,
                                                name: catalogName,
                                                price: catalogPrice,
                                                ringTag: nil,
                                                branchName: branchName,
                                                imageUrl: catalogImage,
                                                gender: nil,
                                                isExactBreedMatch: isBreedMatch,
                                                isGenderMatch: true,
                                                unitId: nil,
                                                productId: docId,
                                                matchScore: score
                                            )
                                        )
                                    }
                                }
                            }
                    } else {
                        // QUANTITY_TRACKED or legacy
                        let qty = (d["quantity"] as? Int) ?? 0
                        let noStock = (d["noStock"] as? Bool) ?? false
                        if qty > 0 && !noStock {
                            var score = 40
                            if isBreedMatch { score += 40 }
                            lock.lock()
                            collectedMatches.append(
                                StoreMatchingPet(
                                    id: docId,
                                    name: catalogName,
                                    price: catalogPrice,
                                    ringTag: (d["ringTag"] as? String) ?? (d["barcode"] as? String),
                                    branchName: branchName,
                                    imageUrl: catalogImage,
                                    gender: nil,
                                    isExactBreedMatch: isBreedMatch,
                                    isGenderMatch: true,
                                    unitId: nil,
                                    productId: docId,
                                    matchScore: score
                                )
                            )
                            lock.unlock()
                        }
                    }
                }

                group.notify(queue: .main) {
                    self.isScanningRadar = false
                    self.hasScannedRadar = true
                    self.matchingInventoryPets = collectedMatches.sorted { a, b in
                        if a.matchScore != b.matchScore {
                            return a.matchScore > b.matchScore
                        }
                        return (a.price ?? 0) < (b.price ?? 0)
                    }
                }
            }
    }

    private func notifyCustomerWithMatch(pet: CustomerWantedPet, match: StoreMatchingPet) {
        let rawNumber = pet.normalizedPhoneNumber.isEmpty ? pet.phoneNumber : pet.normalizedPhoneNumber
        let digits = rawNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)

        var details: [String] = []
        if let ring = match.ringTag, !ring.isEmpty {
            details.append(String(format: Language.get("WantedPets_WhatsApp_Detail_Ring", alter: "رقم التعريف: #%@"), ring))
        }
        if let g = match.gender, !g.isEmpty {
            details.append(String(format: Language.get("WantedPets_WhatsApp_Detail_Gender", alter: "الجنس: %@"), g))
        }
        if let p = match.price, p > 0 {
            details.append(String(format: Language.get("WantedPets_WhatsApp_Detail_Price", alter: "السعر: %.0f %@"), p, Language.isRTL() ? "ر.ق" : "QAR"))
        }
        if let branch = match.branchName, !branch.isEmpty {
            details.append(String(format: Language.get("WantedPets_WhatsApp_Detail_Branch", alter: "الفرع: %@"), branch))
        }
        let detailString = details.isEmpty ? "" : " (" + details.joined(separator: " • ") + ")"

        let template = String(
            format: Language.get("WantedPets_WhatsApp_MatchFound_Template", alter: "مرحباً %@، يسعدنا إبلاغك بتوفر حيوان مطابق لطلبك في بيور بيتس: %@%@. هل ترغب بحجزه لك؟"),
            pet.customerName,
            match.name,
            detailString
        )
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(digits)"
        components.queryItems = [URLQueryItem(name: "text", value: template)]
        guard !digits.isEmpty, let url = components.url,
              UIApplication.shared.canOpenURL(url) else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIApplication.shared.open(url) { opened in
            if opened && pet.status == .waiting {
                DispatchQueue.main.async {
                    if self.canManageRequests {
                        self.showAutoMarkContactedPrompt = true
                    }
                }
            }
        }
    }

    private func transitionStatus(to status: WantedPetStatus, channel: String? = nil) {
        guard canManageRequests else {
            errorMessage = Language.get("WantedPets_View_Only", alter: "تعديل الطلبات يتطلب صلاحية إدارة المخزون")
            return
        }
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
        guard canManageRequests else {
            errorMessage = Language.get("WantedPets_View_Only", alter: "تعديل الطلبات يتطلب صلاحية إدارة المخزون")
            return
        }
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
        guard canManageRequests else {
            errorMessage = Language.get("WantedPets_View_Only", alter: "تعديل الطلبات يتطلب صلاحية إدارة المخزون")
            return
        }
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
        let rawNumber = pet.normalizedPhoneNumber.isEmpty ? pet.phoneNumber : pet.normalizedPhoneNumber
        let digits = rawNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        let template = String(
            format: Language.get("WantedPets_WhatsApp_CheckIn_Template", alter: "مرحباً %@، نتواصل معك من بيور بيتس بخصوص طلبك لـ %@. هل لا يزال طلبك قائماً؟"),
            pet.customerName,
            pet.requestedPetTitle
        )
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(digits)"
        components.queryItems = [URLQueryItem(name: "text", value: template)]
        guard !digits.isEmpty, let url = components.url,
              UIApplication.shared.canOpenURL(url) else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIApplication.shared.open(url) { opened in
            if opened && pet.status == .waiting {
                DispatchQueue.main.async {
                    if self.canManageRequests {
                        self.showAutoMarkContactedPrompt = true
                    }
                }
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
        return MainKindVisuals.symbol(for: item?.mainKindId ?? 0, name: name)
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

public struct StoreMatchingPet: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let price: Double?
    public let ringTag: String?
    public let branchName: String?
    public let imageUrl: String?
    public let gender: String?
    public let isExactBreedMatch: Bool
    public let isGenderMatch: Bool
    public let unitId: String?
    public let productId: String
    public let matchScore: Int

    public init(
        id: String,
        name: String,
        price: Double? = nil,
        ringTag: String? = nil,
        branchName: String? = nil,
        imageUrl: String? = nil,
        gender: String? = nil,
        isExactBreedMatch: Bool = false,
        isGenderMatch: Bool = false,
        unitId: String? = nil,
        productId: String = "",
        matchScore: Int = 0
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.ringTag = ringTag
        self.branchName = branchName
        self.imageUrl = imageUrl
        self.gender = gender
        self.isExactBreedMatch = isExactBreedMatch
        self.isGenderMatch = isGenderMatch
        self.unitId = unitId
        self.productId = productId
        self.matchScore = matchScore
    }
}

// MARK: - Tactile Scale Button Style

private struct DossierScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
