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
import Vision

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
        VStack(alignment: .leading, spacing: 6) {
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
                        .accessibilityLabel(Language.get("Pury_Authoring_Processing", alter: "بيوري يصيغ النص"))
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Label {
                    Text(errorMessage)
                        .font(AdminType.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.red)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Language.get("Pury_Authoring_Error", alter: "تعذر إكمال اقتراح بيوري"))
                .accessibilityValue(errorMessage)
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
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityHint(Language.get("Pury_Authoring_Action_Hint", alter: "ينشئ اقتراحاً للمعاينة قبل تطبيقه في المحرر"))
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
                        .font(AdminType.caption2Bold)
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
                        .font(AdminType.caption2Bold)
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

// MARK: - Pury Vision Extraction Result

public struct PuryVisionExtractionResult: Sendable {
    public let primaryName: String
    public let detectedBrand: String
    public let isArabic: Bool
    public let detectedPetSpecies: String?
    public let rawOcrText: String
    public let attributes: [String: String]
    public let hasValidIdentity: Bool

    public static let empty = PuryVisionExtractionResult(
        primaryName: "",
        detectedBrand: "",
        isArabic: false,
        detectedPetSpecies: nil,
        rawOcrText: "",
        attributes: [:],
        hasValidIdentity: false
    )
}

// MARK: - Pury Vision Intake Engine

public actor PuryVisionIntakeEngine {
    public static let shared = PuryVisionIntakeEngine()

    private let knownBrands: [String] = [
        "Wild Harvest", "Royal Canin", "Purina", "Friskies", "Whiskas",
        "Kaytee", "Versele-Laga", "Vitakraft", "Hagen", "Beaphar",
        "Trixie", "Ferplast", "Catit", "KONG", "Taste of the Wild",
        "Orijen", "Acana", "Hill's", "Science Diet", "Pro Plan",
        "Meow Mix", "Sheba", "Felix", "Pedigree", "Fancy Feast",
        "Blue Buffalo", "Nutro", "Cesar", "Zupreem", "ZuPreem",
        "Harrison's", "Pretty Bird", "Tropican", "Oxbow", "Mazuri",
        "Tetra", "Fluval", "Marina", "Sera", "JBL", "Hikari",
        "Biokat's", "Intersand", "Sanicat", "GimCat", "GimDog",
        "Wanpy", "Applaws", "Schesir", "Brit", "Josera",
        "Happy Dog", "Happy Cat", "Canagan", "Carnilove", "Biogance"
    ]

    private let boilerplateTerms: [String] = [
        "net wt", "fl oz", "ingredients", "distributed by", "made in",
        "best before", "store in", "keep out of", "guaranteed analysis",
        "crude protein", "crude fat", "moisture", "directions",
        "feeding instructions", "www.", ".com", ".sa", ".org", "barcode", "upc",
        "recycle", "gmo", "usa", "germany", "france", "italy", "china"
    ]

    public func extract(from image: UIImage, itemType: String) async -> PuryVisionExtractionResult {
        guard let cgImage = image.cgImage else {
            return .empty
        }

        let cgOrientation = cgImageOrientation(for: image.imageOrientation)

        // 1. Apple Vision Text Recognition (Neural Engine)
        let ocrLines = await performTextRecognition(on: cgImage, orientation: cgOrientation)

        // 2. Identify Brand and Product Title from Packaging
        let parsedPackaging = parsePackaging(from: ocrLines)

        // 3. If live pet or text is scarce, attempt Animal Vision Classification
        var animalSpecies: String? = nil
        if itemType == "live_pet" || (ocrLines.isEmpty && !parsedPackaging.hasBrand) {
            animalSpecies = await performAnimalClassification(on: cgImage, orientation: cgOrientation)
        }

        // 4. Synthesize primary name
        var resolvedName = ""
        let resolvedBrand = parsedPackaging.brand

        if !parsedPackaging.productTitle.isEmpty {
            if !resolvedBrand.isEmpty && !parsedPackaging.productTitle.localizedCaseInsensitiveContains(resolvedBrand) {
                resolvedName = "\(resolvedBrand) \(parsedPackaging.productTitle)"
            } else {
                resolvedName = parsedPackaging.productTitle
            }
        } else if let animal = animalSpecies, !animal.isEmpty {
            resolvedName = animal
        } else if !resolvedBrand.isEmpty {
            resolvedName = resolvedBrand
        }

        resolvedName = resolvedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !resolvedName.isEmpty else {
            return .empty
        }

        let isArabic = resolvedName.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(scalar.value)
        }

        var attributes: [String: String] = [:]
        if !resolvedBrand.isEmpty {
            attributes["brand"] = resolvedBrand
            attributes["packagingBrand"] = resolvedBrand
        }
        if !parsedPackaging.productTitle.isEmpty {
            attributes["packagingTitle"] = parsedPackaging.productTitle
        }
        if let animal = animalSpecies {
            attributes["detectedSpecies"] = animal
        }
        let fullText = ocrLines.map(\.text).joined(separator: "\n")
        if !fullText.isEmpty {
            attributes["packagingText"] = String(fullText.prefix(400))
            attributes["detectedImageText"] = String(fullText.prefix(400))
        }

        return PuryVisionExtractionResult(
            primaryName: resolvedName,
            detectedBrand: resolvedBrand,
            isArabic: isArabic,
            detectedPetSpecies: animalSpecies,
            rawOcrText: fullText,
            attributes: attributes,
            hasValidIdentity: true
        )
    }

    // MARK: - Vision Text Recognition

    private struct RecognizedLine {
        let text: String
        let confidence: Float
        let boundingBox: CGRect
        let prominence: Float
    }

    private func performTextRecognition(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async -> [RecognizedLine] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                guard error == nil, let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var lines: [RecognizedLine] = []
                for obs in observations {
                    guard let topCandidate = obs.topCandidates(1).first else { continue }
                    let clean = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard clean.count >= 2 else { continue }
                    let prom = Float(obs.boundingBox.height * obs.boundingBox.width) * topCandidate.confidence
                    lines.append(RecognizedLine(
                        text: clean,
                        confidence: topCandidate.confidence,
                        boundingBox: obs.boundingBox,
                        prominence: prom
                    ))
                }
                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "ar-SA"]
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Packaging Analysis

    private struct PackagingHeader {
        let brand: String
        let productTitle: String
        let hasBrand: Bool
    }

    private func parsePackaging(from lines: [RecognizedLine]) -> PackagingHeader {
        var foundBrand = ""
        var candidateTitleLines: [String] = []

        // 1. Look for known brand match
        for line in lines {
            for brand in knownBrands {
                if line.text.localizedCaseInsensitiveContains(brand) {
                    if foundBrand.isEmpty {
                        foundBrand = brand
                    }
                }
            }
        }

        // 2. Filter lines that are not boilerplate
        let substantiveLines = lines.filter { line in
            let lower = line.text.lowercased()
            for term in boilerplateTerms {
                if lower.contains(term) { return false }
            }
            if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: line.text.replacingOccurrences(of: " ", with: ""))) {
                return false
            }
            return true
        }

        let midYFiltered = substantiveLines.filter { line in
            line.boundingBox.midY > 0.20
        }
        let upperLines = midYFiltered.sorted { a, b in
            let scoreA = Double(a.boundingBox.height) * Double(a.confidence)
            let scoreB = Double(b.boundingBox.height) * Double(b.confidence)
            return scoreA > scoreB
        }

        for line in upperLines.prefix(4) {
            let t = line.text
            if !foundBrand.isEmpty && t.caseInsensitiveCompare(foundBrand) == .orderedSame {
                continue
            }
            if t.split(separator: " ").count <= 7 {
                candidateTitleLines.append(t)
            }
        }

        let productTitle = candidateTitleLines.prefix(2).joined(separator: " ")
        return PackagingHeader(brand: foundBrand, productTitle: productTitle, hasBrand: !foundBrand.isEmpty)
    }

    // MARK: - Live Pet Image Classification

    private func performAnimalClassification(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { req, error in
                guard error == nil, let observations = req.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let animalMap: [(keyword: String, arabic: String, english: String)] = [
                    ("parrot", "ببغاء", "Parrot"),
                    ("macaw", "ببغاء مكاو", "Macaw"),
                    ("cockatoo", "ببغاء كوكاتو", "Cockatoo"),
                    ("cockatiel", "ببغاء كوكاتيل", "Cockatiel"),
                    ("budgerigar", "طائر بادجي", "Budgerigar"),
                    ("canary", "طائر كناري", "Canary"),
                    ("finch", "طائر حسون", "Finch"),
                    ("lovebird", "طائر الحب", "Lovebird"),
                    ("cat", "قط أليف", "Pet Cat"),
                    ("persian cat", "قط شيرازي", "Persian Cat"),
                    ("siamese cat", "قط سيامي", "Siamese Cat"),
                    ("dog", "كلب أليف", "Pet Dog"),
                    ("golden retriever", "كلب جولدن ريتريفر", "Golden Retriever"),
                    ("german shepherd", "كلب جيرمن شيبرد", "German Shepherd"),
                    ("husky", "كلب هاسكي", "Siberian Husky"),
                    ("pomeranian", "كلب بوميرانيان", "Pomeranian"),
                    ("rabbit", "أرنب أليف", "Pet Rabbit"),
                    ("hamster", "هامستر", "Hamster"),
                    ("guinea pig", "خنزير غينيا", "Guinea Pig"),
                    ("turtle", "سلحفاة", "Turtle"),
                    ("tortoise", "سلحفاة برية", "Tortoise"),
                    ("chameleon", "حرباء", "Chameleon"),
                    ("iguana", "إغوانا", "Iguana"),
                    ("goldfish", "سمكة ذهبية", "Goldfish")
                ]

                for obs in observations.prefix(15) where obs.confidence > 0.3 {
                    let idLower = obs.identifier.lowercased()
                    for item in animalMap {
                        if idLower.contains(item.keyword) {
                            let result = Language.isRTL() ? item.arabic : item.english
                            continuation.resume(returning: result)
                            return
                        }
                    }
                }
                continuation.resume(returning: nil)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func cgImageOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

