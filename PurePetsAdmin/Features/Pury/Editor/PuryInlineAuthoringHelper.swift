//
//  PuryInlineAuthoringHelper.swift
//  PurePetsAdmin
//
//  Bilingual authoring intelligence helper for Pure Pets Admin inventory editors.
//  Invariants:
//   - Zero persistence in AI layer: applies drafts to local @Binding only.
//   - Bounded public-safe editor facts only.
//   - Strict before/after preview before applying.
//

import SwiftUI

@available(iOS 16.0, *)
public struct PuryInlineAuthoringBar: View {
    let itemType: String
    @Binding var arabicText: String
    @Binding var englishText: String
    let targetField: String // "name" or "description"
    let attributes: [String: String]

    @State private var isProcessing: Bool = false
    @State private var activeResponse: PuryAuthoringResponse? = nil
    @State private var showingPreview: Bool = false
    @State private var errorMessage: String? = nil

    private let service = PuryAdminService.shared

    public init(
        itemType: String,
        arabicText: Binding<String>,
        englishText: Binding<String>,
        targetField: String,
        attributes: [String: String] = [:]
    ) {
        self.itemType = itemType
        self._arabicText = arabicText
        self._englishText = englishText
        self.targetField = targetField
        self.attributes = attributes
    }

    public init(
        itemType: String,
        arabicText: Binding<String>,
        englishText: Binding<String>,
        targetField: String,
        attributes: [String: Any]
    ) {
        self.itemType = itemType
        self._arabicText = arabicText
        self._englishText = englishText
        self.targetField = targetField
        self.attributes = attributes.compactMapValues { "\($0)" }
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Task trigger buttons
            if targetField == "name" {
                authoringButton(task: .translate, label: Language.get("Translate", alter: "ترجمة"))
                authoringButton(task: .improveName, label: Language.get("Pury_Task_ImproveName", alter: "تحسين الاسم"))
            } else {
                authoringButton(task: .generateDescription, label: Language.get("Pury_Task_GenDesc", alter: "توليد وصف"))
                authoringButton(task: .rewriteShorter, label: Language.get("Pury_Task_Shorten", alter: "اختصار"))
                authoringButton(task: .translate, label: Language.get("Translate", alter: "ترجمة"))
            }

            Spacer()

            if isProcessing {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(Color(red: 16/255, green: 185/255, blue: 129/255))
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let response = activeResponse {
                previewSheet(for: response)
            }
        }
    }

    private func authoringButton(task: PuryAuthoringTask, label: String) -> some View {
        Button {
            triggerTask(task)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: task.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(AdminType.caption2Bold)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
            .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    @MainActor
    private func triggerTask(_ task: PuryAuthoringTask) {
        isProcessing = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let sourceLang = !arabicText.isEmpty ? "ar" : "en"
        let targetLang = sourceLang == "ar" ? "en" : "ar"

        let currentDict: [String: String] = [
            "nameAr": targetField == "name" ? arabicText : "",
            "nameEn": targetField == "name" ? englishText : "",
            "descAr": targetField == "description" ? arabicText : "",
            "descEn": targetField == "description" ? englishText : ""
        ]
        let currentItemType = itemType
        let currentAttributes = attributes

        Task { @MainActor in
            do {
                let response = try await service.requestAuthoring(
                    task: task,
                    itemType: currentItemType,
                    sourceLanguage: sourceLang,
                    targetLanguage: targetLang,
                    currentText: currentDict,
                    attributes: currentAttributes
                )
                isProcessing = false
                activeResponse = response
                showingPreview = true
            } catch {
                isProcessing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Preview Sheet

    private func previewSheet(for response: PuryAuthoringResponse) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))

                    Text(Language.get("Pury_Authoring_Comparing", alter: "مقارنة النص المقترح بالنص الحالي"))
                        .font(AdminType.headline)
                        .foregroundStyle(AdminSurface.primaryText)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if targetField == "name" {
                            comparisonBlock(
                                title: Language.get("Arabic_Name", alter: "الاسم بالعربية"),
                                current: arabicText,
                                proposed: response.nameAr ?? ""
                            )

                            comparisonBlock(
                                title: Language.get("English_Name", alter: "الاسم بالإنجليزية"),
                                current: englishText,
                                proposed: response.nameEn ?? ""
                            )
                        } else {
                            comparisonBlock(
                                title: Language.get("Arabic_Description", alter: "الوصف بالعربية"),
                                current: arabicText,
                                proposed: response.descAr ?? ""
                            )

                            comparisonBlock(
                                title: Language.get("English_Description", alter: "الوصف بالإنجليزية"),
                                current: englishText,
                                proposed: response.descEn ?? ""
                            )
                        }

                        if let facts = response.factsUsed, !facts.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Language.get("Pury_Facts_Used", alter: "الحقائق المعتمدة في الصياغة:"))
                                    .font(AdminType.caption2Bold)
                                    .foregroundStyle(AdminSurface.secondaryText)

                                ForEach(facts, id: \.self) { fact in
                                    Text("• \(fact)")
                                        .font(AdminType.caption2)
                                        .foregroundStyle(AdminSurface.secondaryText)
                                }
                            }
                            .padding(10)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Apply & Cancel buttons
                HStack(spacing: 12) {
                    Button {
                        applyDraft(response)
                        showingPreview = false
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                            Text(Language.get("Pury_Authoring_Use", alter: "تطبيق في المحرر"))
                                .font(AdminType.subheadlineBold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color(red: 16/255, green: 185/255, blue: 129/255), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingPreview = false
                    } label: {
                        Text(Language.get("Cancel", alter: "إلغاء"))
                            .font(AdminType.subheadline)
                            .foregroundStyle(AdminSurface.secondaryText)
                            .frame(maxWidth: 90)
                            .padding(.vertical, 12)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(AdminSurface.hairline, lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(AdminSurface.background)
        }
        .presentationDetents([.medium, .large])
    }

    private func comparisonBlock(title: String, current: String, proposed: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AdminType.caption1Bold)
                .foregroundStyle(AdminSurface.primaryText)

            if !current.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Current", alter: "الحالي:"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(current)
                        .font(AdminType.caption1)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 8))
            }

            if !proposed.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Proposed", alter: "المقترح:"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                    Text(proposed)
                        .font(AdminType.body)
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.3), lineWidth: 0.75)
                )
            }
        }
    }

    private func applyDraft(_ response: PuryAuthoringResponse) {
        if targetField == "name" {
            if let ar = response.nameAr, !ar.isEmpty {
                arabicText = ar
            }
            if let en = response.nameEn, !en.isEmpty {
                englishText = en
            }
        } else {
            if let ar = response.descAr, !ar.isEmpty {
                arabicText = ar
            }
            if let en = response.descEn, !en.isEmpty {
                englishText = en
            }
        }
    }
}
