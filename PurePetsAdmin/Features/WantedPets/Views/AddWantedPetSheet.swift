//
//  AddWantedPetSheet.swift
//  Pure Pets Admin
//
//  Created for Pure Pets Platform.
//  Ultra-responsive, category-defining Apple-grade Wanted Pet demand capture studio.
//  Rebuilt from absolute first principles with tactile species cards, dynamic breed cloud,
//  real-time customer passport recognition, and floating glass action dock.
//

import SwiftUI
import UIKit
import FirebaseFirestore

public struct AddWantedPetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = WantedPetsService.shared

    // MARK: - Form State: Customer Passport
    @State private var customerName: String = ""
    @State private var phoneNumber: String = ""
    @State private var contactSource: WantedPetContactSource = .whatsapp
    @State private var isLookingUpCustomer: Bool = false
    @State private var lookupFoundCustomerName: String? = nil
    @State private var existingActiveCount: Int = 0

    // MARK: - Form State: Pet Species & Breed Cloud
    @State private var availableMainKinds: [MainKindsModel] = []
    @State private var selectedMainKind: MainKindsModel? = nil
    @State private var availableSubKinds: [SubKindModel] = []
    @State private var selectedSubKind: SubKindModel? = nil
    @State private var customBreedText: String = ""
    @State private var isLoadingTaxonomy: Bool = false
    @State private var isLoadingSubkinds: Bool = false

    // MARK: - Form State: Progressive Studio Preferences
    @State private var showPreferencesSection: Bool = false
    @State private var sexPreference: WantedPetSexPreference = .any
    @State private var colorPreference: String = ""
    @State private var budgetMaxText: String = ""
    @State private var notes: String = ""

    // MARK: - Duplicate & Submission State
    @State private var duplicateWarningMessage: String? = nil
    @State private var duplicateExistingRequest: CustomerWantedPet? = nil
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    private let onSaved: ((String) -> Void)?

    public init(onSaved: ((String) -> Void)? = nil) {
        self.onSaved = onSaved
    }

    // Quick color swatch options
    private let colorPresets: [(nameAr: String, nameEn: String, color: Color)] = [
        ("أبيض", "White", Color.white),
        ("ذهبي", "Golden", Color(red: 0.95, green: 0.77, blue: 0.35)),
        ("رمادي", "Grey", Color(red: 0.65, green: 0.68, blue: 0.72)),
        ("أسود", "Black", Color(red: 0.15, green: 0.15, blue: 0.18)),
        ("بني", "Brown", Color(red: 0.55, green: 0.38, blue: 0.25)),
        ("ملون", "Multi", Color.purple.opacity(0.7))
    ]

    // Quick budget chips
    private let budgetPresets: [Double] = [500, 1000, 2000, 3500, 5000]

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background Layer
                AdminSurface.background
                    .ignoresSafeArea()

                // Main Scrollable Canvas
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Hero Header Card
                        heroHeaderCard

                        // Duplicate Warning Banner (if triggered)
                        if let warning = duplicateWarningMessage {
                            duplicateWarningCard(warning)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        // Section 1: Customer Passport
                        customerPassportCard

                        // Section 2: Interactive Species Showcase & Breed Cloud
                        petSpeciesShowcaseCard

                        // Section 3: Communication Channel Matrix
                        contactChannelCard

                        // Section 4: Progressive Studio Preferences (Collapsible)
                        progressivePreferencesCard

                        // Error Banner (if any)
                        if let error = errorMessage {
                            errorBanner(error)
                                .transition(.opacity)
                        }

                        // Bottom Spacer for floating dock
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // Floating Action Glass Dock
                floatingGlassDock
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                        Text(Language.get("WantedPets_Add_Title", alter: "إضافة طلب حيوان"))
                            .font(Font.custom("Beiruti-Bold", size: 17))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Cancel", alter: "إلغاء"))
                                .font(Font.custom("Beiruti-Regular", size: 14))
                        }
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdminSurface.cardElevated.opacity(0.85), in: Capsule())
                        .overlay(Capsule().strokeBorder(AdminSurface.hairline, lineWidth: 0.5))
                    }
                }
            }
            .onAppear {
                loadTaxonomy()
            }
            .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: - Hero Header Card

    private var heroHeaderCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AdminSurface.primary.opacity(0.18), AdminSurface.primary.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Language.get("WantedPets_QuickAdd_Title", alter: "تسجيل طلب حيوان جديد"))
                        .font(Font.custom("Beiruti-Bold", size: 18))
                        .foregroundStyle(AdminSurface.primaryText)

                    Spacer()

                    // Live Form Readiness Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(canSubmit ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                            .frame(width: 7, height: 7)
                        Text(canSubmit ? Language.get("WantedPets_Ready_Badge", alter: "جاهز للحفظ") : Language.get("WantedPets_Incomplete_Badge", alter: "بانتظار البيانات"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(canSubmit ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (canSubmit ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.12),
                        in: Capsule()
                    )
                }

                Text(Language.get("WantedPets_QuickAdd_Subtitle", alter: "تسجيل فوري لرغبة العميل للتنبيه والمطابقة عند توفر المخزون"))
                    .font(Font.custom("Beiruti-Regular", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Section 1: Customer Passport Card

    private var customerPassportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card Title Header
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("WantedPets_Customer_Section", alter: "بيانات العميل"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                if isLookingUpCustomer {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.65)
                        Text(Language.get("WantedPets_Searching_Customer", alter: "جاري البحث..."))
                            .font(Font.custom("Beiruti-Regular", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            VStack(spacing: 12) {
                // Phone Number Field with Integrated Country/Lookup
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Language.get("WantedPets_Customer_Phone", alter: "رقم الهاتف / الجوال"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Spacer()

                        if !phoneNumber.isEmpty {
                            Button {
                                phoneNumber = ""
                                lookupFoundCustomerName = nil
                                existingActiveCount = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        // Phone Icon Badge
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: "phone.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminSurface.primary)
                        }

                        // Phone TextField
                        TextField("010xxxxxxxx / +974...", text: $phoneNumber)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .keyboardType(.phonePad)
                            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                            .onChange(of: phoneNumber) { newValue in
                                handlePhoneNumberChange(newValue)
                            }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: AdminTouchTarget.inputField)
                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .strokeBorder(
                                !phoneNumber.isEmpty ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline,
                                lineWidth: 1
                            )
                    )
                }

                // Customer Auto-Recognized Identity Pill (Slides in when found)
                if let foundName = lookupFoundCustomerName {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .ppSuccess))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(foundName)
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundStyle(Color(uiColor: .ppSuccess))

                                Text(Language.get("WantedPets_Registered_User", alter: "عميل مسجل"))
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                                    .foregroundStyle(Color(uiColor: .ppSuccess).opacity(0.85))
                            }

                            if existingActiveCount > 0 {
                                Text(String(format: Language.get("WantedPets_ActiveRequests_Notice", alter: "لديه %d طلبات نشطة حالياً."), existingActiveCount))
                                    .font(Font.custom("Beiruti-Regular", size: 11))
                                    .foregroundStyle(Color(uiColor: .systemBlue))
                            }
                        }

                        Spacer()

                        if customerName != foundName {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                customerName = foundName
                            } label: {
                                Text(Language.get("WantedPets_Use_Name_Action", alter: "استخدام"))
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(uiColor: .ppSuccess), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .ppSuccess).opacity(0.10), in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .strokeBorder(Color(uiColor: .ppSuccess).opacity(0.25), lineWidth: 0.75)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Customer Name Field
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(Language.get("WantedPets_Customer_Name", alter: "اسم العميل"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Spacer()

                        if !customerName.isEmpty {
                            Button {
                                customerName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.cardElevated)
                                .frame(width: 32, height: 32)
                            Image(systemName: "person.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        TextField(Language.get("WantedPets_Name_Placeholder", alter: "مثال: محمد أحمد، نورة الكواري..."), text: $customerName)
                            .font(Font.custom("Beiruti-Regular", size: 16))
                            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: AdminTouchTarget.inputField)
                    .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                            .strokeBorder(
                                !customerName.isEmpty ? AdminSurface.primary.opacity(0.4) : AdminSurface.hairline,
                                lineWidth: 1
                            )
                    )
                }
            }
        }
        .padding(16)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Section 2: Interactive Pet Species Showcase & Breed Cloud

    private var petSpeciesShowcaseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("WantedPets_Pet_Section", alter: "الحيوان المطلوب"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                if let selected = selectedMainKind {
                    Text(selected.kindName)
                        .font(Font.custom("Beiruti-Bold", size: 12))
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                }
            }

            // Species Carousel / Grid
            if isLoadingTaxonomy && availableMainKinds.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 70)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableMainKinds, id: \.id) { kind in
                            let isSelected = selectedMainKind?.id == kind.id
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                    selectedMainKind = kind
                                    selectedSubKind = nil
                                    loadSubKinds(for: kind)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? LinearGradient(colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                    : LinearGradient(colors: [AdminSurface.cardElevated, AdminSurface.cardElevated.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            )
                                            .frame(width: 54, height: 54)
                                            .shadow(color: isSelected ? AdminSurface.primary.opacity(0.35) : Color.clear, radius: 8, x: 0, y: 4)

                                        Image(systemName: iconForKind(kind.kindName))
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(isSelected ? Color.white : AdminSurface.primary)
                                    }

                                    Text(kind.kindName)
                                        .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 13))
                                        .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
                                        .lineLimit(1)
                                }
                                .frame(width: 72)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(ScaleBounceButtonStyle())
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }

            // Subkind / Breed Fluid Cloud (Visible when species is selected)
            if let selectedKind = selectedMainKind {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(Language.get("WantedPets_Select_SubKind", alter: "النوع أو السلالة"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Spacer()

                        if isLoadingSubkinds {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }

                    // Breed Quick Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // "Any Breed" Chip
                            let isAnySelected = selectedSubKind == nil
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    selectedSubKind = nil
                                }
                            } label: {
                                Text(Language.get("WantedPets_Any_SubKind", alter: "أي نوع / غير محدد"))
                                    .font(Font.custom(isAnySelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 13))
                                    .foregroundStyle(isAnySelected ? Color.white : AdminSurface.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isAnySelected ? AdminSurface.primary : AdminSurface.cardElevated, in: Capsule())
                                    .overlay(
                                        Capsule().strokeBorder(isAnySelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.75)
                                    )
                            }
                            .buttonStyle(ScaleBounceButtonStyle())

                            // Specific Breed Chips from database
                            ForEach(availableSubKinds, id: \.id) { sub in
                                let isSubSelected = selectedSubKind?.id == sub.id
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        selectedSubKind = sub
                                    }
                                } label: {
                                    Text(sub.subKindName)
                                        .font(Font.custom(isSubSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 13))
                                        .foregroundStyle(isSubSelected ? Color.white : AdminSurface.primaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(isSubSelected ? AdminSurface.primary : AdminSurface.cardElevated, in: Capsule())
                                        .overlay(
                                            Capsule().strokeBorder(isSubSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.75)
                                        )
                                }
                                .buttonStyle(ScaleBounceButtonStyle())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    // MARK: - Section 3: Communication Channel Matrix

    private var contactChannelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)

                Text(Language.get("WantedPets_Contact_Source", alter: "طريقة تواصل العميل"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            // Branded Channel Grid
            HStack(spacing: 8) {
                channelItem(
                    source: .whatsapp,
                    title: "واتساب",
                    icon: "message.fill",
                    brandColor: Color(red: 0.15, green: 0.75, blue: 0.38)
                )

                channelItem(
                    source: .phone,
                    title: "اتصال",
                    icon: "phone.fill",
                    brandColor: Color(red: 0.0, green: 0.48, blue: 1.0)
                )

                channelItem(
                    source: .inStore,
                    title: "المعرض",
                    icon: "storefront.fill",
                    brandColor: Color(red: 0.95, green: 0.55, blue: 0.10)
                )

                channelItem(
                    source: .instagram,
                    title: "إنستغرام",
                    icon: "camera.fill",
                    brandColor: Color(red: 0.88, green: 0.19, blue: 0.42)
                )
            }
        }
        .padding(16)
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private func channelItem(
        source: WantedPetContactSource,
        title: String,
        icon: String,
        brandColor: Color
    ) -> some View {
        let isSelected = contactSource == source
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                contactSource = source
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? brandColor : AdminSurface.cardElevated)
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : brandColor)
                }

                Text(title)
                    .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 12))
                    .foregroundStyle(isSelected ? AdminSurface.primaryText : AdminSurface.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? brandColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .strokeBorder(isSelected ? brandColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleBounceButtonStyle())
    }

    // MARK: - Section 4: Progressive Studio Preferences (Collapsible)

    private var progressivePreferencesCard: some View {
        VStack(spacing: 0) {
            // Collapsible Toggle Header
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showPreferencesSection.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.primary.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AdminSurface.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("WantedPets_Preferences_Section", alter: "مواصفات إضافية (اختياري)"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                            .foregroundStyle(AdminSurface.primaryText)

                        if !showPreferencesSection {
                            Text(preferenceSummaryText)
                                .font(Font.custom("Beiruti-Regular", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: showPreferencesSection ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // Expanded Controls
            if showPreferencesSection {
                VStack(spacing: 16) {
                    Divider()
                        .background(AdminSurface.hairline)

                    // 1. Gender / Sex Preference (4-Segmented Slider)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Language.get("WantedPets_Sex_Preference", alter: "الجنس المفضل"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)

                        HStack(spacing: 6) {
                            ForEach(WantedPetSexPreference.allCases) { sex in
                                let isSelected = sexPreference == sex
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                        sexPreference = sex
                                    }
                                } label: {
                                    Text(sex.title)
                                        .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 13))
                                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(isSelected ? AdminSurface.primary : AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.75)
                                        )
                                }
                                .buttonStyle(ScaleBounceButtonStyle())
                            }
                        }
                    }

                    // 2. Color Preference Swatches & Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("WantedPets_Color_Preference", alter: "اللون المفضل"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)

                        // Quick Color Swatches
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(colorPresets, id: \.nameAr) { preset in
                                    let isSelected = colorPreference == preset.nameAr
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        colorPreference = isSelected ? "" : preset.nameAr
                                    } label: {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(preset.color)
                                                .frame(width: 12, height: 12)
                                                .overlay(Circle().strokeBorder(Color.gray.opacity(0.3), lineWidth: 0.5))

                                            Text(preset.nameAr)
                                                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Regular", size: 12))
                                        }
                                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(isSelected ? AdminSurface.primary : AdminSurface.cardElevated, in: Capsule())
                                        .overlay(
                                            Capsule().strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.75)
                                        )
                                    }
                                    .buttonStyle(ScaleBounceButtonStyle())
                                }
                            }
                        }

                        // Custom color text field
                        TextField(Language.get("WantedPets_Color_Placeholder", alter: "أو اكتب لون محدد (مثل: رصاصي فاتح، مشمشي...)"), text: $colorPreference)
                            .font(Font.custom("Beiruti-Regular", size: 14))
                            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }

                    // 3. Maximum Budget with Quick Chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Language.get("WantedPets_Budget_Max", alter: "الحد الأقصى للميزانية"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)

                        // Quick Budget Chips
                        HStack(spacing: 8) {
                            ForEach(budgetPresets, id: \.self) { amount in
                                let isSelected = budgetMaxText == "\(Int(amount))"
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    budgetMaxText = isSelected ? "" : "\(Int(amount))"
                                } label: {
                                    Text("\(Int(amount))")
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .monospaced))
                                        .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? AdminSurface.primary : AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.75)
                                        )
                                }
                                .buttonStyle(ScaleBounceButtonStyle())
                            }
                        }

                        // Custom Budget Input
                        HStack {
                            TextField(Language.get("WantedPets_Budget_Placeholder", alter: "أو حدد ميزانية مخصصة"), text: $budgetMaxText)
                                .keyboardType(.numberPad)
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)

                            Text(Language.isRTL() ? "ر.ق" : "QAR")
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }

                    // 4. Notes Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Language.get("WantedPets_Notes", alter: "ملاحظات إضافية من العميل"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)

                        TextField(Language.get("WantedPets_Notes_Placeholder", alter: "أي تفاصيل أخرى (عمر محدد، تدريب، متحدث، أليف مع الأطفال...)"), text: $notes)
                            .font(Font.custom("Beiruti-Regular", size: 14))
                            .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(AdminSurface.cardElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AdminSurface.hairline, lineWidth: 0.75))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(
            AdminSurface.surface,
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
        )
    }

    private var preferenceSummaryText: String {
        var items: [String] = []
        if sexPreference != .any { items.append(sexPreference.title) }
        if !colorPreference.isEmpty { items.append(colorPreference) }
        if !budgetMaxText.isEmpty { items.append("حتى \(budgetMaxText) ر.ق") }
        if items.isEmpty {
            return Language.get("WantedPets_No_Preferences", alter: "تحديد الجنس، اللون، والحد الأقصى للميزانية")
        }
        return items.joined(separator: " • ")
    }

    // MARK: - Duplicate Warning Banner

    private func duplicateWarningCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(uiColor: .ppWarning))

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get("WantedPets_Duplicate_Warning_Title", alter: "يوجد طلب نشط سابق لهذا العميل!"))
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(message)
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    submitRequest(addAnyway: true)
                } label: {
                    Text(Language.get("WantedPets_Add_Anyway", alter: "إضافة على أي حال"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .ppWarning), in: Capsule())
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation {
                        duplicateWarningMessage = nil
                    }
                } label: {
                    Text(Language.get("Cancel", alter: "تراجع"))
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(14)
        .background(
            Color(uiColor: .ppWarning).opacity(0.12),
            in: RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .strokeBorder(Color(uiColor: .ppWarning).opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color(uiColor: .ppError))
            Text(error)
                .font(Font.custom("Beiruti-Regular", size: 13))
                .foregroundStyle(Color(uiColor: .ppError))
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Floating Glass Action Dock

    private var floatingGlassDock: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AdminSurface.hairline)

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    submitRequest(addAnyway: false)
                } label: {
                    HStack(spacing: 10) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                            Text(Language.get("WantedPets_Saving", alter: "جاري حفظ الطلب..."))
                                .font(Font.custom("Beiruti-Bold", size: 16))
                                .foregroundStyle(.white)
                        } else if canSubmit {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(Language.get("WantedPets_Save_Action", alter: "حفظ طلب الحيوان 🐾"))
                                .font(Font.custom("Beiruti-Bold", size: 17))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13))
                            Text(validationHelpPrompt)
                                .font(Font.custom("Beiruti-Medium", size: 14))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        canSubmit
                            ? LinearGradient(colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [AdminSurface.cardElevated, AdminSurface.cardElevated], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    )
                    .foregroundStyle(canSubmit ? Color.white : AdminSurface.secondaryText)
                    .shadow(color: canSubmit ? AdminSurface.primary.opacity(0.35) : Color.clear, radius: 10, x: 0, y: 5)
                }
                .disabled(!canSubmit || isSubmitting)
                .buttonStyle(ScaleBounceButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial)
    }

    private var canSubmit: Bool {
        !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedMainKind != nil
    }

    private var validationHelpPrompt: String {
        if phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Language.get("WantedPets_Prompt_Phone", alter: "أدخل رقم هاتف العميل")
        }
        if customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Language.get("WantedPets_Prompt_Name", alter: "أدخل اسم العميل")
        }
        if selectedMainKind == nil {
            return Language.get("WantedPets_Prompt_Species", alter: "اختر فئة الحيوان المطلوبة")
        }
        return Language.get("WantedPets_Save_Action", alter: "حفظ الطلب")
    }

    // MARK: - Actions & Business Operations

    private func handlePhoneNumberChange(_ raw: String) {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 8 else {
            lookupFoundCustomerName = nil
            existingActiveCount = 0
            return
        }

        isLookingUpCustomer = true
        Task {
            do {
                let lookup = try await service.lookupCustomerByPhone(phoneNumber: clean)
                await MainActor.run {
                    self.isLookingUpCustomer = false
                    if lookup.found, let name = lookup.customerName {
                        self.lookupFoundCustomerName = name
                        if self.customerName.isEmpty {
                            self.customerName = name
                        }
                    } else {
                        self.lookupFoundCustomerName = nil
                    }
                    self.existingActiveCount = lookup.activeWantedPetsCount
                }
            } catch {
                await MainActor.run {
                    self.isLookingUpCustomer = false
                }
            }
        }
    }

    private func loadTaxonomy() {
        if let cached = AppManager.shared().mainKindsArray as? [MainKindsModel], !cached.isEmpty {
            self.availableMainKinds = cached
            return
        }

        isLoadingTaxonomy = true
        Firestore.firestore().collection("MainKindsCollection").order(by: "sortingKey").getDocuments { snapshot, _ in
            DispatchQueue.main.async {
                self.isLoadingTaxonomy = false
                guard let docs = snapshot?.documents else { return }
                self.availableMainKinds = docs.map { MainKindsModel(snapshot: $0) }
            }
        }
    }

    private func loadSubKinds(for species: MainKindsModel) {
        let docID = species.documentID.isEmpty ? "\(species.id)" : species.documentID
        guard !docID.isEmpty else { return }

        isLoadingSubkinds = true
        Firestore.firestore().collection("MainKindsCollection").document(docID).collection("SubKinds").order(by: "ID").getDocuments { snapshot, _ in
            DispatchQueue.main.async {
                self.isLoadingSubkinds = false
                guard let docs = snapshot?.documents else { return }
                self.availableSubKinds = docs.map { doc in
                    let sub = SubKindModel(snapshot: doc)
                    sub.documentID = doc.documentID
                    return sub
                }
            }
        }
    }

    private func submitRequest(addAnyway: Bool) {
        guard let main = selectedMainKind else { return }
        isSubmitting = true
        errorMessage = nil

        let budget = Double(budgetMaxText.trimmingCharacters(in: .whitespacesAndNewlines))

        Task {
            do {
                let result = try await service.createRequest(
                    customerName: customerName.trimmingCharacters(in: .whitespacesAndNewlines),
                    phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                    contactSource: contactSource,
                    mainKindId: main.id,
                    mainKindName: main.kindName,
                    subkindId: selectedSubKind?.id,
                    subkindName: selectedSubKind?.subKindName,
                    sexPreference: sexPreference,
                    colorPreference: colorPreference.trimmingCharacters(in: .whitespacesAndNewlines),
                    budgetMin: nil,
                    budgetMax: budget,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    addAnyway: addAnyway
                )

                await MainActor.run {
                    self.isSubmitting = false
                    if result.duplicateDetected {
                        self.duplicateWarningMessage = result.message ?? Language.get("WantedPets_Duplicate_Generic", alter: "يوجد طلب نشط سابق لهذا العميل لنفس الحيوان.")
                        self.duplicateExistingRequest = result.existingRequest
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    } else if result.ok {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        self.onSaved?(result.id ?? "")
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSubmitting = false
                    self.errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    // Dynamic icon picker based on category name
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
        } else if lower.contains("أرنب") || lower.contains("صغيرة") || lower.contains("rabbit") || lower.contains("hamster") {
            return "hare.fill"
        } else if lower.contains("زواحف") || lower.contains("reptile") {
            return "lizard.fill"
        }
        return "pawprint.fill"
    }
}

// MARK: - ScaleBounceButtonStyle

private struct ScaleBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
