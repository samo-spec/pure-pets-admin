//
//  PPServiceEditorView.swift
//  PurePetsAdmin
//
//  Created by Antigravity on 11/09/2026.
//  First-Principles Category-Defining Service Creative Studio & Campaign Command Center.
//  Tailored separately for iPhone (Mobile Tactile Studio) and iPad (Desktop-Class Split Studio).
//

import SwiftUI
import PhotosUI
import UIKit
import Firebase
import FirebaseAuth

// MARK: - Species Preset Model

public struct PPServiceSpeciesPreset: Identifiable, Hashable, Sendable {
    public let id: Int
    public let nameAr: String
    public let nameEn: String
    public let iconName: String
    public let badgeColor: Color

    public static let presets: [PPServiceSpeciesPreset] = [
        PPServiceSpeciesPreset(id: 0, nameAr: "جميع الحيوانات", nameEn: "All Animals", iconName: "pawprint.fill", badgeColor: Color(uiColor: .ppPrimary)),
        PPServiceSpeciesPreset(id: 1, nameAr: "كلاب", nameEn: "Dogs", iconName: "dog.fill", badgeColor: Color.orange),
        PPServiceSpeciesPreset(id: 2, nameAr: "قطط", nameEn: "Cats", iconName: "cat.fill", badgeColor: Color.purple),
        PPServiceSpeciesPreset(id: 3, nameAr: "طيور وصقور", nameEn: "Birds & Falcons", iconName: "bird.fill", badgeColor: Color.blue),
        PPServiceSpeciesPreset(id: 4, nameAr: "خيول", nameEn: "Horses", iconName: "hare.fill", badgeColor: Color.brown)
    ]

    public func localizedName() -> String {
        return Language.isRTL() ? nameAr : nameEn
    }
}

// MARK: - View Model

@MainActor
public final class PPServiceEditorViewModel: ObservableObject {
    public let originalService: PPServiceModel?
    public let isEditing: Bool
    public let onDismiss: @Sendable () -> Void
    public let onSuccess: @Sendable () -> Void

    // Core Proposition Fields
    @Published public var title: String = ""
    @Published public var serviceDescription: String = ""
    @Published public var priceText: String = ""
    @Published public var serviceType: PPServiceType = .training

    // Classification & Taxonomy
    @Published public var selectedSpeciesID: Int = 0
    @Published public var category: String = ""
    @Published public var categoryID: String = ""

    // Availability & Scheduling
    @Published public var hasAvailableDate: Bool = false
    @Published public var availableDate: Date = Date()
    @Published public var creationDate: Date = Date()

    // Media
    @Published public var existingImageURL: String = ""
    @Published public var selectedImage: UIImage? = nil
    @Published public var blurHash: String = ""

    // Governance & Advanced
    @Published public var ownerID: String = ""
    @Published public var auditNote: String = ""
    @Published public var extraJSONText: String = ""

    // UI & Validation States
    @Published public var isSubmitting: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showImagePicker: Bool = false
    @Published public var isCamera: Bool = false
    @Published public var previewDeviceMode: Int = 0 // 0: iPhone Card, 1: iPad Sheet
    @Published public var isGovernanceDrawerExpanded: Bool = false

    public init(
        service: PPServiceModel?,
        onDismiss: @escaping @Sendable () -> Void,
        onSuccess: @escaping @Sendable () -> Void
    ) {
        self.originalService = service
        self.isEditing = (service != nil)
        self.onDismiss = onDismiss
        self.onSuccess = onSuccess

        if let s = service {
            self.title = s.title ?? ""
            self.serviceDescription = s.serviceDescriptionText ?? ""
            self.priceText = s.price > 0 ? String(format: "%.2f", s.price) : ""
            self.serviceType = s.type
            self.selectedSpeciesID = Int(s.petMainKindID)
            self.category = s.category ?? ""
            self.categoryID = s.categoryID ?? ""
            if let ad = s.availableDate {
                self.hasAvailableDate = true
                self.availableDate = ad
            }
            self.creationDate = s.timestamp ?? s.createdAt ?? Date()
            self.existingImageURL = s.imageURL ?? ""
            self.blurHash = s.blurHash ?? ""
            self.ownerID = s.serviceOwnerID ?? (Auth.auth().currentUser?.uid ?? "")
            self.extraJSONText = PPServiceEditorViewModel.prettyJSON(from: s.extraFields)
        } else {
            self.ownerID = Auth.auth().currentUser?.uid ?? ""
            self.creationDate = Date()
            self.category = Language.isRTL() ? "خدمات عامة" : "General Services"
            self.categoryID = "general"
        }
    }

    public var parsedPrice: Double {
        let cleaned = priceText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0.0
    }

    public var validationErrors: [String] {
        var errors: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(Language.get("Service_Error_TitleRequired", alter: "عنوان الخدمة مطلوب"))
        }
        if serviceDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(Language.get("Service_Error_DescriptionRequired", alter: "وصف الخدمة مطلوب"))
        }
        if parsedPrice <= 0 {
            errors.append(Language.get("Service_Error_InvalidPrice", alter: "السعر يجب أن يكون أكبر من صفر"))
        }
        if ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(Language.get("Service_Error_OwnerRequired", alter: "معرّف المالك مطلوب"))
        }
        return errors
    }

    public var isValid: Bool {
        return validationErrors.isEmpty
    }

    public func adjustPrice(by delta: Double) {
        let current = parsedPrice
        let newPrice = max(0, current + delta)
        priceText = String(format: "%.2f", newPrice)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func setPrice(_ value: Double) {
        priceText = value > 0 ? String(format: "%.2f", value) : ""
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public func save() {
        guard isValid else {
            errorMessage = validationErrors.first
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }

        // Validate JSON if provided
        var parsedExtras: [String: Any]? = nil
        let trimmedJSON = extraJSONText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedJSON.isEmpty {
            guard let data = trimmedJSON.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                  let dict = obj as? [String: Any] else {
                errorMessage = Language.get("Service_Error_ExtraJSONInvalid", alter: "يجب أن تكون الحقول الإضافية نص JSON صالحاً")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            parsedExtras = dict
        }

        isSubmitting = true
        errorMessage = nil

        let model = originalService?.copy() as? PPServiceModel ?? PPServiceModel()
        model.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        model.serviceDescriptionText = serviceDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        model.price = parsedPrice
        model.type = serviceType
        model.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        model.categoryID = categoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        model.petMainKindID = selectedSpeciesID
        model.availableDate = hasAvailableDate ? availableDate : nil
        model.timestamp = creationDate
        model.serviceOwnerID = ownerID.trimmingCharacters(in: .whitespacesAndNewlines)
        model.imageURL = existingImageURL
        model.blurHash = blurHash
        if let extras = parsedExtras {
            model.extraFields = extras
        }

        let note = auditNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteToPass = note.isEmpty ? nil : note

        let completion: PPServiceVoidBlock = { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSubmitting = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.onSuccess()
                }
            }
        }

        if isEditing {
            PPServiceManager.shared().updateService(model, image: selectedImage, auditNote: noteToPass, completion: completion)
        } else {
            PPServiceManager.shared().addService(model, image: selectedImage, auditNote: noteToPass, completion: completion)
        }
    }

    private static func prettyJSON(from dict: [String: Any]?) -> String {
        guard let dict = dict, !dict.isEmpty else { return "" }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }
}

// MARK: - Master Container Screen

public struct PPServiceEditorScreen: View {
    @StateObject public var viewModel: PPServiceEditorViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(viewModel: PPServiceEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            AdminSurface.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom Sovereign Navigation Bar
                PPServiceEditorNavigationBar(viewModel: viewModel)
                    .zIndex(10)

                // Adaptive Branch: iPhone vs iPad
                if horizontalSizeClass == .regular {
                    PPServiceEditorIPadView(viewModel: viewModel)
                } else {
                    PPServiceEditorIPhoneView(viewModel: viewModel)
                }
            }

            // Global Loading HUD
            if viewModel.isSubmitting {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(Color.white)
                        Text(Language.get("Service_Saving", alter: "جارٍ حفظ الخدمة واعتمادها..."))
                            .font(AdminType.headline)
                            .foregroundColor(.white)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $viewModel.showImagePicker) {
            PPServicePhotoPickerSheet(
                isCamera: viewModel.isCamera,
                onImageSelected: { img in
                    viewModel.selectedImage = img
                }
            )
        }
        .alert(item: Binding<AlertItem?>(
            get: { viewModel.errorMessage.map { AlertItem(message: $0) } },
            set: { _ in viewModel.errorMessage = nil }
        )) { item in
            Alert(
                title: Text(Language.get("Error", alter: "تنبيه")),
                message: Text(item.message),
                dismissButton: .default(Text(Language.get("OK", alter: "حسناً")))
            )
        }
    }
}

public struct AlertItem: Identifiable {
    public let id = UUID()
    public let message: String
}

// MARK: - Custom Sovereign Navigation Bar

public struct PPServiceEditorNavigationBar: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        HStack(spacing: 14) {
            // Dismiss Button
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.onDismiss()
            }) {
                Image(systemName: Language.isRTL() ? "arrow.right" : "arrow.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 40, height: 40)
                    .background(AdminSurface.surface, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
            }
            .accessibilityLabel(Language.get("Back", alter: "رجوع"))

            // Title & Breadcrumb Block
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(viewModel.isEditing
                         ? Language.get("Service_Edit_Title", alter: "تعديل الخدمة")
                         : Language.get("Service_Add_Title", alter: "إضافة خدمة جديدة"))
                        .font(AdminType.title3Bold)
                        .foregroundColor(AdminSurface.primaryText)

                    // Type Pip
                    Text(viewModel.serviceType == .grooming
                         ? Language.get("Service_Type_Grooming", alter: "عناية وتنظيف")
                         : Language.get("Service_Type_Training", alter: "تدريب"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(viewModel.serviceType == .grooming ? Color.teal : AdminSurface.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (viewModel.serviceType == .grooming ? Color.teal : AdminSurface.primary).opacity(0.12),
                            in: Capsule()
                        )
                }

                Text(Language.get("Service_Creative_Studio_Sub", alter: "استوديو الخدمات السيادي • إدارة العروض والتسعير"))
                    .font(AdminType.caption2)
                    .foregroundColor(AdminSurface.secondaryText)
            }

            Spacer()

            // Live Validation Telemetry Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isValid ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
                    .frame(width: 7, height: 7)

                Text(viewModel.isValid
                     ? Language.get("Service_Status_Ready", alter: "جاهز للاعتماد")
                     : String(format: Language.get("Service_Status_Incomplete_Format", alter: "%d حقول مطلوبة"), viewModel.validationErrors.count))
                    .font(AdminType.captionBold)
                    .foregroundColor(viewModel.isValid ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (viewModel.isValid ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning)).opacity(0.10),
                in: Capsule()
            )

            // Primary Save Button
            Button(action: {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                viewModel.save()
            }) {
                HStack(spacing: 6) {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14, weight: .bold))
                    }

                    Text(Language.get("Save", alter: "حفظ واعتماد"))
                        .font(AdminType.subheadlineBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background {
                    if viewModel.isValid {
                        LinearGradient(colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color.gray.opacity(0.4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: viewModel.isValid ? AdminSurface.primary.opacity(0.28) : Color.clear, radius: 8, y: 3)
            }
            .disabled(!viewModel.isValid || viewModel.isSubmitting)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            AdminSurface.surface
                .overlay(
                    Rectangle()
                        .fill(AdminSurface.hairline)
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }
}

// MARK: - iPhone Studio Layout (Mobile Tactile Studio)

public struct PPServiceEditorIPhoneView: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // 1. Fluid Media Hero Stage
                PPServiceHeroMediaCard(viewModel: viewModel)

                // 2. Tactile Service Type Dial
                PPServiceTypeDial(viewModel: viewModel)

                // 3. Core Commercial Proposition (Title, Description, Price Stepper)
                PPServiceCorePropositionCard(viewModel: viewModel)

                // 4. Species & Taxonomy Grid
                PPServiceSpeciesCard(viewModel: viewModel)

                // 5. Booking Availability Card
                PPServiceAvailabilityCard(viewModel: viewModel)

                // 6. Enterprise Governance & Advanced Parameters
                PPServiceGovernanceCard(viewModel: viewModel)

                // Spacing for Bottom Dock
                Spacer()
                    .frame(height: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay(
            // Sticky Floating Action Dock
            VStack {
                Spacer()
                PPServiceFloatingActionDock(viewModel: viewModel)
            },
            alignment: .bottom
        )
    }
}

// MARK: - iPad Studio Layout (Desktop-Class Split Studio)

public struct PPServiceEditorIPadView: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left Column: Live Consumer Experience Simulator (~42% width)
            VStack(spacing: 16) {
                HStack {
                    Label(
                        Language.get("Service_Live_Preview_Title", alter: "معاينة العميل المباشرة"),
                        systemImage: "iphone.radiowaves.left.and.right"
                    )
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                    Spacer()

                    // Device Mode Toggle (Card vs Detail Sheet)
                    Picker("", selection: $viewModel.previewDeviceMode) {
                        Text(Language.get("Service_Preview_Card", alter: "بطاقة المتجر")).tag(0)
                        Text(Language.get("Service_Preview_Sheet", alter: "صفحة الخدمة")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.horizontal, 8)

                // Live Consumer Card Mockup
                PPServiceLiveConsumerCard(viewModel: viewModel)

                // Interactive Media Drop & Upload Zone
                PPServiceHeroMediaCard(viewModel: viewModel, compact: true)

                Spacer()
            }
            .frame(minWidth: 380, maxWidth: 440)

            // Right Column: Configuration & Bento Matrix (~58% width)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    // Type Switcher
                    PPServiceTypeDial(viewModel: viewModel)

                    // Core Specs Bento Card
                    PPServiceCorePropositionCard(viewModel: viewModel)

                    // Species & Category Bento Card
                    PPServiceSpeciesCard(viewModel: viewModel)

                    // Availability & Scheduling Card
                    PPServiceAvailabilityCard(viewModel: viewModel)

                    // Governance, Schema & Audit Card
                    PPServiceGovernanceCard(viewModel: viewModel)

                    Spacer().frame(height: 40)
                }
                .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }
}

// MARK: - Hero Media Card (Alive & Interactive)

public struct PPServiceHeroMediaCard: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel
    var compact: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                // Background Frame
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AdminSurface.control)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AdminSurface.hairline, lineWidth: 1)
                    )

                if let img = viewModel.selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: compact ? 180 : 220)
                        .clipped()
                        .cornerRadius(22)
                } else if !viewModel.existingImageURL.isEmpty, let url = URL(string: viewModel.existingImageURL) {
                    AdminRemoteImage(url: url, contentMode: .fill) {
                        ProgressView().tint(AdminSurface.primary)
                    }
                    .frame(maxHeight: compact ? 180 : 220)
                    .clipped()
                    .cornerRadius(22)
                } else {
                    // Empty State Graphic
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AdminSurface.primary.opacity(0.12))
                                .frame(width: 58, height: 58)

                            Image(systemName: "camera.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(AdminSurface.primary)
                        }

                        Text(Language.get("Service_Form_ImageHint", alter: "اضغط لاختيار صورة للخدمة"))
                            .font(AdminType.subheadlineBold)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("Service_Form_ImageSub", alter: "يُفضل صورة مربعة أو أفقية بنسبة 16:9 فائقة الوضوح"))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(24)
                }

                // Top Floating Badge Overlays
                VStack {
                    HStack {
                        // Category Chip
                        Text(viewModel.serviceType == .grooming
                             ? Language.get("Service_Type_Grooming", alter: "عناية وتنظيف")
                             : Language.get("Service_Type_Training", alter: "تدريب"))
                            .font(AdminType.caption2Bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        // Price Chip
                        if viewModel.parsedPrice > 0 {
                            Text(String(format: "%.2f %@", viewModel.parsedPrice, Language.isRTL() ? "ر.ق" : "QAR"))
                                .font(Font.custom("Beiruti-Bold", size: 15, relativeTo: .subheadline))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AdminSurface.primary, in: Capsule())
                                .shadow(color: AdminSurface.primary.opacity(0.4), radius: 6, y: 2)
                        }
                    }
                    .padding(14)

                    Spacer()

                    // Bottom Image Control Pill (When image exists)
                    if viewModel.selectedImage != nil || !viewModel.existingImageURL.isEmpty {
                        HStack(spacing: 10) {
                            Button(action: {
                                viewModel.isCamera = false
                                viewModel.showImagePicker = true
                            }) {
                                Label(Language.get("Change", alter: "تغيير الصورة"), systemImage: "photo")
                                    .font(AdminType.captionBold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }

                            Button(action: {
                                viewModel.selectedImage = nil
                                viewModel.existingImageURL = ""
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.red.opacity(0.9))
                                    .frame(width: 28, height: 28)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(height: compact ? 180 : 220)
            .contentShape(Rectangle())
            .onTapGesture {
                if viewModel.selectedImage == nil && viewModel.existingImageURL.isEmpty {
                    viewModel.isCamera = false
                    viewModel.showImagePicker = true
                }
            }

            // Quick Photo Action Bar
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.isCamera = false
                    viewModel.showImagePicker = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 13, weight: .semibold))
                        Text(Language.get("Service_Action_Gallery", alter: "مكتبة الصور"))
                            .font(AdminType.captionBold)
                    }
                    .foregroundColor(AdminSurface.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(action: {
                        viewModel.isCamera = true
                        viewModel.showImagePicker = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 13, weight: .semibold))
                            Text(Language.get("Service_Action_Camera", alter: "التقاط صورة"))
                                .font(AdminType.captionBold)
                        }
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }
                }
            }
        }
    }
}

// MARK: - Tactile Service Type Dial

public struct PPServiceTypeDial: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Language.get("Service_Field_Type", alter: "تصنيف نوع الخدمة"))
                .font(AdminType.captionBold)
                .foregroundColor(AdminSurface.secondaryText)

            HStack(spacing: 10) {
                // Training Segment
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        viewModel.serviceType = .training
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 15, weight: .bold))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(Language.get("Service_Type_Training", alter: "تدريب الحيوانات"))
                                .font(AdminType.subheadlineBold)
                            Text(Language.get("Service_Type_Training_Desc", alter: "طاعة، مهارات، وسلوكيات"))
                                .font(AdminType.caption2)
                                .opacity(0.8)
                        }
                        Spacer()
                    }
                    .foregroundColor(viewModel.serviceType == .training ? .white : AdminSurface.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        if viewModel.serviceType == .training {
                            LinearGradient(colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            AdminSurface.surface
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(viewModel.serviceType == .training ? Color.clear : AdminSurface.hairline)
                    )
                    .shadow(color: viewModel.serviceType == .training ? AdminSurface.primary.opacity(0.25) : Color.clear, radius: 6, y: 3)
                }

                // Grooming Segment
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        viewModel.serviceType = .grooming
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.bubble.left.and.bubble.right.fill")
                            .font(.system(size: 15, weight: .bold))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(Language.get("Service_Type_Grooming", alter: "تنظيف وعناية"))
                                .font(AdminType.subheadlineBold)
                            Text(Language.get("Service_Type_Grooming_Desc", alter: "استحمام، تمشيط، وقص أظافر"))
                                .font(AdminType.caption2)
                                .opacity(0.8)
                        }
                        Spacer()
                    }
                    .foregroundColor(viewModel.serviceType == .grooming ? .white : AdminSurface.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        if viewModel.serviceType == .grooming {
                            LinearGradient(colors: [Color.teal, Color.teal.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        } else {
                            AdminSurface.surface
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(viewModel.serviceType == .grooming ? Color.clear : AdminSurface.hairline)
                    )
                    .shadow(color: viewModel.serviceType == .grooming ? Color.teal.opacity(0.25) : Color.clear, radius: 6, y: 3)
                }
            }
        }
    }
}

// MARK: - Core Proposition Bento Card

public struct PPServiceCorePropositionCard: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label(
                    Language.get("Service_Form_BasicSection", alter: "المعلومات الأساسية والتسعير"),
                    systemImage: "tag.fill"
                )
                .font(AdminType.subheadlineBold)
                .foregroundColor(AdminSurface.primaryText)

                Spacer()

                Text(Language.get("Required_Pill", alter: "إلزامي"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(AdminSurface.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AdminSurface.primary.opacity(0.09), in: Capsule())
            }

            // 1. Service Title Input
            VStack(alignment: .leading, spacing: 6) {
                Text(Language.get("Service_Field_Title", alter: "عنوان الخدمة"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                HStack(spacing: 8) {
                    Image(systemName: "pencil.line")
                        .foregroundColor(AdminSurface.secondaryText)
                        .font(.system(size: 14))

                    TextField(
                        Language.get("Service_Field_Title_Placeholder", alter: "مثال: تدريب الطاعة الأساسي للكلاب الجرو"),
                        text: $viewModel.title
                    )
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primaryText)

                    if !viewModel.title.isEmpty {
                        Button(action: { viewModel.title = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AdminSurface.secondaryText)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
            }

            // 2. Service Description Input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Language.get("Service_Field_Description", alter: "وصف الخدمة ومميزاتها"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    Spacer()

                    Text("\(viewModel.serviceDescription.count) حرف")
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText.opacity(0.7))
                }

                ZStack(alignment: .topLeading) {
                    if viewModel.serviceDescription.isEmpty {
                        Text(Language.get("Service_Field_Description_Placeholder", alter: "اكتب وصفاً جذاباً وشاملاً يتضمن مراحل الخدمة والفوائد التي يحصل عليها الحيوان الأليف..."))
                            .font(AdminType.callout)
                            .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $viewModel.serviceDescription)
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.primaryText)
                        .frame(minHeight: 90)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                }
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AdminSurface.hairline))
            }

            // 3. Tactile Currency Price Matrix
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("Service_Field_Price", alter: "السعر ورسوم الخدمة"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                HStack(spacing: 12) {
                    // Large Price Input Field
                    HStack(spacing: 8) {
                        Text(Language.isRTL() ? "ر.ق" : "QAR")
                            .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                            .foregroundColor(AdminSurface.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        TextField("0.00", text: $viewModel.priceText)
                            .font(Font.custom("Beiruti-Bold", size: 24, relativeTo: .title2))
                            .foregroundColor(AdminSurface.primaryText)
                            .keyboardType(.decimalPad)

                        if !viewModel.priceText.isEmpty {
                            Button(action: { viewModel.priceText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .font(.system(size: 14))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 52)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline))

                    // Quick Increment Chips
                    HStack(spacing: 6) {
                        Button("+50") { viewModel.adjustPrice(by: 50) }
                            .buttonStyle(PPServiceStepperButtonStyle())
                        Button("+100") { viewModel.adjustPrice(by: 100) }
                            .buttonStyle(PPServiceStepperButtonStyle())
                        Button("+250") { viewModel.adjustPrice(by: 250) }
                            .buttonStyle(PPServiceStepperButtonStyle())
                    }
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline))
    }
}

public struct PPServiceStepperButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AdminType.captionBold)
            .foregroundColor(AdminSurface.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(configuration.isPressed ? AdminSurface.hairline : AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Species & Taxonomy Grid

public struct PPServiceSpeciesCard: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                Language.get("Service_Classification_Species", alter: "الأنواع المستهدفة والتصنيف"),
                systemImage: "square.grid.2x2.fill"
            )
            .font(AdminType.subheadlineBold)
            .foregroundColor(AdminSurface.primaryText)

            // Species Quick Selector Chips
            VStack(alignment: .leading, spacing: 8) {
                Text(Language.get("Service_Field_PetMainKindID", alter: "فئة الحيوان الأساسية"))
                    .font(AdminType.captionBold)
                    .foregroundColor(AdminSurface.secondaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PPServiceSpeciesPreset.presets) { preset in
                            let isSelected = (viewModel.selectedSpeciesID == preset.id)
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.28)) {
                                    viewModel.selectedSpeciesID = preset.id
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: preset.iconName)
                                        .font(.system(size: 13, weight: .bold))
                                    Text(preset.localizedName())
                                        .font(AdminType.captionBold)
                                }
                                .foregroundColor(isSelected ? .white : AdminSurface.primaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(
                                    isSelected ? preset.badgeColor : AdminSurface.control,
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline))
                                .shadow(color: isSelected ? preset.badgeColor.opacity(0.3) : Color.clear, radius: 4, y: 2)
                            }
                        }
                    }
                }
            }

            // Category & Category ID Details
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Service_Field_Category", alter: "اسم الفئة"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField(Language.get("Service_Field_Category", alter: "الفئة"), text: $viewModel.category)
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Service_Field_CategoryID", alter: "معرّف الفئة"))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.secondaryText)

                    TextField(Language.get("Service_Field_CategoryID", alter: "Category ID"), text: $viewModel.categoryID)
                        .font(AdminType.callout.monospaced())
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline))
    }
}

// MARK: - Availability & Scheduling Card

public struct PPServiceAvailabilityCard: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                Language.get("Service_Field_AvailableDate", alter: "الجدولة وتاريخ التوفر"),
                systemImage: "calendar.badge.clock"
            )
            .font(AdminType.subheadlineBold)
            .foregroundColor(AdminSurface.primaryText)

            Toggle(isOn: $viewModel.hasAvailableDate.animation(.spring())) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Service_Availability_Toggle", alter: "تحديد موعد بدء التوفر"))
                        .font(AdminType.calloutBold)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get("Service_Availability_Toggle_Sub", alter: "تفعيل حجز الخدمة بدءاً من تاريخ ووقت محددين"))
                        .font(AdminType.caption2)
                        .foregroundColor(AdminSurface.secondaryText)
                }
            }
            .tint(AdminSurface.primary)

            if viewModel.hasAvailableDate {
                DatePicker(
                    Language.get("Service_Field_AvailableDate", alter: "تاريخ التوفر"),
                    selection: $viewModel.availableDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline))
    }
}

// MARK: - Enterprise Governance & Parameters

public struct PPServiceGovernanceCard: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.isGovernanceDrawerExpanded.toggle()
                }
            }) {
                HStack {
                    Label(
                        Language.get("Service_Form_AdvancedSection", alter: "الحوكمة وسجل التدقيق والبيانات الفنية"),
                        systemImage: "shield.lefthalf.filled"
                    )
                    .font(AdminType.subheadlineBold)
                    .foregroundColor(AdminSurface.primaryText)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .rotationEffect(.degrees(viewModel.isGovernanceDrawerExpanded ? 180 : 0))
                }
            }

            if viewModel.isGovernanceDrawerExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    // Owner ID
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Language.get("Service_Field_OwnerID", alter: "معرّف المالك المسؤول (UID)"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        TextField(Language.get("Service_Field_OwnerID", alter: "Owner UID"), text: $viewModel.ownerID)
                            .font(AdminType.caption1.monospaced())
                            .foregroundColor(AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Audit Trail Note
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Language.get("Service_Field_AuditNote", alter: "ملاحظة سجل التدقيق الإداري"))
                            .font(AdminType.captionBold)
                            .foregroundColor(AdminSurface.secondaryText)

                        TextField(
                            Language.get("Service_Field_AuditNote_Placeholder", alter: "مثال: تحديث تسعيرة باقة التدريب المتقدم"),
                            text: $viewModel.auditNote
                        )
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }

                    // Extra JSON
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(Language.get("Service_Field_ExtraJSON", alter: "الحقول الإضافية (JSON)"))
                                .font(AdminType.captionBold)
                                .foregroundColor(AdminSurface.secondaryText)
                            Spacer()
                            Text(Language.get("Service_Field_ExtraJSON_Optional", alter: "اختياري"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText.opacity(0.6))
                        }

                        TextEditor(text: $viewModel.extraJSONText)
                            .font(Font.system(size: 13, design: .monospaced))
                            .foregroundColor(AdminSurface.primaryText)
                            .frame(height: 80)
                            .padding(8)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AdminSurface.hairline))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline))
    }
}

// MARK: - Live Consumer Card Simulator (iPad Live Canvas)

public struct PPServiceLiveConsumerCard: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Media Banner Container
            ZStack(alignment: .topTrailing) {
                if let img = viewModel.selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 210)
                        .clipped()
                } else if !viewModel.existingImageURL.isEmpty, let url = URL(string: viewModel.existingImageURL) {
                    AdminRemoteImage(url: url, contentMode: .fill) {
                        ProgressView().tint(AdminSurface.primary)
                    }
                    .frame(height: 210)
                    .clipped()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [AdminSurface.control, AdminSurface.control.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        VStack(spacing: 8) {
                            Image(systemName: viewModel.serviceType == .grooming ? "sparkles" : "graduationcap")
                                .font(.system(size: 36))
                                .foregroundColor(AdminSurface.primary.opacity(0.6))
                            Text(Language.get("Service_Preview_Placeholder", alter: "صورة الخدمة المباشرة"))
                                .font(AdminType.caption)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }
                    .frame(height: 210)
                }

                // Consumer Badge Overlays
                HStack {
                    Text(viewModel.serviceType == .grooming
                         ? Language.get("Service_Type_Grooming", alter: "عناية وتنظيف")
                         : Language.get("Service_Type_Training", alter: "تدريب"))
                        .font(AdminType.caption2Bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())

                    Spacer()

                    // Rating Mockup
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text("5.0")
                            .font(AdminType.caption2Bold)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: Capsule())
                }
                .padding(12)
            }

            // Card Body (Title, Price, Description, Booking Button)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.title.isEmpty ? Language.get("Service_Field_Title_Placeholder", alter: "عنوان الخدمة هنا...") : viewModel.title)
                            .font(AdminType.headline)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: 11))
                                .foregroundColor(AdminSurface.primary)

                            let preset = PPServiceSpeciesPreset.presets.first(where: { $0.id == viewModel.selectedSpeciesID })
                            Text(preset?.localizedName() ?? Language.get("All_Pets", alter: "جميع الحيوانات"))
                                .font(AdminType.caption2)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    }

                    Spacer()

                    // Price Tag
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "%.2f", viewModel.parsedPrice))
                            .font(Font.custom("Beiruti-Bold", size: 22, relativeTo: .title3))
                            .foregroundColor(AdminSurface.primary)

                        Text(Language.isRTL() ? "ر.ق" : "QAR")
                            .font(AdminType.caption2Bold)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }

                // Description Snippet
                Text(viewModel.serviceDescription.isEmpty ? Language.get("Service_Preview_Desc_Placeholder", alter: "وصف الخدمة ومميزاتها سيظهر للعميل في هذا المكان بدقة وأناقة...") : viewModel.serviceDescription)
                    .font(AdminType.caption)
                    .foregroundColor(AdminSurface.secondaryText)
                    .lineLimit(3)
                    .lineSpacing(3)

                Divider()
                    .padding(.vertical, 2)

                // Simulated Consumer Booking Button
                HStack {
                    Label(Language.get("Service_Book_Now", alter: "حجز موعد الخدمة"), systemImage: "calendar.badge.plus")
                        .font(AdminType.subheadlineBold)
                    Spacer()
                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(
                    LinearGradient(colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .padding(16)
        }
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline))
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 6)
    }
}

// MARK: - Floating Action Dock (iPhone)

public struct PPServiceFloatingActionDock: View {
    @ObservedObject var viewModel: PPServiceEditorViewModel

    public var body: some View {
        HStack(spacing: 12) {
            // Live Status Indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isValid
                     ? Language.get("Service_Ready_To_Save", alter: "مكتمل وجاهز للاعتماد")
                     : Language.get("Service_Needs_Completion", alter: "يرجى إكمال الحقول"))
                    .font(AdminType.caption2Bold)
                    .foregroundColor(viewModel.isValid ? Color(uiColor: .ppSuccess) : Color(uiColor: .ppWarning))

                Text(String(format: "%.2f %@", viewModel.parsedPrice, Language.isRTL() ? "ر.ق" : "QAR"))
                    .font(Font.custom("Beiruti-Bold", size: 16, relativeTo: .headline))
                    .foregroundColor(AdminSurface.primaryText)
            }

            Spacer()

            // Save Button
            Button(action: {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                viewModel.save()
            }) {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(viewModel.isEditing
                         ? Language.get("Service_Update_Action", alter: "تحديث الخدمة")
                         : Language.get("Service_Save_Action", alter: "حفظ واعتماد"))
                        .font(AdminType.subheadlineBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background {
                    if viewModel.isValid {
                        LinearGradient(colors: [AdminSurface.primary, AdminSurface.primary.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else {
                        Color.gray.opacity(0.4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: viewModel.isValid ? AdminSurface.primary.opacity(0.3) : Color.clear, radius: 8, y: 4)
            }
            .disabled(!viewModel.isValid || viewModel.isSubmitting)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// MARK: - Photos & Camera Picker Sheet

public struct PPServicePhotoPickerSheet: UIViewControllerRepresentable {
    public let isCamera: Bool
    public let onImageSelected: (UIImage) -> Void

    public func makeUIViewController(context: Context) -> UIViewController {
        if isCamera && UIImagePickerController.isSourceTypeAvailable(.camera) {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        } else {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
        }
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public class Coordinator: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PPServicePhotoPickerSheet

        init(_ parent: PPServicePhotoPickerSheet) {
            self.parent = parent
        }

        public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                if let img = image as? UIImage {
                    DispatchQueue.main.async {
                        self?.parent.onImageSelected(img)
                    }
                }
            }
        }

        public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage {
                parent.onImageSelected(img)
            }
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Objective-C Hosting Bridge

@objc @MainActor
public final class PPServiceEditorHostingBridge: NSObject {
    @objc public static func makeViewController(
        service: PPServiceModel?,
        onDismiss: @escaping @Sendable () -> Void,
        onSuccess: @escaping @Sendable () -> Void
    ) -> UIViewController {
        let viewModel = PPServiceEditorViewModel(
            service: service,
            onDismiss: onDismiss,
            onSuccess: onSuccess
        )
        let screen = PPServiceEditorScreen(viewModel: viewModel)
        let host = UIHostingController(rootView: screen)
        host.view.backgroundColor = .clear
        return host
    }
}
