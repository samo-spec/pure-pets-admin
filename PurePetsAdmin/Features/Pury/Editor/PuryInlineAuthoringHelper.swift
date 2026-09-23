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
import FirebaseFunctions
import FirebaseAuth

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
                if task == .generateDescription {
                    let effectiveName = currentDict["nameAr"]?.isEmpty == false ? (currentDict["nameAr"] ?? "") : (currentDict["nameEn"] ?? "")
                    let synth = PuryDescriptionSynthesizer.synthesize(
                        itemType: currentItemType,
                        nameAr: currentDict["nameAr"] ?? "",
                        nameEn: currentDict["nameEn"] ?? "",
                        category: currentAttributes["category"],
                        subcategory: currentAttributes["subcategory"],
                        brand: currentAttributes["brand"],
                        attributes: currentAttributes
                    )
                    let fallbackResponse = PuryAuthoringResponse(
                        nameAr: nil,
                        nameEn: nil,
                        descAr: synth.descAr,
                        descEn: synth.descEn,
                        limitations: ["صياغة فورية ذكية"],
                        factsUsed: currentAttributes.map { "\($0.key): \($0.value)" },
                        task: task.rawValue
                    )
                    isProcessing = false
                    activeResponse = fallbackResponse
                    showingPreview = true
                } else {
                    isProcessing = false
                    errorMessage = error.localizedDescription
                }
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

// MARK: - Pury Description Synthesizer

public struct PuryDescriptionSynthesizer {
    public static func synthesize(
        itemType: String,
        nameAr: String,
        nameEn: String,
        category: String?,
        subcategory: String?,
        brand: String?,
        attributes: [String: String]
    ) -> (descAr: String, descEn: String) {
        let cleanNameAr = nameAr.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNameEn = nameEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBrand = (brand ?? attributes["brand"] ?? attributes["packagingBrand"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let brandSuffixAr = cleanBrand.isEmpty ? "" : " من \(cleanBrand)"
        let brandSuffixEn = cleanBrand.isEmpty ? "" : " by \(cleanBrand)"

        let titleAr = !cleanNameAr.isEmpty ? cleanNameAr : (!cleanNameEn.isEmpty ? cleanNameEn : "منتج حيوانات أليفة")
        let titleEn = !cleanNameEn.isEmpty ? cleanNameEn : (!cleanNameAr.isEmpty ? cleanNameAr : "Pet Product")

        // 1. Food
        if itemType == "food" {
            let weight = attributes["weight"] ?? ""
            let weightBulletAr = weight.isEmpty ? "" : "\n• الوزن والعبوة: \(weight)."
            let weightBulletEn = weight.isEmpty ? "" : "\n• Weight / Pack Size: \(weight)."

            let descAr = """
            \(titleAr)\(brandSuffixAr) طعام متكامل ومغذي، تم تصميمه بعناية فائقة لتلبية الاحتياجات الغذائية اليومية ودعم صحة ونشاط الحيوان الأليف. يتميز بتركيبة متوازنة غنية بالعناصر الضرورية وسهلة الهضم مع مذاق شهي ومحبب للأليف.

            المميزات والمواصفات:
            • تركيبة متوازنة تدعم المناعة وصحة الجهاز الهضمي والنشاط الحركي.
            • مكونات مختارة بجودة عالية خالية من المواد الضارة.
            • مذاق ونكهة ممتازة تضمن إقبالاً طبيعياً وسريعاً من الحيوان الأليف.\(weightBulletAr)
            • مناسب كوجبة يومية متكاملة وفق الإرشادات الموصى بها.
            """

            let descEn = """
            \(titleEn)\(brandSuffixEn) provides complete and balanced nutrition carefully formulated to support overall vitality, digestive health, and daily wellness. Made with high-quality ingredients that ensure maximum digestibility and superior taste.

            Key Features & Specifications:
            • Balanced formula supporting immune defense, coat sheen, and gut health.
            • Premium select ingredients free from harmful additives.
            • Irresistible aroma and taste ensuring enthusiastic meal acceptance.\(weightBulletEn)
            • Suitable for daily nourishing meals following recommended portions.
            """

            return (descAr, descEn)
        }

        // 2. Live Pet
        if itemType == "live_pet" {
            let gender = attributes["gender"] ?? ""
            let isVaccinated = attributes["vaccinated"] == "true"
            let genderAr = gender == "female" ? "أنثى" : (gender == "male" ? "ذكر" : "")
            let genderEn = gender == "female" ? "Female" : (gender == "male" ? "Male" : "")
            let healthNotesAr = isVaccinated ? "\n• الحالة الصحية: محصن ومفحوص طبياً." : ""
            let healthNotesEn = isVaccinated ? "\n• Health: Vaccinated and veterinary checked." : ""
            let genderBulletAr = genderAr.isEmpty ? "" : "\n• الجنس: \(genderAr)."
            let genderBulletEn = genderEn.isEmpty ? "" : "\n• Gender: \(genderEn)."

            let descAr = """
            \(titleAr) يتميز بصحة ممتازة ونشاط حيوي وطباع أليفة، خضع للمتابعة والرعاية البيطرية اللازمة في بيور بيتس لضمان سلامته وجاهزيته للانضمام إلى منزله الجديد.

            المواصفات والسمات:
            • حيوان أليف مميز يتمتع بنشاط طبيعي وسلوك هادئ ومحبب.\(genderBulletAr)\(healthNotesAr)
            • معتاد على التعامل الودود ومناسب للتربية المنزلية.
            • نقدم مع كل أليف دليلاً وإرشادات متكاملة للتغذية والبيئة المثالية.
            """

            let descEn = """
            Healthy, energetic, and gentle \(titleEn), nurtured under attentive veterinary supervision at Pure Pets to ensure optimal wellness and seamless transition to a loving home.

            Key Traits & Care Notes:
            • Excellent health, natural vitality, and affectionate temperament.\(genderBulletEn)\(healthNotesEn)
            • Well-acclimated for peaceful indoor companionship.
            • Comprehensive dietary and environmental setup guidance provided.
            """

            return (descAr, descEn)
        }

        // 3. Service
        if itemType == "service" {
            let descAr = """
            خدمة \(titleAr) المتخصصة والمقدمة من بيور بيتس على يد كوادر مؤهلة ومحترفة في رعاية الحيوانات الأليفة. نضمن تطبيق أعلى معايير النظافة والراحة والأمان لحيوانك الأليف طوال فترة الخدمة.

            مميزات الخدمة:
            • رعاية فردية مخصصة تلبي احتياجات حيوانك الأليف بدقة.
            • أدوات ومرافق معقمة ومجهزة بأحدث التقنيات.
            • متابعة مستمرة وتجربة مريحة وخالية من التوتر للأليف.
            """

            let descEn = """
            Professional \(titleEn) delivered by certified pet care specialists at Pure Pets. We uphold the highest industry standards of hygiene, safety, and comfort throughout the service session.

            Service Highlights:
            • Dedicated individual attention tailored to your pet's needs.
            • Sanitized equipment and state-of-the-art care facilities.
            • Calm, stress-free environment handled by compassionate experts.
            """

            return (descAr, descEn)
        }

        // 4. Accessory / Supplies
        let combinedSearch = "\(cleanNameAr) \(cleanNameEn) \(category ?? "") \(subcategory ?? "")".lowercased()

        // 4A. Nail Clippers / Shears / Pliers / Trimmers
        if combinedSearch.contains("مقراض") || combinedSearch.contains("أظافر") || combinedSearch.contains("مقص") ||
           combinedSearch.contains("clipper") || combinedSearch.contains("nail") || combinedSearch.contains("claw") ||
           combinedSearch.contains("trimmer") || combinedSearch.contains("shears") || combinedSearch.contains("plier") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) مصمم بشفرات دقيقة من الستانلس ستيل المقاوم للصدأ لقص آمن ودقيق دون التسبب في إجهاد أو ألم للأليف. يتميز بمقبض مريح مانع للانزلاق يمنحك تحكماً وثباتاً مثالياً أثناء تقليم الأظافر، مع تصميم يراعي سلامة الأوعية الدموية في مخلب الحيوان.

            المميزات والمواصفات:
            • شفرات حادة ومتينة من الفولاذ المقاوم للصدأ لقص متقن ونظيف دون تشقق الأظافر.
            • مقبض هندسي مريح ومضاد للانزلاق لتوفير أقصى درجات التحكم والثبات أثناء الاستخدام.
            • يحافظ على صحة ونظافة أظافر الأليف ويحمي أثاث وسجاد المنزل من الخدش.
            • مناسب للاستخدام المنزلي المنتظم ولجميع المربين بسهولة وأمان.
            """

            let descEn = """
            Precision \(titleEn)\(brandSuffixEn) engineered with sharp stainless steel cutting blades for swift, safe, and comfortable claw trimming. Features an ergonomic anti-slip handle that guarantees maximum control and steady handling during grooming.

            Key Features & Specifications:
            • High-grade stainless steel blades deliver clean, smooth cuts without splitting nails.
            • Ergonomic non-slip grip provides confident handling and fatigue-free operation.
            • Promotes optimal claw hygiene while safeguarding household furniture and upholstery.
            • Ideal for stress-free routine home grooming.
            """

            return (descAr, descEn)
        }

        // 4B. Brushes & Combs / Deshedding
        if combinedSearch.contains("فرشاة") || combinedSearch.contains("مشط") || combinedSearch.contains("تمشيط") ||
           combinedSearch.contains("brush") || combinedSearch.contains("comb") || combinedSearch.contains("grooming") ||
           combinedSearch.contains("deshedding") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) أداة عناية أساسية لإزالة الشعر المتساقط وفك التشابكات بلطف، مع تدليك لطيف ينشط الدورة الدموية ويعيد الحيوية واللمعان الطبيعي لفراء الأليف.

            المميزات والمواصفات:
            • تزيل الشعر الزائد بكفاءة وتقلل تساقط الفراء في أرجاء المنزل.
            • رؤوس ناعمة وآمنة تمنح تدليكاً لطيفاً دون تهيج البشرة الحساسة.
            • مقبض مريح ومضاد للإجهاد مصمم للاستخدام اليومي المريح.
            • ملائمة لمختلف أنواع وأطوال الفراء.
            """

            let descEn = """
            Essential \(titleEn)\(brandSuffixEn) crafted for gentle daily grooming, detangling mats and removing loose undercoat fur while delivering a soothing skin massage.

            Key Features & Specifications:
            • Efficiently removes dead shedding fur and helps prevent hairballs and tangles.
            • Rounded safety bristles protect delicate skin while stimulating healthy circulation.
            • Ergonomic comfort-grip handle designed for effortless, fatigue-free grooming sessions.
            • Suitable for short, medium, and long coats.
            """

            return (descAr, descEn)
        }

        // 4C. Collars / Leashes / Harnesses
        if combinedSearch.contains("طوق") || combinedSearch.contains("مقود") || combinedSearch.contains("حزام") ||
           combinedSearch.contains("collar") || combinedSearch.contains("leash") || combinedSearch.contains("harness") ||
           combinedSearch.contains("lead") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) مصمم لتوفير أعلى معايير الأمان والتحكم المريح أثناء النزهات والتدريب اليومي. مصنوع من خامات عالية التحمل ومبطن بملمس ناعم يمنع الاحتكاك بالجلد.

            المميزات والمواصفات:
            • نسيج متين ومقاوم للشد والتآكل لتحمل الحركة القوية بأمان تام.
            • بطانة داخلية ناعمة وجيدة التهوية لراحة تامة حول الرقبة والجسم.
            • إبزيم أمان متين قابل للتعديل لقياس ملائم وثابت.
            • حلقات معدنية صلبة لتثبيت المقود وبطاقة التعريف بسهولة.
            """

            let descEn = """
            Durable \(titleEn)\(brandSuffixEn) engineered for maximum safety, comfort, and control during daily walks and outdoor adventures. Crafted from high-tensile materials with soft breathable padding.

            Key Features & Specifications:
            • Ultra-strong, pull-resistant webbing built to withstand rigorous activity.
            • Soft breathable lining prevents friction and skin irritation.
            • Fully adjustable heavy-duty quick-release buckle for a secure custom fit.
            • Reinforced metal ring for reliable leash and ID tag attachment.
            """

            return (descAr, descEn)
        }

        // 4D. Bowls / Feeders / Dispensers
        if combinedSearch.contains("صحن") || combinedSearch.contains("طبق") || combinedSearch.contains("وعاء") ||
           combinedSearch.contains("مغذي") || combinedSearch.contains("سقاية") || combinedSearch.contains("نافورة") ||
           combinedSearch.contains("bowl") || combinedSearch.contains("feeder") || combinedSearch.contains("dish") ||
           combinedSearch.contains("waterer") || combinedSearch.contains("fountain") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) يوفر تجربة تغذية صحية ونظيفة للأليف، مصمم من مواد غذائية آمنة بنسبة 100% مع قاعدة ثابتة تمنع الانزلاق والانسكاب أثناء تناول الطعام والماء.

            المميزات والمواصفات:
            • مواد آمنة وخالية من السموم وسهلة الغسيل والتنظيف الدوري.
            • قاعدة مطاطية مانعة للانزلاق تحافظ على ثبات الصحن على الأرضية.
            • زاوية مريحة تسهل وصول الأليف للوجبة دون إجهاد الرقبة.
            • ملائم للطعام الجاف والرطب والمياه العذبة.
            """

            let descEn = """
            Practical \(titleEn)\(brandSuffixEn) offering a hygienic and comfortable mealtime experience for your pet. Made from 100% pet-safe, food-grade materials with an anti-skid base.

            Key Features & Specifications:
            • Food-grade, non-toxic, and ultra-easy to clean and sanitize.
            • Non-slip rubber base keeps the bowl steadily in place to prevent tipping and spills.
            • Ergonomic contour promotes natural, strain-free feeding posture.
            • Suitable for dry kibble, wet food, and fresh water.
            """

            return (descAr, descEn)
        }

        // 4E. Beds / Cushions / Mats
        if combinedSearch.contains("سرير") || combinedSearch.contains("مفرش") || combinedSearch.contains("وسادة") ||
           combinedSearch.contains("مرتبة") || combinedSearch.contains("bed") || combinedSearch.contains("cushion") ||
           combinedSearch.contains("pillow") || combinedSearch.contains("mat") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) يوفر ملاذاً دافئاً ومريحاً لنوم عميق وهادئ لحيوانك الأليف، محشو بألياف ناعمة تدعم المفاصل والعمود الفقري ومكسو بقماش عالي الجودة يدوم طويلاً.

            المميزات والمواصفات:
            • حشوة مريحة تدعم راحة الجسم وتخفف الضغط على المفاصل.
            • قماش فائق النعومة ومقاوم للوبر والخدوش وسهل التنظيف.
            • قاعدة مانعة للانزلاق لضمان الثبات التام على كافة الأرضيات.
            • حواف مريحة تدعم رأس ورقبة الأليف لإحساس فائق بالأمان.
            """

            let descEn = """
            Cozy \(titleEn)\(brandSuffixEn) designed to provide rejuvenating, orthopedic sleep for your pet. Built with plush fabrics and supportive high-density fill that cushions pressure points.

            Key Features & Specifications:
            • Supportive cushioning relieves joint pressure and encourages deep rest.
            • Soft-touch, tear-resistant fabric that resists shedding and is easy to clean.
            • Non-skid bottom keeps the bed securely positioned on any floor surface.
            • Raised bolster edges provide a sense of security and neck support.
            """

            return (descAr, descEn)
        }

        // 4F. Cages & Carriers
        if combinedSearch.contains("قفص") || combinedSearch.contains("حقيبة") || combinedSearch.contains("شنطة") ||
           combinedSearch.contains("تنقل") || combinedSearch.contains("carrier") || combinedSearch.contains("cage") ||
           combinedSearch.contains("crate") || combinedSearch.contains("kennel") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) مصمم لتوفير أقصى درجات الحماية والراحة أثناء السفر والرحلات والزيارات البيطرية، مزود بنوافذ تهوية ممتازة وأقفال أمان متينة وموثوقة.

            المميزات والمواصفات:
            • هيكل متين وخفيف الوزن مزود بمقبض مريح للحمل السلس.
            • فتحات شبكية واسعة تضمن تدفق الهواء النقي ورؤية واضحة للأليف.
            • نظام إغلاق آمن ومحكم يمنع الفتح غير المقصود أثناء النقل.
            • قاعدة مريحة وقابلة للإزالة لتسهيل الغسيل والتنظيف الدوري.
            """

            let descEn = """
            Dependable \(titleEn)\(brandSuffixEn) designed for safe, stress-free travel, vet trips, and everyday transit. Features robust lightweight construction with generous ventilation windows.

            Key Features & Specifications:
            • Lightweight yet sturdy body with reinforced ergonomic carry handles.
            • Multi-sided mesh panels deliver fresh ventilation and calming visibility.
            • Secure locking latches eliminate the risk of accidental escapes.
            • Removable padded base insert for quick, sanitary cleaning.
            """

            return (descAr, descEn)
        }

        // 4G. Litter Boxes & Scoops
        if combinedSearch.contains("رمل") || combinedSearch.contains("صندوق") || combinedSearch.contains("مجرفة") ||
           combinedSearch.contains("litter") || combinedSearch.contains("scoop") || combinedSearch.contains("tray") ||
           combinedSearch.contains("toilet") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) حل صحي ومثالي للحفاظ على نظافة المنزل ومنع انتشار الروائح وتناثر الرمال، مصنوع من بلاستيك فائق الجودة وسهل التنظيف.

            المميزات والمواصفات:
            • حواف مرتفعة تمنع تناثر حبيبات الرمل خارج الصندوق.
            • أسطح غير لاصقة ومقاومة للبقع والروائح الكريهة لتنظيف سريع.
            • مدخل مريح وواسع يسهل حركة الدخول والخروج للأليف.
            • سهل الفك والغسيل للتعقيم والتنظيف الدوري.
            """

            let descEn = """
            Hygienic \(titleEn)\(brandSuffixEn) designed to minimize odor and keep litter neatly contained. Made from durable, non-stick materials engineered for quick, effortless maintenance.

            Key Features & Specifications:
            • High-rim design effectively prevents litter scatter and tracking.
            • Smooth, stain- and odor-resistant plastic surfaces for fast cleaning.
            • Wide, low-entry threshold provides comfortable access.
            • Disassembles effortlessly for thorough washing and sanitation.
            """

            return (descAr, descEn)
        }

        // 4H. Scratchers & Cat Trees
        if combinedSearch.contains("خدش") || combinedSearch.contains("شجرة") || combinedSearch.contains("عمود") ||
           combinedSearch.contains("scratch") || combinedSearch.contains("cat tree") || combinedSearch.contains("post") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) يلبي الغريزة الطبيعية للقطط في الخدش واللعب، ملفوف بحبال سيزال طبيعية متينة تحافظ على صحة المخالب وتبعد القطة عن خدش أثاث المنزل.

            المميزات والمواصفات:
            • حبال سيزال طبيعية شديدة التحمل ومقاومة للتآكل والاهتراء.
            • قاعدة صلبة ومستقرة تمنع الانقلاب أو الاهتزاز أثناء اللعب والقفز.
            • يحافظ على قوة وصحة مخالب القطط ويساعدها على تفريغ طاقتها.
            • يحمي الكنب والأثاث المنزلي من أضرار الخدش.
            """

            let descEn = """
            Sturdy \(titleEn)\(brandSuffixEn) crafted to satisfy your cat's natural scratching and stretching instincts, wrapped in durable natural sisal fiber to encourage healthy claw maintenance.

            Key Features & Specifications:
            • Wrapped in heavy-duty natural sisal rope built for long-lasting scratching fun.
            • Solid, stable base prevents wobbling or tipping during vigorous play.
            • Promotes claw health, muscle stretching, and constructive stress relief.
            • Effectively diverts scratching away from household furniture and rugs.
            """

            return (descAr, descEn)
        }

        // 4I. Toys & Play
        if combinedSearch.contains("لعبة") || combinedSearch.contains("كرة") || combinedSearch.contains("حبل") ||
           combinedSearch.contains("دمية") || combinedSearch.contains("toy") || combinedSearch.contains("ball") ||
           combinedSearch.contains("chew") || combinedSearch.contains("rope") {
            let descAr = """
            \(titleAr)\(brandSuffixAr) يمنح الأليف ساعات من المرح والنشاط التفاعلي، مصمم من مواد آمنة وغير سامة ومقاومة للعض واللعب النشط لتفريغ الطاقة والتخلص من الملل والتوتر.

            المميزات والمواصفات:
            • خامات متينة وآمنة بنسبة 100% على أسنان ولثة الحيوان الأليف.
            • يحفز النشاط البدني والذكاء الحركي ويمنع السلوكيات الناتجة عن الوحدة.
            • تصميم تفاعلي ممتع مناسب للعب الفردي أو المشترك مع المربي.
            • سهل التنظيف والغسيل بعد كل جلسة لعب.
            """

            let descEn = """
            Engaging \(titleEn)\(brandSuffixEn) designed to deliver hours of interactive play and physical exercise. Built from pet-safe, non-toxic materials engineered for energetic chewing and fetching.

            Key Features & Specifications:
            • 100% pet-safe, durable construction gentle on teeth and gums.
            • Encourages active exercise, mental stimulation, and healthy energy release.
            • Fun interactive design suitable for solo entertainment or bonding play.
            • Easy to clean and maintain fresh after playtime.
            """

            return (descAr, descEn)
        }

        // 4J. Universal / General Accessory
        let descAr = """
        \(titleAr)\(brandSuffixAr) منتج متميز وعالي الجودة، مصمم خصيصاً لتوفير أقصى درجات الراحة والعملية لحيوانك الأليف، مصنوع من خامات ممتازة تلبي معايير الجودة والسلامة المعتمدة.

        المميزات والمواصفات:
        • تصميم عصري وعملي يجمع بين الأناقة وسهولة الاستخدام اليومي.
        • خامات آمنة وعالية المتانة مصممة للاستخدام طويل الأمد.
        • يمنح الحيوان الأليف والمربي تجربة مريحة وسلسة وموثوقة.
        • معتمد ومطابق لأعلى معايير الجودة في منصة بيور بيتس.
        """

        let descEn = """
        Premium quality \(titleEn)\(brandSuffixEn), thoughtfully designed to deliver optimal comfort, safety, and everyday utility for your pet. Built from select high-grade materials for long-lasting durability.

        Key Features & Specifications:
        • Practical modern design combining durability with effortless daily use.
        • Safe, high-grade materials crafted for dependable long-term performance.
        • Ensures a seamless, comfortable experience for pets and caregivers alike.
        • Quality tested and assured according to Pure Pets platform standards.
        """

        return (descAr, descEn)
    }
}

// MARK: - Pury Vision Extraction Result

public struct PuryVisionExtractionResult: Sendable {
    public let primaryName: String
    public let detectedBrand: String
    public let isArabic: Bool
    public let detectedPetSpecies: String?
    public let detectedAccessoryCategory: String?
    public let englishName: String?
    public let arabicName: String?
    public let rawOcrText: String
    public let attributes: [String: String]
    public let hasValidIdentity: Bool

    public init(
        primaryName: String,
        detectedBrand: String,
        isArabic: Bool,
        detectedPetSpecies: String?,
        detectedAccessoryCategory: String? = nil,
        englishName: String? = nil,
        arabicName: String? = nil,
        rawOcrText: String,
        attributes: [String: String],
        hasValidIdentity: Bool
    ) {
        self.primaryName = primaryName
        self.detectedBrand = detectedBrand
        self.isArabic = isArabic
        self.detectedPetSpecies = detectedPetSpecies
        self.detectedAccessoryCategory = detectedAccessoryCategory
        self.englishName = englishName
        self.arabicName = arabicName
        self.rawOcrText = rawOcrText
        self.attributes = attributes
        self.hasValidIdentity = hasValidIdentity
    }

    public static let empty = PuryVisionExtractionResult(
        primaryName: "",
        detectedBrand: "",
        isArabic: false,
        detectedPetSpecies: nil,
        detectedAccessoryCategory: nil,
        englishName: nil,
        arabicName: nil,
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

        // 3. Visual Classification on-device: Detects accessories, tools, supplies, and animals
        let visualClassification = await performVisualClassification(on: cgImage, orientation: cgOrientation)

        // 4. Animal Species identification
        var animalSpecies: String? = visualClassification.detectedAnimal?.arabicName
        var animalSpeciesEn: String? = visualClassification.detectedAnimal?.englishName
        if itemType == "live_pet" && animalSpecies == nil {
            animalSpecies = await performAnimalClassification(on: cgImage, orientation: cgOrientation)
        }

        // 5. Synthesize primary name
        var resolvedName = ""
        var resolvedNameAr = ""
        var resolvedNameEn = ""
        let resolvedBrand = parsedPackaging.brand
        var detectedCategoryAr: String? = visualClassification.detectedAccessory?.categoryAr

        if !parsedPackaging.productTitle.isEmpty {
            if !resolvedBrand.isEmpty && !parsedPackaging.productTitle.localizedCaseInsensitiveContains(resolvedBrand) {
                resolvedName = "\(resolvedBrand) \(parsedPackaging.productTitle)"
            } else {
                resolvedName = parsedPackaging.productTitle
            }
        } else if let acc = visualClassification.detectedAccessory {
            if let animal = visualClassification.detectedAnimal {
                resolvedNameAr = "\(acc.arabicTitle) لـ\(animal.speciesAr)"
                resolvedNameEn = "\(animal.speciesEn) \(acc.englishTitle)"
            } else {
                resolvedNameAr = "\(acc.arabicTitle) للحيوانات الأليفة"
                resolvedNameEn = "Pet \(acc.englishTitle)"
            }
            resolvedName = Language.isRTL() ? resolvedNameAr : resolvedNameEn
        } else if itemType == "live_pet", let animal = animalSpecies, !animal.isEmpty {
            resolvedName = animal
            resolvedNameAr = animal
            resolvedNameEn = animalSpeciesEn ?? animal
        } else if !resolvedBrand.isEmpty {
            resolvedName = resolvedBrand
        }

        // 6. If on-device produced no clear identity, attempt Cloud Gemini Vision fallback
        if resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let cloudVision = await performCloudVisionFallback(image: image) {
                resolvedName = cloudVision.name
                if detectedCategoryAr == nil {
                    detectedCategoryAr = cloudVision.category
                }
                if animalSpecies == nil {
                    animalSpecies = cloudVision.species
                }
            }
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
        if let cat = detectedCategoryAr {
            attributes["detectedCategory"] = cat
        }
        if let acc = visualClassification.detectedAccessory {
            attributes["accessoryType"] = acc.englishTitle
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
            detectedAccessoryCategory: detectedCategoryAr,
            englishName: resolvedNameEn.isEmpty ? nil : resolvedNameEn,
            arabicName: resolvedNameAr.isEmpty ? nil : resolvedNameAr,
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

    // MARK: - Visual Classification (Accessory & Pet Taxonomy)

    private struct DetectedAccessory {
        let arabicTitle: String
        let englishTitle: String
        let categoryAr: String
        let categoryEn: String
        let confidence: Float
    }

    private struct DetectedAnimal {
        let arabicName: String
        let englishName: String
        let speciesAr: String
        let speciesEn: String
        let confidence: Float
    }

    private func performVisualClassification(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async -> (detectedAccessory: DetectedAccessory?, detectedAnimal: DetectedAnimal?) {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { req, error in
                guard error == nil, let observations = req.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                // 1. Accessory Mapping (clippers, shears, brushes, collars, beds, bowls, cages, etc.)
                let accessoryTaxonomy: [(keywords: [String], ar: String, en: String, catAr: String, catEn: String)] = [
                    (["clipper", "scissors", "shears", "nail", "claw", "plier", "cutters", "trimmer"],
                     "مقراض أظافر", "Nail Clipper", "عناية ونظافة", "Grooming"),
                    (["brush", "comb", "hairbrush", "carder", "grooming", "slicker", "deshedding"],
                     "فرشاة عناية وتمشيط", "Grooming Brush & Comb", "عناية ونظافة", "Grooming"),
                    (["collar", "leash", "harness", "tether", "muzzle", "lead", "halter"],
                     "طوق ومقود", "Pet Collar & Leash", "أطواق ومستلزمات مشي", "Collars & Leashes"),
                    (["bowl", "dish", "saucer", "feeder", "trough", "dispenser", "fountain", "waterer"],
                     "صحن طعام وماء", "Pet Food & Water Bowl", "أطباق ومغذيات", "Feeders & Bowls"),
                    (["bed", "cushion", "pillow", "mat", "blanket", "mattress", "pad"],
                     "سرير نوم مريح", "Comfort Pet Bed", "أسرة ومفارش", "Beds & Mats"),
                    (["cage", "birdcage", "crate", "carrier", "kennel", "pen", "coop", "enclosure", "hutch"],
                     "قفص وحقيبة تنقل", "Pet Carrier & Cage", "أقفاص وحقائب تنقل", "Cages & Carriers"),
                    (["litter", "tray", "scoop", "toilet", "sand box"],
                     "صندوق رمل ومجرفة", "Cat Litter Box & Scoop", "نظافة ورمل القطط", "Litter & Waste"),
                    (["scratch", "cat tree", "condo", "post", "tower", "scratcher"],
                     "عمود خدش وشجرة قطط", "Cat Scratching Post", "خدوشات وأشجار", "Scratchers & Trees"),
                    (["toy", "ball", "rubber", "chew", "rope", "plush", "doll", "teaser"],
                     "لعبة ترفيهية ومسلية", "Pet Play Toy", "ألعاب وتسالي", "Pet Toys"),
                    (["aquarium", "fish tank", "filter", "aerator", "pump", "tank"],
                     "مستلزمات وحوض أسماك", "Aquarium & Fish Supplies", "مستلزمات أسماك", "Aquarium Supplies"),
                    (["apparel", "clothing", "coat", "jacket", "sweater", "boot", "vest", "costume"],
                     "ملابس وسترة للحيوانات الأليفة", "Pet Apparel & Jacket", "ملابس وإكسسوارات", "Pet Apparel"),
                    (["shampoo", "spray", "lotion", "soap", "cleanser", "wipe", "wipes", "hygiene"],
                     "شامبو ومستحضر نظافة", "Pet Hygiene Shampoo & Care", "عناية ونظافة", "Hygiene & Care"),
                    (["food", "kibble", "can", "tin", "pouch", "biscuit", "treat", "pellet", "seed"],
                     "طعام ومكافآت مغذية", "Nutritious Pet Food & Treats", "أغذية ومكافآت", "Pet Food & Treats")
                ]

                // 2. Animal Taxonomy (cats, dogs, parrots, birds, etc.)
                let animalTaxonomy: [(keywords: [String], ar: String, en: String, speciesAr: String, speciesEn: String)] = [
                    (["cat", "feline", "kitten", "persian cat", "siamese"],
                     "قط أليف", "Pet Cat", "القطط", "Cat"),
                    (["dog", "canine", "puppy", "retriever", "shepherd", "husky", "pomeranian", "bulldog"],
                     "كلب أليف", "Pet Dog", "الكلاب", "Dog"),
                    (["parrot", "macaw", "cockatoo", "cockatiel", "budgerigar", "canary", "finch", "bird"],
                     "طائر / ببغاء", "Bird / Parrot", "الطيور", "Bird"),
                    (["rabbit", "hare"],
                     "أرنب أليف", "Pet Rabbit", "الأرانب", "Rabbit"),
                    (["hamster", "guinea pig", "rodent"],
                     "هامستر أليف", "Pet Hamster", "القوارض", "Small Pet"),
                    (["turtle", "tortoise"],
                     "سلحفاة", "Turtle", "الزواحف", "Reptile"),
                    (["fish", "goldfish"],
                     "سمكة زينة", "Pet Fish", "الأسماك", "Fish"),
                    (["horse", "stallion", "equine"],
                     "خيل", "Horse", "الخيول", "Horse"),
                    (["camel"],
                     "إبل", "Camel", "الإبل", "Camel"),
                    (["falcon", "hawk"],
                     "صقر", "Falcon", "الصقور", "Falcon")
                ]

                var bestAccessory: DetectedAccessory? = nil
                var bestAnimal: DetectedAnimal? = nil

                for obs in observations.prefix(30) where obs.confidence > 0.15 {
                    let idLower = obs.identifier.lowercased()

                    if bestAccessory == nil {
                        for item in accessoryTaxonomy {
                            if item.keywords.contains(where: { idLower.contains($0) }) {
                                bestAccessory = DetectedAccessory(
                                    arabicTitle: item.ar,
                                    englishTitle: item.en,
                                    categoryAr: item.catAr,
                                    categoryEn: item.catEn,
                                    confidence: obs.confidence
                                )
                                break
                            }
                        }
                    }

                    if bestAnimal == nil {
                        for item in animalTaxonomy {
                            if item.keywords.contains(where: { idLower.contains($0) }) {
                                bestAnimal = DetectedAnimal(
                                    arabicName: item.ar,
                                    englishName: item.en,
                                    speciesAr: item.speciesAr,
                                    speciesEn: item.speciesEn,
                                    confidence: obs.confidence
                                )
                                break
                            }
                        }
                    }

                    if bestAccessory != nil && bestAnimal != nil {
                        break
                    }
                }

                continuation.resume(returning: (bestAccessory, bestAnimal))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: (nil, nil))
            }
        }
    }

    // MARK: - Cloud Gemini Vision Fallback (Via imageSearch Callable)

    private func performCloudVisionFallback(image: UIImage) async -> (name: String, category: String?, species: String?)? {
        guard let data = image.jpegData(compressionQuality: 0.65) else { return nil }
        let base64 = data.base64EncodedString()
        let callable = Functions.functions(region: "us-central1").httpsCallable("imageSearch")
        callable.timeoutInterval = 10.0
        let payload: [String: Any] = [
            "imageBase64": base64,
            "contentType": "image/jpeg",
            "searchMode": "auto",
            "limit": 1
        ]
        do {
            let res = try await callable.call(payload)
            guard let dict = res.data as? [String: Any],
                  let detected = dict["detected"] as? [String: Any] else {
                return nil
            }
            let terms = detected["searchTerms"] as? [String] ?? []
            let productType = detected["productType"] as? String
            let speciesText = detected["speciesText"] as? String
            if let firstTerm = terms.first, !firstTerm.isEmpty {
                return (firstTerm, productType, speciesText)
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Animal Classification (Legacy Compatibility)

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

                for obs in observations.prefix(20) where obs.confidence > 0.25 {
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


