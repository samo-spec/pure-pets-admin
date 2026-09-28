//
//  AddWantedPetSheet.swift
//  Pure Pets Admin
//
//  A focused, native demand-capture surface for the existing Wanted Pets service.
//

import SwiftUI
import UIKit
import FirebaseFirestore

public struct AddWantedPetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var service = WantedPetsService.shared
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case phone, name, color, budget, notes
    }

    @State private var customerName = ""
    @State private var phoneNumber = ""
    @State private var selectedPOSCustomer: POSCustomerRecord?
    @State private var showsCustomerPicker = false
    @State private var contactSource: WantedPetContactSource = .whatsapp
    @State private var isLookingUpCustomer = false
    @State private var lookupFoundCustomerName: String?
    @State private var existingActiveCount = 0
    @State private var phoneLookupTask: Task<Void, Never>?

    @State private var availableMainKinds: [MainKindsModel] = []
    @State private var selectedMainKind: MainKindsModel?
    @State private var availableSubKinds: [SubKindModel] = []
    @State private var selectedSubKind: SubKindModel?
    @State private var isLoadingTaxonomy = false
    @State private var isLoadingSubkinds = false
    @State private var taxonomyError: String?
    @State private var subkindError: String?

    @State private var showPreferencesSection = false
    @State private var sexPreference: WantedPetSexPreference = .any
    @State private var colorPreference = ""
    @State private var budgetMaxText = ""
    @State private var notes = ""

    @State private var duplicateWarningMessage: String?
    @State private var duplicateExistingRequest: CustomerWantedPet?
    @State private var reviewExistingRequest: CustomerWantedPet?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let onSaved: ((String) -> Void)?

    public init(onSaved: ((String) -> Void)? = nil) {
        self.onSaved = onSaved
    }

    private var staffCanManage: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff else { return false }
        return staff.isActive() && staff.hasPermission("stock.manage")
    }

    private var canReadPOSDirectory: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isActive() else { return false }
        return staff.hasPermission("pos.view") || staff.hasPermission("pos.sell")
    }

    private var canCreatePOSCustomer: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isActive() else { return false }
        return staff.hasPermission("pos.sell")
    }

    private let colorPresets: [(ar: String, en: String, color: Color)] = [
        ("أبيض", "White", .white),
        ("ذهبي", "Golden", Color(red: 0.95, green: 0.77, blue: 0.35)),
        ("رمادي", "Grey", Color(red: 0.65, green: 0.68, blue: 0.72)),
        ("أسود", "Black", Color(red: 0.15, green: 0.15, blue: 0.18)),
        ("بني", "Brown", Color(red: 0.55, green: 0.38, blue: 0.25)),
        ("ملون", "Multi", .purple)
    ]
    private let budgetPresets: [Int] = [500, 1000, 2000, 3500, 5000]

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    introduction

                    if let warning = duplicateWarningMessage {
                        duplicateWarningCard(warning)
                            .padding(.top, AdminSpacing.lg)
                    }
                    if let error = errorMessage {
                        errorBanner(error)
                            .padding(.top, AdminSpacing.lg)
                    }

                    customerSection
                        .padding(.top, AdminSpacing.xl)
                    sectionDivider
                    petSection
                    sectionDivider
                    sourceSection
                    sectionDivider
                    preferencesSection
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, AdminSpacing.screenMargin)
                .frame(maxWidth: .infinity)
                .padding(.top, AdminSpacing.lg)
                .padding(.bottom, AdminSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .allowsHitTesting(!isSubmitting)
            .background(AdminSurface.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { actionDock }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(Language.get("WantedPets_Add_Title", alter: "إضافة طلب عميل"))
                        .font(Font.custom("Beiruti-Bold", size: 18))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AdminSurface.primaryText)
                            .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                            .background(AdminSurface.surface, in: Circle())
                    }
                    .accessibilityLabel(Language.get("Cancel", alter: "إلغاء"))
                    .disabled(isSubmitting)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(Language.get("Done", alter: "تم")) { focusedField = nil }
                        .font(AdminType.bodyBold)
                }
            }
            .sheet(isPresented: $showsCustomerPicker) {
                POSCustomerPickerSheet(
                    currentSelected: selectedPOSCustomer,
                    canCreateCustomer: canCreatePOSCustomer,
                    purpose: .wantedPetRequest,
                    onSelect: { customer in
                        customerName = customer.name
                        phoneNumber = customer.phone
                        selectedPOSCustomer = customer
                        duplicateWarningMessage = nil
                        showsCustomerPicker = false
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                )
            }
            .navigationDestination(item: $reviewExistingRequest) { request in
                WantedPetDetailView(wantedPetId: request.id)
            }
            .onAppear(perform: loadTaxonomy)
            .onDisappear { phoneLookupTask?.cancel() }
            .interactiveDismissDisabled(isSubmitting)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    // MARK: - Living request header

    private var introduction: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            HStack(alignment: .top, spacing: AdminSpacing.base) {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(Language.get("WantedPets_Capture_Title", alter: "نحفظ رغبة العميل حتى يجد رفيقه"))
                        .font(AdminType.title2)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(Language.get("WantedPets_Capture_Subtitle", alter: "حدّد من نُبلغ، وما الحيوان الذي نبحث عنه."))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                let headerColor = selectedMainKind != nil
                    ? MainKindVisuals.color(for: selectedMainKind!.id, name: selectedMainKind!.kindName)
                    : AdminSurface.primary
                let headerSymbol = selectedMainKind != nil
                    ? MainKindVisuals.symbol(for: selectedMainKind!.id, name: selectedMainKind!.kindName)
                    : "pawprint.fill"

                Image(systemName: headerSymbol)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(headerColor)
                    .frame(width: 52, height: 52)
                    .background(headerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AdminRadius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: AdminRadius.large)
                            .strokeBorder(headerColor.opacity(0.25), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }

            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: canSubmit ? "checkmark.circle.fill" : (staffCanManage ? "circle.dotted" : "lock.fill"))
                    .foregroundStyle(canSubmit ? AdminSurface.emerald : AdminSurface.secondaryText)
                Text(!staffCanManage
                     ? Language.get("WantedPets_No_Manage_Permission", alter: "يلزم إذن إدارة المخزون لحفظ الطلب")
                     : (canSubmit
                        ? Language.get("WantedPets_Ready_Badge", alter: "جاهز للحفظ")
                        : Language.get("WantedPets_Incomplete_Badge", alter: "بانتظار البيانات")))
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(AdminSurface.hairline)
            .frame(height: 1)
            .padding(.vertical, AdminSpacing.xl)
            .accessibilityHidden(true)
    }

    private func sectionHeading(_ index: String, _ title: String, complete: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.md) {
            Text(index)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AdminSurface.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(AdminType.title3)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if complete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(AdminSurface.emerald)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Customer identity

    private var customerSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            sectionHeading("01", Language.get("WantedPets_Customer_Section", alter: "بيانات العميل"),
                           complete: !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                           !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if canReadPOSDirectory {
                Button {
                    focusedField = nil
                    showsCustomerPicker = true
                } label: {
                    HStack(spacing: AdminSpacing.md) {
                        Group {
                            if let selectedPOSCustomer {
                                Text(selectedPOSCustomer.initials)
                                    .font(AdminType.headlineBold)
                            } else {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.primary.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(selectedPOSCustomer?.name ?? Language.get("WantedPets_Directory_Action", alter: "اختيار عميل من الدليل"))
                                .font(AdminType.bodyBold)
                                .foregroundStyle(AdminSurface.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let selectedPOSCustomer {
                                Text(selectedPOSCustomer.phone)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .environment(\.layoutDirection, .leftToRight)
                            } else {
                                Text(Language.get("WantedPets_Directory_Hint", alter: "ابحث عن عميل مسجّل أو أضف عميلاً جديداً"))
                                    .font(AdminType.footnote)
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AdminSurface.primary)
                            .accessibilityHidden(true)
                    }
                    .padding(AdminSpacing.base)
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).strokeBorder(AdminSurface.primary.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Language.get("WantedPets_Directory_A11y", alter: "يفتح دليل عملاء نقطة البيع"))
            }

            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(Language.get("WantedPets_Customer_Phone", alter: "رقم الهاتف"))
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                HStack(spacing: AdminSpacing.md) {
                    Image(systemName: "phone")
                        .foregroundStyle(AdminSurface.primary)
                        .accessibilityHidden(true)
                    TextField(Language.get("WantedPets_Phone_Placeholder", alter: "+974 0000 0000"), text: $phoneNumber)
                        .font(.system(.body, design: .rounded))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .multilineTextAlignment(.leading)
                        .environment(\.layoutDirection, .leftToRight)
                        .focused($focusedField, equals: .phone)
                        .onChange(of: phoneNumber) { newValue in
                            if let selectedPOSCustomer, selectedPOSCustomer.phone != newValue {
                                self.selectedPOSCustomer = nil
                            }
                            duplicateWarningMessage = nil
                            handlePhoneNumberChange(newValue)
                        }
                        .accessibilityLabel(Language.get("WantedPets_Customer_Phone", alter: "رقم الهاتف"))
                }
                .padding(.horizontal, AdminSpacing.base)
                .padding(.vertical, AdminSpacing.md)
                .frame(minHeight: 54)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }

            if isLookingUpCustomer {
                Label(Language.get("WantedPets_Searching_Customer", alter: "جاري البحث..."), systemImage: "magnifyingglass")
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
            } else if let foundName = lookupFoundCustomerName {
                HStack(spacing: AdminSpacing.sm) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(AdminSurface.emerald)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: Language.get("WantedPets_Customer_Found", alter: "وجدنا العميل: %@"), foundName))
                            .font(AdminType.footnoteBold)
                        if existingActiveCount > 0 {
                            Text(String(format: Language.get("WantedPets_ActiveRequests_Notice", alter: "لديه %d طلبات نشطة حالياً."), existingActiveCount))
                                .font(AdminType.footnote)
                        }
                    }
                    Spacer(minLength: 0)
                    if customerName != foundName {
                        Button(Language.get("WantedPets_Use_Name_Action", alter: "استخدام")) {
                            customerName = foundName
                        }
                        .font(AdminType.footnoteBold)
                        .frame(minHeight: AdminTouchTarget.minimum)
                    }
                }
                .foregroundStyle(AdminSurface.secondaryText)
                .padding(AdminSpacing.md)
                .background(AdminSurface.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: AdminRadius.medium))
            }

            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(Language.get("WantedPets_Customer_Name", alter: "اسم العميل"))
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                HStack(spacing: AdminSpacing.md) {
                    Image(systemName: "person")
                        .foregroundStyle(AdminSurface.primary)
                        .accessibilityHidden(true)
                    TextField(Language.get("WantedPets_Name_Placeholder", alter: "اسم العميل الكامل"), text: $customerName)
                        .font(AdminType.body)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .multilineTextAlignment(.leading)
                        .onChange(of: customerName) { newValue in
                            if let selectedPOSCustomer, selectedPOSCustomer.name != newValue {
                                self.selectedPOSCustomer = nil
                            }
                            duplicateWarningMessage = nil
                        }
                        .accessibilityLabel(Language.get("WantedPets_Customer_Name", alter: "اسم العميل"))
                }
                .padding(.horizontal, AdminSpacing.base)
                .padding(.vertical, AdminSpacing.md)
                .frame(minHeight: 54)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
        }
    }

    // MARK: - Pet intent

    private var petSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            sectionHeading("02", Language.get("WantedPets_Pet_Section", alter: "الحيوان المطلوب"), complete: selectedMainKind != nil)
            Text(Language.get("WantedPets_Pet_Hint", alter: "اختر الفئة التي سنراقب توفرها للعميل."))
                .font(AdminType.subheadline)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if isLoadingTaxonomy && availableMainKinds.isEmpty {
                HStack(spacing: AdminSpacing.sm) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(Language.get("WantedPets_Loading_Categories", alter: "جاري تحميل فئات الحيوانات..."))
                        .font(AdminType.footnote)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            } else if let taxonomyError {
                inlineRecovery(taxonomyError, action: loadTaxonomy)
            } else if availableMainKinds.isEmpty {
                inlineRecovery(Language.get("WantedPets_No_Categories", alter: "لا توجد فئات متاحة حالياً."), action: loadTaxonomy)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 138), spacing: AdminSpacing.sm)], spacing: AdminSpacing.sm) {
                    ForEach(availableMainKinds, id: \.id) { kind in
                        kindChoice(kind)
                    }
                }
            }

            if selectedMainKind != nil {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(Language.get("WantedPets_Select_SubKind", alter: "النوع أو السلالة (اختياري)"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.secondaryText)
                    if isLoadingSubkinds {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                    } else if let subkindError, let selectedMainKind {
                        inlineRecovery(subkindError) { loadSubKinds(for: selectedMainKind) }
                    } else {
                        Menu {
                            Button(Language.get("WantedPets_Any_SubKind", alter: "أي نوع من هذه الفئة")) { selectedSubKind = nil }
                            ForEach(availableSubKinds, id: \.id) { sub in
                                Button(displayName(for: sub)) { selectedSubKind = sub }
                            }
                        } label: {
                            HStack(spacing: AdminSpacing.sm) {
                                Text(selectedBreedTitle)
                                    .font(AdminType.body)
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AdminSurface.primary)
                            }
                            .padding(AdminSpacing.base)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                            .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                        }
                        .accessibilityLabel(Language.get("WantedPets_Select_SubKind", alter: "النوع أو السلالة (اختياري)"))
                        .accessibilityValue(selectedBreedTitle)
                    }
                }
                .padding(.top, AdminSpacing.sm)
            }
        }
    }

    private func kindChoice(_ kind: MainKindsModel) -> some View {
        let isSelected = selectedMainKind?.id == kind.id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(AdminAnimation.motion(.spring(response: 0.28, dampingFraction: 0.86), reduceMotion: reduceMotion)) {
                selectedMainKind = kind
                selectedSubKind = nil
                availableSubKinds = []
                duplicateWarningMessage = nil
                loadSubKinds(for: kind)
            }
        } label: {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: iconForKind(kind.kindName))
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 34)
                    .accessibilityHidden(true)
                Text(displayName(for: kind))
                    .font(AdminType.bodyBold)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
            .padding(.horizontal, AdminSpacing.md)
            .padding(.vertical, AdminSpacing.base)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(isSelected ? AdminSurface.primary : AdminSurface.surface,
                        in: RoundedRectangle(cornerRadius: AdminRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.card)
                .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func displayName(for kind: MainKindsModel) -> String {
        let preferred = Language.isRTL() ? kind.kindNameAr : kind.kindNameEn
        return preferred.isEmpty ? kind.kindName : preferred
    }

    private func displayName(for sub: SubKindModel) -> String {
        let preferred = Language.isRTL() ? sub.subKindNameAr : sub.subKindNameEn
        return preferred.isEmpty ? sub.subKindName : preferred
    }

    private var selectedBreedTitle: String {
        guard let selectedSubKind else {
            return Language.get("WantedPets_Any_SubKind", alter: "أي نوع من هذه الفئة")
        }
        return displayName(for: selectedSubKind)
    }

    // MARK: - How the request arrived

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            sectionHeading("03", Language.get("WantedPets_Contact_Source", alter: "مصدر الطلب"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 180 : 138), spacing: AdminSpacing.sm)], spacing: AdminSpacing.sm) {
                ForEach(WantedPetContactSource.allCases) { source in
                    let isSelected = contactSource == source
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(AdminAnimation.motion(.easeOut(duration: 0.18), reduceMotion: reduceMotion)) {
                            contactSource = source
                        }
                    } label: {
                        HStack(spacing: AdminSpacing.sm) {
                            Image(systemName: source.iconName)
                                .font(.system(size: 16))
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            Text(source.title)
                                .font(AdminType.subheadlineBold)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.primaryText)
                        .padding(.horizontal, AdminSpacing.md)
                        .padding(.vertical, AdminSpacing.md)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(isSelected ? AdminSurface.primary.opacity(0.10) : AdminSurface.surface,
                                    in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium)
                            .strokeBorder(isSelected ? AdminSurface.primary.opacity(0.55) : AdminSurface.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Optional matching details

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(AdminAnimation.motion(.spring(response: 0.3, dampingFraction: 0.86), reduceMotion: reduceMotion)) {
                    showPreferencesSection.toggle()
                }
            } label: {
                HStack(spacing: AdminSpacing.md) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 19))
                        .foregroundStyle(AdminSurface.primary)
                        .frame(width: 44, height: 44)
                        .background(AdminSurface.primary.opacity(0.09), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Language.get("WantedPets_Preferences_Section", alter: "المواصفات والتفضيلات (اختياري)"))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if !showPreferencesSection {
                            Text(preferenceSummaryText)
                                .font(AdminType.footnote)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: showPreferencesSection ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(AdminSpacing.base)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.card).strokeBorder(AdminSurface.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityValue(showPreferencesSection
                                ? Language.get("WantedPets_Expanded", alter: "مفتوح")
                                : Language.get("WantedPets_Collapsed", alter: "مغلق"))

            if showPreferencesSection {
                VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                    sexControl
                    colorControl
                    budgetControl
                    notesControl
                }
                .padding(.top, AdminSpacing.sm)
            }
        }
    }

    private var sexControl: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(Language.get("WantedPets_Sex_Preference", alter: "الجنس المفضل"))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 100), spacing: AdminSpacing.sm)], spacing: AdminSpacing.sm) {
                ForEach(WantedPetSexPreference.allCases) { sex in
                    selectionButton(sex.title, selected: sexPreference == sex) {
                        sexPreference = sex
                    }
                }
            }
        }
    }

    private var colorControl: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(Language.get("WantedPets_Color_Preference", alter: "اللون المفضل"))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 104), spacing: AdminSpacing.sm)], spacing: AdminSpacing.sm) {
                ForEach(colorPresets.indices, id: \.self) { index in
                    let preset = colorPresets[index]
                    let title = Language.isRTL() ? preset.ar : preset.en
                    let isSelected = colorPreference == preset.ar || colorPreference == preset.en
                    Button {
                        // Existing matching data uses the Arabic preset value.
                        colorPreference = isSelected ? "" : preset.ar
                    } label: {
                        HStack(spacing: AdminSpacing.sm) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 1))
                                .accessibilityHidden(true)
                            Text(title)
                                .font(AdminType.footnoteBold)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.primaryText)
                        .padding(.horizontal, AdminSpacing.md)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(isSelected ? AdminSurface.primary.opacity(0.10) : AdminSurface.surface,
                                    in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                        .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium)
                            .strokeBorder(isSelected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            TextField(Language.get("WantedPets_Color_Placeholder", alter: "أو اكتب لوناً محدداً"), text: colorTextBinding)
                .font(AdminType.body)
                .focused($focusedField, equals: .color)
                .multilineTextAlignment(.leading)
                .padding(AdminSpacing.md)
                .frame(minHeight: 54)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                .accessibilityLabel(Language.get("WantedPets_Color_Preference", alter: "اللون المفضل"))
        }
    }

    private var budgetControl: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(Language.get("WantedPets_Budget_Max", alter: "أقصى ميزانية (ر.ق)"))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 128 : 84), spacing: AdminSpacing.sm)], spacing: AdminSpacing.sm) {
                ForEach(budgetPresets, id: \.self) { amount in
                    selectionButton("\(amount)", selected: budgetMaxText == "\(amount)") {
                        budgetMaxText = budgetMaxText == "\(amount)" ? "" : "\(amount)"
                    }
                }
            }
            HStack(spacing: AdminSpacing.sm) {
                TextField(Language.get("WantedPets_Budget_Placeholder", alter: "أو اكتب ميزانية مخصصة"), text: $budgetMaxText)
                    .keyboardType(.numberPad)
                    .font(.system(.body, design: .rounded))
                    .focused($focusedField, equals: .budget)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(Language.get("WantedPets_Budget_Max", alter: "أقصى ميزانية (ر.ق)"))
                Text(Language.get("WantedPets_Currency_QAR", alter: "ر.ق"))
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(AdminSpacing.md)
            .frame(minHeight: 54)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).strokeBorder(AdminSurface.hairline, lineWidth: 1))
        }
    }

    private var notesControl: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(Language.get("WantedPets_Notes", alter: "ملاحظات إضافية"))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
            TextField(Language.get("WantedPets_Notes_Placeholder", alter: "أي تفاصيل أخرى تساعدنا في المطابقة"), text: $notes, axis: .vertical)
                .font(AdminType.body)
                .focused($focusedField, equals: .notes)
                .lineLimit(2...4)
                .multilineTextAlignment(.leading)
                .padding(AdminSpacing.md)
                .frame(minHeight: 70, alignment: .topLeading)
                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium).strokeBorder(AdminSurface.hairline, lineWidth: 1))
                .accessibilityLabel(Language.get("WantedPets_Notes", alter: "ملاحظات إضافية"))
        }
    }

    private func selectionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Text(title)
                .font(AdminType.footnoteBold)
                .foregroundStyle(selected ? AdminSurface.primary : AdminSurface.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, AdminSpacing.sm)
                .background(selected ? AdminSurface.primary.opacity(0.10) : AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium)
                    .strokeBorder(selected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func inlineRecovery(_ message: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: AdminSpacing.sm) {
            Text(message)
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(Language.get("Retry", alter: "إعادة المحاولة"), action: action)
                .font(AdminType.footnoteBold)
                .frame(minHeight: AdminTouchTarget.minimum)
        }
        .padding(AdminSpacing.md)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
    }

    private var preferenceSummaryText: String {
        var items: [String] = []
        if sexPreference != .any { items.append(sexPreference.title) }
        if !colorPreference.isEmpty { items.append(displayedColorPreference) }
        if !budgetMaxText.isEmpty {
            items.append(String(format: Language.get("WantedPets_Budget_UpTo", alter: "حتى %@ ر.ق"), budgetMaxText))
        }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(Language.get("WantedPets_Notes_Added", alter: "ملاحظات مضافة"))
        }
        return items.isEmpty
            ? Language.get("WantedPets_Preferences_Hint", alter: "الجنس، اللون، الميزانية والملاحظات")
            : items.joined(separator: " · ")
    }

    private var displayedColorPreference: String {
        guard !Language.isRTL(),
              let preset = colorPresets.first(where: { $0.ar == colorPreference }) else {
            return colorPreference
        }
        return preset.en
    }

    private var colorTextBinding: Binding<String> {
        Binding(
            get: { displayedColorPreference },
            set: { colorPreference = $0 }
        )
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
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(message)
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let duplicateExistingRequest {
                Button {
                    reviewExistingRequest = duplicateExistingRequest
                } label: {
                    Label(Language.get("WantedPets_Review_Existing", alter: "مراجعة الطلب الحالي"), systemImage: "arrow.up.right.square")
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(AdminSurface.primary)
                        .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                }
                .buttonStyle(.plain)
            }

            let actionLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
                : AnyLayout(HStackLayout(spacing: AdminSpacing.md))
            actionLayout {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    submitRequest(addAnyway: true)
                } label: {
                    Text(Language.get("WantedPets_Add_Anyway", alter: "إضافة على أي حال"))
                        .font(AdminType.footnoteBold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: AdminTouchTarget.minimum)
                        .background(Color(uiColor: .ppWarning), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || !canSubmit)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    duplicateWarningMessage = nil
                } label: {
                    Text(Language.get("Cancel", alter: "تراجع"))
                        .font(AdminType.footnote)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(minHeight: AdminTouchTarget.minimum)
                }
                .buttonStyle(.plain)
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
                .font(AdminType.footnote)
                .foregroundStyle(Color(uiColor: .ppError))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .ppError).opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Safe-area action

    private var actionDock: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AdminSurface.hairline).frame(height: 1)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                submitRequest(addAnyway: false)
            } label: {
                HStack(spacing: AdminSpacing.sm) {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: canSubmit ? "arrow.forward" : "lock.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isSubmitting
                         ? Language.get("WantedPets_Saving", alter: "جاري حفظ الطلب...")
                         : (canSubmit ? Language.get("WantedPets_Save_Action", alter: "حفظ الطلب") : validationHelpPrompt))
                        .font(AdminType.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(canSubmit ? Color.white : AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.horizontal, AdminSpacing.md)
                .background(canSubmit ? AdminSurface.primary : AdminSurface.cardElevated,
                            in: RoundedRectangle(cornerRadius: AdminRadius.button))
            }
            .disabled(!canSubmit || isSubmitting)
            .buttonStyle(.plain)
            .padding(.horizontal, AdminSpacing.screenMargin)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.top, AdminSpacing.md)
            .padding(.bottom, AdminSpacing.sm)
        }
        .background(AdminSurface.background)
    }

    private var budgetValue: Double? {
        let text = budgetMaxText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let digitMap: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        return Double(String(text.map { digitMap[$0] ?? $0 }))
    }

    private var isBudgetValid: Bool {
        let text = budgetMaxText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || (budgetValue.map { $0.isFinite && $0 >= 0 } ?? false)
    }

    private var canSubmit: Bool {
        let digits = phoneDigits(in: phoneNumber).count
        return staffCanManage &&
            !customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            customerName.count <= 120 &&
            (6...20).contains(digits) &&
            selectedMainKind != nil && isBudgetValid
    }

    private var validationHelpPrompt: String {
        if !staffCanManage {
            return Language.get("WantedPets_No_Manage_Permission", alter: "يلزم إذن إدارة المخزون لحفظ الطلب")
        }
        if !(6...20).contains(phoneDigits(in: phoneNumber).count) {
            return Language.get("WantedPets_Prompt_ValidPhone", alter: "أدخل رقم هاتف صحيحاً")
        }
        if customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Language.get("WantedPets_Prompt_Name", alter: "أدخل اسم العميل")
        }
        if customerName.count > 120 {
            return Language.get("WantedPets_Prompt_ShortName", alter: "اختصر اسم العميل إلى 120 حرفاً")
        }
        if selectedMainKind == nil {
            return Language.get("WantedPets_Prompt_Species", alter: "اختر فئة الحيوان المطلوبة")
        }
        if !isBudgetValid {
            return Language.get("WantedPets_Prompt_ValidBudget", alter: "أدخل ميزانية صحيحة")
        }
        return Language.get("WantedPets_Save_Action", alter: "حفظ الطلب")
    }

    // MARK: - Actions & Business Operations

    private func phoneDigits(in value: String) -> String {
        let digitMap: [Character: Character] = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]
        return String(value.compactMap { character in
            if let mapped = digitMap[character] { return mapped }
            return "0123456789".contains(character) ? character : nil
        })
    }

    private func handlePhoneNumberChange(_ raw: String) {
        phoneLookupTask?.cancel()
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        lookupFoundCustomerName = nil
        existingActiveCount = 0
        isLookingUpCustomer = false
        guard phoneDigits(in: clean).count >= 6 else {
            lookupFoundCustomerName = nil
            return
        }

        isLookingUpCustomer = true
        phoneLookupTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                let lookup = try await service.lookupCustomerByPhone(phoneNumber: clean)
                await MainActor.run {
                    guard !Task.isCancelled,
                          self.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines) == clean else { return }
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
                    if !Task.isCancelled,
                       self.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines) == clean {
                        self.isLookingUpCustomer = false
                    }
                }
            }
        }
    }

    private func loadTaxonomy() {
        taxonomyError = nil
        if let cached = AppManager.shared().mainKindsArray as? [MainKindsModel], !cached.isEmpty {
            self.availableMainKinds = cached
            return
        }

        isLoadingTaxonomy = true
        Firestore.firestore().collection("MainKindsCollection").order(by: "sortingKey").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingTaxonomy = false
                if error != nil {
                    self.taxonomyError = Language.get("WantedPets_Categories_Error", alter: "تعذر تحميل فئات الحيوانات.")
                    return
                }
                guard let docs = snapshot?.documents else { return }
                self.availableMainKinds = docs.map { MainKindsModel(snapshot: $0) }
            }
        }
    }

    private func loadSubKinds(for species: MainKindsModel) {
        let docID = species.documentID.isEmpty ? "\(species.id)" : species.documentID
        guard !docID.isEmpty else { return }

        isLoadingSubkinds = true
        subkindError = nil
        Firestore.firestore().collection("MainKindsCollection").document(docID).collection("SubKinds").order(by: "ID").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                guard self.selectedMainKind?.id == species.id else { return }
                self.isLoadingSubkinds = false
                if error != nil {
                    self.subkindError = Language.get("WantedPets_Breeds_Error", alter: "تعذر تحميل السلالات.")
                    return
                }
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
        guard canSubmit, !isSubmitting, let main = selectedMainKind else { return }
        focusedField = nil
        isSubmitting = true
        errorMessage = nil

        let budget = budgetValue
        let capturedName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedSource = contactSource
        let capturedSubkind = selectedSubKind
        let capturedSex = sexPreference
        let capturedColor = colorPreference.trimmingCharacters(in: .whitespacesAndNewlines)
        let capturedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let result = try await service.createRequest(
                    customerName: capturedName,
                    phoneNumber: capturedPhone,
                    contactSource: capturedSource,
                    mainKindId: main.id,
                    mainKindName: main.kindName,
                    subkindId: capturedSubkind?.id,
                    subkindName: capturedSubkind?.subKindName,
                    sexPreference: capturedSex,
                    colorPreference: capturedColor,
                    budgetMin: nil,
                    budgetMax: budget,
                    notes: capturedNotes,
                    addAnyway: addAnyway
                )

                await MainActor.run {
                    self.isSubmitting = false
                    if result.duplicateDetected {
                        self.duplicateWarningMessage = Language.get("WantedPets_Duplicate_Generic", alter: "يوجد طلب نشط سابق لهذا العميل لنفس الحيوان.")
                        self.duplicateExistingRequest = result.existingRequest
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    } else if result.ok, let id = result.id, !id.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        self.onSaved?(id)
                        dismiss()
                    } else {
                        self.errorMessage = Language.get("WantedPets_Save_Failed", alter: "تعذر حفظ الطلب. حاول مرة أخرى.")
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
        return MainKindVisuals.symbol(for: 0, name: name)
    }
}
