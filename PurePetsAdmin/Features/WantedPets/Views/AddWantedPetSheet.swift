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
    @State private var automaticallyFilledName: String?
    @State private var automaticallyFilledPhone: String?

    @State private var availableMainKinds: [MainKindsModel] = []
    @State private var selectedMainKind: MainKindsModel?
    @State private var availableSubKinds: [SubKindModel] = []
    @State private var selectedSubKind: SubKindModel?
    @State private var isLoadingTaxonomy = false
    @State private var isLoadingSubkinds = false
    @State private var taxonomyError: String?
    @State private var subkindError: String?
    @State private var subkindLoadID = UUID()

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

    private var canLookupCustomers: Bool {
        guard let staff = PPStaffAuth.shared().cachedCurrentStaff, staff.isActive() else { return false }
        return staff.hasPermission("stock.view")
    }

    // Arabic values are the established matching payload, not display copy.
    private let colorPresets: [(value: String, key: String, color: Color)] = [
        ("أبيض", "WantedPets_Color_White", .white),
        ("ذهبي", "WantedPets_Color_Golden", Color(red: 0.95, green: 0.77, blue: 0.35)),
        ("رمادي", "WantedPets_Color_Grey", Color(red: 0.65, green: 0.68, blue: 0.72)),
        ("أسود", "WantedPets_Color_Black", Color(red: 0.15, green: 0.15, blue: 0.18)),
        ("بني", "WantedPets_Color_Brown", Color(red: 0.55, green: 0.38, blue: 0.25)),
        ("ملون", "WantedPets_Color_Multi", .purple)
    ]
    private let budgetPresets: [Int] = [500, 1000, 2000, 3500, 5000]

    public var body: some View {
        VStack(spacing: 0) {
            navigationHeader
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: AdminSpacing.lg) {
                        introduction
                        VStack(spacing: AdminSpacing.md) {
                            if let warning = duplicateWarningMessage {
                                duplicateWarningCard(warning)
                            }
                            if let error = errorMessage {
                                errorBanner(error)
                            }
                        }
                        .id("captureFeedback")
                        customerSection
                        petSection
                        VStack(spacing: AdminSpacing.base) {
                            sourceSection
                            Divider().overlay(AdminSurface.hairline)
                            preferencesSection
                        }
                        .padding(AdminSpacing.base)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large))
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, AdminSpacing.screenMargin)
                    .frame(maxWidth: .infinity)
                    .padding(.top, AdminSpacing.base)
                    .padding(.bottom, AdminSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .disabled(isSubmitting)
                .safeAreaInset(edge: .bottom, spacing: 0) { actionDock }
                .onChange(of: duplicateWarningMessage) { message in
                    guard message != nil else { return }
                    withAnimation(AdminAnimation.motion(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                        proxy.scrollTo("captureFeedback", anchor: .top)
                    }
                }
                .onChange(of: errorMessage) { message in
                    guard message != nil else { return }
                    withAnimation(AdminAnimation.motion(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                        proxy.scrollTo("captureFeedback", anchor: .top)
                    }
                }
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(
            WantedPetCaptureNavigationGuard(isSaving: isSubmitting, isRTL: Language.isRTL())
        )
        .toolbar {
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
                    automaticallyFilledName = nil
                    automaticallyFilledPhone = nil
                    customerName = customer.name
                    phoneNumber = customer.phone
                    selectedPOSCustomer = customer
                    clearDuplicateWarning()
                    showsCustomerPicker = false
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            )
        }
        .navigationDestination(item: $reviewExistingRequest) { request in
            WantedPetDetailView(wantedPetId: request.id)
        }
        .onAppear {
            if availableMainKinds.isEmpty { loadTaxonomy() }
        }
        .onDisappear {
            phoneLookupTask?.cancel()
            isLookingUpCustomer = false
        }
        .interactiveDismissDisabled(isSubmitting)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .multilineTextAlignment(.leading)
        .accessibilityAction(.escape) {
            guard !isSubmitting else { return }
            dismiss()
        }
    }

    // MARK: - Request brief

    private var navigationHeader: some View {
        HStack(spacing: AdminSpacing.md) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                    .background(AdminSurface.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityLabel(Language.get("Back", alter: "رجوع"))
            .accessibilityIdentifier("wantedPets.capture.back")
            Text(Language.get("WantedPets_Add_Title", alter: "إضافة طلب عميل"))
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AdminSpacing.screenMargin)
        .padding(.vertical, AdminSpacing.sm)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.background)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.md))

            let baseLottieWidth: CGFloat = 118
            let baseLottieHeight: CGFloat = 102
            // Increase Lottie size a little from top with bottom anchor preserved
            let lottieWidth: CGFloat = 140
            let lottieHeight: CGFloat = 122

            headerLayout {
                VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                    Text(Language.get("WantedPets_Capture_Brief_Title", alter: "رفيق يستحق الانتظار"))
                        .font(AdminType.title)
                        .foregroundStyle(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(Language.get("WantedPets_Capture_Brief_Hint", alter: "نسجّل رغبة العميل لنعود إليه عند توفر ما يناسبه."))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PPLottieFirebaseView(
                    fileName: "Boy Giving Food To Bird.json",
                    loop: true,
                    speed: 1.0,
                    contentMode: .scaleAspectFit
                )
                .frame(width: lottieWidth, height: lottieHeight)
                .offset(y: -((lottieHeight - baseLottieHeight) / 2.0))
                .frame(width: lottieWidth, height: baseLottieHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            let briefLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.md))
                : AnyLayout(HStackLayout(alignment: .top, spacing: AdminSpacing.base))
            briefLayout {
                briefItem(title: Language.get("WantedPets_Customer_Section", alter: "بيانات العميل"),
                          value: customerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? Language.get("WantedPets_Capture_Customer_Empty", alter: "أضف العميل") : customerName,
                          complete: isCustomerComplete, symbol: "person")
                briefItem(title: Language.get("WantedPets_Pet_Section", alter: "الحيوان المطلوب"),
                          value: selectedMainKind.map { displayName(for: $0) }
                          ?? Language.get("WantedPets_Capture_Animal_Empty", alter: "اختر الحيوان"),
                          complete: selectedMainKind != nil, symbol: "pawprint")
            }
            .padding(AdminSpacing.base)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large))
        }
    }

    private var isCustomerComplete: Bool {
        let name = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 120 && (6...20).contains(phoneDigits(in: phoneNumber).count)
    }

    private func briefItem(title: String, value: String, complete: Bool, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(spacing: AdminSpacing.sm) {
                Image(systemName: complete ? "checkmark.circle.fill" : symbol)
                    .foregroundStyle(complete ? AdminSurface.emerald : AdminSurface.secondaryText)
                    .accessibilityHidden(true)
                Text(title).font(AdminType.caption1Bold).foregroundStyle(AdminSurface.secondaryText)
            }
            Text(value)
                .font(AdminType.bodyBold)
                .foregroundStyle(complete ? AdminSurface.primaryText : AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeading(_ title: String, symbol: String, complete: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AdminSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
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
        VStack(alignment: .leading, spacing: AdminSpacing.md) {
            sectionHeading(Language.get("WantedPets_Capture_Customer", alter: "لمن نبحث؟"),
                           symbol: "person.crop.circle", complete: isCustomerComplete)

            VStack(spacing: 0) {
                captureField(Language.get("WantedPets_Customer_Name", alter: "اسم العميل"), symbol: "person") {
                    TextField(Language.get("WantedPets_Name_Placeholder", alter: "اسم العميل الكامل"), text: $customerName)
                        .font(AdminType.body)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .name)
                        .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
                        .onSubmit { focusedField = .phone }
                        .onChange(of: customerName) { newValue in
                            if let selectedPOSCustomer, selectedPOSCustomer.name != newValue {
                                self.selectedPOSCustomer = nil
                            }
                            if newValue != automaticallyFilledName {
                                automaticallyFilledName = nil
                                automaticallyFilledPhone = nil
                            }
                            clearDuplicateWarning()
                        }
                        .accessibilityLabel(Language.get("WantedPets_Customer_Name", alter: "اسم العميل"))
                        .accessibilityIdentifier("wantedPets.capture.name")
                }
                Divider().overlay(AdminSurface.hairline).padding(.horizontal, AdminSpacing.base)
                captureField(Language.get("WantedPets_Customer_Phone", alter: "رقم الهاتف"), symbol: "phone") {
                    ZStack(alignment: .leading) {
                        if phoneNumber.isEmpty {
                            Text(Language.get("WantedPets_Phone_Placeholder", alter: "+974 0000 0000"))
                                .font(AdminType.body)
                                .foregroundStyle(AdminSurface.secondaryText.opacity(0.6))
                                .environment(\.layoutDirection, .leftToRight)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextField("", text: $phoneNumber)
                            .font(AdminType.body)
                            .foregroundStyle(AdminSurface.primaryText)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .multilineTextAlignment(.leading)
                            .environment(\.layoutDirection, .leftToRight)
                            .focused($focusedField, equals: .phone)
                            .onChange(of: phoneNumber) { newValue in
                                if let selectedPOSCustomer, selectedPOSCustomer.phone != newValue {
                                    self.selectedPOSCustomer = nil
                                }
                                clearDuplicateWarning()
                                handlePhoneNumberChange(newValue)
                            }
                            .accessibilityLabel(Language.get("WantedPets_Customer_Phone", alter: "رقم الهاتف"))
                            .accessibilityIdentifier("wantedPets.capture.phone")
                    }
                }

                if canReadPOSDirectory {
                    Divider().overlay(AdminSurface.hairline).padding(.horizontal, AdminSpacing.base)
                    Button {
                        focusedField = nil
                        showsCustomerPicker = true
                    } label: {
                        HStack(spacing: AdminSpacing.sm) {
                            Image(systemName: "person.crop.rectangle.stack")
                                .accessibilityHidden(true)
                            Text(Language.get("WantedPets_Capture_Directory", alter: "من دليل العملاء"))
                                .font(AdminType.subheadlineBold)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(AdminSurface.primary)
                        .padding(.horizontal, AdminSpacing.base)
                        .padding(.vertical, AdminSpacing.sm)
                        .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Language.get("WantedPets_Directory_A11y", alter: "يفتح دليل عملاء نقطة البيع"))
                    .accessibilityIdentifier("wantedPets.capture.directory")
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.large)
                .strokeBorder(AdminSurface.hairline, lineWidth: AdminStroke.hairline))

            if isLookingUpCustomer {
                HStack(spacing: AdminSpacing.sm) {
                    ProgressView().controlSize(.small).tint(AdminSurface.primary)
                    Text(Language.get("WantedPets_Searching_Customer", alter: "جاري البحث..."))
                        .font(AdminType.footnote)
                }
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityElement(children: .combine)
            } else if let foundName = lookupFoundCustomerName {
                let lookupLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.md))
                lookupLayout {
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Label(String(format: Language.get("WantedPets_Customer_Found", alter: "وجدنا العميل: %@"), foundName),
                              systemImage: "person.crop.circle.badge.checkmark")
                            .font(AdminType.footnoteBold)
                        if existingActiveCount > 0 {
                            Text(String(format: Language.get("WantedPets_ActiveRequests_Notice", alter: "لديه %d طلبات نشطة حالياً."), existingActiveCount))
                                .font(AdminType.footnote)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if customerName != foundName {
                        Button(Language.get("WantedPets_Use_Name_Action", alter: "استخدام")) {
                            automaticallyFilledName = foundName
                            automaticallyFilledPhone = phoneDigits(in: phoneNumber)
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
        }
    }

    private func captureField<Content: View>(_ title: String, symbol: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: AdminSpacing.md) {
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(title)
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .accessibilityHidden(true)
                content()
                    .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
            }
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(AdminSurface.secondaryText)
                .frame(width: 24)
                .accessibilityHidden(true)
        }
        .padding(AdminSpacing.base)
    }

    // MARK: - Pet intent

    private var petSection: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            Text(Language.get("WantedPets_Pet_Section", alter: "الحيوان المطلوب"))
                .font(AdminType.footnoteBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                if isLoadingTaxonomy && availableMainKinds.isEmpty {
                    HStack(spacing: AdminSpacing.sm) {
                        ProgressView().tint(AdminSurface.primary)
                        Text(Language.get("WantedPets_Loading_Categories", alter: "جاري تحميل فئات الحيوانات..."))
                            .font(AdminType.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(AdminSpacing.base)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                } else if let taxonomyError {
                    inlineRecovery(taxonomyError, action: loadTaxonomy)
                } else if availableMainKinds.isEmpty {
                    inlineRecovery(Language.get("WantedPets_No_Categories", alter: "لا توجد فئات متاحة حالياً."), action: loadTaxonomy)
                } else {
                    categoryPicker
                }

                if selectedMainKind != nil {
                    Divider().overlay(AdminSurface.hairline).padding(.horizontal, AdminSpacing.base)
                    VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                        Text(Language.get("WantedPets_Select_SubKind", alter: "النوع أو السلالة (اختياري)"))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.secondaryText)
                        if isLoadingSubkinds {
                            ProgressView().tint(AdminSurface.primary)
                                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
                        } else if let subkindError, let selectedMainKind {
                            inlineRecovery(subkindError) { loadSubKinds(for: selectedMainKind) }
                        } else {
                            Menu {
                                Button(Language.get("WantedPets_Any_SubKind", alter: "أي نوع من هذه الفئة")) {
                                    selectedSubKind = nil
                                    clearDuplicateWarning()
                                }
                                ForEach(availableSubKinds, id: \.id) { sub in
                                    Button {
                                        selectedSubKind = sub
                                        clearDuplicateWarning()
                                    } label: {
                                        if selectedSubKind?.id == sub.id {
                                            Label(displayName(for: sub), systemImage: "checkmark")
                                        } else {
                                            Text(displayName(for: sub))
                                        }
                                    }
                                }
                            } label: {
                                pickerValue(selectedBreedTitle)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Language.get("WantedPets_Select_SubKind", alter: "النوع أو السلالة (اختياري)"))
                            .accessibilityValue(selectedBreedTitle)
                            .accessibilityIdentifier("wantedPets.capture.breed")
                        }
                    }
                    .padding(.horizontal, AdminSpacing.base)
                    .padding(.vertical, AdminSpacing.sm)
                }
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: AdminRadius.large))
            .overlay(RoundedRectangle(cornerRadius: AdminRadius.large)
                .strokeBorder(AdminSurface.hairline, lineWidth: AdminStroke.hairline))
        }
    }

    private var categoryPicker: some View {
        let symbol = selectedMainKind.map { MainKindVisuals.symbol(for: $0.id, name: $0.kindName) } ?? "pawprint"
        let color = selectedMainKind.map { MainKindVisuals.color(for: $0.id, name: $0.kindName) } ?? AdminSurface.primary
        let title = selectedMainKind.map { displayName(for: $0) }
            ?? Language.get("WantedPets_Capture_Animal_Empty", alter: "اختر الحيوان")
        return Menu {
            ForEach(availableMainKinds, id: \.id) { kind in
                Button { selectMainKind(kind) } label: {
                    Label(displayName(for: kind),
                          systemImage: selectedMainKind?.id == kind.id
                          ? "checkmark" : MainKindVisuals.symbol(for: kind.id, name: kind.kindName))
                }
            }
        } label: {
            HStack(spacing: AdminSpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                pickerValue(title)
            }
            .padding(.horizontal, AdminSpacing.base)
            .padding(.vertical, AdminSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Language.get("WantedPets_Pet_Section", alter: "الحيوان المطلوب"))
        .accessibilityValue(title)
        .accessibilityIdentifier("wantedPets.capture.category")
    }

    private func pickerValue(_ title: String) -> some View {
        HStack(spacing: AdminSpacing.sm) {
            Text(title)
                .font(AdminType.bodyBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: AdminSpacing.sm)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AdminSurface.secondaryText)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
    }

    private func selectMainKind(_ kind: MainKindsModel) {
        guard selectedMainKind?.id != kind.id else { return }
        focusedField = nil
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(AdminAnimation.motion(.easeOut(duration: 0.18), reduceMotion: reduceMotion)) {
            selectedMainKind = kind
            selectedSubKind = nil
            availableSubKinds = []
            clearDuplicateWarning()
        }
        loadSubKinds(for: kind)
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
        Menu {
            ForEach(WantedPetContactSource.allCases) { source in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    contactSource = source
                } label: {
                    Label(source.title, systemImage: contactSource == source ? "checkmark" : source.iconName)
                }
            }
        } label: {
            let sourceLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: AdminSpacing.md))
            sourceLayout {
                Text(Language.get("WantedPets_Contact_Source", alter: "مصدر الطلب"))
                    .font(AdminType.subheadline)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: AdminSpacing.sm) {
                    Image(systemName: contactSource.iconName).accessibilityHidden(true)
                    Text(contactSource.title)
                        .font(AdminType.bodyBold)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(AdminSurface.primaryText)
            }
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Language.get("WantedPets_Contact_Source", alter: "مصدر الطلب"))
        .accessibilityValue(contactSource.title)
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
                        .frame(width: 24, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Language.get("WantedPets_Capture_Preferences", alter: "تخصيص الطلب"))
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
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.comfortable, alignment: .leading)
                .contentShape(Rectangle())
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
                    let title = Language.get(preset.key, alter: preset.value)
                    let isSelected = colorPreference == preset.value
                    Button {
                        // Existing matching data uses the Arabic preset value.
                        colorPreference = isSelected ? "" : preset.value
                    } label: {
                        HStack(spacing: AdminSpacing.sm) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(AdminSurface.hairline, lineWidth: 1))
                                .accessibilityHidden(true)
                            Text(title)
                                .font(AdminType.footnoteBold)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(isSelected ? AdminSurface.primary : AdminSurface.primaryText)
                        .padding(.horizontal, AdminSpacing.md)
                        .padding(.vertical, AdminSpacing.sm)
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
                .multilineTextAlignment(Language.isRTL() ? .trailing : .leading)
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
                    .keyboardType(.decimalPad)
                    .font(.system(.body, design: .rounded))
                    .focused($focusedField, equals: .budget)
                    .multilineTextAlignment(budgetMaxText.isEmpty && Language.isRTL() ? .trailing : .leading)
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
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, AdminSpacing.sm)
                .padding(.vertical, AdminSpacing.xs)
                .background(selected ? AdminSurface.primary.opacity(0.10) : AdminSurface.surface,
                            in: RoundedRectangle(cornerRadius: AdminRadius.medium))
                .overlay(RoundedRectangle(cornerRadius: AdminRadius.medium)
                    .strokeBorder(selected ? AdminSurface.primary : AdminSurface.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func inlineRecovery(_ message: String, action: @escaping () -> Void) -> some View {
        let recoveryLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AdminSpacing.sm))
            : AnyLayout(HStackLayout(spacing: AdminSpacing.sm))
        return recoveryLayout {
            Text(message)
                .font(AdminType.footnote)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
            ? Language.get("WantedPets_Capture_Preferences_Hint", alter: "اختياري · الجنس واللون والميزانية والملاحظات")
            : items.joined(separator: " · ")
    }

    private var displayedColorPreference: String {
        guard let preset = colorPresets.first(where: { $0.value == colorPreference }) else {
            return colorPreference
        }
        return Language.get(preset.key, alter: preset.value)
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
                        .background(AdminSurface.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting || !canSubmit)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    clearDuplicateWarning()
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
        VStack(alignment: .leading, spacing: AdminSpacing.sm) {
            HStack(alignment: .top, spacing: AdminSpacing.sm) {
                Image(systemName: canSubmit ? "checkmark.circle.fill" : (staffCanManage ? "circle.dotted" : "lock.fill"))
                    .foregroundStyle(canSubmit ? AdminSurface.emerald : AdminSurface.secondaryText)
                    .accessibilityHidden(true)
                Text(canSubmit
                     ? Language.get("WantedPets_Capture_Ready", alter: "الطلب مكتمل")
                     : validationHelpPrompt)
                    .font(AdminType.footnoteBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                submitRequest(addAnyway: false)
            } label: {
                HStack(spacing: AdminSpacing.sm) {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isSubmitting
                         ? Language.get("WantedPets_Saving", alter: "جاري حفظ الطلب...")
                         : Language.get("WantedPets_Save_Action", alter: "حفظ الطلب"))
                        .font(AdminType.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(canSubmit ? Color.white : AdminSurface.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, AdminSpacing.md)
                .padding(.vertical, AdminSpacing.sm)
                .background(canSubmit ? AdminSurface.primary : AdminSurface.cardElevated,
                            in: RoundedRectangle(cornerRadius: AdminRadius.button))
            }
            .disabled(!canSubmit || isSubmitting)
            .buttonStyle(.plain)
            .accessibilityIdentifier("wantedPets.capture.save")
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, AdminSpacing.screenMargin)
        .frame(maxWidth: .infinity)
        .padding(.top, AdminSpacing.md)
        .padding(.bottom, AdminSpacing.sm)
        .background(AdminSurface.background)
        .overlay(alignment: .top) {
            Rectangle().fill(AdminSurface.hairline).frame(height: AdminStroke.hairline)
                .accessibilityHidden(true)
        }
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
        return Double(String(text.map { digitMap[$0] ?? $0 }).replacingOccurrences(of: "٫", with: "."))
    }

    private var isBudgetValid: Bool {
        let text = budgetMaxText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || (budgetValue.map { $0.isFinite && $0 >= 0 } ?? false)
    }

    private var canSubmit: Bool {
        return staffCanManage && isCustomerComplete && selectedMainKind != nil && isBudgetValid
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
        if customerName.trimmingCharacters(in: .whitespacesAndNewlines).count > 120 {
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

    private func clearDuplicateWarning() {
        duplicateWarningMessage = nil
        duplicateExistingRequest = nil
    }

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
        if let automaticallyFilledName,
           customerName == automaticallyFilledName,
           automaticallyFilledPhone != phoneDigits(in: clean) {
            customerName = ""
            self.automaticallyFilledName = nil
            automaticallyFilledPhone = nil
        }
        lookupFoundCustomerName = nil
        existingActiveCount = 0
        isLookingUpCustomer = false
        guard canLookupCustomers, (6...20).contains(phoneDigits(in: clean).count) else {
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
                            self.automaticallyFilledName = name
                            self.automaticallyFilledPhone = phoneDigits(in: clean)
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
        guard !isLoadingTaxonomy else { return }
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
                guard let docs = snapshot?.documents else {
                    self.taxonomyError = Language.get("WantedPets_Categories_Error", alter: "تعذر تحميل فئات الحيوانات.")
                    return
                }
                self.availableMainKinds = docs.map { MainKindsModel(snapshot: $0) }
            }
        }
    }

    private func loadSubKinds(for species: MainKindsModel) {
        let docID = species.documentID.isEmpty ? "\(species.id)" : species.documentID
        guard !docID.isEmpty else { return }

        isLoadingSubkinds = true
        subkindError = nil
        availableSubKinds = []
        let loadID = UUID()
        subkindLoadID = loadID
        Firestore.firestore().collection("MainKindsCollection").document(docID).collection("SubKinds").order(by: "ID").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                guard self.selectedMainKind?.id == species.id, self.subkindLoadID == loadID else { return }
                self.isLoadingSubkinds = false
                if error != nil {
                    self.subkindError = Language.get("WantedPets_Breeds_Error", alter: "تعذر تحميل السلالات.")
                    return
                }
                guard let docs = snapshot?.documents else {
                    self.subkindError = Language.get("WantedPets_Breeds_Error", alter: "تعذر تحميل السلالات.")
                    return
                }
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
        phoneLookupTask?.cancel()
        isLookingUpCustomer = false
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
                    self.errorMessage = Language.get("WantedPets_Save_Failed", alter: "تعذر حفظ الطلب. حاول مرة أخرى.")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

}

// The existing route embeds SwiftUI navigation in a UIKit host. Only the
// nearest stack may pop this form; an outer gesture must not skip the form or
// leave a callable completion dismissing a different destination.
private struct WantedPetCaptureNavigationGuard: UIViewControllerRepresentable {
    let isSaving: Bool
    let isRTL: Bool

    func makeUIViewController(context: Context) -> CaptureNavigationController {
        let controller = CaptureNavigationController()
        controller.isSaving = isSaving
        controller.isRTL = isRTL
        return controller
    }

    func updateUIViewController(_ controller: CaptureNavigationController, context: Context) {
        controller.isSaving = isSaving
        controller.isRTL = isRTL
        controller.configureNavigation()
    }

    static func dismantleUIViewController(_ controller: CaptureNavigationController, coordinator: ()) {
        controller.restoreNavigation()
    }

    final class CaptureNavigationController: UIViewController {
        var isSaving = false
        var isRTL = false
        private var isVisible = false
        private var priorGestures: [PriorGesture] = []

        private struct PriorGesture {
            weak var gesture: UIGestureRecognizer?
            let wasEnabled: Bool
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            isVisible = true
            configureNavigation()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            configureNavigation()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            configureNavigation()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isVisible = false
            // Keep the active edge recognizer intact until the interactive
            // transition finishes. Restoring here can cancel a begun swipe.
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            restoreNavigation()
        }

        func configureNavigation() {
            guard isVisible else { return }
            var stacks: [UINavigationController] = []
            var current: UIViewController? = self
            while let controller = current {
                let navigation = (controller as? UINavigationController) ?? controller.navigationController
                if let navigation, !stacks.contains(where: { $0 === navigation }) {
                    stacks.append(navigation)
                }
                current = controller.parent
            }
            for (index, navigation) in stacks.enumerated() {
                guard let gesture = navigation.interactivePopGestureRecognizer else { continue }
                if !priorGestures.contains(where: { $0.gesture === gesture }) {
                    priorGestures.append(PriorGesture(gesture: gesture, wasEnabled: gesture.isEnabled))
                }
                if index == 0 {
                    navigation.pp_enableSwipeToPop()
                    navigation.view.semanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
                    if let edge = gesture as? UIScreenEdgePanGestureRecognizer {
                        edge.edges = isRTL ? .right : .left
                    }
                    gesture.isEnabled = !isSaving
                } else {
                    gesture.isEnabled = false
                }
            }
        }

        func restoreNavigation() {
            for prior in priorGestures {
                prior.gesture?.isEnabled = prior.wasEnabled
            }
            priorGestures.removeAll()
        }
    }
}
