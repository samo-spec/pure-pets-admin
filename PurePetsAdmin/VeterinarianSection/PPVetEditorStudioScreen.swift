//
//  PPVetEditorStudioScreen.swift
//  PurePetsAdmin
//
//  First-Principles Invention: Category-Defining Clinical Registration & Editor Studio.
//  Reinvented from absolute first principles in SwiftUI with tactile archetype switching,
//  brand media studio, high-contrast input ergonomics, Qatar municipalities & area coverage pickers,
//  multi-species clinical support grid, working hours, licensing, emergency & home-visit services,
//  and resilient Firebase persistence.
//

import SwiftUI
import UIKit

// MARK: - Qatar Municipalities & Coverage Catalog (Pro App Parity)

public struct PPCityItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let nameAr: String
    public let nameEn: String
    public let areaKeys: [String]

    public var localizedName: String {
        Language.isRTL() ? nameAr : nameEn
    }
}

public struct PPAreaItem: Identifiable, Hashable, Sendable {
    public let id: String // area key
    public let cityID: String
    public let nameAr: String
    public let nameEn: String

    public var localizedName: String {
        let fallback = Language.isRTL() ? nameAr : nameEn
        return Language.get(id, alter: fallback)
    }
}

@MainActor
public enum PPQatarCitiesCatalog {
    public static let cities: [PPCityItem] = [
        PPCityItem(id: "15001", nameAr: "الدوحة", nameEn: "Doha", areaKeys: [
            "ProviderQatarAreaDohaAll", "ProviderQatarAreaMsheireb", "ProviderQatarAreaWestBay",
            "ProviderQatarAreaAlDafna", "ProviderQatarAreaAlSadd", "ProviderQatarAreaBinMahmoud",
            "ProviderQatarAreaNajma", "ProviderQatarAreaAlMansoura", "ProviderQatarAreaOldAirport",
            "ProviderQatarAreaThePearl"
        ]),
        PPCityItem(id: "15004", nameAr: "الريان", nameEn: "Al Rayyan", areaKeys: [
            "ProviderQatarAreaAlRayyanAll", "ProviderQatarAreaEducationCity", "ProviderQatarAreaAlWaab",
            "ProviderQatarAreaMuaither", "ProviderQatarAreaAlGharrafa", "ProviderQatarAreaAlLuqta",
            "ProviderQatarAreaAlAziziya", "ProviderQatarAreaAinKhaled", "ProviderQatarAreaAbuSidra",
            "ProviderQatarAreaRawdatEgdaim"
        ]),
        PPCityItem(id: "15002", nameAr: "الوكرة", nameEn: "Al Wakrah", areaKeys: [
            "ProviderQatarAreaAlWakrahAll", "ProviderQatarAreaAlWakrahCity", "ProviderQatarAreaAlWukair",
            "ProviderQatarAreaMesaieed", "ProviderQatarAreaEzdanOasis", "ProviderQatarAreaAlMashaf",
            "ProviderQatarAreaBarwaVillage", "ProviderQatarAreaRasAbuFontas"
        ]),
        PPCityItem(id: "15003", nameAr: "الخور", nameEn: "Al Khor", areaKeys: [
            "ProviderQatarAreaAlKhorAll", "ProviderQatarAreaAlKhorCity", "ProviderQatarAreaAlThakhira",
            "ProviderQatarAreaRasLaffan", "ProviderQatarAreaAlGhuwairiya", "ProviderQatarAreaUmmBirka"
        ]),
        PPCityItem(id: "15005", nameAr: "الشمال", nameEn: "Al Shamal", areaKeys: [
            "ProviderQatarAreaAlShamalAll", "ProviderQatarAreaMadinatAlShamal", "ProviderQatarAreaArRuays",
            "ProviderQatarAreaAbuDhalouf", "ProviderQatarAreaFuwayrit", "ProviderQatarAreaAlZubarah"
        ]),
        PPCityItem(id: "15007", nameAr: "أم صلال", nameEn: "Umm Salal", areaKeys: [
            "ProviderQatarAreaUmmSalalAll", "ProviderQatarAreaUmmSalalAli", "ProviderQatarAreaUmmSalalMohammed",
            "ProviderQatarAreaUmmAlAmad", "ProviderQatarAreaIzghawa", "ProviderQatarAreaAlKharaitiyat"
        ]),
        PPCityItem(id: "15006", nameAr: "الظعاين", nameEn: "Al Daayen", areaKeys: [
            "ProviderQatarAreaAlDaayenAll", "ProviderQatarAreaLusail", "ProviderQatarAreaUmmQarn",
            "ProviderQatarAreaRawdatAlHamama", "ProviderQatarAreaAlEbb", "ProviderQatarAreaLeabaib",
            "ProviderQatarAreaWadiAlBanat", "ProviderQatarAreaJeryanJenaihat"
        ]),
        PPCityItem(id: "15008", nameAr: "الشحانية", nameEn: "Al Shahaniya", areaKeys: [
            "ProviderQatarAreaAlShahaniyaAll", "ProviderQatarAreaAlShahaniyaCity", "ProviderQatarAreaDukhan",
            "ProviderQatarAreaUmmBab", "ProviderQatarAreaRawdatRashed", "ProviderQatarAreaAlNasraniya",
            "ProviderQatarAreaAlJemailiya"
        ])
    ]

    private static let areaNamesMap: [String: (ar: String, en: String)] = [
        "ProviderQatarAreaDohaAll": ("كل الدوحة", "All Doha"),
        "ProviderQatarAreaMsheireb": ("مشيرب", "Msheireb"),
        "ProviderQatarAreaWestBay": ("الخليج الغربي", "West Bay"),
        "ProviderQatarAreaAlDafna": ("الدفنة", "Al Dafna"),
        "ProviderQatarAreaAlSadd": ("السد", "Al Sadd"),
        "ProviderQatarAreaBinMahmoud": ("بن محمود", "Bin Mahmoud"),
        "ProviderQatarAreaNajma": ("نجمة", "Najma"),
        "ProviderQatarAreaAlMansoura": ("المنصورة", "Al Mansoura"),
        "ProviderQatarAreaOldAirport": ("المطار القديم", "Old Airport"),
        "ProviderQatarAreaThePearl": ("اللؤلؤة", "The Pearl"),
        "ProviderQatarAreaAlRayyanAll": ("كل الريان", "All Al Rayyan"),
        "ProviderQatarAreaEducationCity": ("المدينة التعليمية", "Education City"),
        "ProviderQatarAreaAlWaab": ("الوعب", "Al Waab"),
        "ProviderQatarAreaMuaither": ("معيذر", "Muaither"),
        "ProviderQatarAreaAlGharrafa": ("الغرافة", "Al Gharrafa"),
        "ProviderQatarAreaAlLuqta": ("اللقطة", "Al Luqta"),
        "ProviderQatarAreaAlAziziya": ("العزيزية", "Al Aziziya"),
        "ProviderQatarAreaAinKhaled": ("عين خالد", "Ain Khaled"),
        "ProviderQatarAreaAbuSidra": ("أبو سدرة", "Abu Sidra"),
        "ProviderQatarAreaRawdatEgdaim": ("روضة القديم", "Rawdat Egdaim"),
        "ProviderQatarAreaAlWakrahAll": ("كل الوكرة", "All Al Wakrah"),
        "ProviderQatarAreaAlWakrahCity": ("مدينة الوكرة", "Al Wakrah City"),
        "ProviderQatarAreaAlWukair": ("الوكير", "Al Wukair"),
        "ProviderQatarAreaMesaieed": ("مسيعيد", "Mesaieed"),
        "ProviderQatarAreaEzdanOasis": ("إزدان أواسيس", "Ezdan Oasis"),
        "ProviderQatarAreaAlMashaf": ("المشاف", "Al Mashaf"),
        "ProviderQatarAreaBarwaVillage": ("قرية بروة", "Barwa Village"),
        "ProviderQatarAreaRasAbuFontas": ("رأس أبو فنطاس", "Ras Abu Fontas"),
        "ProviderQatarAreaAlKhorAll": ("كل الخور", "All Al Khor"),
        "ProviderQatarAreaAlKhorCity": ("مدينة الخور", "Al Khor City"),
        "ProviderQatarAreaAlThakhira": ("الذخيرة", "Al Thakhira"),
        "ProviderQatarAreaRasLaffan": ("رأس لفان", "Ras Laffan"),
        "ProviderQatarAreaAlGhuwairiya": ("الغويرية", "Al Ghuwairiya"),
        "ProviderQatarAreaUmmBirka": ("أم بركة", "Umm Birka"),
        "ProviderQatarAreaAlShamalAll": ("كل الشمال", "All Al Shamal"),
        "ProviderQatarAreaMadinatAlShamal": ("مدينة الشمال", "Madinat Al Shamal"),
        "ProviderQatarAreaArRuays": ("الرويس", "Ar Ruays"),
        "ProviderQatarAreaAbuDhalouf": ("أبو ظلوف", "Abu Dhalouf"),
        "ProviderQatarAreaFuwayrit": ("فويرط", "Fuwayrit"),
        "ProviderQatarAreaAlZubarah": ("الزبارة", "Al Zubarah"),
        "ProviderQatarAreaUmmSalalAll": ("كل أم صلال", "All Umm Salal"),
        "ProviderQatarAreaUmmSalalAli": ("أم صلال علي", "Umm Salal Ali"),
        "ProviderQatarAreaUmmSalalMohammed": ("أم صلال محمد", "Umm Salal Mohammed"),
        "ProviderQatarAreaUmmAlAmad": ("أم العمد", "Umm Al Amad"),
        "ProviderQatarAreaIzghawa": ("إزغوى", "Izghawa"),
        "ProviderQatarAreaAlKharaitiyat": ("الخريطيات", "Al Kharaitiyat"),
        "ProviderQatarAreaAlDaayenAll": ("كل الضعاين", "All Al Daayen"),
        "ProviderQatarAreaLusail": ("لوسيل", "Lusail"),
        "ProviderQatarAreaUmmQarn": ("أم قرن", "Umm Qarn"),
        "ProviderQatarAreaRawdatAlHamama": ("روضة الحمامة", "Rawdat Al Hamama"),
        "ProviderQatarAreaAlEbb": ("العِب", "Al Ebb"),
        "ProviderQatarAreaLeabaib": ("لعبيب", "Leabaib"),
        "ProviderQatarAreaWadiAlBanat": ("وادي البنات", "Wadi Al Banat"),
        "ProviderQatarAreaJeryanJenaihat": ("جريان جنيحات", "Jeryan Jenaihat"),
        "ProviderQatarAreaAlShahaniyaAll": ("كل الشحانية", "All Al Shahaniya"),
        "ProviderQatarAreaAlShahaniyaCity": ("مدينة الشحانية", "Al Shahaniya City"),
        "ProviderQatarAreaDukhan": ("دخان", "Dukhan"),
        "ProviderQatarAreaUmmBab": ("أم باب", "Umm Bab"),
        "ProviderQatarAreaRawdatRashed": ("روضة راشد", "Rawdat Rashed"),
        "ProviderQatarAreaAlNasraniya": ("النصرانية", "Al Nasraniya"),
        "ProviderQatarAreaAlJemailiya": ("الجميلية", "Al Jemailiya")
    ]

    public static func city(for id: String) -> PPCityItem? {
        cities.first { $0.id == id }
    }

    public static func areas(for cityID: String) -> [PPAreaItem] {
        guard let c = city(for: cityID) else { return [] }
        return c.areaKeys.map { key in
            let names = areaNamesMap[key] ?? (key, key)
            return PPAreaItem(id: key, cityID: cityID, nameAr: names.ar, nameEn: names.en)
        }
    }

    public static func localizedAreaName(for areaKey: String) -> String {
        if let names = areaNamesMap[areaKey] {
            let fallback = Language.isRTL() ? names.ar : names.en
            return Language.get(areaKey, alter: fallback)
        }
        return Language.get(areaKey, alter: areaKey)
    }
}

// MARK: - Reusable High-Contrast Input Field Container

public struct AdminFieldContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Color(uiColor: UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor.secondarySystemBackground
                        : UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0)
                }),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.8)
            )
    }
}

// MARK: - Species Item Definition

public struct PPSpeciesItem: Identifiable, Hashable, Sendable {
    public let id: Int
    public let nameAr: String
    public let nameEn: String
    public let imageName: String

    public var localizedName: String {
        Language.isRTL() ? nameAr : nameEn
    }
}

// MARK: - Clinical Registration & Editor Studio Screen

@MainActor
public struct PPVetEditorStudioScreen: View {
    private let vetToEdit: PPVetModel?
    private let onDismiss: () -> Void
    private let onSaved: (PPVetModel) -> Void

    // Core Properties
    @State private var type: PPVetType = .personal
    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var phone: String = ""
    @State private var whatsapp: String = ""
    @State private var vetCost: String = ""
    @State private var hasAvailableDate: Bool = false
    @State private var availableDate: Date = Date()
    @State private var isDisabled: Bool = false
    @State private var petMainKindID: Int = 1

    // Media
    @State private var selectedImage: UIImage? = nil
    @State private var existingLogoURL: String? = nil
    @State private var showImagePicker: Bool = false
    @State private var showActionSheet: Bool = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary

    // Geographic Coverage & Location (Qatar Municipalities)
    @State private var cityID: String = "15001"
    @State private var cityName: String = ""
    @State private var workingAreas: [String] = []
    @State private var address: String = ""
    @State private var showCityPickerSheet: Bool = false
    @State private var showAreaPickerSheet: Bool = false

    // Supported Pet Kinds & Species
    @State private var supportedKindIDs: Set<Int> = [1, 2]
    @State private var availableSpecies: [PPSpeciesItem] = []

    // Clinical Practice Credentials & Availability
    @State private var licenseNumber: String = ""
    @State private var workingHours: String = ""
    @State private var emergency247: Bool = false
    @State private var homeVisitAvailable: Bool = false
    @State private var readyToContact: Bool = true

    // State HUD
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    public init(
        vetToEdit: PPVetModel? = nil,
        onDismiss: @escaping () -> Void,
        onSaved: @escaping (PPVetModel) -> Void
    ) {
        self.vetToEdit = vetToEdit
        self.onDismiss = onDismiss
        self.onSaved = onSaved

        if let vet = vetToEdit {
            _type = State(initialValue: vet.type)
            _title = State(initialValue: vet.title ?? "")
            _descriptionText = State(initialValue: vet.descriptionText ?? "")
            _phone = State(initialValue: vet.phone ?? "")
            _whatsapp = State(initialValue: vet.whatsapp ?? "")
            _vetCost = State(initialValue: vet.vetCost > 0 ? String(format: "%.0f", vet.vetCost) : "")
            _isDisabled = State(initialValue: vet.isDisabled)
            _petMainKindID = State(initialValue: vet.petMainKindID > 0 ? vet.petMainKindID : 1)
            _existingLogoURL = State(initialValue: vet.logoURL)
            if let date = vet.availableDate {
                _hasAvailableDate = State(initialValue: true)
                _availableDate = State(initialValue: date)
            }

            // Geographic Coverage
            _cityID = State(initialValue: vet.cityID ?? "15001")
            _cityName = State(initialValue: vet.cityName ?? (PPQatarCitiesCatalog.city(for: vet.cityID ?? "15001")?.localizedName ?? ""))
            _workingAreas = State(initialValue: vet.workingAreas ?? [])
            _address = State(initialValue: vet.address ?? "")

            // Species
            if let ids = vet.supportedKindIDs, !ids.isEmpty {
                _supportedKindIDs = State(initialValue: Set(ids.map { $0.intValue }))
            } else {
                _supportedKindIDs = State(initialValue: [vet.petMainKindID > 0 ? vet.petMainKindID : 1])
            }

            // Clinical Practice
            _licenseNumber = State(initialValue: vet.licenseNumber ?? "")
            _workingHours = State(initialValue: vet.workingHours ?? "")
            _emergency247 = State(initialValue: vet.emergency247)
            _homeVisitAvailable = State(initialValue: vet.homeVisitAvailable)
            _readyToContact = State(initialValue: vet.readyToContact)
        } else {
            // Default setup for brand new registration
            let defaultCity = PPQatarCitiesCatalog.cities.first!
            _cityID = State(initialValue: defaultCity.id)
            _cityName = State(initialValue: defaultCity.localizedName)
            _workingAreas = State(initialValue: [defaultCity.areaKeys.first ?? "ProviderQatarAreaDohaAll"])
        }
    }

    private var isEditing: Bool { vetToEdit != nil }

    private var isClinic: Bool { type == .company }

    private var primaryAccent: Color {
        isClinic ? Color(red: 0.12, green: 0.68, blue: 0.88) : Color(red: 0.08, green: 0.72, blue: 0.65)
    }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        ZStack {
            // Background
            AdminSurface.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sovereign Navigation Header
                navigationHeader

                // Scrollable Form Studio
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Error Banner if present
                        if let err = errorMessage {
                            errorBanner(err)
                        }

                        // 1. Archetype Switcher (Doctor vs Clinic)
                        archetypeSelectorCard

                        // 2. Brand Logo & Media Studio
                        brandingMediaStudioCard

                        // 3. Identity & Accreditation Card
                        identityCredentialsCard

                        // 4. Geographic Coverage & Locations (Qatar Municipalities & Areas)
                        geographicCoverageCard

                        // 5. Supported Animal Species & Specializations
                        supportedSpeciesCard

                        // 6. Clinical Availability, Working Hours & Fees
                        clinicalAvailabilityCard

                        // 7. Direct Telehealth & Channels
                        telehealthContactCard

                        // 8. Governance & Regulatory Status
                        governanceStatusCard

                        // 9. Save Trigger Bar
                        saveTriggerCard

                        // Bottom Inset
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
                        Text(isEditing ? Language.get("Vet_Updating", alter: "جارٍ تحديث البيانات...") : Language.get("Vet_Saving", alter: "جارٍ حفظ الجهة الطبية..."))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            loadSpeciesData()
        }
        .actionSheet(isPresented: $showActionSheet) {
            ActionSheet(
                title: Text(Language.get("Image_Source_Title", alter: "تحديد صورة الشعار / الهوية")),
                buttons: [
                    .default(Text(Language.get("Camera", alter: "التقاط بالكاميرا"))) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            imagePickerSource = .camera
                            showImagePicker = true
                        }
                    },
                    .default(Text(Language.get("PhotoLibrary", alter: "ألبوم الصور"))) {
                        imagePickerSource = .photoLibrary
                        showImagePicker = true
                    },
                    .cancel(Text(Language.get("Cancel", alter: "إلغاء")))
                ]
            )
        }
        .sheet(isPresented: $showImagePicker) {
            PPAdminImagePickerRepresentable(sourceType: imagePickerSource) { image in
                if let image {
                    selectedImage = image
                }
            }
        }
        .sheet(isPresented: $showCityPickerSheet) {
            PPCityPickerSheet(
                selectedCityID: $cityID,
                onCitySelected: { selected in
                    cityID = selected.id
                    cityName = selected.localizedName
                    // Default to municipality-wide area if no areas currently set for this city
                    let cityAreas = PPQatarCitiesCatalog.areas(for: selected.id)
                    if let firstArea = cityAreas.first {
                        workingAreas = [firstArea.id]
                    }
                }
            )
        }
        .sheet(isPresented: $showAreaPickerSheet) {
            PPAreaMultiPickerSheet(
                cityID: cityID,
                cityName: cityName,
                selectedAreaKeys: $workingAreas
            )
        }
    }

    // MARK: - Navigation Header

    private var navigationHeader: some View {
        AdminSovereignNavigationBar(
            title: isEditing
                ? Language.get("Vet_Edit_Title", alter: "تعديل بيانات الجهة")
                : Language.get("Vet_Add_Title", alter: "تسجيل جهة بيطرية"),
            subtitle: isEditing
                ? vetToEdit?.title
                : Language.get("AdminVet_QuickAction_Add_Sub", alter: "طبيب بيطري أو عيادة معتمدة"),
            isModal: true,
            customTopSpacing: 0,
            onBack: onDismiss
        ) {
            // Save Button
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
                        .background(
                            isFormValid
                                ? primaryAccent
                                : AdminSurface.secondaryText.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(!isFormValid || isSaving)
            .accessibilityLabel(Language.get("Save", alter: "حفظ"))
        }
    }

    // MARK: - 1. Archetype Selector Card

    private var archetypeSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Language.get("Vet_Field_Type", alter: "تصنيف الجهة الطبية"))
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.secondaryText)

            HStack(spacing: 12) {
                // Doctor Option
                archetypeOptionTile(
                    title: Language.get("Vet_Type_Personal", alter: "طبيب بيطري"),
                    subtitle: Language.get("AdminVet_LicensedDoctor", alter: "استشاري بيطري مرخص"),
                    icon: "stethoscope",
                    isSelected: type == .personal,
                    color: Color(red: 0.08, green: 0.72, blue: 0.65)
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    type = .personal
                }

                // Clinic Option
                archetypeOptionTile(
                    title: Language.get("Vet_Type_Company", alter: "عيادة ومستشفى"),
                    subtitle: Language.get("AdminVet_VerifiedClinic", alter: "منشأة ومستشفى بيطري"),
                    icon: "building.2.fill",
                    isSelected: type == .company,
                    color: Color(red: 0.12, green: 0.68, blue: 0.88)
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    type = .company
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

    private func archetypeOptionTile(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isSelected ? color : color.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isSelected ? .white : color)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(color)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? color.opacity(0.08) : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground : UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0) }),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? color : Color(uiColor: .separator).opacity(0.3), lineWidth: isSelected ? 1.5 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Branding Media Studio Card

    private var brandingMediaStudioCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Media Preview
                ZStack {
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 74, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else if let logo = existingLogoURL, !logo.isEmpty, let url = URL(string: logo) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFill()
                            default:
                                mediaPlaceholder
                            }
                        }
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        mediaPlaceholder
                    }

                    // Camera Icon Beacon
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(primaryAccent)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                                .offset(x: 4, y: 4)
                        }
                    }
                }
                .frame(width: 74, height: 74)
                .onTapGesture {
                    showActionSheet = true
                }

                // Media Instructions & Change Buttons
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Image_Picker_Prompt", alter: "صورة الشعار أو الهوية المهنية"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Image_Picker_Sub", alter: "تظهر في بطاقة الطبيب ونتائج البحث وملف الاعتماد"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)

                    HStack(spacing: 8) {
                        Button {
                            showActionSheet = true
                        } label: {
                            Text(selectedImage != nil || existingLogoURL != nil ? Language.get("Change", alter: "تغيير الصورة") : Language.get("Upload", alter: "رفع صورة"))
                                .font(AdminType.caption1Bold)
                                .foregroundStyle(primaryAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(primaryAccent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if selectedImage != nil {
                            Button {
                                selectedImage = nil
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(red: 0.92, green: 0.35, blue: 0.28))
                                    .padding(6)
                                    .background(Color(red: 0.92, green: 0.35, blue: 0.28).opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    private var mediaPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(primaryAccent.opacity(0.12))
                .frame(width: 74, height: 74)
            Image(systemName: isClinic ? "building.2.fill" : "stethoscope")
                .font(.system(size: 30))
                .foregroundStyle(primaryAccent)
        }
    }

    // MARK: - 3. Identity & Accreditation Card

    private var identityCredentialsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("Vet_Section_Info", alter: "البيانات الأساسية والاعتماد"), icon: "person.text.rectangle.fill")

            // Name Field
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Name", alter: "الاسم أو المسمى الطبي *"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                AdminFieldContainer {
                    TextField(
                        isClinic ? Language.get("Vet_Placeholder_ClinicName", alter: "مثال: مجمع الشفاء البيطري") : Language.get("Vet_Placeholder_DoctorName", alter: "مثال: د. محمد السعيد"),
                        text: $title
                    )
                    .font(AdminType.body)
                }
            }

            // License Number Field
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_License", alter: "رقم الترخيص الطبي / المنشأة"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                AdminFieldContainer {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(primaryAccent)
                        TextField(
                            Language.get("Vet_Field_License_Placeholder", alter: "مثال: MOPH-VET-2024-884"),
                            text: $licenseNumber
                        )
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
                }
            }

            // Description / Bio Field
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Description", alter: "نبذة عن المؤهلات والخدمات"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                AdminFieldContainer {
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 84)
                        .font(AdminType.body)
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

    // MARK: - 4. Geographic Coverage & Locations Card (Qatar Municipalities)

    private var geographicCoverageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("Vet_Section_Coverage", alter: "النطاق الجغرافي ومناطق التغطية"), icon: "map.fill")

            // Primary Municipality / City Selector
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_City", alter: "البلدية / المدينة الرئيسية"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                Button {
                    showCityPickerSheet = true
                } label: {
                    AdminFieldContainer {
                        HStack {
                            Image(systemName: "building.columns.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(primaryAccent)

                            Text(cityName.isEmpty ? Language.get("Vet_Field_City_Placeholder", alter: "اختر البلدية") : cityName)
                                .font(AdminType.bodyBold)
                                .foregroundStyle(cityName.isEmpty ? AdminSurface.secondaryText : AdminSurface.primaryText)

                            Spacer()

                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // Service & Coverage Areas Multi-Select
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Language.get("Vet_Field_Areas", alter: "مناطق التغطية والخدمة"))
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    Button {
                        showAreaPickerSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .bold))
                            Text(Language.get("Vet_Select_Areas_Action", alter: "تحديد وتعديل المناطق"))
                                .font(AdminType.caption1Bold)
                        }
                        .foregroundStyle(primaryAccent)
                    }
                    .buttonStyle(.plain)
                }

                // Selected Areas Chips
                if workingAreas.isEmpty {
                    AdminFieldContainer {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 13))
                                .foregroundStyle(AdminSurface.secondaryText)
                            Text(Language.get("Vet_Field_Areas_Placeholder", alter: "لم يتم تحديد مناطق محددة (تغطية كامل البلدية)"))
                                .font(AdminType.caption1)
                                .foregroundStyle(AdminSurface.secondaryText)
                            Spacer()
                        }
                    }
                    .onTapGesture {
                        showAreaPickerSheet = true
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(workingAreas, id: \.self) { areaKey in
                                HStack(spacing: 6) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(primaryAccent)

                                    Text(PPQatarCitiesCatalog.localizedAreaName(for: areaKey))
                                        .font(AdminType.caption1Bold)
                                        .foregroundStyle(AdminSurface.primaryText)

                                    Button {
                                        workingAreas.removeAll { $0 == areaKey }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(primaryAccent.opacity(0.10), in: Capsule())
                                .overlay(
                                    Capsule().strokeBorder(primaryAccent.opacity(0.25), lineWidth: 0.8)
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // Physical Facility / Clinic Address
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Address", alter: "العنوان والفرع الفعلي"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                AdminFieldContainer {
                    HStack {
                        Image(systemName: "signpost.right.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(primaryAccent)
                        TextField(
                            Language.get("Vet_Field_Address_Placeholder", alter: "مثال: الخليج الغربي، شارع لوسيل، مبنى 12"),
                            text: $address
                        )
                        .font(AdminType.body)
                    }
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

    // MARK: - 5. Supported Animal Species & Specializations Card

    private var supportedSpeciesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader(title: Language.get("Vet_Section_SupportedKinds", alter: "فصائل وأنواع الحيوانات المشمولة"), icon: "pawprint.fill")
                Spacer()
                Text("\(supportedKindIDs.count) " + Language.get("Kind", alter: "أنواع"))
                    .font(AdminType.caption2Bold)
                    .foregroundStyle(primaryAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(primaryAccent.opacity(0.12), in: Capsule())
            }

            Text(Language.get("AdminVet_SpeciesSelection_Hint", alter: "حدد الحيوانات التي يستقبلها الطبيب/العيادة، واضغط على النجمة لتعيين التخصص الرئيسي."))
                .font(AdminType.caption2)
                .foregroundStyle(AdminSurface.secondaryText)

            // Species Grid
            let columns = [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(availableSpecies) { item in
                    let isSupported = supportedKindIDs.contains(item.id)
                    let isPrimary = petMainKindID == item.id

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isSupported {
                            // Don't allow deselecting if it's the only one
                            if supportedKindIDs.count > 1 {
                                supportedKindIDs.remove(item.id)
                                if isPrimary, let firstRemaining = supportedKindIDs.first {
                                    petMainKindID = firstRemaining
                                }
                            }
                        } else {
                            supportedKindIDs.insert(item.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            // Species Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSupported ? primaryAccent.opacity(0.15) : Color(uiColor: .separator).opacity(0.15))
                                    .frame(width: 38, height: 38)

                                Image(systemName: iconForSpecies(item.id))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(isSupported ? primaryAccent : AdminSurface.secondaryText)
                            }

                            // Species Name
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.localizedName)
                                    .font(AdminType.subheadlineBold)
                                    .foregroundStyle(AdminSurface.primaryText)
                                    .lineLimit(1)

                                if isPrimary {
                                    Text(Language.get("Vet_Primary_Species", alter: "التخصص الرئيسي"))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.orange)
                                }
                            }

                            Spacer()

                            // Primary Star Toggle
                            if isSupported {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    petMainKindID = item.id
                                } label: {
                                    Image(systemName: isPrimary ? "star.fill" : "star")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(isPrimary ? Color.orange : AdminSurface.secondaryText.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }

                            // Selection Checkmark
                            Image(systemName: isSupported ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(isSupported ? primaryAccent : Color(uiColor: .separator).opacity(0.5))
                        }
                        .padding(10)
                        .background(
                            isSupported
                                ? primaryAccent.opacity(0.06)
                                : Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground : UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0) }),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isSupported ? primaryAccent : Color(uiColor: .separator).opacity(0.35), lineWidth: isSupported ? 1.4 : 0.8)
                        )
                    }
                    .buttonStyle(.plain)
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

    // MARK: - 6. Clinical Availability, Working Hours & Fees Card

    private var clinicalAvailabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("AdminVet_Consultation_Fee", alter: "الرسوم وساعات ومواعيد العمل"), icon: "clock.badge.checkmark.fill")

            // Consultation Fee
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Cost", alter: "تكلفة الاستشارة (ر.ق)"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                AdminFieldContainer {
                    HStack {
                        TextField("0", text: $vetCost)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16, weight: .bold, design: .rounded))

                        Text(Language.get("QAR", alter: "ر.ق"))
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            // Official Working Hours
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Hours", alter: "ساعات وأيام العمل الرسمية"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                AdminFieldContainer {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 13))
                            .foregroundStyle(primaryAccent)
                        TextField(
                            Language.get("Vet_Field_Hours_Placeholder", alter: "مثال: السبت - الخميس: 9:00 ص - 10:00 م"),
                            text: $workingHours
                        )
                        .font(AdminType.body)
                    }
                }
            }

            // 24/7 Emergency Toggle
            Toggle(isOn: $emergency247) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(emergency247 ? Color(red: 0.92, green: 0.35, blue: 0.28).opacity(0.15) : Color(uiColor: .separator).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "cross.case.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(emergency247 ? Color(red: 0.92, green: 0.35, blue: 0.28) : AdminSurface.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Vet_Field_Emergency", alter: "طوارئ بيطرية 24/7"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Vet_Field_Emergency_Sub", alter: "استقبال الحالات الحرجة والطارئة على مدار الساعة"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .tint(Color(red: 0.92, green: 0.35, blue: 0.28))

            Divider().opacity(0.4)

            // Home Visit Service Toggle
            Toggle(isOn: $homeVisitAvailable) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(homeVisitAvailable ? Color.blue.opacity(0.15) : Color(uiColor: .separator).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "car.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(homeVisitAvailable ? Color.blue : AdminSurface.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Vet_Field_HomeVisit", alter: "خدمة الزيارة المنزلية متوفرة"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Vet_Field_HomeVisit_Sub", alter: "إمكانية الكشف والتدخل الطبي في منزل العميل"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .tint(Color.blue)

            Divider().opacity(0.4)

            // Available Date Toggle & Picker
            Toggle(isOn: $hasAvailableDate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Vet_Field_AvailableDate", alter: "تحديد تاريخ بدء الاستقبال"))
                        .font(AdminType.subheadline)
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Vet_AvailableDate_Hint", alter: "تحديد موعد جاهزية الطبيب أو العيادة"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .tint(primaryAccent)

            if hasAvailableDate {
                DatePicker(
                    Language.get("Date", alter: "التاريخ"),
                    selection: $availableDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .padding(10)
                .background(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground : UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0) }), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - 7. Direct Telehealth & Channels Card

    private var telehealthContactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("Vet_Section_Contact", alter: "قنوات التواصل والاستشارة"), icon: "phone.circle.fill")

            // Instant Telehealth Ready Toggle
            Toggle(isOn: $readyToContact) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(readyToContact ? Color(red: 0.16, green: 0.78, blue: 0.48).opacity(0.15) : Color(uiColor: .separator).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: "video.bubble.left.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(readyToContact ? Color(red: 0.16, green: 0.78, blue: 0.48) : AdminSurface.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Vet_Field_ReadyToContact", alter: "جاهزية الاستشارة الفورية (أونلاين)"))
                            .font(AdminType.subheadlineBold)
                            .foregroundStyle(AdminSurface.primaryText)
                        Text(Language.get("Vet_Field_ReadyToContact_Sub", alter: "ظهور شارة الجاهزية للتواصل الفوري في التطبيق"))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .tint(Color(red: 0.16, green: 0.78, blue: 0.48))

            Divider().opacity(0.4)

            // Phone Number
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Phone", alter: "رقم الهاتف المعتمد *"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                AdminFieldContainer {
                    HStack {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))

                        TextField("974xxxxxxxx", text: $phone)
                            .keyboardType(.phonePad)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
                }
            }

            // WhatsApp Number
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Language.get("Vet_Field_Whatsapp", alter: "رقم الواتساب للاستشارات"))
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    // Quick Copy Phone to WhatsApp
                    if !phone.isEmpty && whatsapp.isEmpty {
                        Button {
                            whatsapp = phone
                        } label: {
                            Text(Language.get("CopyFromPhone", alter: "مطابق لرقم الهاتف"))
                                .font(AdminType.caption2Bold)
                                .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))
                        }
                        .buttonStyle(.plain)
                    }
                }

                AdminFieldContainer {
                    HStack {
                        Image(systemName: "message.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))

                        TextField("974xxxxxxxx", text: $whatsapp)
                            .keyboardType(.phonePad)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    }
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

    // MARK: - 8. Governance & Regulatory Status Card

    private var governanceStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("Vet_Field_Status", alter: "حالة الترخيص والاعتماد"), icon: "shield.checkered")

            Toggle(isOn: Binding(
                get: { !isDisabled },
                set: { isDisabled = !$0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(!isDisabled ? Language.get("Vet_Status_Active", alter: "الترخيص نشط ومتاح للعامة") : Language.get("Vet_Status_Disabled", alter: "موقوف مؤقتاً عن الظهور"))
                        .font(AdminType.subheadlineBold)
                        .foregroundStyle(!isDisabled ? Color(red: 0.16, green: 0.78, blue: 0.48) : Color(red: 0.92, green: 0.35, blue: 0.28))
                    Text(Language.get("Vet_Status_Description", alter: "عند التعطيل، يُحجب الكيان الطبي من نتائج بحث وتطبيق العملاء"))
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .tint(Color(red: 0.16, green: 0.78, blue: 0.48))
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - 9. Save Trigger Bar

    private var saveTriggerCard: some View {
        Button {
            saveAction()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(isEditing ? Language.get("Vet_Action_Save", alter: "حفظ التعديلات") : Language.get("AdminVet_QuickAdd", alter: "اعتماد وتسجيل الكيان الطبي"))
                    .font(AdminType.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: isFormValid
                        ? (isClinic ? [Color(red: 0.12, green: 0.68, blue: 0.88), Color(red: 0.06, green: 0.52, blue: 0.78)] : [Color(red: 0.08, green: 0.72, blue: 0.65), Color(red: 0.04, green: 0.56, blue: 0.50)])
                        : [Color.gray.opacity(0.4), Color.gray.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .shadow(color: isFormValid ? primaryAccent.opacity(0.25) : Color.clear, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!isFormValid || isSaving)
    }

    // MARK: - Helpers & Data Loading

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primaryAccent)
            Text(title)
                .font(AdminType.subheadlineBold)
                .foregroundStyle(AdminSurface.primaryText)
        }
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

    private func iconForSpecies(_ kindID: Int) -> String {
        switch kindID {
        case 1: return "pawprint.fill"      // Dogs
        case 2: return "cat.fill"           // Cats
        case 3: return "bird.fill"          // Birds
        case 4: return "fish.fill"          // Fish
        case 5: return "hare.fill"          // Horses / Large pets
        case 6: return "tortoise.fill"      // Small Pets
        case 7: return "lizard.fill"        // Reptiles
        default: return "pawprint.fill"
        }
    }

    private func loadSpeciesData() {
        var species: [PPSpeciesItem] = []
        let mainKindsManager = MainKindsArrayManager.shared()
        if let mainKinds = mainKindsManager.mainKindsArray as? [MainKindsModel], !mainKinds.isEmpty {
            for kind in mainKinds {
                species.append(PPSpeciesItem(
                    id: Int(kind.id),
                    nameAr: kind.kindNameAr ?? "",
                    nameEn: kind.kindNameEn ?? "",
                    imageName: kind.kindImageNamed ?? ""
                ))
            }
        }

        // Resilient fallback if MainKinds not yet loaded from memory
        if species.isEmpty {
            species = [
                PPSpeciesItem(id: 1, nameAr: "كلاب", nameEn: "Dogs", imageName: "dogs"),
                PPSpeciesItem(id: 2, nameAr: "قطط", nameEn: "Cats", imageName: "cats"),
                PPSpeciesItem(id: 3, nameAr: "طيور", nameEn: "Birds", imageName: "birds"),
                PPSpeciesItem(id: 4, nameAr: "أسماك", nameEn: "Fish", imageName: "fish"),
                PPSpeciesItem(id: 5, nameAr: "خيول", nameEn: "Horses", imageName: "horses"),
                PPSpeciesItem(id: 6, nameAr: "حيوانات صغيرة", nameEn: "Small Pets", imageName: "small_pets"),
                PPSpeciesItem(id: 7, nameAr: "زواحف", nameEn: "Reptiles", imageName: "reptiles")
            ]
        }
        availableSpecies = species
    }

    private func saveAction() {
        guard isFormValid else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        errorMessage = nil
        isSaving = true

        let target = vetToEdit != nil ? (vetToEdit!.copy() as! PPVetModel) : PPVetModel()
        target.type = type
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.descriptionText = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        target.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        target.whatsapp = whatsapp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : whatsapp.trimmingCharacters(in: .whitespacesAndNewlines)
        target.vetCost = Double(vetCost) ?? 0.0
        target.isDisabled = isDisabled
        target.petMainKindID = petMainKindID
        target.availableDate = hasAvailableDate ? availableDate : nil

        // Geographic Coverage
        target.cityID = cityID.isEmpty ? nil : cityID
        target.cityName = cityName.isEmpty ? nil : cityName
        target.workingAreas = workingAreas.isEmpty ? nil : workingAreas
        target.address = address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : address.trimmingCharacters(in: .whitespacesAndNewlines)

        // Supported Species
        let sortedKindIDs = Array(supportedKindIDs).sorted()
        target.supportedKindIDs = sortedKindIDs.map { NSNumber(value: $0) }
        let animalNameList = availableSpecies
            .filter { supportedKindIDs.contains($0.id) }
            .map { $0.localizedName }
        target.animalTypes = animalNameList.isEmpty ? nil : animalNameList

        // Clinical Credentials & Availability
        target.licenseNumber = licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : licenseNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        target.workingHours = workingHours.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : workingHours.trimmingCharacters(in: .whitespacesAndNewlines)
        target.emergency247 = emergency247
        target.homeVisitAvailable = homeVisitAvailable
        target.readyToContact = readyToContact

        let manager = PPVetManager.shared()
        if isEditing {
            manager.updateVet(target, image: selectedImage) { error in
                isSaving = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onSaved(target)
                    onDismiss()
                }
            }
        } else {
            manager.addVet(target, image: selectedImage) { error in
                isSaving = false
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onSaved(target)
                    onDismiss()
                }
            }
        }
    }
}

// MARK: - Qatar Municipality Single Selection Sheet

private struct PPCityPickerSheet: View {
    @Binding var selectedCityID: String
    let onCitySelected: (PPCityItem) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var searchQuery: String = ""

    private var filteredCities: [PPCityItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return PPQatarCitiesCatalog.cities
        }
        return PPQatarCitiesCatalog.cities.filter {
            $0.nameAr.contains(q) || $0.nameEn.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 12) {
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)
                        TextField(Language.get("Search", alter: "بحث عن البلدية..."), text: $searchQuery)
                            .font(AdminType.body)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground : UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0) }), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Cities List
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filteredCities) { city in
                                let isSelected = city.id == selectedCityID

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onCitySelected(city)
                                    presentationMode.wrappedValue.dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(isSelected ? Color(red: 0.08, green: 0.72, blue: 0.65).opacity(0.15) : Color(uiColor: .separator).opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "building.columns.fill")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(isSelected ? Color(red: 0.08, green: 0.72, blue: 0.65) : AdminSurface.secondaryText)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(city.localizedName)
                                                .font(AdminType.subheadlineBold)
                                                .foregroundStyle(AdminSurface.primaryText)
                                            Text(Language.isRTL() ? city.nameEn : city.nameAr)
                                                .font(AdminType.caption2)
                                                .foregroundStyle(AdminSurface.secondaryText)
                                        }

                                        Spacer()

                                        let areasSuffix: String = Language.get("Vet_Areas_Picker_Title", alter: "مناطق")
                                        Text("\(city.areaKeys.count) \(areasSuffix)")
                                            .font(AdminType.caption2Bold)
                                            .foregroundStyle(AdminSurface.secondaryText)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(AdminSurface.surface, in: Capsule())

                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(isSelected ? Color(red: 0.08, green: 0.72, blue: 0.65) : Color(uiColor: .separator).opacity(0.4))
                                    }
                                    .padding(14)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(isSelected ? Color(red: 0.08, green: 0.72, blue: 0.65) : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle(Language.get("Vet_City_Picker_Title", alter: "اختر البلدية"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Close", alter: "إغلاق")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Qatar Municipality Multi-Area Picker Sheet

private struct PPAreaMultiPickerSheet: View {
    let cityID: String
    let cityName: String
    @Binding var selectedAreaKeys: [String]
    @Environment(\.presentationMode) private var presentationMode
    @State private var searchQuery: String = ""
    @State private var workingSelection: Set<String> = []

    private var allCityAreas: [PPAreaItem] {
        PPQatarCitiesCatalog.areas(for: cityID)
    }

    private var filteredAreas: [PPAreaItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return allCityAreas
        }
        return allCityAreas.filter {
            $0.nameAr.contains(q) || $0.nameEn.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AdminSurface.background.ignoresSafeArea()

                VStack(spacing: 12) {
                    // Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(AdminSurface.secondaryText)
                        TextField(Language.get("Search", alter: "بحث عن منطقة..."), text: $searchQuery)
                            .font(AdminType.body)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground : UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0) }), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Quick Select All / Deselect All
                    HStack {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if workingSelection.count == allCityAreas.count {
                                workingSelection.removeAll()
                            } else {
                                workingSelection = Set(allCityAreas.map { $0.id })
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: workingSelection.count == allCityAreas.count ? "xmark.circle" : "checkmark.circle")
                                Text(workingSelection.count == allCityAreas.count ? Language.get("Vet_Deselect_All_Areas", alter: "إلغاء تحديد الكل") : Language.get("Vet_Select_All_Areas", alter: "تحديد كافة مناطق البلدية"))
                            }
                            .font(AdminType.caption1Bold)
                            .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(String(format: Language.get("Vet_Selected_Areas_Count_Format", alter: "تم تحديد %d منطقة"), workingSelection.count))
                            .font(AdminType.caption2)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 16)

                    // Areas List
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(filteredAreas) { area in
                                let isSelected = workingSelection.contains(area.id)

                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if isSelected {
                                        workingSelection.remove(area.id)
                                    } else {
                                        workingSelection.insert(area.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(isSelected ? Color(red: 0.08, green: 0.72, blue: 0.65) : AdminSurface.secondaryText)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(area.localizedName)
                                                .font(AdminType.subheadlineBold)
                                                .foregroundStyle(AdminSurface.primaryText)
                                            Text(Language.isRTL() ? area.nameEn : area.nameAr)
                                                .font(AdminType.caption2)
                                                .foregroundStyle(AdminSurface.secondaryText)
                                        }

                                        Spacer()

                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(isSelected ? Color(red: 0.08, green: 0.72, blue: 0.65) : Color(uiColor: .separator).opacity(0.4))
                                    }
                                    .padding(14)
                                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(isSelected ? Color(red: 0.08, green: 0.72, blue: 0.65) : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }

                    // Bottom Confirm Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        selectedAreaKeys = Array(workingSelection)
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                            Text(Language.get("Done", alter: "تأكيد المناطق المحددة"))
                                .font(AdminType.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.08, green: 0.72, blue: 0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle(cityName.isEmpty ? Language.get("Vet_Areas_Picker_Title", alter: "مناطق التغطية") : cityName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                workingSelection = Set(selectedAreaKeys)
            }
        }
    }
}

// MARK: - Image Picker Representable

private struct PPAdminImagePickerRepresentable: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PPAdminImagePickerRepresentable

        init(_ parent: PPAdminImagePickerRepresentable) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let img = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            parent.onImagePicked(img)
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImagePicked(nil)
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Hosting Controller Bridge (for UIKit push/present)

@objc(PPVetEditorHostingController)
public class PPVetEditorHostingController: UIViewController {
    private let vetToEdit: PPVetModel?

    @objc public init(vetToEdit: PPVetModel? = nil) {
        self.vetToEdit = vetToEdit
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

        let swiftUIView = PPVetEditorStudioScreen(
            vetToEdit: vetToEdit,
            onDismiss: { [weak self] in
                if let nav = self?.navigationController, nav.viewControllers.count > 1 {
                    nav.popViewController(animated: true)
                } else {
                    self?.dismiss(animated: true)
                }
            },
            onSaved: { _ in }
        )

        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear
        hostingController.extendedLayoutIncludesOpaqueBars = true
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
