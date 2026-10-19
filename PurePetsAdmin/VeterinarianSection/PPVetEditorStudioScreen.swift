//
//  PPVetEditorStudioScreen.swift
//  PurePetsAdmin
//
//  First-Principles Invention: Category-Defining Clinical Registration & Editor Studio.
//  Reinvented from absolute first principles in SwiftUI with tactile archetype switching,
//  brand media studio, live validation, and resilient Firebase persistence.
//

import SwiftUI
import UIKit

// MARK: - Clinical Registration & Editor Studio Screen

@MainActor
public struct PPVetEditorStudioScreen: View {
    private let vetToEdit: PPVetModel?
    private let onDismiss: () -> Void
    private let onSaved: (PPVetModel) -> Void

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

    @State private var selectedImage: UIImage? = nil
    @State private var existingLogoURL: String? = nil
    @State private var showImagePicker: Bool = false
    @State private var showActionSheet: Bool = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSuccessNotice: Bool = false

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

                        // Archetype Switcher (Doctor vs Clinic)
                        archetypeSelectorCard

                        // Brand Logo & Media Studio
                        brandingMediaStudioCard

                        // Identity & Credentials Group
                        identityCredentialsCard

                        // Financial & Clinical Availability Group
                        financialAvailabilityCard

                        // Direct Telehealth & Contact Group
                        telehealthContactCard

                        // Governance & Status Group
                        governanceStatusCard

                        // Save Trigger Bar
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

    // MARK: - Archetype Selector Card

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
                isSelected ? color.opacity(0.08) : AdminSurface.control,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Branding Media Studio Card

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

    // MARK: - Identity & Credentials Card

    private var identityCredentialsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("Vet_Section_Info", alter: "البيانات الأساسية والاعتماد"), icon: "person.text.rectangle.fill")

            // Name Field
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Name", alter: "الاسم أو المسمى الطبي *"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                TextField(
                    isClinic ? Language.get("Vet_Placeholder_ClinicName", alter: "مثال: مجمع الشفاء البيطري") : Language.get("Vet_Placeholder_DoctorName", alter: "مثال: د. محمد السعيد"),
                    text: $title
                )
                .font(AdminType.body)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Description / Bio Field
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Description", alter: "نبذة عن المؤهلات والخدمات"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                TextEditor(text: $descriptionText)
                    .frame(minHeight: 88)
                    .font(AdminType.body)
                    .padding(8)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Financial & Availability Card

    private var financialAvailabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("AdminVet_Consultation_Fee", alter: "الرسوم والمواعيد"), icon: "tag.fill")

            // Consultation Fee
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Cost", alter: "تكلفة الاستشارة (ر.ق)"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack {
                    TextField("0", text: $vetCost)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    Text(Language.get("QAR", alter: "ر.ق"))
                        .font(AdminType.caption1Bold)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

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
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Telehealth & Contact Card

    private var telehealthContactCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: Language.get("Vet_Section_Contact", alter: "قنوات التواصل الرسمية"), icon: "phone.circle.fill")

            // Phone Number
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Vet_Field_Phone", alter: "رقم الهاتف المعتمد *"))
                    .font(AdminType.caption1Bold)
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.08, green: 0.72, blue: 0.65))

                    TextField("974xxxxxxxx", text: $phone)
                        .keyboardType(.phonePad)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                HStack {
                    Image(systemName: "message.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.48))

                    TextField("974xxxxxxxx", text: $whatsapp)
                        .keyboardType(.phonePad)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CommandCorner.card, style: .continuous)
                .strokeBorder(AdminSurface.hairline, lineWidth: 0.8)
        )
    }

    // MARK: - Governance & Status Card

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

    // MARK: - Helpers

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
